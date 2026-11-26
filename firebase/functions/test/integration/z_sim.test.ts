/**
 * Seed + sim runner against the emulators (runs last: it fills the database with bots and
 * the simulated tables). The last test is the load probe (16 simulated tables, tick p95).
 */
import { describe, expect, it } from 'vitest';
import { verifyFairness } from '../../src/engine';
import type { GameTableDoc } from '../../src/shared/games/common';
import type { HandHistoryDoc, MarketDoc, ProfileDoc, TableDoc } from '../../src/shared/types';
import { gameSimTableIds } from '../../src/sim/gameSims';
import { runLoadProbe, useTestModules } from '../../src/sim/loadProbe';
import { BOTS, BOTS_V1, SIM_TABLE_COUNT, simTableId } from '../../src/sim/profiles';
import { SimRunner } from '../../src/sim/runner';
import { ensureSeedV2, seed } from '../../src/sim/seed';
import { admin, playerClient } from './client';

describe('seed and sim runner', () => {
  it('seeds 120 bots with stats, leaderboard, friendships and 8 live tables with history; no table for stub games', async () => {
    const res = await seed({ historyHands: 6 });
    expect(res.skipped).toBe(false);
    expect(res.tables).toBe(SIM_TABLE_COUNT); // phase-A stubs: no kernel game table
    const db = admin();
    const profiles = await db.collection('profiles').where('isBot', '==', true).get();
    expect(profiles.size).toBe(BOTS.length);
    expect(BOTS).toHaveLength(120);
    expect(BOTS_V1.map((b) => b.username)).toEqual(BOTS.slice(0, 60).map((b) => b.username));
    const top = await db.collection('profiles').orderBy('rankPoints', 'desc').limit(10).get();
    expect(top.size).toBe(10);
    const p = top.docs[0].data() as ProfileDoc;
    expect(p.stats.handsPlayed).toBeGreaterThan(0);
    expect((await db.collection('friendships').where('uids', 'array-contains', BOTS[0].uid).get()).size).toBeGreaterThan(0);
    expect((await db.collection('friendships').where('uids', 'array-contains', BOTS[100].uid).get()).size).toBeGreaterThan(0);
    for (let i = 0; i < SIM_TABLE_COUNT; i++) {
      const t = (await db.doc(`tables/${simTableId(i)}`).get()).data() as TableDoc;
      expect(t.status).toBe('open');
      expect(t.botCount).toBeGreaterThanOrEqual(2);
      expect(t.handNumber).toBeGreaterThanOrEqual(6);
    }
    const hands = await db.collection(`tables/${simTableId(0)}/hands`).get();
    expect(hands.size).toBeGreaterThanOrEqual(6);
    for (const h of hands.docs) expect(verifyFairness((h.data() as HandHistoryDoc).fairness)).toBe(true);
    expect((await seed()).skipped).toBe(true); // idempotent
    expect(await ensureSeedV2(db)).toEqual({ bots: 0, tables: [] }); // idempotent upgrade
  });

  it('ensureSeedV2 upgrades a Sprint 1 database: missing bots, then the game tables of available games', async () => {
    const db = admin();
    await db.doc(`profiles/${BOTS[110].uid}`).delete();
    const restore = useTestModules();
    try {
      const v2 = await ensureSeedV2(db, { gameTablesPerGame: 1, historyRounds: 2 });
      expect(v2.bots).toBe(1);
      expect(v2.tables.sort()).toEqual(gameSimTableIds(1).sort());
      for (const id of v2.tables) {
        const t = (await db.doc(`gameTables/${id}`).get()).data() as GameTableDoc;
        expect(t).toMatchObject({ status: 'open', simManaged: true, isPrivate: false });
        expect(t.botCount).toBeGreaterThanOrEqual(2); // 3–4 seated, churn keeps at least 2
        expect(t.round).toBeGreaterThanOrEqual(1);
      }
      expect(await ensureSeedV2(db, { gameTablesPerGame: 1 })).toEqual({ bots: 0, tables: [] });
    } finally {
      restore();
    }
  });

  it('the runner advances tables, bots trade on markets, and a human joins a live table (bots yield)', async () => {
    const db = admin();
    const before = new Map<string, number>();
    for (let i = 0; i < SIM_TABLE_COUNT; i++) before.set(simTableId(i), ((await db.doc(`tables/${simTableId(i)}`).get()).get('eventSeq') as number));
    // the game tables created above belong to stub games again: the runner closes them
    const runner = new SimRunner(db, 300, { gameTablesPerGame: 1 });
    const stats = await runner.run(12_000);
    expect(stats.errors).toBe(0);
    expect(stats.advanced).toBeGreaterThan(5);
    let moved = 0;
    for (let i = 0; i < SIM_TABLE_COUNT; i++) {
      const t = (await db.doc(`tables/${simTableId(i)}`).get()).data() as TableDoc;
      if (t.eventSeq > before.get(t.tableId)!) moved++;
    }
    expect(moved).toBe(SIM_TABLE_COUNT);
    for (const id of gameSimTableIds(1, ['roulette', 'baccarat', 'holdem', 'craps'])) {
      expect((await db.doc(`gameTables/${id}`).get()).get('status')).toBe('closed');
    }
    const open = await db.collection('markets').where('status', '==', 'open').get();
    expect(open.size).toBeGreaterThan(0);
    const traded = open.docs.map((d) => d.data() as MarketDoc).filter((m) => m.tradeCount > 0);
    expect(traded.length + stats.trades).toBeGreaterThan(0);

    // a human quick-joins the 'mid' tier: lands on a live simulated table
    const h = await playerClient();
    const r = await h.call('joinMatchmaking', { mode: 'quick', stakeTier: 'mid' });
    const t = (await db.doc(`tables/${r.tableId}`).get()).data() as TableDoc;
    expect(t.simManaged).toBe(true);
    expect(t.seatedUids.includes(h.uid) || t.queue.some((q) => q.uid === h.uid)).toBe(true);
    await h.call('leaveTable', { tableId: r.tableId });
    await h.close();
  });

  it('load probe: 8 blackjack + 8 kernel-game simulated tables (16 in all), tick p95 < 400 ms', async () => {
    const r = await runLoadProbe(admin(), { durationMs: Number(process.env.LOAD_PROBE_MS ?? 30_000), gameTablesPerGame: 2, blackjack: true });
    console.log(`load probe: ${JSON.stringify(r)}`);
    expect(r.tables.total).toBe(16);
    expect(r.errors).toBe(0);
    expect(r.gameRounds).toBeGreaterThan(8);
    expect(r.blackjackHands).toBeGreaterThanOrEqual(8); // ~1 hand per table per 30 s (20 s betting)
    expect(r.tickP95Ms).toBeLessThan(400);
  });
});
