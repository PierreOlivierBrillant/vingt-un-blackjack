/**
 * GameTableMachine — generic table state machine of every kernel-driven game (pure: no Firebase,
 * no clock — `now` and randomness are injected). Modelled on table/machine.ts (blackjack).
 *
 * The kernel owns seats, queue, bots yielding their seat, missed rounds, closing + refunds,
 * events (reset each round, capped), commit/reveal, money effects, settlement bookkeeping and
 * markets; the game itself is a GameModule (./module.ts, which documents the lifecycle and the
 * money rules). Side effects on other documents are returned in `effects` / `boards` and applied
 * by GameTableTx (./tx.ts) in the same transaction.
 *
 * SAFETY: every transition the kernel runs by itself (deadlines, round opening, bots) is wrapped in
 * `auto()`; a debit attempted inside it throws — only a user's own action may debit.
 */
import { commitForSeed } from '../../engine/fair';
import { cryptoRng, newSeedHex, nextFloat, seededRng, type Rng } from '../../engine/rng';
import { fail } from '../../shared/errors';
import {
  GAME_EVENTS_CAP, GAME_MISSED_ROUNDS_LIMIT, GAME_SEATS, GAME_TIMING,
  type BetMap, type GameBetDoc, type GamePhase, type GamePrivateDoc, type GameQueueEntry, type GameSeatDoc,
  type GameTableDoc,
} from '../../shared/games/common';
import { DEALER_OF } from '../../shared/romance';
import {
  DECISION_GRACE_MS, MARKET_LIQUIDITY, type LocalizedText, type MarketDoc, type MarketKind, type RankTier, type StakeTier,
} from '../../shared/types';
import { BOT_BY_UID, gameSimRoster } from '../../sim/profiles';
import type { PlayerInfo } from '../../table/model';
import { gameMarketIds, type GameEffect } from './effects';
import {
  boardTotal, cleanBoard, defaultRankOutcome, type AnyGameModule, type GameAction, type GameCtx, type LockedBoard,
  type MarketScope, type Rec, type SettleInput,
} from './module';

export interface GameDeps {
  /** Bots, churn (never the outcome of a round). */
  rng: Rng;
  /** 32-byte hex seed of a round (CSPRNG in production). */
  newSeed: () => string;
}

export function prodGameDeps(): GameDeps {
  return { rng: cryptoRng(), newSeed: newSeedHex };
}

export interface NewGameTableParams {
  tableId: string;
  name: string;
  stakeTier: StakeTier;
  isPrivate: boolean;
  simManaged: boolean;
  rankTier: RankTier;
  code?: string | null;
}

export function newGameTableState(module: AnyGameModule, p: NewGameTableParams, now: number): { pub: GameTableDoc; priv: GamePrivateDoc } {
  const limits = module.limits(p.stakeTier);
  const init = module.init({ tableId: p.tableId, stakeTier: p.stakeTier, isPrivate: p.isPrivate, simManaged: p.simManaged, limits });
  const pub: GameTableDoc = {
    tableId: p.tableId, game: module.game, name: p.name, stakeTier: p.stakeTier, limits, isPrivate: p.isPrivate,
    simManaged: p.simManaged, status: 'open', phase: 'idle', step: null, phaseStartedAtMs: now, deadlineMs: null, round: 0,
    turn: null, seats: Array.from({ length: GAME_SEATS[module.game] }, () => null), queue: [], seatedUids: [],
    humanCount: 0, botCount: 0, rankTier: p.rankTier, dealer: { characterId: DEALER_OF[module.game] },
    fairness: { currentCommit: null, currentHandNumber: 0, lastHandNumber: null, lastCommit: null, lastSeed: null },
    events: [], eventSeq: 0, markets: { round: {}, series: {} }, g: init.g, createdAtMs: now, updatedAtMs: now,
  };
  const priv: GamePrivateDoc = { seed: null, commit: null, roundStartedAtMs: null, code: p.code ?? null, g: init.priv };
  return { pub, priv };
}

const isHumanActive = (s: GameSeatDoc | null | undefined): s is GameSeatDoc => !!s && !s.isBot && s.status === 'active';

export interface LeaveResult { refundedCents: number; cashOutCents: number; deferred: boolean }

export class GameTableMachine {
  readonly effects: GameEffect[] = [];
  /** Bet boards changed in this transaction (written or deleted by GameTableTx). */
  readonly dirtyBoards = new Set<string>();
  changed = false;
  readonly ctx: GameCtx;
  private autoDepth = 0;
  /** Incremented by every phase change (detects a module that forgot to set one). */
  private phaseWrites = 0;
  private readonly closedNow = new Set<string>();

  constructor(
    public pub: GameTableDoc,
    public priv: GamePrivateDoc,
    /** Bet boards of the seated uids (bet-board games), uid → doc. Absent = empty board. */
    public boards: Map<string, GameBetDoc>,
    readonly module: AnyGameModule,
    private readonly deps: GameDeps,
    public now: number,
  ) {
    this.ctx = this.makeCtx();
  }

  // ------------------------------------------------------------------------------------------
  // module context

  private makeCtx(): GameCtx {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const m = this;
    return {
      get game() { return m.pub.game; },
      get now() { return m.now; },
      get table() { return m.pub; },
      get priv() { return m.priv; },
      get limits() { return m.pub.limits; },
      get rng() { return m.deps.rng; },
      get seed() { return m.priv.seed; },
      fairRng: () => {
        if (!m.priv.seed) throw new Error('kernel: no round seed');
        return seededRng(m.priv.seed);
      },
      botProfile: (uid) => BOT_BY_UID.get(uid) ?? null,
      seats: () => m.occupied(),
      board: (uid) => m.boardOf(uid),
      setPhase: (phase, deadlineMs, step) => {
        if (phase !== 'betting' && phase !== 'live') throw new Error(`kernel: setPhase(${phase as string}) not allowed`);
        if (!Number.isFinite(deadlineMs)) throw new Error('kernel: setPhase needs a deadline');
        m.setPhase(phase, deadlineMs, step);
      },
      setStep: (step) => { m.pub.step = step; m.changed = true; },
      setTurn: (seatIndex) => {
        if (seatIndex !== null && !m.pub.seats[seatIndex]) throw new Error('kernel: turn on an empty seat');
        m.pub.turn = seatIndex === null ? null : { seatIndex };
        m.changed = true;
      },
      event: (type, seatIndex, d) => m.event(type, seatIndex, d ?? null),
      botDelayMs: () => GAME_TIMING.botMinMs + m.deps.rng.nextInt(GAME_TIMING.botMaxMs - GAME_TIMING.botMinMs + 1),
      settle: (input) => m.settleRound(input),
      idle: () => m.idle(),
      secret: (uid, cards) => {
        m.effects.push({ kind: 'secret', uid, doc: { round: m.pub.round, cards: [...cards], createdAtMs: m.now } });
      },
      removeSeat: (seatIndex) => m.removeSeatAt(seatIndex),
      markets: {
        create: (scope, kind, question, opts) => m.marketCreate(scope, kind, question, opts?.series),
        close: (scope, kind) => m.marketSet(scope, kind, 'closed', null),
        resolve: (scope, kind, outcome) => m.marketSet(scope, kind, 'resolved', outcome),
        void: (scope, kind) => m.marketSet(scope, kind, 'void', null),
        id: (scope, kind) => m.pub.markets[scope][kind] ?? null,
      },
    };
  }

  /** Runs a transition the kernel drives by itself: debits are forbidden inside. */
  private auto<T>(fn: () => T): T {
    this.autoDepth++;
    try {
      return fn();
    } finally {
      this.autoDepth--;
    }
  }

  // ------------------------------------------------------------------------------------------
  // helpers

  get game() {
    return this.pub.game;
  }

  occupied(): GameSeatDoc[] {
    return this.pub.seats.filter((s): s is GameSeatDoc => s !== null);
  }

  seatOf(uid: string): GameSeatDoc | null {
    return this.pub.seats.find((s) => s?.uid === uid) ?? null;
  }

  isQueued(uid: string): boolean {
    return this.pub.queue.some((q) => q.uid === uid);
  }

  boardOf(uid: string): BetMap {
    return this.boards.get(uid)?.bets ?? {};
  }

  private setBoard(seat: Pick<GameSeatDoc, 'uid' | 'seatIndex' | 'isBot'>, bets: BetMap, opts: { previous?: BetMap; power?: GameBetDoc['power'] } = {}): void {
    const cur = this.boards.get(seat.uid);
    const clean = cleanBoard(bets);
    const doc: GameBetDoc = {
      uid: seat.uid, seatIndex: seat.seatIndex, isBot: seat.isBot, round: this.pub.round, bets: clean,
      totalCents: boardTotal(clean), power: opts.power !== undefined ? opts.power : cur?.power ?? null,
      previous: opts.previous ?? cur?.previous ?? {}, updatedAtMs: this.now,
    };
    this.boards.set(seat.uid, doc);
    this.dirtyBoards.add(seat.uid);
  }

  private deleteBoard(uid: string): void {
    if (!this.boards.has(uid)) return;
    this.boards.delete(uid);
    this.dirtyBoards.add(uid);
  }

  private debit(uid: string, cents: number, ledger: 'bet' | 'buyIn'): void {
    if (this.autoDepth > 0) throw new Error('kernel: a transition run by the kernel (deadline, bots) must never debit');
    if (!Number.isSafeInteger(cents) || cents < 0) throw new Error('kernel: bad debit');
    if (cents === 0) return;
    this.effects.push({ kind: 'debit', uid, cents, ledger, round: this.pub.round });
  }

  private credit(uid: string, cents: number, ledger: 'payout' | 'refund' | 'cashOut'): void {
    if (!Number.isSafeInteger(cents) || cents < 0) throw new Error('kernel: bad credit');
    if (cents === 0) return;
    this.effects.push({ kind: 'credit', uid, cents, ledger, round: this.pub.round });
  }

  private event(type: string, seatIndex: number | null, d: Rec | null = null): void {
    this.pub.eventSeq += 1;
    this.pub.events.push({ seq: this.pub.eventSeq, type, seatIndex, atMs: this.now, d });
    if (this.pub.events.length > GAME_EVENTS_CAP) this.pub.events.splice(0, this.pub.events.length - GAME_EVENTS_CAP);
    this.changed = true;
  }

  private setPhase(phase: GamePhase, deadline: number | null, step?: string | null): void {
    this.phaseWrites++;
    if (this.pub.phase !== phase) this.pub.phaseStartedAtMs = this.now;
    this.pub.phase = phase;
    this.pub.deadlineMs = deadline;
    if (step !== undefined) this.pub.step = step;
    this.changed = true;
  }

  private idle(): void {
    this.pub.turn = null;
    this.setPhase('idle', null, null);
  }

  private refreshCounts(): void {
    const seats = this.occupied();
    this.pub.humanCount = seats.filter((s) => !s.isBot).length;
    this.pub.botCount = seats.filter((s) => s.isBot).length;
    this.pub.seatedUids = seats.map((s) => s.uid);
    this.pub.updatedAtMs = this.now;
  }

  private freeSeat(): number | null {
    const i = this.pub.seats.findIndex((s) => s === null);
    return i < 0 ? null : i;
  }

  private canChangeSeatsNow(): boolean {
    const p = this.pub.phase;
    return p === 'idle' || p === 'settled' || (p === 'betting' && this.module.money === 'board');
  }

  /** Last bot seat (bots yield to humans). */
  private yieldableBot(): number | null {
    for (let i = this.pub.seats.length - 1; i >= 0; i--) if (this.pub.seats[i]?.isBot) return i;
    return null;
  }

  /** Whether a human could get a seat or a queue slot here. */
  hasRoomForHuman(): boolean {
    if (this.pub.status !== 'open' || !this.module.available) return false;
    if (this.freeSeat() !== null) return true;
    if (this.pub.isPrivate) return false;
    return this.pub.botCount > this.pub.queue.length;
  }

  /** Grace after the displayed deadline when a human decision is pending (see DECISION_GRACE_MS). */
  graceMs(): number {
    const p = this.pub;
    switch (p.phase) {
      case 'betting':
        return this.occupied().some(isHumanActive) ? DECISION_GRACE_MS : 0;
      case 'live':
        return p.turn && isHumanActive(p.seats[p.turn.seatIndex]) ? DECISION_GRACE_MS : 0;
      default:
        return 0;
    }
  }

  private assertPhase(): void {
    const p = this.pub;
    if (p.status !== 'open') return;
    if ((p.phase === 'betting' || p.phase === 'live' || p.phase === 'settled') && (p.deadlineMs === null || !Number.isFinite(p.deadlineMs))) {
      throw new Error(`kernel: ${p.game} left phase ${p.phase} without a deadline`);
    }
  }

  private botBuyIn(uid: string): number {
    const bot = BOT_BY_UID.get(uid);
    const lim = this.pub.limits;
    const v = bot && this.module.botBuyInCents ? this.module.botBuyInCents(lim, bot) : lim.extra.maxBuyInCents ?? 0;
    return Math.max(0, Math.floor(v / 100) * 100);
  }

  private newSeat(p: PlayerInfo, idx: number, stack: number | null): GameSeatDoc {
    const seat: GameSeatDoc = {
      seatIndex: idx, uid: p.uid, username: p.username, avatar: p.avatar, isBot: p.isBot, rankTier: p.rankTier,
      status: 'active', joinedAtMs: this.now, missedRounds: 0, stakeCents: 0,
      stackCents: this.module.money === 'stack' ? stack ?? 0 : null, powerUsed: null, roundNetCents: null, g: {},
    };
    seat.g = this.module.seatInit(this.ctx, seat);
    return seat;
  }

  private place(p: PlayerInfo, idx: number, stack: number | null): void {
    this.pub.seats[idx] = this.newSeat(p, idx, stack);
    this.event('join', idx);
    if (!p.isBot) this.effects.push({ kind: 'location', uid: p.uid, tableId: this.pub.tableId });
    this.refreshCounts();
    this.changed = true;
  }

  /** Removes a seat: refunds what is left on its board (humans), cashes out its stack (humans). */
  removeSeatAt(idx: number): void {
    const s = this.pub.seats[idx];
    if (!s) return;
    const b = this.boards.get(s.uid);
    if (b) {
      if (!s.isBot && b.totalCents > 0) this.credit(s.uid, b.totalCents, 'refund');
      this.deleteBoard(s.uid);
    }
    if (!s.isBot && s.stackCents !== null && s.stackCents > 0) this.credit(s.uid, s.stackCents, 'cashOut');
    s.stackCents = s.stackCents === null ? null : 0;
    this.pub.seats[idx] = null;
    if (this.pub.turn?.seatIndex === idx) this.pub.turn = null;
    this.event('leave', idx);
    // A 'leaving' human already had their location cleared (they may be seated elsewhere now).
    if (!s.isBot && s.status !== 'leaving') this.effects.push({ kind: 'location', uid: s.uid, tableId: null });
    this.refreshCounts();
    this.changed = true;
  }

  // ------------------------------------------------------------------------------------------
  // seating

  /** Seats (or queues) a player. Bots yield their seat to humans. Hold'em: `buyInCents` debited now. */
  join(p: PlayerInfo, buyInCents: number | null = null): { status: 'seated' | 'queued'; seatIndex: number | null } {
    if (this.pub.status !== 'open') throw fail.pre('TABLE_CLOSED');
    if (!this.module.available) throw fail.pre('FEATURE_UNAVAILABLE');
    const existing = this.seatOf(p.uid);
    if (existing) {
      if (existing.status === 'leaving') {
        // came back before the round they left was over: keep the seat (and its stack)
        existing.status = 'active';
        if (!p.isBot) this.effects.push({ kind: 'location', uid: p.uid, tableId: this.pub.tableId });
        this.changed = true;
      }
      return { status: 'seated', seatIndex: existing.seatIndex };
    }
    if (this.isQueued(p.uid)) return { status: 'queued', seatIndex: null };
    let stack: number | null = null;
    if (this.module.money === 'stack') {
      if (p.isBot) stack = this.botBuyIn(p.uid);
      else {
        const min = this.pub.limits.extra.minBuyInCents ?? 0;
        const max = this.pub.limits.extra.maxBuyInCents ?? 0;
        if (buyInCents === null || !Number.isSafeInteger(buyInCents) || buyInCents % 100 !== 0 || buyInCents < min || buyInCents > max) {
          throw fail.invalid('BUY_IN_OUT_OF_RANGE');
        }
        stack = buyInCents;
      }
    }
    let idx = this.freeSeat();
    if (idx === null && !p.isBot && !this.pub.isPrivate && this.canChangeSeatsNow()) {
      const b = this.yieldableBot();
      if (b !== null) {
        this.removeSeatAt(b);
        idx = b;
      }
    }
    if (idx !== null) {
      if (!p.isBot && stack) this.debit(p.uid, stack, 'buyIn');
      this.place(p, idx, stack);
      // Bots seated first on a fresh matchmaking table must not open (and close) it.
      if (this.pub.phase === 'idle' && (this.pub.simManaged || this.pub.humanCount > 0)) this.openRound();
      return { status: 'seated', seatIndex: idx };
    }
    if (p.isBot || this.pub.isPrivate || !this.hasRoomForHuman()) throw fail.pre('TABLE_FULL');
    if (stack) this.debit(p.uid, stack, 'buyIn');
    const q: GameQueueEntry = {
      uid: p.uid, username: p.username, avatar: p.avatar, rankTier: p.rankTier, queuedAtMs: this.now, buyInCents: stack,
    };
    this.pub.queue.push(q);
    this.effects.push({ kind: 'location', uid: p.uid, tableId: this.pub.tableId });
    this.changed = true;
    return { status: 'queued', seatIndex: null };
  }

  /** Leaves the seat or the queue. Unlocked bets are refunded; the stack is cashed out (deferred mid-round). */
  leave(uid: string): LeaveResult {
    const qi = this.pub.queue.findIndex((q) => q.uid === uid);
    if (qi >= 0) {
      const [q] = this.pub.queue.splice(qi, 1);
      const cash = q.buyInCents ?? 0;
      this.credit(uid, cash, 'cashOut');
      this.effects.push({ kind: 'location', uid, tableId: null });
      this.changed = true;
      this.maybeClose();
      return { refundedCents: 0, cashOutCents: cash, deferred: false };
    }
    const seat = this.seatOf(uid);
    if (!seat) throw fail.pre('NOT_SEATED');
    if (seat.status === 'leaving') return { refundedCents: 0, cashOutCents: 0, deferred: true };
    const unlocked = this.pub.phase !== 'live';
    const board = this.boardOf(uid);
    let refund = 0;
    const kept = this.module.onLeaving(this.ctx, seat, { ...board }, unlocked);
    if (this.module.money === 'board' && unlocked) {
      const keep = cleanBoard(kept);
      for (const [spot, v] of Object.entries(keep)) {
        if (!Number.isSafeInteger(v) || v < 0 || v > (board[spot] ?? 0)) throw new Error('kernel: onLeaving may only remove bets');
      }
      refund = boardTotal(board) - boardTotal(keep);
      if (refund > 0) {
        this.credit(uid, refund, 'refund');
        this.setBoard(seat, keep);
      }
    }
    this.effects.push({ kind: 'location', uid, tableId: null });
    seat.status = 'leaving';
    let cash = 0;
    if (this.module.seatClear(this.ctx, seat, this.boardOf(uid))) {
      cash = seat.stackCents ?? 0;
      this.removeSeatAt(seat.seatIndex);
    } else {
      this.event('leave', seat.seatIndex, { pending: true });
    }
    this.changed = true;
    this.maybeClose();
    return { refundedCents: refund, cashOutCents: cash, deferred: this.seatOf(uid) !== null };
  }

  /** Non-simulated tables close when no human is left (once nothing of theirs is in play). */
  private maybeClose(): void {
    if (this.pub.simManaged || this.pub.status !== 'open') return;
    const humans = this.occupied().filter((s) => !s.isBot);
    if (humans.some((s) => s.status !== 'leaving') || this.pub.queue.length > 0) return;
    if (!humans.every((s) => this.module.seatClear(this.ctx, s, this.boardOf(s.uid)))) return;
    this.closeTable();
  }

  /** Closes the table: every human's board refunded, stacks and queued buy-ins cashed out, markets voided. */
  closeTable(): void {
    if (this.pub.status !== 'open') return;
    this.auto(() => {
      if (this.module.available && this.module.onClose) {
        try {
          this.module.onClose(this.ctx);
        } catch {
          /* resolution is best effort: whatever is left is voided below */
        }
      }
      for (let i = 0; i < this.pub.seats.length; i++) if (this.pub.seats[i]) this.removeSeatAt(i);
      for (const q of this.pub.queue) {
        this.credit(q.uid, q.buyInCents ?? 0, 'cashOut');
        this.effects.push({ kind: 'location', uid: q.uid, tableId: null });
      }
      this.pub.queue = [];
      for (const scope of ['round', 'series'] as const) {
        for (const kind of Object.keys(this.pub.markets[scope]) as MarketKind[]) this.marketSet(scope, kind, 'void', null);
      }
      this.pub.markets = { round: {}, series: {} };
      this.pub.status = 'closed';
      this.pub.turn = null;
      this.setPhase('closed', null, null);
      this.refreshCounts();
    });
  }

  // ------------------------------------------------------------------------------------------
  // markets

  private marketCreate(scope: MarketScope, kind: MarketKind, question: LocalizedText, series?: number): string | null {
    if (scope === 'series' && !this.pub.simManaged) return null;
    const map = this.pub.markets[scope];
    const existing = map[kind];
    if (existing) return existing;
    const t = this.pub;
    const id = scope === 'round' ? gameMarketIds.round(t.tableId, t.round, kind) : gameMarketIds.series(t.tableId, series ?? t.round, kind);
    const market: MarketDoc = {
      marketId: id, tableId: t.tableId, tableName: t.name, game: t.game, humanTradeCount: 0, kind,
      handNumber: scope === 'round' ? t.round : null, shoeNumber: series ?? 0, subjectUid: null, subjectUsername: null,
      subjectSeatIndex: null, question, status: 'open', outcome: null, b: MARKET_LIQUIDITY[kind], qYes: 0, qNo: 0,
      priceYes: 0.5, volumeCents: 0, tradeCount: 0, payoutsDone: false, createdAtMs: this.now, closedAtMs: null,
      resolvedAtMs: null,
    };
    this.effects.push({ kind: 'marketCreate', market });
    map[kind] = id;
    this.changed = true;
    return id;
  }

  private marketSet(scope: MarketScope, kind: MarketKind, status: 'closed' | 'resolved' | 'void', outcome: 'yes' | 'no' | null): void {
    const map = this.pub.markets[scope];
    const id = map[kind];
    if (!id) return;
    if (status === 'closed') {
      if (this.closedNow.has(id)) return;
      this.closedNow.add(id);
    } else {
      delete map[kind];
    }
    this.effects.push({ kind: 'marketStatus', marketId: id, status, outcome });
    this.changed = true;
  }

  // ------------------------------------------------------------------------------------------
  // rounds

  /** Sim tables: bots come and go a little; humans keep priority. */
  private simChurn(): void {
    if (!this.pub.simManaged) return;
    const roster = gameSimRoster(this.pub.tableId);
    if (!roster) return;
    const seated = this.occupied();
    const bots = seated.filter((s) => s.isBot && this.module.seatClear(this.ctx, s, this.boardOf(s.uid)));
    const maxSeated = Math.max(2, this.pub.seats.length - 2);
    const r = nextFloat(this.deps.rng);
    if (r < 0.12 && this.pub.botCount > 2 && bots.length > 0) {
      this.removeSeatAt(bots[this.deps.rng.nextInt(bots.length)].seatIndex);
    } else if ((r > 0.75 || seated.length < 2) && this.freeSeat() !== null && this.pub.queue.length === 0 && seated.length < maxSeated) {
      const out = roster.filter((b) => !this.seatOf(b.uid));
      if (out.length > 0) {
        const b = out[this.deps.rng.nextInt(out.length)];
        const info: PlayerInfo = { uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true };
        this.place(info, this.freeSeat()!, this.module.money === 'stack' ? this.botBuyIn(b.uid) : null);
      }
    }
  }

  private seatQueue(): void {
    while (this.pub.queue.length > 0) {
      let idx = this.freeSeat();
      if (idx === null) {
        const b = this.yieldableBot();
        if (b === null) break;
        this.removeSeatAt(b);
        idx = b;
      }
      const q = this.pub.queue.shift()!;
      this.place({ uid: q.uid, username: q.username, avatar: q.avatar, rankTier: q.rankTier, isBot: false }, idx, q.buyInCents);
    }
  }

  /** Removes leaving seats and inactive humans whose seat is clear. */
  private cleanupSeats(): void {
    for (const s of this.occupied()) {
      const inactive = !s.isBot && s.status !== 'leaving' && s.missedRounds >= GAME_MISSED_ROUNDS_LIMIT;
      if ((s.status === 'leaving' || inactive) && this.module.seatClear(this.ctx, s, this.boardOf(s.uid))) this.removeSeatAt(s.seatIndex);
    }
  }

  /** Opens a new round (see module.ts header). */
  openRound(): void {
    this.auto(() => {
      this.cleanupSeats();
      if (!this.pub.simManaged) {
        this.maybeClose();
        if (this.pub.status !== 'open') return;
      }
      this.simChurn();
      this.seatQueue();
      for (const kind of Object.keys(this.pub.markets.round) as MarketKind[]) this.marketSet('round', kind, 'void', null);
      this.pub.markets.round = {};
      this.pub.events = [];
      this.pub.turn = null;
      for (const s of this.occupied()) {
        s.stakeCents = 0;
        s.powerUsed = null;
        s.roundNetCents = null;
      }
      this.refreshCounts();
      if (this.occupied().length === 0 || !(this.module.canStart ? this.module.canStart(this.ctx) : true)) {
        this.idle();
        return;
      }
      const t = this.pub;
      t.round += 1;
      this.priv.seed = this.deps.newSeed();
      this.priv.commit = commitForSeed(this.priv.seed);
      this.priv.roundStartedAtMs = this.now;
      t.fairness.currentCommit = this.priv.commit;
      t.fairness.currentHandNumber = t.round;
      t.step = null;
      t.deadlineMs = null;
      this.changed = true;
      const writes = this.phaseWrites;
      this.module.openRound(this.ctx);
      if (this.phaseWrites === writes) throw new Error(`kernel: ${t.game} openRound must set the phase (ctx.setPhase / settle / idle)`);
      this.maybeClose(); // the module may have removed the last human (e.g. sitting out too long)
      if (this.pub.phase === 'idle' || this.pub.phase === 'closed') return;
      this.assertPhase();
      if (this.pub.phase === 'betting' && this.module.money === 'board') this.botsBet();
    });
  }

  private botsBet(): void {
    for (const s of this.occupied()) {
      if (!s.isBot || s.status !== 'active') continue;
      let mv;
      try {
        mv = this.module.bot(this.ctx, s, 'bets');
      } catch {
        mv = null;
      }
      if (!mv || mv.kind !== 'bets') continue;
      try {
        const next = cleanBoard(this.module.validateBets(this.ctx, s, cleanBoard(mv.bets), this.boardOf(s.uid)));
        const total = boardTotal(next);
        const lim = this.pub.limits;
        if (Object.values(next).some((v) => !Number.isSafeInteger(v) || v < 0 || v % 100 !== 0)) continue;
        if ((total > 0 && total < lim.minBetCents) || total > lim.maxRoundCents) continue;
        this.setBoard(s, next, { power: null });
      } catch {
        /* an invalid bot board is simply not placed */
      }
    }
  }

  /** Betting deadline of a bet-board game: re-read boards, lock them, run the round. */
  private closeBetting(): void {
    const seats = this.occupied();
    const locked: LockedBoard[] = [];
    for (const s of seats) {
      const b = this.boards.get(s.uid);
      if (b && b.totalCents > 0) locked.push({ seatIndex: s.seatIndex, uid: s.uid, isBot: s.isBot, bets: { ...b.bets }, totalCents: b.totalCents, power: b.power });
    }
    // A private table whose players all skip is waiting for friends: such rounds do not count.
    if (locked.length > 0 || !this.pub.isPrivate) {
      for (const s of seats) {
        if (!s.isBot && s.status === 'active') s.missedRounds = (this.boards.get(s.uid)?.totalCents ?? 0) > 0 ? 0 : s.missedRounds + 1;
      }
    }
    if (locked.length === 0) {
      this.cleanupSeats();
      if (!this.pub.simManaged) this.maybeClose();
      if (this.pub.status !== 'open') return;
      if (this.occupied().length === 0) { this.idle(); return; }
      const last = (this.pub.deadlineMs ?? this.now) - this.pub.phaseStartedAtMs;
      const dur = last >= 1_000 ? last : GAME_TIMING.bettingMs;
      this.pub.phaseStartedAtMs = this.now;
      this.setPhase('betting', this.now + dur);
      this.botsBet();
      return;
    }
    for (const s of seats) {
      const b = this.boards.get(s.uid);
      s.stakeCents = b?.totalCents ?? 0;
      s.powerUsed = b?.power ?? null;
    }
    this.changed = true;
    this.module.closeBetting(this.ctx, locked);
    this.assertPhase();
  }

  /** Snapshot/restore around a bot move: a throwing move must leave no trace. */
  private atomic(fn: () => void): boolean {
    const pub = structuredClone(this.pub);
    const priv = structuredClone(this.priv);
    const boards = new Map([...this.boards].map(([k, v]) => [k, structuredClone(v)]));
    const dirty = new Set(this.dirtyBoards);
    const nEffects = this.effects.length;
    try {
      fn();
      return true;
    } catch {
      this.pub = pub;
      this.priv = priv;
      this.boards = boards;
      this.dirtyBoards.clear();
      for (const d of dirty) this.dirtyBoards.add(d);
      this.effects.length = nEffects;
      return false;
    }
  }

  private liveDeadline(): void {
    const t = this.pub.turn;
    const seat = t ? this.pub.seats[t.seatIndex] : null;
    if (seat && seat.isBot && seat.status === 'active') {
      const played = this.atomic(() => {
        const mv = this.module.bot(this.ctx, seat, 'turn');
        if (!mv || mv.kind !== 'action') throw new Error('no bot move');
        const a = this.module.actionSchema.parse(mv.action);
        this.module.act(this.ctx, this.pub.seats[t!.seatIndex]!, a);
      });
      if (played) return;
    }
    this.module.onDeadline(this.ctx);
  }

  /** Applies every transition that is due at `now`. Returns true if something changed. */
  advance(): boolean {
    const start = this.changed;
    this.changed = false;
    let any = false;
    if (this.pub.status === 'open' && !this.module.available) {
      // The game was withdrawn: close and refund everything (locked boards included).
      this.closeTable();
      this.changed = true;
      return true;
    }
    for (let guard = 0; guard < 60; guard++) {
      const p = this.pub;
      if (p.status !== 'open' || p.deadlineMs === null || p.deadlineMs + this.graceMs() > this.now) break;
      this.auto(() => {
        switch (p.phase) {
          case 'idle':
          case 'settled':
            this.openRound();
            break;
          case 'betting':
            if (this.module.money === 'board') this.closeBetting();
            else this.module.onDeadline(this.ctx);
            break;
          case 'live':
            this.liveDeadline();
            break;
          default:
            p.deadlineMs = null;
        }
        if (this.pub.phase !== 'live') this.maybeClose(); // a module may have removed the last human
        this.assertPhase();
      });
      any = true;
    }
    this.changed = start || this.changed || any;
    return any;
  }

  // ------------------------------------------------------------------------------------------
  // player actions (full path; setBets uses the fast path in ./bets.ts)

  /** A game action or sitOut/sitIn of `uid`. Returns the cents to debit (already pushed as an effect) and module data. */
  action(uid: string, round: number, raw: GameAction): { debitCents: number; data: Rec | null } {
    if (this.pub.status !== 'open') throw fail.pre('TABLE_CLOSED');
    if (!this.module.available) throw fail.pre('FEATURE_UNAVAILABLE');
    if (raw.type === 'setBets') throw fail.pre('ILLEGAL_ACTION', 'setBets uses its own path');
    if (round !== this.pub.round) throw fail.pre('STALE_HAND');
    const seat = this.seatOf(uid);
    if (!seat || seat.status === 'leaving') throw fail.pre('NOT_SEATED');
    if (raw.type === 'sitOut' || raw.type === 'sitIn') {
      this.sit(seat, raw.type === 'sitOut');
      return { debitCents: 0, data: null };
    }
    const a = this.module.actionSchema.parse(raw);
    const out = this.module.act(this.ctx, seat, a) ?? {};
    const cents = out.debitCents ?? 0;
    if (!Number.isSafeInteger(cents) || cents < 0) throw new Error('kernel: bad debitCents');
    if (cents > 0 && !seat.isBot) this.debit(uid, cents, out.ledger ?? 'bet');
    this.changed = true;
    this.assertPhase();
    return { debitCents: seat.isBot ? 0 : cents, data: out.data ?? null };
  }

  private sit(seat: GameSeatDoc, out: boolean): void {
    const hook = out ? this.module.onSitOut : this.module.onSitIn;
    if (!hook) throw fail.pre('ILLEGAL_ACTION');
    if (out && seat.status === 'active') {
      seat.status = 'sittingOut';
      hook.call(this.module, this.ctx, seat);
      this.event('sitOut', seat.seatIndex);
    } else if (!out && seat.status === 'sittingOut') {
      seat.status = 'active';
      seat.missedRounds = 0;
      hook.call(this.module, this.ctx, seat);
      this.event('sitIn', seat.seatIndex);
      if (this.pub.phase === 'idle') this.openRound();
    }
    this.changed = true;
  }

  // ------------------------------------------------------------------------------------------
  // settlement

  private settleRound(input: SettleInput): void {
    const t = this.pub;
    const rows = input.rows;
    const seen = new Set<string>();
    for (const r of rows) {
      const seat = this.seatOf(r.uid);
      if (!seat || seat.seatIndex !== r.seatIndex) throw new Error(`kernel: settlement row for an absent seat (${r.uid})`);
      for (const v of [r.stakedCents, r.returnCents]) if (!Number.isSafeInteger(v) || v < 0) throw new Error('kernel: bad settlement amount');
      if (r.netCents !== r.returnCents - r.stakedCents) throw new Error('kernel: netCents must equal returnCents - stakedCents');
      if (seen.has(r.uid)) throw new Error('kernel: two settlement rows for one seat');
      seen.add(r.uid);
    }
    if (this.module.money === 'board') {
      for (const s of this.occupied()) {
        const b = this.boards.get(s.uid);
        const before = b?.bets ?? {};
        const bt = boardTotal(before);
        const carry = cleanBoard(input.carry?.[s.uid] ?? {});
        if (Object.values(carry).some((v) => !Number.isSafeInteger(v) || v < 0 || v % 100 !== 0)) throw new Error('kernel: bad carry');
        const ct = boardTotal(carry);
        if (ct > bt) throw new Error('kernel: carry exceeds the board (winnings are paid to the wallet)');
        const row = rows.find((r) => r.uid === s.uid);
        const resolved = bt - ct;
        if (row && row.stakedCents !== resolved) throw new Error('kernel: row stake must equal the money leaving the board');
        if (!row && resolved > 0) throw new Error('kernel: money left a board without a settlement row');
        if (row && row.returnCents > 0 && !s.isBot) this.credit(s.uid, row.returnCents, 'payout');
        if (bt > 0 || ct > 0 || b?.power) this.setBoard(s, carry, { previous: before, power: null });
      }
    }
    for (const r of rows) {
      const seat = this.seatOf(r.uid)!;
      seat.roundNetCents = r.netCents;
    }
    const lim = t.limits;
    this.effects.push({
      kind: 'settle', round: t.round,
      rows: rows.map((r) => ({
        ...r,
        outcome: this.module.rank ? this.module.rank(r, lim) : defaultRankOutcome(r),
        affinity: !r.isBot && (this.module.countsForAffinity ? this.module.countsForAffinity(r, lim) : r.stakedCents >= lim.minBetCents),
      })),
    });
    for (const r of rows) {
      if (r.netCents >= 10_000 || (r.highlight === 'jackpot' && r.netCents > 0)) {
        this.effects.push({
          kind: 'feed',
          entry: {
            username: r.username, avatar: r.avatar, isBot: r.isBot, kind: r.highlight === 'jackpot' ? 'jackpot' : 'bigWin',
            amountCents: r.netCents, tableId: t.tableId, createdAtMs: this.now, game: t.game,
          },
        });
      }
    }
    this.effects.push({
      kind: 'history',
      doc: {
        tableId: t.tableId, game: t.game, round: t.round, startedAtMs: this.priv.roundStartedAtMs ?? this.now, endedAtMs: this.now,
        seats: rows.map((r) => ({ seatIndex: r.seatIndex, uid: r.uid, username: r.username, isBot: r.isBot, stakedCents: r.stakedCents, netCents: r.netCents })),
        result: input.result,
        fairness: {
          commit: this.priv.commit ?? '', seed: this.priv.seed ?? '', remainingBefore: input.fairness.remainingBefore,
          dealt: input.fairness.dealt, decks: input.fairness.decks,
        },
      },
    });
    t.fairness.lastHandNumber = t.round;
    t.fairness.lastCommit = this.priv.commit;
    t.fairness.lastSeed = this.priv.seed;
    t.turn = null;
    this.setPhase('settled', this.now + (input.settledMs ?? GAME_TIMING.settledMs));
  }
}
