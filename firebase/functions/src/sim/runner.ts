/**
 * sim_runner: keeps the classroom world alive without scheduled functions.
 *  - LISTENS (onSnapshot) to the open tables of both collections (`tables` for blackjack,
 *    `gameTables` for the kernel games) instead of polling them; every tick (500 ms) it applies the
 *    overdue deadlines of the tables that are due according to the snapshots (bots act, timeouts,
 *    new rounds) through the same transactional code as the callables;
 *  - recreates missing simulated tables (8 blackjack + N per available kernel game, ensureSeedV2);
 *  - bots trade on open spectator markets toward a noisy fair-value estimate (blackjack estimate
 *    here, every other game's from its GameModule.fairEstimate);
 *  - in the background (single flight, every ~10 s): pays resolved markets whose payouts were
 *    interrupted, promotes due KYC reviews, accepts friend requests sent to bots, syncs bots'
 *    presence/location on both collections, prunes the feed, runs the Rendez-vous bots' tasks.
 *
 *   node lib/sim/runner.js [--duration=<ms>] [--tick=<ms>] [--game-tables=<0..8>]
 */
import type { Firestore } from 'firebase-admin/firestore';
import { cryptoRng, nextFloat, type Rng } from '../engine/rng';
import { cardPoints } from '../engine/cards';
import { applyOverdueAny } from '../games/overdue';
import { gameModule } from '../games/registry';
import { datingBotTick } from '../romance/bots';
import { firestore } from '../shared/admin';
import { gameOfTableId, type GameTableDoc } from '../shared/games/common';
import { refs } from '../shared/paths';
import type { FriendRequestDoc, FriendshipDoc, KycDoc, MarketDoc, ProfileDoc, TableDoc } from '../shared/types';
import { DECISION_GRACE_MS } from '../shared/types';
import { botTrade, settleMarketPayouts } from '../table/markets';
import { gameSimTableIds, gameSimTablesPerGame } from './gameSims';
import { BOT_BY_UID, BOTS, SIM_TABLE_COUNT, simTableId } from './profiles';
import { createSimTable, ensureSeedV2, seed } from './seed';

/** Probability the dealer busts given the up card (6 decks, S17). */
const BUST_BY_UP: Record<number, number> = { 1: 0.17, 2: 0.35, 3: 0.37, 4: 0.40, 5: 0.42, 6: 0.42, 7: 0.26, 8: 0.24, 9: 0.23, 10: 0.21 };

function blackjackEstimate(m: MarketDoc, t: TableDoc | undefined): number {
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
    default:
      return 0.5;
  }
}

/** Fair YES probability of any market (blackjack here, other games from their module). */
export function fairEstimate(m: MarketDoc, bj: ReadonlyMap<string, TableDoc>, games: ReadonlyMap<string, GameTableDoc>): number {
  const game = m.game ?? gameOfTableId(m.tableId);
  if (game === 'blackjack') return blackjackEstimate(m, bj.get(m.tableId));
  try {
    return gameModule(game).fairEstimate(m, games.get(m.tableId) ?? null);
  } catch {
    return 0.5;
  }
}

export interface RunnerStats {
  ticks: number;
  advanced: number;
  trades: number;
  errors: number;
}

export interface RunnerOptions {
  /** Simulated tables per kernel game (default SIM_GAME_TABLES / 2). */
  gameTablesPerGame?: number;
  /** Keep the 8 blackjack simulated tables alive (default true). */
  blackjackSims?: boolean;
}

export class SimRunner {
  stats: RunnerStats = { ticks: 0, advanced: 0, trades: 0, errors: 0 };
  /** Duration of every tick (ms), for the load probe. */
  readonly tickDurations: number[] = [];
  readonly bj = new Map<string, TableDoc>();
  readonly games = new Map<string, GameTableDoc>();
  private readonly retry = new Map<string, { deadline: number | null; at: number }>();
  private unsubs: Array<() => void> = [];
  private listening: Promise<void> | null = null;
  private lastEnsure = 0;
  private lastSlow = 0;
  private ensuring = false;
  private slowRunning = false;
  private stopped = false;
  private readonly rng: Rng = cryptoRng();
  private readonly perGame: number;
  private readonly blackjackSims: boolean;
  private seededV2 = false;

  constructor(private readonly db: Firestore, private readonly tickMs = 500, opts: RunnerOptions = {}) {
    this.perGame = opts.gameTablesPerGame ?? gameSimTablesPerGame();
    this.blackjackSims = opts.blackjackSims ?? true;
  }

  stop(): void {
    this.stopped = true;
    for (const u of this.unsubs) u();
    this.unsubs = [];
  }

  /** Starts the two listeners; resolves once both delivered their first snapshot. */
  listen(): Promise<void> {
    if (this.listening) return this.listening;
    const follow = <T>(coll: string, into: Map<string, T>) => new Promise<void>((resolve) => {
      let done = false;
      const unsub = this.db.collection(coll).where('status', '==', 'open').onSnapshot((snap) => {
        for (const ch of snap.docChanges()) {
          if (ch.type === 'removed') into.delete(ch.doc.id);
          else into.set(ch.doc.id, ch.doc.data() as T);
        }
        if (!done) { done = true; resolve(); }
      }, (e) => {
        this.stats.errors++;
        console.error(`sim: ${coll} listener error:`, e.message);
        if (!done) { done = true; resolve(); }
      });
      this.unsubs.push(unsub);
    });
    this.listening = Promise.all([follow('tables', this.bj), follow('gameTables', this.games)]).then(() => undefined);
    return this.listening;
  }

  async run(durationMs = Infinity): Promise<RunnerStats> {
    await this.listen();
    const end = Date.now() + durationMs;
    try {
      while (!this.stopped && Date.now() < end) {
        const t0 = Date.now();
        await this.tick();
        const wait = this.tickMs - (Date.now() - t0);
        if (wait > 0) await new Promise((r) => setTimeout(r, wait));
      }
      // let background work finish (bounded)
      for (let i = 0; i < 200 && (this.ensuring || this.slowRunning); i++) await new Promise((r) => setTimeout(r, 100));
    } finally {
      this.stop();
    }
    return this.stats;
  }

  /** Tables due now according to the snapshots (a deadline not applied yet is retried a bit later). */
  private dueTables(now: number): string[] {
    const out: string[] = [];
    const check = (id: string, deadline: number | null, force: boolean) => {
      if (!force && (deadline === null || deadline > now)) return;
      const r = this.retry.get(id);
      if (r && r.deadline === deadline && r.at > now) return;
      out.push(id);
    };
    for (const t of this.bj.values()) if (t.status === 'open') check(t.tableId, t.deadlineMs, false);
    for (const t of this.games.values()) if (t.status === 'open') check(t.tableId, t.deadlineMs, !gameModule(t.game).available);
    return out;
  }

  private deadlineOf(id: string): number | null {
    return (gameOfTableId(id) === 'blackjack' ? this.bj.get(id)?.deadlineMs : this.games.get(id)?.deadlineMs) ?? null;
  }

  async tick(): Promise<void> {
    this.stats.ticks++;
    const t0 = Date.now();
    try {
      if (t0 - this.lastEnsure > 3_000 && !this.ensuring) {
        this.lastEnsure = t0;
        this.ensuring = true;
        void this.ensureSimTables()
          .catch((e) => { this.stats.errors++; console.error('sim: ensure tables failed:', (e as Error).message); })
          .finally(() => { this.ensuring = false; });
      }
      const due = this.dueTables(t0);
      const results = await Promise.allSettled(due.map((id) => applyOverdueAny(this.db, id)));
      results.forEach((r, i) => {
        const id = due[i];
        if (r.status === 'fulfilled' && r.value) {
          this.stats.advanced++;
          this.retry.delete(id);
          return;
        }
        if (r.status === 'rejected') {
          this.stats.errors++;
          console.error(`sim: advancing ${id} failed:`, (r.reason as Error)?.message);
        }
        // Not applied (human grace not over, snapshot behind): retry this same deadline later.
        const deadline = this.deadlineOf(id);
        const now = Date.now();
        const at = r.status === 'rejected' ? now + 1_000 : Math.min(Math.max(now + 250, (deadline ?? now) + DECISION_GRACE_MS + 20), now + DECISION_GRACE_MS + 250);
        this.retry.set(id, { deadline, at });
      });
      await this.botTrades();
      if (t0 - this.lastSlow > 10_000 && !this.slowRunning) {
        this.lastSlow = t0;
        this.slowRunning = true;
        void Promise.allSettled([this.payPending(), this.promoteKyc(), this.acceptBotFriends(), this.syncBots(), this.pruneFeed(), datingBotTick(this.db, t0)])
          .then((rs) => {
            for (const x of rs) {
              if (x.status === 'rejected') { this.stats.errors++; console.error('sim: background task failed:', (x.reason as Error)?.message); }
            }
          })
          .finally(() => { this.slowRunning = false; });
      }
    } catch (e) {
      this.stats.errors++;
      console.error('sim tick error:', (e as Error).message);
    } finally {
      this.tickDurations.push(Date.now() - t0);
      if (this.tickDurations.length > 100_000) this.tickDurations.splice(0, 50_000);
    }
  }

  private async ensureSimTables(): Promise<void> {
    const presentBj = new Set([...this.bj.values()].filter((t) => t.simManaged).map((t) => t.tableId));
    if (presentBj.size === 0 && this.games.size === 0 && !(await refs(this.db).profile(BOTS[0].uid).get()).exists) {
      await seed({ historyHands: 3 }); // empty database: full seed
      console.log('sim: database was empty, seeded bots and simulated tables');
      this.seededV2 = true;
      return;
    }
    if (!this.seededV2) {
      // once per run: missing Sprint 2 bots and game tables (idempotent)
      const v2 = await ensureSeedV2(this.db, { gameTablesPerGame: this.perGame });
      this.seededV2 = true;
      if (v2.bots > 0 || v2.tables.length > 0) console.log(`sim: seed v2 added ${v2.bots} bots, game tables ${v2.tables.join(', ') || '-'}`);
    }
    if (this.blackjackSims) {
      for (let i = 0; i < SIM_TABLE_COUNT; i++) {
        if (presentBj.has(simTableId(i))) continue;
        await createSimTable(this.db, i, 2);
        console.log(`sim: (re)created ${simTableId(i)}`);
      }
    }
    const missing = gameSimTableIds(this.perGame).filter((id) => !this.games.has(id));
    if (missing.length > 0) {
      const v2 = await ensureSeedV2(this.db, { gameTablesPerGame: this.perGame, historyRounds: 2 });
      if (v2.tables.length > 0) console.log(`sim: (re)created ${v2.tables.join(', ')}`);
    }
  }

  private async botTrades(): Promise<void> {
    if (nextFloat(this.rng) > 0.5) return;
    const snap = await this.db.collection('markets').where('status', '==', 'open').limit(60).get();
    if (snap.empty) return;
    const picks = Math.min(3, snap.size);
    for (let i = 0; i < picks; i++) {
      const m = snap.docs[this.rng.nextInt(snap.size)].data() as MarketDoc;
      const t = gameOfTableId(m.tableId) === 'blackjack' ? this.bj.get(m.tableId) : this.games.get(m.tableId);
      const bot = BOTS[this.rng.nextInt(BOTS.length)];
      if (t?.seatedUids.includes(bot.uid)) continue; // bots don't bet on their own table either
      if (nextFloat(this.rng) > 0.3 + bot.traderAppetite * 0.7) continue;
      const est = Math.min(0.97, Math.max(0.03, fairEstimate(m, this.bj, this.games) + (nextFloat(this.rng) - 0.5) * 0.2));
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

  /** Bots' `currentTableId` / presence, from the open tables of BOTH collections. */
  private async syncBots(): Promise<void> {
    const r = refs(this.db);
    const where = new Map<string, string>();
    for (const t of this.bj.values()) for (const s of t.seats) if (s?.isBot) where.set(s.uid, t.tableId);
    for (const t of this.games.values()) for (const s of t.seats) if (s?.isBot && !where.has(s.uid)) where.set(s.uid, t.tableId);
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

/** p-th percentile (0..100) of a list of durations (nearest rank). */
export function percentile(values: readonly number[], p: number): number {
  if (values.length === 0) return 0;
  const s = [...values].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.max(0, Math.ceil((p / 100) * s.length) - 1))];
}

if (require.main === module) {
  const arg = (k: string) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split('=')[1];
  const duration = arg('duration') ? Number(arg('duration')) : Infinity;
  const tick = arg('tick') ? Number(arg('tick')) : 500;
  const gt = arg('game-tables');
  const runner = new SimRunner(firestore(), tick, { gameTablesPerGame: gt !== undefined ? gameSimTablesPerGame(gt) : undefined });
  process.on('SIGINT', () => runner.stop());
  process.on('SIGTERM', () => runner.stop());
  console.log(`sim_runner: ticking every ${tick} ms${Number.isFinite(duration) ? ` for ${duration} ms` : ''} (Ctrl+C to stop)`);
  const report = setInterval(() => {
    const s = runner.stats;
    console.log(`sim_runner: ticks=${s.ticks} advanced=${s.advanced} botTrades=${s.trades} errors=${s.errors} tickP95=${percentile(runner.tickDurations.slice(-120), 95)}ms tables=${runner.bj.size}+${runner.games.size}`);
  }, 30_000);
  runner.run(duration).then((s) => {
    clearInterval(report);
    console.log(`sim_runner stopped: ticks=${s.ticks} advanced=${s.advanced} botTrades=${s.trades} errors=${s.errors} tickP95=${percentile(runner.tickDurations, 95)}ms`);
    process.exit(0);
  });
}
