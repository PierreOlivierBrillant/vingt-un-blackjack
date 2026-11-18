/**
 * Seed + sim runner against the emulators (runs last: it fills the database with bots and
 * the 8 permanent simulated tables).
 */
import { describe, expect, it } from 'vitest';
import { verifyFairness } from '../../src/engine';
import type { HandHistoryDoc, MarketDoc, ProfileDoc, TableDoc } from '../../src/shared/types';
import { BOTS, SIM_TABLE_COUNT, simTableId } from '../../src/sim/profiles';
import { SimRunner } from '../../src/sim/runner';
import { seed } from '../../src/sim/seed';
import { admin, playerClient } from './client';

describe('seed and sim runner', () => {
  it('seeds ~60 bots with stats, leaderboard, friendships and 8 live tables with history', async () => {
    const res = await seed({ historyHands: 6 });
    expect(res.skipped).toBe(false);
    const db = admin();
    const profiles = await db.collection('profiles').where('isBot', '==', true).get();
    expect(profiles.size).toBe(BOTS.length);
    const top = await db.collection('profiles').orderBy('rankPoints', 'desc').limit(10).get();
    expect(top.size).toBe(10);
    const p = top.docs[0].data() as ProfileDoc;
    expect(p.stats.handsPlayed).toBeGreaterThan(0);
    expect((await db.collection('friendships').where('uids', 'array-contains', BOTS[0].uid).get()).size).toBeGreaterThan(0);
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
  });

  it('the runner advances tables, bots trade on markets, and a human joins a live table (bots yield)', async () => {
    const db = admin();
    const before = new Map<string, number>();
    for (let i = 0; i < SIM_TABLE_COUNT; i++) before.set(simTableId(i), ((await db.doc(`tables/${simTableId(i)}`).get()).get('eventSeq') as number));
    const runner = new SimRunner(db, 300);
    const stats = await runner.run(12_000);
    expect(stats.errors).toBe(0);
    expect(stats.advanced).toBeGreaterThan(5);
    let moved = 0;
    for (let i = 0; i < SIM_TABLE_COUNT; i++) {
      const t = (await db.doc(`tables/${simTableId(i)}`).get()).data() as TableDoc;
      if (t.eventSeq > before.get(t.tableId)!) moved++;
    }
    expect(moved).toBe(SIM_TABLE_COUNT);
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
});
