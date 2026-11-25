/**
 * ============================================================================================
 *  MULTI-GAME CONTRACT (Sprint 2) — roulette, baccarat, Texas hold'em, craps.
 * ============================================================================================
 *
 * Blackjack keeps its own collection (`tables/{id}`, see ../types.ts). Every other game lives in
 * `gameTables/{tableId}` and is driven by the generic kernel (src/games/kernel/) plus one
 * `GameModule` per game (src/games/<game>/). Each game's specific shapes (public state `g`, seat
 * state `seats[i].g`, action payloads) are documented in ./<game>.ts.
 *
 * TABLE IDS carry the game: `rl-…` roulette, `bc-…` baccarat, `ho-…` hold'em, `cr-…` craps (sim
 * tables `rl-sim-01`, …). Anything else is a blackjack table id (`sim-01`, Firestore auto-ids: they
 * never contain a dash). Use `gameOfTableId` everywhere (server and client) instead of storing the
 * game next to a table id.
 *
 * DOCUMENTS
 *  - `gameTables/{id}`              public state (GameTableDoc). READ: signed-in. WRITE: server.
 *  - `gameTables/{id}/private/state` seed, shoe/deck, secrets (GamePrivateDoc). READ/WRITE: nobody.
 *  - `gameTables/{id}/bets/{uid}`    a seat's bet board for the current round (GameBetDoc; roulette,
 *                                    baccarat, craps; bots included). READ: signed-in.
 *  - `gameTables/{id}/holes/{uid}`   hold'em hole cards (GameSecretDoc). READ: that uid only.
 *  - `gameTables/{id}/rounds/{n}`    finished round + fairness proof (GameRoundDoc, id = round
 *                                    zero-padded to 8 digits). READ: signed-in.
 *  - `tableCodes/{code}`             { tableId, game, createdAtMs } (server only).
 *
 * MONEY FLOW (kernel invariants)
 *  - Only a user's OWN action debits their wallet (gameJoin buy-in, gameAction setBets / rebuy).
 *    Deadline-driven transitions never debit (a failed debit would freeze the table).
 *  - Bet-board games: `gameAction{action:{type:'setBets', bets}}` sends the WHOLE desired board for
 *    the round; the server debits/refunds only the difference (ledger 'bet' / 'refund'). Undo,
 *    clear, repeat, double and roulette announcements are computed by the client.
 *  - Hold'em: the buy-in (ledger 'buyIn') moves money from the wallet to `seats[i].stackCents`; the
 *    stack is credited back (ledger 'cashOut') when leaving (after the hand if mid-hand), when
 *    kicked for sitting out, or when the table closes. Bot stacks are house money.
 *
 * FAIRNESS: one seed per round, `fairness.currentCommit = sha256(seed)` published when the round
 * opens (before any bet / before the deal), seed revealed in `fairness.lastSeed` and in
 * `rounds/{n}` after settlement. Randomness = `seededRng(seed)` (engine/rng.ts, ported to Dart):
 * roulette `nextInt(37)`; craps `nextInt(6)+1` twice; baccarat `fairDealOrder(remaining, seed, 8)`;
 * hold'em `fairDealOrder(buildShoe(1), seed, 1)` with fixed positions (see ./holdem.ts).
 */
import type {
  AvatarId, BaseRequest, CardCode, Cents, EpochMs, FairnessPublic, LocalizedText, MarketKind, PowerId, QueueEntry,
  RankTier, StakeTier, Uid,
} from '../types';
import type { CharacterId } from '../romance';

export const GAME_IDS = ['roulette', 'baccarat', 'holdem', 'craps'] as const;
/** A kernel-driven game (stored in `gameTables`). */
export type GameId = (typeof GAME_IDS)[number];
/** Every game of the casino. */
export type AnyGame = 'blackjack' | GameId;
export const ALL_GAMES: readonly AnyGame[] = ['blackjack', ...GAME_IDS];

export const GAME_PREFIX: Record<GameId, string> = { roulette: 'rl', baccarat: 'bc', holdem: 'ho', craps: 'cr' };
export const GAME_SEATS: Record<GameId, number> = { roulette: 7, baccarat: 7, holdem: 6, craps: 8 };

/** Game of a table id (see header). */
export function gameOfTableId(tableId: string): AnyGame {
  const m = /^(rl|bc|ho|cr)-/.exec(tableId);
  if (!m) return 'blackjack';
  return (Object.keys(GAME_PREFIX) as GameId[]).find((g) => GAME_PREFIX[g] === m[1])!;
}

export function isGameId(v: unknown): v is GameId {
  return typeof v === 'string' && (GAME_IDS as readonly string[]).includes(v);
}

/**
 * Kernel phases. The game-specific sub-step (e.g. roulette 'spinning', hold'em 'flop') is `step`.
 *  - idle:    nobody seated / waiting (hold'em: fewer than 2 players with chips). deadline null.
 *  - betting: bet-board games accept `setBets` until `deadlineMs` (+ grace for humans).
 *  - live:    the round is being played (spin, deal, betting streets, rolls…), see `step` and `turn`.
 *  - settled: results visible until `deadlineMs`, then the next round opens.
 *  - closed:  permanently closed.
 */
export const GAME_PHASES = ['idle', 'betting', 'live', 'settled', 'closed'] as const;
export type GamePhase = (typeof GAME_PHASES)[number];

/** Round outcome of a seat, used for rank points (see GAME_RANK_POINTS). */
export type GameRankOutcome = 'bigWin' | 'win' | 'lose' | 'none';

/** One seat. `g` holds the game-specific seat state (documented in ./<game>.ts). */
export interface GameSeatDoc<S = Record<string, unknown>> {
  seatIndex: number;
  uid: Uid;
  username: string;
  avatar: AvatarId;
  isBot: boolean;
  rankTier: RankTier;
  /** leaving = removed once nothing of theirs is live any more; sittingOut = hold'em pause. */
  status: 'active' | 'leaving' | 'sittingOut';
  joinedAtMs: EpochMs;
  /** Consecutive rounds without taking part (humans are removed after GAME_MISSED_ROUNDS_LIMIT). */
  missedRounds: number;
  /** Total staked by this seat in the current round (frozen when betting closes). */
  stakeCents: Cents;
  /** Hold'em chips in front of the player (null for bet-board games). */
  stackCents: Cents | null;
  /** Power used this round (max 1). */
  powerUsed: PowerId | null;
  /** Set at settlement: total return − total stake for this round. */
  roundNetCents: Cents | null;
  g: S;
}

/** Animation/event log of the current round (reset when a round opens, capped at 200), by `seq`. */
export interface GameEvent {
  seq: number;
  /** Game-specific type (documented in ./<game>.ts); kernel types: join, leave, sitOut, sitIn, timeout, power, shuffle. */
  type: string;
  seatIndex: number | null;
  atMs: EpochMs;
  /** Game-specific payload (cards, number, dice, amounts…). */
  d: Record<string, unknown> | null;
}
export const GAME_EVENTS_CAP = 200;

export interface GameLimits {
  /** Smallest chip / minimum total bet of a round (whole dollars). */
  minBetCents: Cents;
  /** Maximum on one bet spot. */
  maxBetCents: Cents;
  /** Maximum total staked by one seat in one round. */
  maxRoundCents: Cents;
  /** Game-specific limits (e.g. hold'em smallBlindCents, bigBlindCents, minBuyInCents, maxBuyInCents). */
  extra: Record<string, number>;
}

export interface GameMarketsPublic {
  /** Per-round markets of the current round: kind → marketId. */
  round: Partial<Record<MarketKind, string>>;
  /** Long ("series") markets in progress: kind → marketId. Sim tables only. */
  series: Partial<Record<MarketKind, string>>;
}

/** `gameTables/{tableId}` — public state of a kernel-driven table. */
export interface GameTableDoc<P = Record<string, unknown>, S = Record<string, unknown>> {
  tableId: string;
  game: GameId;
  name: string;
  stakeTier: StakeTier;
  limits: GameLimits;
  isPrivate: boolean;
  simManaged: boolean;
  status: 'open' | 'closed';
  phase: GamePhase;
  /** Game-specific sub-step of the phase (e.g. 'spinning', 'preflop', 'comeOut'), or null. */
  step: string | null;
  phaseStartedAtMs: EpochMs;
  deadlineMs: EpochMs | null;
  /** +1 each time a round opens (spin / coup / hand / roll). 0 before the first. Send it with gameAction. */
  round: number;
  /** Seat whose decision is pending (hold'em player, craps shooter), else null. */
  turn: { seatIndex: number } | null;
  /** Always length GAME_SEATS[game]; null = empty seat. */
  seats: (GameSeatDoc<S> | null)[];
  queue: GameQueueEntry[];
  /** uids of seated players (humans and bots). Required by tradeShares (OWN_TABLE_MARKET). */
  seatedUids: Uid[];
  humanCount: number;
  botCount: number;
  rankTier: RankTier;
  /** The croupier character of this table (Rendez-vous meta). */
  dealer: { characterId: CharacterId };
  /** Same shape as blackjack; `currentHandNumber`/`lastHandNumber` hold round numbers. */
  fairness: FairnessPublic;
  events: GameEvent[];
  eventSeq: number;
  markets: GameMarketsPublic;
  /** Game-specific public state (documented in ./<game>.ts). */
  g: P;
  createdAtMs: EpochMs;
  updatedAtMs: EpochMs;
}

export interface GameQueueEntry extends QueueEntry {
  /** Hold'em: buy-in already debited at gameJoin (credited back if the player leaves the queue). */
  buyInCents: Cents | null;
}

/** `gameTables/{id}/private/state` — never readable by clients. */
export interface GamePrivateDoc<V = Record<string, unknown>> {
  seed: string | null;
  commit: string | null;
  roundStartedAtMs: EpochMs | null;
  /** Private join code (private tables), else null. */
  code: string | null;
  /** Game-specific secret state (shoe, deck order, hole cards…). */
  g: V;
}

/** Bet board of one seat: spotId → cents (whole dollars). Spot ids are game-specific (./<game>.ts). */
export type BetMap = Record<string, Cents>;

/** `gameTables/{id}/bets/{uid}` — public. */
export interface GameBetDoc {
  uid: Uid;
  seatIndex: number;
  isBot: boolean;
  round: number;
  bets: BetMap;
  totalCents: Cents;
  power: PowerId | null;
  /** Board of the previous round (client "Rejouer"). */
  previous: BetMap;
  updatedAtMs: EpochMs;
}

/** `gameTables/{id}/holes/{uid}` — hold'em hole cards. READ: that uid. */
export interface GameSecretDoc {
  round: number;
  cards: CardCode[];
  createdAtMs: EpochMs;
}

/** `gameTables/{id}/rounds/{round8}` — finished round. READ: signed-in. */
export interface GameRoundDoc {
  tableId: string;
  game: GameId;
  round: number;
  startedAtMs: EpochMs;
  endedAtMs: EpochMs;
  seats: Array<{ seatIndex: number; uid: Uid; username: string; isBot: boolean; stakedCents: Cents; netCents: Cents }>;
  /** Game-specific result (number, cards, dice, pots…). */
  result: Record<string, unknown>;
  fairness: {
    commit: string;
    seed: string;
    /** Card games: canonical input of fairDealOrder and the cards dealt (prefix of the order). */
    remainingBefore: CardCode[] | null;
    dealt: CardCode[] | null;
    decks: number | null;
  };
}

/** Settlement row of one seat (kernel effect 'settle'). */
export interface GameSeatSettlement {
  uid: Uid;
  username: string;
  avatar: AvatarId;
  isBot: boolean;
  seatIndex: number;
  stakedCents: Cents;
  returnCents: Cents;
  netCents: Cents;
  /** Game-specific counters added to profile `gameStats[game].counters` (e.g. straightUps, pots). */
  counters: Record<string, number>;
  /** Feed highlight: 'jackpot' (game-specific big hit) or null. */
  highlight: 'jackpot' | null;
}

/** `profiles/{uid}.gameStats[game]`. */
export interface GameStatsDoc {
  rounds: number;
  won: number;
  lost: number;
  netCents: Cents;
  biggestWinCents: Cents;
  counters: Record<string, number>;
}

/**
 * Rank points per settled round (shared ladder). Anti-farming: a round only counts as a win if
 * net ≥ 0.5 × staked (bigWin if net ≥ 5 × staked), a loss if net ≤ −0.5 × staked (hold'em: ±1 big
 * blind), otherwise 'none'. Points per game and UTC day are capped (profiles/{uid}.rankDaily).
 */
export const GAME_RANK_POINTS: Record<GameRankOutcome, number> = { bigWin: 15, win: 10, lose: -4, none: 0 };
export const RANK_POINTS_DAILY_CAP_PER_GAME = 250;
export const GAME_MISSED_ROUNDS_LIMIT = 5;

/** Kernel timing defaults (ms); modules may use their own per step (./<game>.ts). */
export const GAME_TIMING = {
  bettingMs: 20_000,
  decisionMs: 20_000,
  settledMs: 6_000,
  botMinMs: 700,
  botMaxMs: 1_800,
} as const;

// ============================================================================================
// Callables
// ============================================================================================

/**
 * gameJoin — find a seat at a kernel-driven game (same modes as joinMatchmaking).
 *  - 'quick': best public table of `game` + `stakeTier` (humans of the same rank first), else a new
 *    table completed with 2 bots; queued if no seat is free right now.
 *  - 'createPrivate': new private table of `game` (no bots); returns its 6-char `code`.
 *  - 'joinCode': join the private table of ANY game with `code` (`game`/`stakeTier` ignored; the
 *    response says which game — may be 'blackjack', in which case the blackjack table is joined).
 *  - hold'em: `buyInCents` required (limits.extra.minBuyInCents..maxBuyInCents), debited now.
 * One location per user across all games (ALREADY_SEATED if seated elsewhere, leave first).
 * Errors: BAD_CODE, TABLE_FULL, ALREADY_SEATED, PROFILE_REQUIRED, BUY_IN_OUT_OF_RANGE, INSUFFICIENT_FUNDS.
 */
export interface GameJoinRequest extends BaseRequest {
  game: GameId;
  mode: 'quick' | 'createPrivate' | 'joinCode';
  stakeTier: StakeTier;
  code?: string;
  buyInCents?: Cents;
}
export interface GameJoinResponse {
  tableId: string;
  game: AnyGame;
  status: 'seated' | 'queued';
  seatIndex: number | null;
  code: string | null;
}

/**
 * gameLeave — leave the seat or the queue. Bets not yet locked are refunded; hold'em stack is cashed
 * out (after the current hand if you are in it: `deferred` true).
 */
export interface GameLeaveRequest extends BaseRequest { tableId: string }
export interface GameLeaveResponse { left: true; refundedCents: Cents; cashOutCents: Cents; deferred: boolean }

/** Kernel actions (every game), validated by the kernel; game actions are listed in ./<game>.ts. */
export type KernelAction =
  /** Bet-board games, phase 'betting' (craps: between rolls). Whole desired board; power optional. */
  | { type: 'setBets'; bets: BetMap; power?: PowerId }
  | { type: 'sitOut' }
  | { type: 'sitIn' };

/**
 * gameAction — a decision on YOUR seat. `round` must equal `table.round` (else STALE_HAND).
 * `action` is a KernelAction or an action of the table's game (validated by the game's strict schema).
 * Errors: BAD_PHASE, STALE_HAND, NOT_SEATED, NOT_YOUR_TURN, ILLEGAL_ACTION, BAD_BET_SPOT,
 * BET_OUT_OF_RANGE, BET_INCREMENT, BET_NOT_REMOVABLE, INSUFFICIENT_FUNDS, POWER_* , game reasons.
 */
export interface GameActionRequest extends BaseRequest {
  tableId: string;
  round: number;
  action: { type: string } & Record<string, unknown>;
}
export interface GameActionResponse {
  phase: GamePhase;
  round: number;
  balanceCents: Cents;
  stackCents: Cents | null;
  /** Game-specific extra (e.g. accepted board), or null. */
  data: Record<string, unknown> | null;
}

/** gamePoke — apply overdue deadlines of a kernel-driven table (server re-checks its clock). */
export interface GamePokeRequest extends BaseRequest { tableId: string }
export interface GamePokeResponse { phase: GamePhase; round: number; deadlineMs: EpochMs | null; advanced: boolean }

/** Helper: question text of a market (server-generated, both languages). */
export type MarketQuestion = LocalizedText;
