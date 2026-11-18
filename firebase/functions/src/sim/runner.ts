/**
 * sim_runner: keeps the classroom world alive without scheduled functions.
 *  - every tick (500 ms): applies overdue deadlines of every open table (bots act, timeouts,
 *    new hands) through the same transactional code as the callables;
 *  - recreates missing simulated tables (8 live tables);
 *  - bots trade on open spectator markets toward a noisy fair-value estimate;
 *  - pays resolved markets whose payouts were interrupted, promotes due KYC reviews,
 *    accepts friend requests sent to bots, syncs bots' presence/location, prunes the feed.
 *
 *   node lib/sim/runner.js [--duration=<ms>] [--tick=<ms>]
 */
import type { Firestore } from 'firebase-admin/firestore';
import { cryptoRng, nextFloat, type Rng } from '../engine/rng';
import { firestore } from '../shared/admin';
import { refs } from '../shared/paths';
import type { FriendRequestDoc, FriendshipDoc, KycDoc, MarketDoc, ProfileDoc, TableDoc } from '../shared/types';
import { cardPoints } from '../engine/cards';
import { botTrade, settleMarketPayouts } from '../table/markets';
import { applyOverdue } from '../table/service';
import { BOT_BY_UID, BOTS, SIM_TABLE_COUNT, simTableId } from './profiles';
import { createSimTable, seed } from './seed';

/** Probability the dealer busts given the up card (6 decks, S17). */
const BUST_BY_UP: Record<number, number> = { 1: 0.17, 2: 0.35, 3: 0.37, 4: 0.40, 5: 0.42, 6: 0.42, 7: 0.26, 8: 0.24, 9: 0.23, 10: 0.21 };

function fairEstimate(m: MarketDoc, t: TableDoc | undefined): number {
  switch (m.kind) {
    case 'dealerBust': {
      const up = t?.handNumber === m.handNumber ? t.dealer.cards[0] : undefined;
      return up ? BUST_BY_UP[cardPoints(up)] : 0.28;
    }
    case 'natural': {
      const n = t ? t.seats.filter((s) => s && s.betCents > 0).length || t.seatedUids.length : 3;
      return 1 - (1 - 0.0475) ** (n + 1);
    }
    case 'playerWins': {
      const seat = t?.seats.find((s) => s?.uid === m.subjectUid);
      const h = seat?.hands[0];
      if (h?.busted) return 0.02;
      if (h?.blackjack) return 0.97;
      return 0.43;
    }
    case 'shoeDealerBustRate':
      return 0.5;
  }
}

export interface RunnerStats {
  ticks: number;
  advanced: number;
  trades: number;
  errors: number;
}

export class SimRunner {
  stats: RunnerStats = { ticks: 0, advanced: 0, trades: 0, errors: 0 };
  private tables: TableDoc[] = [];
  private lastScan = 0;
  private lastSlow = 0;
  private stopped = false;
  private readonly rng: Rng = cryptoRng();

  constructor(private readonly db: Firestore, private readonly tickMs = 500) {}

  stop(): void {
    this.stopped = true;
  }

  async run(durationMs = Infinity): Promise<RunnerStats> {
    const end = Date.now() + durationMs;
    while (!this.stopped && Date.now() < end) {
      const t0 = Date.now();
      await this.tick();
      const wait = this.tickMs - (Date.now() - t0);
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    }
    return this.stats;
  }

  async tick(): Promise<void> {
    this.stats.ticks++;
    const now = Date.now();
    try {
      if (now - this.lastScan > 3_000) {
        const snap = await this.db.collection('tables').where('status', '==', 'open').get();
        this.tables = snap.docs.map((d) => d.data() as TableDoc);
        this.lastScan = now;
        await this.ensureSimTables();
      }
      // advance every overdue table (fresh read inside applyOverdue)
      const results = await Promise.allSettled(this.tables.map((t) => applyOverdue(this.db, t.tableId)));
      for (const r of results) {
        if (r.status === 'fulfilled' && r.value) this.stats.advanced++;
        if (r.status === 'rejected') this.stats.errors++;
      }
      if (results.some((r) => r.status === 'fulfilled' && r.value)) this.lastScan = 0; // refresh cache soon
      await this.botTrades();
      if (now - this.lastSlow > 10_000) {
        this.lastSlow = now;
        await Promise.allSettled([this.payPending(), this.promoteKyc(), this.acceptBotFriends(), this.syncBots(), this.pruneFeed()]);
      }
    } catch (e) {
      this.stats.errors++;
      console.error('sim tick error:', (e as Error).message);
    }
  }

  private async ensureSimTables(): Promise<void> {
    const present = new Set(this.tables.filter((t) => t.simManaged).map((t) => t.tableId));
    if (present.size === 0 && !(await refs(this.db).profile(BOTS[0].uid).get()).exists) {
      await seed({ historyHands: 3 }); // empty database: full seed
      console.log('sim: database was empty, seeded bots and simulated tables');
      this.lastScan = 0;
      return;
    }
    for (let i = 0; i < SIM_TABLE_COUNT; i++) {
      if (present.has(simTableId(i))) continue;
      await createSimTable(this.db, i, 2);
      console.log(`sim: (re)created ${simTableId(i)}`);
      this.lastScan = 0;
    }
  }

  private async botTrades(): Promise<void> {
    if (nextFloat(this.rng) > 0.5) return;
    const snap = await this.db.collection('markets').where('status', '==', 'open').limit(60).get();
    if (snap.empty) return;
    const byId = new Map(this.tables.map((t) => [t.tableId, t]));
    const picks = Math.min(3, snap.size);
    for (let i = 0; i < picks; i++) {
      const m = snap.docs[this.rng.nextInt(snap.size)].data() as MarketDoc;
      const t = byId.get(m.tableId);
      const bot = BOTS[this.rng.nextInt(BOTS.length)];
      if (t?.seatedUids.includes(bot.uid)) continue; // bots don't bet on their own table either
      if (nextFloat(this.rng) > 0.3 + bot.traderAppetite * 0.7) continue;
      const est = Math.min(0.97, Math.max(0.03, fairEstimate(m, t) + (nextFloat(this.rng) - 0.5) * 0.2));
      const side = m.priceYes < est ? 'yes' : 'no';
      const shares = 1 + this.rng.nextInt(Math.max(2, Math.round(4 + bot.traderAppetite * 20)));
      try {
        if (await botTrade(this.db, m.marketId, bot, side, shares)) this.stats.trades++;
      } catch {
        this.stats.errors++;
      }
    }
  }

  private async payPending(): Promise<void> {
    for (const status of ['resolved', 'void'] as const) {
      const snap = await this.db.collection('markets').where('status', '==', status).where('payoutsDone', '==', false).limit(50).get();
      for (const d of snap.docs) await settleMarketPayouts(this.db, d.id);
    }
  }

  private async promoteKyc(): Promise<void> {
    const snap = await this.db.collectionGroup('private').where('status', '==', 'pending').limit(100).get();
    const now = Date.now();
    for (const d of snap.docs) {
      const k = d.data() as KycDoc;
      if (d.id !== 'kyc' || k.verifyAfterMs === null || k.verifyAfterMs > now) continue;
      const uid = d.ref.parent.parent!.id;
      await this.db.runTransaction(async (tx) => {
        const cur = await tx.get(d.ref);
        if ((cur.data() as KycDoc).status !== 'pending') return;
        tx.update(d.ref, { status: 'verified', verifiedAtMs: now });
        tx.update(refs(this.db).profile(uid), { kycVerified: true });
      });
    }
  }

  private async acceptBotFriends(): Promise<void> {
    const r = refs(this.db);
    const snap = await this.db.collection('friendRequests').where('toUid', '>=', 'bot_').where('toUid', '<', 'bot_~').limit(50).get();
    for (const d of snap.docs) {
      const req = d.data() as FriendRequestDoc;
      if (!BOT_BY_UID.has(req.toUid) || Date.now() - req.createdAtMs < 3_000) continue;
      await this.db.runTransaction(async (tx) => {
        const cur = await tx.get(d.ref);
        if (!cur.exists) return;
        const f: FriendshipDoc = {
          uids: [req.fromUid, req.toUid].sort() as [string, string],
          usernames: { [req.fromUid]: req.fromUsername, [req.toUid]: req.toUsername }, sinceMs: Date.now(),
        };
        tx.delete(d.ref);
        tx.set(r.friendship(req.fromUid, req.toUid), f);
      });
    }
  }

  private async syncBots(): Promise<void> {
    const r = refs(this.db);
    const where = new Map<string, string>();
    for (const t of this.tables) for (const s of t.seats) if (s?.isBot) where.set(s.uid, t.tableId);
    const batch = this.db.batch();
    const snaps = await this.db.getAll(...BOTS.map((b) => r.profile(b.uid)));
    let n = 0;
    const now = Date.now();
    for (const s of snaps) {
      if (!s.exists) continue;
      const p = s.data() as ProfileDoc;
      const tableId = where.get(p.uid) ?? null;
      if (p.currentTableId !== tableId || (tableId && now - p.lastSeenAtMs > 60_000)) {
        batch.update(s.ref, { currentTableId: tableId, ...(tableId ? { lastSeenAtMs: now } : {}) });
        n++;
      }
    }
    if (n > 0) await batch.commit();
  }

  private async pruneFeed(): Promise<void> {
    const snap = await this.db.collection('feed').orderBy('createdAtMs', 'desc').offset(200).limit(200).get();
    if (snap.empty) return;
    const batch = this.db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

if (require.main === module) {
  const arg = (k: string) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split('=')[1];
  const duration = arg('duration') ? Number(arg('duration')) : Infinity;
  const tick = arg('tick') ? Number(arg('tick')) : 500;
  const runner = new SimRunner(firestore(), tick);
  process.on('SIGINT', () => runner.stop());
  process.on('SIGTERM', () => runner.stop());
  console.log(`sim_runner: ticking every ${tick} ms${Number.isFinite(duration) ? ` for ${duration} ms` : ''} (Ctrl+C to stop)`);
  const report = setInterval(() => {
    const s = runner.stats;
    console.log(`sim_runner: ticks=${s.ticks} advanced=${s.advanced} botTrades=${s.trades} errors=${s.errors}`);
  }, 30_000);
  runner.run(duration).then((s) => {
    clearInterval(report);
    console.log(`sim_runner stopped: ticks=${s.ticks} advanced=${s.advanced} botTrades=${s.trades} errors=${s.errors}`);
    process.exit(0);
  });
}
