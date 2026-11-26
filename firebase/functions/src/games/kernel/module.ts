/**
 * ============================================================================================
 *  GameModule — what each kernel-driven game provides (roulette, baccarat, hold'em, craps).
 * ============================================================================================
 *
 * The kernel (GameTableMachine, ./machine.ts) owns everything that is common to every game:
 * seats, queue, bots yielding their seat, missed rounds, closing and refunds, events (reset at
 * each round, capped at GAME_EVENTS_CAP), provably-fair commit/reveal, money movements (wallet
 * debits/credits, bet boards, stacks), settlement bookkeeping (profile gameStats, rank points with
 * the anti-farming rule and daily cap, feed, Rendez-vous table affinity), spectator markets
 * (creation, closing, resolution, voiding) and the round history document. A module only says
 * what its game does at each step, through the `GameCtx` it receives. A module is pure: no
 * Firebase, no clock (use `ctx.now`), no Math.random (use `ctx.rng` / `ctx.fairRng()`).
 *
 * ROUND LIFECYCLE (kernel phases, see shared/games/common.ts)
 *   idle ──join / sitIn──▶ openRound ──▶ betting ──deadline──▶ closeBetting ──▶ live ──deadlines──▶ settle ──▶ settled ──deadline──▶ openRound …
 *  1. openRound (kernel): removes leaving/inactive seats that are clear, closes a non-simulated
 *     table without humans, sim churn, seats the queue (bots yield), asks `canStart`, then
 *     round += 1, new seed + commit, events reset, per-round markets reset. Then `module.openRound`
 *     MUST set the phase: `ctx.setPhase('betting', deadline)` (bet-board games, bots then get
 *     `bot(…,'bets')`) or `ctx.setPhase('live', deadline)` (hold'em: blinds, deal, first turn),
 *     or call `ctx.idle()`.
 *  2. betting (bet-board games): humans send whole boards through `gameAction setBets` (fast path,
 *     only `bets/{uid}` and the wallet are written: `validateBets` and `power` see a read-only
 *     view). At the deadline (+ DECISION_GRACE_MS when a human is seated) the kernel re-reads every
 *     board in the same transaction; if every board is empty betting simply restarts (same round),
 *     otherwise seats get `stakeCents`/`powerUsed`, missed rounds are counted and
 *     `module.closeBetting(ctx, lockedBoards)` runs the round (draw, deal…) and sets the next phase.
 *  3. live: every deadline calls `module.onDeadline(ctx)`, except when `table.turn` points at an
 *     active bot: the kernel then asks `bot(ctx, seat, 'turn')` and plays it through `act` (a bot
 *     plays by the same rules as a human; if its move throws, `onDeadline` is used instead).
 *     Human actions arrive through `act` (gameAction, validated first by `actionSchema`).
 *  4. `ctx.settle(input)` ends the round: wallet credits (bet-board games: `returnCents` of each
 *     row; hold'em: none, the module moved chips between stacks itself), boards replaced by
 *     `carry`, stats, rank, feed, affinity, history `rounds/{n}`, seed reveal, phase 'settled'.
 *
 * MONEY RULES (checked by the kernel, property-tested with test modules src/games/testing/*)
 *  - Only a user's OWN action debits their wallet: gameJoin buy-in, setBets, an `act` returning
 *    `debitCents` (e.g. hold'em rebuy). A transition run by a deadline (`onDeadline`,
 *    `closeBetting`, `openRound`, bots) can NEVER debit: the kernel throws if it is attempted.
 *  - Bet-board settlement: for every seat, the money on its board B goes to the wallet (row
 *    `returnCents`) or stays on the board (`carry`, total ≤ B); `stakedCents` of the row must be
 *    B − carry (what left the board) and `netCents` = returnCents − stakedCents. A seat with money
 *    leaving its board must have a row. Winnings are always paid to the wallet.
 *  - Stack games: chips move between `seats[i].stackCents` and the module's pot only; the kernel
 *    credits the stack back (ledger 'cashOut') when the seat is removed or the table closes.
 *  - A leaving seat stays (status 'leaving') until `seatClear` is true; `seatClear` MUST become
 *    true through deadlines alone (no state may wait for an absent player).
 *
 * MARKETS: open per-round markets in `openRound` (or later), close them at the latest in the
 * transaction that makes useful information public, resolve them in the transaction that makes the
 * outcome certain. Series (long) markets are only created on simulated tables (`ctx.markets.create`
 * returns null elsewhere). Anything still open at the next openRound / at closing is voided.
 *
 * RANK: default outcome (see GAME_RANK_POINTS): bigWin if net ≥ 5 × staked, win if net ≥ 0.5 ×
 * staked, lose if net ≤ −0.5 × staked, else none (covering every number is never a win). Hold'em
 * overrides `rank` (±1 big blind). Points are capped per game and UTC day by the kernel.
 */
import type { z } from 'zod';
import type { Rng } from '../../engine/rng';
import type {
  BetMap, GameId, GameLimits, GamePrivateDoc, GameRankOutcome, GameSeatDoc, GameSeatSettlement, GameStatsDoc,
  GameTableDoc,
} from '../../shared/games/common';
import type { BotProfile } from '../../sim/profiles';
import type { CardCode, LocalizedText, MarketDoc, MarketKind, PowerId, StakeTier } from '../../shared/types';

export type Rec = Record<string, unknown>;

/** A game-specific action (KernelAction types `setBets`, `sitOut`, `sitIn` are reserved). */
export type GameAction = { type: string } & Rec;

/** 'board': bets live in `bets/{uid}` (roulette, baccarat, craps). 'stack': chips in front of the seat (hold'em). */
export type MoneyStyle = 'board' | 'stack';

/** A seat's board when betting closes (only seats with money on the board). */
export interface LockedBoard {
  seatIndex: number;
  uid: string;
  isBot: boolean;
  bets: BetMap;
  totalCents: number;
  power: PowerId | null;
}

/** Result of `act`. */
export interface ActOutcome {
  /** Cents to debit from the acting HUMAN's wallet now (e.g. hold'em rebuy). Ignored for bots (house money). */
  debitCents?: number;
  ledger?: 'buyIn' | 'bet';
  /** Returned to the caller in GameActionResponse.data. */
  data?: Rec | null;
}

/** A bot's decision. */
export type BotMove =
  | { kind: 'bets'; bets: BetMap; power?: PowerId | null }
  | { kind: 'action'; action: GameAction };

export interface SettleInput {
  /** One row per seat that took part (see MONEY RULES). */
  rows: GameSeatSettlement[];
  /** Bet-board games: what stays on each seat's board (uid → board). Default: nothing. */
  carry?: Record<string, BetMap>;
  /** Game-specific result stored in rounds/{n}.result (number, cards, dice, pots…). */
  result: Rec;
  /** Card games: canonical input of fairDealOrder and the cards dealt; null otherwise. */
  fairness: { remainingBefore: CardCode[] | null; dealt: CardCode[] | null; decks: number | null };
  /** Duration of the 'settled' phase (default GAME_TIMING.settledMs). */
  settledMs?: number;
}

export type MarketScope = 'round' | 'series';

export interface GameMarkets {
  /**
   * Creates a market of `kind` (question in both languages). 'series' markets only exist on
   * simulated tables: returns null elsewhere. Returns the market id. One market per kind and scope.
   */
  create(scope: MarketScope, kind: MarketKind, question: LocalizedText, opts?: { series?: number }): string | null;
  /** Stops trading (outcome still pending). No-op if absent. */
  close(scope: MarketScope, kind: MarketKind): void;
  /** Resolves and pays (after the commit). No-op if absent. */
  resolve(scope: MarketScope, kind: MarketKind, outcome: 'yes' | 'no'): void;
  /** Voids (every position refunded). No-op if absent. */
  void(scope: MarketScope, kind: MarketKind): void;
  /** Id of the live market of `kind`, or null. */
  id(scope: MarketScope, kind: MarketKind): string | null;
}

/** Read-only view given to the fast path (setBets): no private state, no effects. */
export interface ReadCtx<P = Rec, S = Rec> {
  readonly game: GameId;
  readonly now: number;
  readonly table: GameTableDoc<P, S>;
  readonly limits: GameLimits;
}

/** What a module may do inside a table transaction. `table` / `priv` are mutable (g, seats[i].g, stackCents…). */
export interface GameCtx<P = Rec, S = Rec, V = Rec> extends ReadCtx<P, S> {
  readonly priv: GamePrivateDoc<V>;
  /** Non-fair randomness: bots, churn. Never for the game's outcome. */
  readonly rng: Rng;
  /** Seed of the current round (null before the first round). */
  readonly seed: string | null;
  /**
   * `seededRng(seed)` of the current round — the ONLY source for outcomes (dealt cards, number,
   * dice). Each call restarts the stream: draw everything at once and keep it in `priv.g`.
   */
  fairRng(): Rng;
  /** Bot personality (null for humans). */
  botProfile(uid: string): BotProfile | null;
  /** Occupied seats, in seat order. */
  seats(): GameSeatDoc<S>[];
  /** Current board of a seat (bet-board games; {} if none). */
  board(uid: string): BetMap;
  /** Sets phase 'betting' or 'live' with its deadline (absolute ms) and optional sub-step. */
  setPhase(phase: 'betting' | 'live', deadlineMs: number, step?: string | null): void;
  setStep(step: string | null): void;
  /** Seat whose decision is pending (bots are played by the kernel at the deadline). */
  setTurn(seatIndex: number | null): void;
  event(type: string, seatIndex: number | null, d?: Rec | null): void;
  /** Random bot "thinking" delay (GAME_TIMING.botMinMs..botMaxMs). */
  botDelayMs(): number;
  /** Ends the round (see SettleInput and MONEY RULES). */
  settle(input: SettleInput): void;
  /** No round can be played now (e.g. hold'em with fewer than 2 players): phase idle, no deadline. */
  idle(): void;
  /** Private cards of a player (`holes/{uid}`, readable by that player only). */
  secret(uid: string, cards: CardCode[]): void;
  /** Removes a seat now (humans: stack cashed out, anything left on the board refunded). */
  removeSeat(seatIndex: number): void;
  readonly markets: GameMarkets;
}

export interface NewTableInfo {
  tableId: string;
  stakeTier: StakeTier;
  isPrivate: boolean;
  simManaged: boolean;
  limits: GameLimits;
}

/**
 * One game. Type parameters: P = public `g`, S = seat `g`, V = private `g`, A = game actions.
 * Every method is called inside one table transaction; throw an AppError (shared/errors `fail.*`)
 * to refuse a player's request (the transaction is aborted, nothing is written).
 */
export interface GameModule<P = Rec, S = Rec, V = Rec, A extends GameAction = GameAction> {
  readonly game: GameId;
  /** false = not implemented yet: gameJoin refuses (FEATURE_UNAVAILABLE), an open table closes and refunds. */
  readonly available: boolean;
  readonly money: MoneyStyle;
  /** Strict zod schema of the game's own actions (gameAction `action` when not a KernelAction). */
  readonly actionSchema: z.ZodType<A>;

  /** Table limits for a stake tier (hold'em: extra.smallBlindCents, bigBlindCents, minBuyInCents, maxBuyInCents). */
  limits(tier: StakeTier): GameLimits;
  /** Initial public and private game state of a new table. */
  init(info: NewTableInfo): { g: P; priv: V };
  /** Initial seat state `seats[i].g` of a new seat. */
  seatInit(ctx: GameCtx<P, S, V>, seat: GameSeatDoc<S>): S;
  /** Can a round start now? Default: at least one seat. (Hold'em: 2 players with chips.) */
  canStart?(ctx: GameCtx<P, S, V>): boolean;
  /** A round was opened by the kernel (round, seed, commit already set): set the phase (see header). */
  openRound(ctx: GameCtx<P, S, V>): void;

  /**
   * Bet-board games: validates the WHOLE desired board `next` of `seat` against the current one
   * (spot ids → BAD_BET_SPOT, per-spot limits → BET_OUT_OF_RANGE, increments → BET_INCREMENT,
   * contract bets → BET_NOT_REMOVABLE). Returns the normalized board. The kernel checks whole
   * dollars, the round total (min / maxRoundCents) and the money. Stack games: throw ILLEGAL_ACTION.
   */
  validateBets(ctx: ReadCtx<P, S>, seat: GameSeatDoc<S>, next: BetMap, current: BetMap): BetMap;
  /** Checks that `powerId` (already checked to belong to this game) applies to `board`; throw POWER_NOT_APPLICABLE. */
  power(ctx: ReadCtx<P, S>, seat: GameSeatDoc<S>, powerId: PowerId, board: BetMap): void;
  /** Bet-board games: betting closed with these boards (non-empty). Run the round, set the next phase or settle. */
  closeBetting(ctx: GameCtx<P, S, V>, boards: LockedBoard[]): void;

  /** A game action of `seat` (round and seat already checked by the kernel). */
  act(ctx: GameCtx<P, S, V>, seat: GameSeatDoc<S>, action: A): ActOutcome;
  /** Every action `seat` may legally take now (empty when none). Used by bots and property tests. */
  legalActions(ctx: GameCtx<P, S, V>, seat: GameSeatDoc<S>): A[];
  /** The phase deadline passed (live phase; human turn timeouts included). Must never debit. */
  onDeadline(ctx: GameCtx<P, S, V>): void;

  /** Nothing of this seat is in play any more (it may be removed). */
  seatClear(ctx: ReadCtx<P, S>, seat: GameSeatDoc<S>, board: BetMap): boolean;
  /**
   * A human leaves (status becomes 'leaving' unless `seatClear` right after). Returns the board to
   * keep; when `unlocked` (not phase 'live') the kernel refunds the rest. Stack games: board is {}.
   */
  onLeaving(ctx: GameCtx<P, S, V>, seat: GameSeatDoc<S>, board: BetMap, unlocked: boolean): BetMap;
  /** KernelAction sitOut / sitIn (hold'em). Absent = ILLEGAL_ACTION. */
  onSitOut?(ctx: GameCtx<P, S, V>, seat: GameSeatDoc<S>): void;
  onSitIn?(ctx: GameCtx<P, S, V>, seat: GameSeatDoc<S>): void;

  /** Bot decision: its board when betting opens ('bets') or its move when the turn is its ('turn'). */
  bot(ctx: GameCtx<P, S, V>, seat: GameSeatDoc<S>, need: 'bets' | 'turn'): BotMove | null;
  /** Stack games: chips a bot sits down with (house money). Default limits.extra.maxBuyInCents. */
  botBuyInCents?(limits: GameLimits, bot: BotProfile): number;

  /** Rank outcome of a row (default: see header). */
  rank?(row: GameSeatSettlement, limits: GameLimits): GameRankOutcome;
  /** Folds a row into profile `gameStats[game]` (default: rounds/won/lost/net/biggest + counters). */
  stats?(prev: GameStatsDoc, row: GameSeatSettlement): GameStatsDoc;
  /** Does this HUMAN row count as "played at the croupier's table" (default: staked ≥ limits.minBetCents). */
  countsForAffinity?(row: GameSeatSettlement, limits: GameLimits): boolean;
  /** Fair YES probability of one of this game's markets (sim_runner bots trade toward it). */
  fairEstimate(market: MarketDoc, table: GameTableDoc<P, S> | null): number;
  /** The table is closing: resolve the series markets whose outcome is already certain (the rest is voided). */
  onClose?(ctx: GameCtx<P, S, V>): void;
}

/** Any module, as stored in the registry. */
export type AnyGameModule = GameModule<Rec, Rec, Rec, GameAction>;

/**
 * Declares a module with its own state types and returns it as stored by the registry
 * (`export const rouletteModule = defineGameModule<RoulettePublic, RouletteSeat, RoulettePrivate, RouletteAction>({…})`).
 * The kernel only ever hands a module the documents it created, so the cast is sound.
 */
export function defineGameModule<P, S, V, A extends GameAction>(m: GameModule<P, S, V, A>): AnyGameModule {
  return m as unknown as AnyGameModule;
}

export function boardTotal(b: BetMap | null | undefined): number {
  if (!b) return 0;
  let t = 0;
  for (const v of Object.values(b)) t += v;
  return t;
}

/** Board without zero entries (amounts are validated elsewhere). */
export function cleanBoard(b: BetMap): BetMap {
  const out: BetMap = {};
  for (const [k, v] of Object.entries(b)) if (v !== 0) out[k] = v;
  return out;
}

/** Default rank outcome (anti-farming, see header). */
export function defaultRankOutcome(row: GameSeatSettlement): GameRankOutcome {
  const staked = row.stakedCents;
  if (staked <= 0) return 'none';
  if (row.netCents >= 5 * staked) return 'bigWin';
  if (row.netCents * 2 >= staked) return 'win';
  if (row.netCents * 2 <= -staked) return 'lose';
  return 'none';
}

/** Default stats fold. */
export function defaultFoldStats(prev: GameStatsDoc | undefined, row: GameSeatSettlement): GameStatsDoc {
  const p: GameStatsDoc = prev
    ? { ...prev, counters: { ...prev.counters } }
    : { rounds: 0, won: 0, lost: 0, netCents: 0, biggestWinCents: 0, counters: {} };
  p.rounds += 1;
  if (row.netCents > 0) p.won += 1;
  if (row.netCents < 0) p.lost += 1;
  p.netCents += row.netCents;
  p.biggestWinCents = Math.max(p.biggestWinCents, row.netCents);
  for (const [k, v] of Object.entries(row.counters)) p.counters[k] = (p.counters[k] ?? 0) + v;
  return p;
}
