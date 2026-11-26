/**
 * Texas hold'em No-Limit (player vs player) — shared contract. OWNER: hold'em implementer.
 * Values in the exported lists below are spread into the global unions of ../types.ts.
 * Append new values at the END of a list (never rename/remove: Dart mirrors them).
 * No powers in hold'em (PvP fairness). No commission (rake). Bots' stacks are house money.
 *
 * ============================================================================================
 *  TABLE, MONEY AND TIMING
 * ============================================================================================
 *  - 6 seats. Blinds per stake tier (HOLDEM_BLINDS, whole dollars): low 1/2, mid 5/10, high 25/50 $.
 *    `limits.extra` = { smallBlindCents, bigBlindCents, minBuyInCents (40 BB), maxBuyInCents (100 BB) }.
 *    Every amount is a whole dollar (unit $1 = 100 cents).
 *  - Buy-in debited at gameJoin (kernel). The stack (`seats[i].stackCents`) is credited back
 *    ('cashOut') when the seat is removed: leaving between hands (at once), leaving mid-hand (at the
 *    end of that hand), 3 hands sitting out / without chips, table closing.
 *  - `rebuy {cents}` between hands (not while dealt in a hand being played): debited from the
 *    wallet (ledger 'buyIn'), stack + cents ≤ maxBuyInCents (else BUY_IN_OUT_OF_RANGE).
 *  - Bots sit with `botBuyInCents` (house money) and are topped up by the house between hands when
 *    their stack falls under 20 big blinds (event 'topUp'); their winnings / losses are the house's.
 *  - 20 s per decision (HOLDEM_TIMING.decisionMs, + the kernel's DECISION_GRACE_MS). Timeout =
 *    check if possible, else fold. Two timeouts in a row → the seat is put in pause ('sittingOut').
 *    A seat that is 'sittingOut' or 'leaving' and still in the hand is played at once when its turn
 *    comes (check if possible, else fold; events carry `auto: true`). A human not dealt in (pause, or
 *    no chips) for 3 hands in a row (HOLDEM_HANDS_OUT_LIMIT) is removed (stack credited).
 *
 * ============================================================================================
 *  HAND LIFECYCLE (kernel phase 'live', `table.step` = street)
 * ============================================================================================
 *  - Dealt in: seats 'active' with chips, except new arrivals who WAIT FOR THE BIG BLIND
 *    (`g.waitBB`): with fewer than 2 players not waiting (table start, after a pause…) nobody waits.
 *  - Moving big blind: the big blind moves to the next seat with chips after last hand's big blind
 *    (`g.bb`); a seat waiting for the big blind is dealt in when it reaches it. The small blind is
 *    the dealt-in player just before the big blind, the button the one before the small blind.
 *    HEADS-UP (2 dealt in): the button posts the small blind, acts first preflop and last after.
 *  - Blinds are posted from the stacks (chips → pot, never a wallet debit); a short stack posts
 *    what it has (all-in). The amount to call preflop is always the full big blind.
 *  - `fairDealOrder(buildShoe(1), seed, 1)` with FIXED POSITIONS (holdemDeckLayout, n = players
 *    dealt in): hole cards 0..2n-1 (two passes from the small blind: player k of `g.order` gets
 *    cards k and n+k), burn 2n, flop 2n+1..2n+3, burn 2n+4, turn 2n+5, burn 2n+6, river 2n+7. The
 *    board is therefore fixed at the deal (board markets settle on it even if everyone folds).
 *    Hole cards → `holes/{uid}` (humans; readable by that player only).
 *  - Betting (No-Limit): preflop first to act is the player after the big blind, after the flop the
 *    first player after the button. Minimum bet = big blind; minimum raise = the last full bet or
 *    raise of the street (`g.minRaiseCents`, big blind at the start of a street). Anybody may go
 *    all-in for less. An all-in raise smaller than a full raise does NOT reopen the betting for the
 *    players who already acted (they may only call or fold), unless the all-ins since their last
 *    action add up to a full raise. Raising is impossible when nobody else can call any more.
 *  - End of a street: the uncalled part of the biggest bet goes back to its owner ('uncalled'), bets
 *    are pushed to the pot ('collect', `g.potCents`, `g.pots` = main pot then side pots). If fewer
 *    than 2 players can still bet, the remaining board is dealt at once (run-out) then showdown.
 *  - Everybody folds but one: that player takes the pot, no card is shown (step 'folded').
 *  - Showdown (step 'showdown'): best 5 of 7 for every player still in; each pot (main, then side
 *    pots) is split between its eligible best hands in whole dollars, the odd dollar(s) one by one
 *    to the winners in seat order starting left of the button (first seat after the button).
 *  - Settlement rows (kernel 'settle'): stakedCents = chips put in the pot (uncalled bets excluded),
 *    returnCents = chips won, netCents = returnCents − stakedCents (Σ net = 0 exactly: no rake).
 *    No wallet credit at settlement: chips move between stacks.
 *  - Rank (kernel ladder): win if net ≥ 1 big blind, lose if net ≤ −1 big blind, big win if
 *    net ≥ 40 big blinds, else nothing. Feed 'jackpot' highlight for a pot won with quads or better.
 *  - Waiting (step 'waiting', no turn): two seats are active but fewer than two have chips (a player
 *    busted at a private table): re-checked every HOLDEM_TIMING.waitingMs, a `rebuy` or a `sitIn`
 *    deals at once. Fewer than 2 active seats → kernel phase 'idle' (a join / sitIn restarts).
 *
 * MARKETS (per hand, created at the deal, closed when the flop is shown — or at the end of the hand
 * if nobody saw it —, resolved as soon as the outcome is publicly certain, at the latest at the end
 * of the hand on the board fixed at the deal): holdemBoardAce "Is there an ace on the board?",
 * holdemBoardFlush "3 or more cards of one suit on the board?". No long market.
 *
 * FAIRNESS: `rounds/{n}.fairness` = { remainingBefore: buildShoe(1), dealt: the first 2n+8 cards,
 * decks: 1 }; with `result.order` anybody can rebuild every hole card. ASSUMED CHOICE (shown in the
 * rules): the revealed seed makes the folded cards verifiable, hence visible.
 *
 * ============================================================================================
 *  STATE, ACTIONS, EVENTS
 * ============================================================================================
 * Public `g` = HoldemPublic, seat `g` = HoldemSeat, private `g` = HoldemPrivate (never readable).
 * ACTIONS (gameAction `action`, strict): {type:'fold'} | {type:'check'} | {type:'call'} |
 *  {type:'allIn'} | {type:'bet', toCents} | {type:'raise', toCents} | {type:'rebuy', cents};
 *  `toCents` = the player's TOTAL bet on this street after the action ("raise to"). 'bet' when
 *  `currentBetCents` is 0, 'raise' otherwise (`g.toAct.kind`). Errors: NOT_YOUR_TURN, BAD_PHASE,
 *  ILLEGAL_ACTION (check facing a bet, call with nothing to call, raise not reopened…),
 *  BET_OUT_OF_RANGE (below the minimum / above the stack), BET_INCREMENT (not whole dollars),
 *  SITTING_OUT (a paused seat acting), REBUY_NOT_ALLOWED (dealt in a hand being played),
 *  BUY_IN_OUT_OF_RANGE. Kernel actions sitOut / sitIn are supported.
 *
 * EVENTS (`table.events`, reset each hand; seat = seatIndex; amounts in cents):
 *  button {button, sb, bb, order} · blind seat {kind:'sb'|'bb', cents, allIn} · deal {order}
 *  (two cards pitched to each, no value) · fold seat {auto?} · check seat {auto?} ·
 *  call seat {cents, toCents, allIn} · bet seat {cents, toCents, allIn} ·
 *  raise seat {cents, toCents, allIn, full} · uncalled seat {cents} · collect {potCents, pots} ·
 *  burn {street} · flop {cards} · turn {cards} · river {cards} ·
 *  showdown {hands: {[seat]: {cards, category, best}}} · win seat {cents, pot, category|null} ·
 *  timeout seat · sitOut seat · rebuy seat {cents, stackCents} · topUp seat {cents} ·
 *  waiting {} · kernel: join, leave, sitIn.
 */
import type { CardCode, Cents, StakeTier } from '../types';

export const HOLDEM_POWER_IDS = [] as const;
export const HOLDEM_MARKET_KINDS = ['holdemBoardAce', 'holdemBoardFlush'] as const;
export const HOLDEM_REASONS = [
  'BUY_IN_OUT_OF_RANGE', 'REBUY_NOT_ALLOWED', 'SITTING_OUT',
  // gameJoin of a hold'em table without buyInCents (e.g. a private code typed with another game selected)
  'BUY_IN_REQUIRED',
] as const;

/** Small / big blind (cents) of each stake tier. */
export const HOLDEM_BLINDS: Record<StakeTier, { sb: Cents; bb: Cents }> = {
  low: { sb: 100, bb: 200 },
  mid: { sb: 500, bb: 1_000 },
  high: { sb: 2_500, bb: 5_000 },
};
export const HOLDEM_MIN_BUY_IN_BB = 40;
export const HOLDEM_MAX_BUY_IN_BB = 100;
/** Bots are topped up by the house between hands below this many big blinds. */
export const HOLDEM_BOT_TOP_UP_BB = 20;
/** Timeouts in a row before being put in pause. */
export const HOLDEM_SIT_OUT_TIMEOUTS = 2;
/** Hands (or waiting periods) not dealt in before the seat is freed (stack credited). */
export const HOLDEM_HANDS_OUT_LIMIT = 3;
/** Big win (rank ladder) from this many big blinds of net. */
export const HOLDEM_BIG_WIN_BB = 40;

export const HOLDEM_TIMING = {
  /** A human's decision. */
  decisionMs: 20_000,
  /** Re-check period while waiting for a second player with chips. */
  waitingMs: 15_000,
  /** 'settled' phase after a hand won without showdown. */
  settledMs: 5_000,
  /** Extra 'settled' time after a showdown. */
  showdownExtraMs: 2_500,
  /** Extra 'settled' time per street dealt in an all-in run-out. */
  runoutStreetMs: 1_200,
  /** Extra delay before a bot acts right after new board cards. */
  boardDelayMs: 1_200,
} as const;

export const HOLDEM_STREETS = ['preflop', 'flop', 'turn', 'river'] as const;
export type HoldemStreet = (typeof HOLDEM_STREETS)[number];
/** `table.step` while phase 'live' (a street, or 'waiting'); 'showdown' / 'folded' once the hand is over. */
export type HoldemStep = HoldemStreet | 'waiting' | 'showdown' | 'folded';

/**
 * Hand categories, weakest first. `best` = the 5 cards of the hand in significance order: quads
 * then kicker; full house trips then pair; two pair high pair, low pair, kicker; trips then 2
 * kickers; pair then 3 kickers; flush / high card / straights from the top card down (wheel:
 * 5 4 3 2 A); equal ranks in suit order S, H, D, C. SCORE (comparable integer, equal = exact tie) =
 * `category × 16^5 + Σ rank(best[i]) × 16^(4−i)`, ranks 2..14 (ace 14, except the ace of a wheel,
 * which counts 1). A royal flush is a straightFlush topped by the ace.
 */
export const HOLDEM_HAND_CATEGORIES = [
  'highCard', 'pair', 'twoPair', 'trips', 'straight', 'flush', 'fullHouse', 'quads', 'straightFlush',
] as const;
export type HoldemHandCategory = (typeof HOLDEM_HAND_CATEGORIES)[number];

/** Fixed positions of the hold'em deal for `n` players dealt in (see header). */
export function holdemDeckLayout(n: number) {
  return {
    /** Hole card `pass` (0 or 1) of the player at position `k` of `g.order`. */
    hole: (k: number, pass: 0 | 1) => pass * n + k,
    burns: [2 * n, 2 * n + 4, 2 * n + 6] as const,
    flop: [2 * n + 1, 2 * n + 2, 2 * n + 3] as const,
    turn: 2 * n + 5,
    river: 2 * n + 7,
    /** Cards used by a hand (prefix of the deal order published in rounds/{n}.fairness.dealt). */
    total: 2 * n + 8,
  };
}

/** A pot: main pot first, then side pots. `eligible` = seats (not folded) that can win it. */
export interface HoldemPot {
  cents: Cents;
  eligible: number[];
}

/** What the seat on turn may do (null when no decision is pending). */
export interface HoldemToAct {
  seat: number;
  /** Chips needed to call, capped at the stack (0 = check is possible). */
  callCents: Cents;
  /** 'bet' when nobody bet on this street, 'raise' otherwise; null = no bet/raise possible (only fold/check/call). */
  kind: 'bet' | 'raise' | null;
  /** Smallest legal "to" amount of a bet / raise (= maxToCents when only an all-in for less is possible). */
  minToCents: Cents | null;
  /** All-in "to" amount (betCents + stack). */
  maxToCents: Cents | null;
}

/** `rounds/{n}.result` and `g.result` (end of the hand). */
export interface HoldemResult {
  button: number;
  sb: number | null;
  bb: number;
  smallBlindCents: Cents;
  bigBlindCents: Cents;
  /** Seats dealt in, in dealing order (position k got deal cards k and n+k). */
  order: number[];
  /** The 5 board cards fixed at the deal. */
  board: CardCode[];
  /** How many of them were shown (0, 3, 4 or 5). */
  boardShown: number;
  /** Total chips won (Σ pots). */
  potCents: Cents;
  pots: Array<HoldemPot & { winners: number[] }>;
  /** Showdown hands (seat → hand), only players who reached the showdown. */
  hands: Record<string, { cards: CardCode[]; category: HoldemHandCategory; score: number; best: CardCode[] }>;
  /** Seats that won something, seat order. */
  winners: number[];
  showdown: boolean;
}

/** Public table state (`gameTables/{id}.g`). */
export interface HoldemPublic {
  /** Seat of the button (-1 before the first hand). */
  button: number;
  /** Seat that posted the small blind (heads-up: the button), null before the first hand. */
  sb: number | null;
  /** Seat of the big blind of the current / last hand (the moving big blind starts after it). */
  bb: number | null;
  /** Seats dealt in this hand, in dealing order (from the small blind). */
  order: number[];
  /** Board cards shown so far (0, 3, 4 or 5). */
  board: CardCode[];
  /** Chips collected from the previous streets (bets in front of the players excluded). */
  potCents: Cents;
  /** Breakdown of `potCents` at the last collection (main pot first). */
  pots: HoldemPot[];
  /** Highest bet of the current street (what a call matches; the big blind preflop). */
  currentBetCents: Cents;
  /** Minimum raise increment (last full bet / raise of the street, the big blind at its start). */
  minRaiseCents: Cents;
  /** Internal: +1 at each full bet / raise of the street (reopening rule). */
  fullRaiseSeq: number;
  /** Decision pending (mirrors `table.turn`), null otherwise. */
  toAct: HoldemToAct | null;
  /** End of the last hand (null while a hand is played). */
  result: HoldemResult | null;
}

/** Last action of a seat in this hand (UI badge). */
export type HoldemLastAction = 'sb' | 'bb' | 'fold' | 'check' | 'call' | 'bet' | 'raise' | 'allIn';

/** Seat state (`seats[i].g`). */
export interface HoldemSeat {
  /** Dealt in the current / last hand (stays true after a fold). */
  inHand: boolean;
  folded: boolean;
  allIn: boolean;
  /** Chips in front of the player on this street. */
  betCents: Cents;
  /** Chips put in the pot this hand (betCents included, uncalled bets excluded). */
  committedCents: Cents;
  /** Has acted on this street. */
  acted: boolean;
  /** Internal (reopening rule): `g.fullRaiseSeq` and `g.currentBetCents` right after this seat's last action. */
  actSeq: number;
  actLevel: Cents;
  lastAction: HoldemLastAction | null;
  /** New arrival (or back from a pause) waiting for the big blind. */
  waitBB: boolean;
  /** Timeouts in a row. */
  timeouts: number;
  /** Hands (or waiting periods) in a row not dealt in (pause / no chips). */
  handsOut: number;
  /** Hole cards shown at the showdown (null otherwise). */
  shown: CardCode[] | null;
}

/** Private state (`private/state.g`). */
export interface HoldemPrivate {
  /** Deal order prefix used by the hand (2n + 8 cards), [] before the first deal. */
  deck: CardCode[];
  /** uid → hole cards. */
  holes: Record<string, CardCode[]>;
  /** The 5 board cards fixed at the deal. */
  board: CardCode[];
}

export type HoldemAction =
  | { type: 'fold' }
  | { type: 'check' }
  | { type: 'call' }
  | { type: 'allIn' }
  | { type: 'bet'; toCents: Cents }
  | { type: 'raise'; toCents: Cents }
  | { type: 'rebuy'; cents: Cents };
