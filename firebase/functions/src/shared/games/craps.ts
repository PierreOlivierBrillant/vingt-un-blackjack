/**
 * Craps — shared contract. OWNER: craps implementer.
 * Values in the exported lists below are spread into the global unions of ../types.ts.
 * Append new values at the END of a list (never rename/remove: Dart mirrors them).
 *
 * ============================================================================================
 *  TABLE: 8 seats, rotating shooter. EVERY ROLL IS A ROUND (own seed + commit, own rounds/{n}).
 * ============================================================================================
 * Bets live in `gameTables/{id}/bets/{uid}` (GameBetDoc) and STAY ON THE BOARD from one roll to
 * the next (the kernel's `carry`): `bets` is always what is on the layout now, `round` the last
 * roll at which that board changed. The client sends the WHOLE desired board with
 * `gameAction {type:'setBets', bets, power?}` during the betting window between two rolls.
 *
 * ROLL CYCLE (kernel phases, see ./common.ts)
 *  - betting (step 'comeOut' | 'point'): bets are open; `turn` = the shooter's seat. The shooter
 *    throws with `gameAction {type:'roll'}` (gesture; no debit) — the dice are out at `g.rollAt`
 *    (≥ CRAPS_TIMING.minWindowMs after the window opened, + diceOutMs), bets close then — or the
 *    dice are rolled automatically at the deadline (CRAPS_TIMING.shooterMs = 15 s for a human
 *    shooter, botShooterMs / botsOnlyMs for a bot or no shooter). A human's DECISION_GRACE_MS
 *    applies as usual (the throw sets `deadlineMs = rollAt − DECISION_GRACE_MS`).
 *  - live (step 'rolling'): the dice are drawn and public (`g.dice`, `g.roll`, event 'roll'):
 *    `d1 = seededRng(seed).nextInt(6) + 1`, then `d2 = nextInt(6) + 1` (same stream). The per-roll
 *    market is resolved now. Lasts CRAPS_TIMING.rollMs (dice flight on the clients).
 *  - settled: every bet decided by the roll is paid / collected (events 'pay'), the puck moves
 *    (`g.point`), the next round opens after CRAPS_TIMING.settledMs.
 *  - Come-out whose shooter has NO line bet when the dice should roll: no roll, the dice pass to
 *    the next player (event 'noRoll', round settled without any row, `result.noRoll` true).
 *
 * SPOT IDS (`bets` keys; amounts in whole dollars, cents on the wire)
 *   pass, dontPass                      line bets (1:1; Don't Pass: 2/3 win, 12 barred = push)
 *   come, dontCome                      come box (only while a point is ON); travel to their number
 *   come4 … come10, dontCome4 … dontCome10   come / don't come bets moved to a number (set by the
 *                                       server only: a client may keep them, lower a don't come)
 *   odds:pass, odds:dontPass            free odds behind the line (point ON only)
 *   odds:come4 …, odds:dontCome4 …      odds on a come / don't come number
 *   place4, place5, place6, place8, place9, place10   place bets (9:5, 7:5, 7:6)
 *   field                               one roll: 2 pays 2:1, 12 pays 3:1, 3-4-9-10-11 pay 1:1
 *   hard4, hard6, hard8, hard10         hardways (7:1 on 4/10, 9:1 on 6/8)
 *   any7 (4:1), anyCraps (7:1), two (30:1), three (15:1), yo (15:1, i.e. 11), twelve (30:1) — one roll
 * Points N ∈ {4, 5, 6, 8, 9, 10}.
 *
 * BET RULES (server-validated, `validateBets`, in this order)
 *  - unknown spot id → BAD_BET_SPOT;
 *  - not open now → BET_NOT_OPEN: pass / dontPass raised while a point is ON (no "put" bets),
 *    come / dontCome on the come-out, raising a come / don't come number bet, line odds on the
 *    come-out, odds without their flat bet;
 *  - contract bets cannot be taken down or lowered → BET_NOT_REMOVABLE: pass once a point is ON,
 *    comeN. (Don't Pass / Don't Come numbers, odds, place, hardways, field and props may be taken
 *    down while betting is open.)
 *  - every spot except odds: limits.minBetCents ≤ amount ≤ limits.maxBetCents, odds ≥ $1
 *    (else BET_OUT_OF_RANGE); odds (true odds, 3-4-5×): odds:pass / odds:comeN ≤ 3× (4/10),
 *    4× (5/9), 5× (6/8) the flat bet; lay odds odds:dontPass / odds:dontComeN ≤ 6× the flat bet;
 *    above → BET_OUT_OF_RANGE (odds are not capped by maxBetCents);
 *  - place6 / place8 and lay odds on 5, 9, 6, 8 by multiples of $3 (exact to the cent) → BET_INCREMENT;
 *  - the SHOOTER must bet the line → MUST_BET_LINE: on the come-out a non-empty board of the
 *    shooter holds pass or dontPass (an empty board = the shooter declines: the dice pass on), and
 *    a shooter's line bet may not be taken down during the point; `roll` on the come-out without a
 *    line bet → MUST_BET_LINE; `roll` by anyone else → NOT_SHOOTER; outside betting → BAD_PHASE.
 *  - The kernel adds: whole dollars, board total ≤ limits.maxRoundCents (= 20 × maxBetCents).
 *  - Place bets and hardways are OFF on the come-out (no action, they stay); come odds are OFF on
 *    the come-out (returned if their come bet is decided then); lay odds always work.
 *
 * WHAT STAYS UP after a decision: line bets (pass / dontPass), place bets and hardways stay on the
 * board when they win (only the winnings are paid); come / don't come (box or number), every odds
 * bet and the one-roll bets (field, props) come back to the wallet with their winnings; a Don't
 * Come bar-12 push comes back too. A bet that loses leaves the board. A player who left (seat
 * 'leaving') keeps only pending contract bets: everything else comes back (stake returned,
 * winnings paid) at the next roll.
 *
 * POWER safetyNet ("Filet de sécurité"): set on the come-out with a Pass Line bet on the board
 * (`setBets … power:'safetyNet'`), armed when betting closes (`seats[i].g.safetyNet`, event
 * 'power'), it refunds that Pass Line bet on a seven-out, once, until that Pass Line bet is
 * decided (natural, craps, point made or seven-out). Odds are not covered. Elsewhere (point ON, no
 * Pass Line bet, net already armed) → POWER_NOT_APPLICABLE.
 *
 * MARKETS: per roll `crapsSeven` ("a seven on the next roll?", fair 1/6, created when betting opens,
 * closed and resolved when the dice are drawn); long `crapsPoint` ("does the shooter make the
 * point?", sim tables only) created when a point is set, resolved by the roll that decides it (fair
 * ways(N) / (ways(N) + 6): 1/3 on 4/10, 2/5 on 5/9, 5/11 on 6/8 — no roll in between changes it, so
 * it stays open for the duration of the point).
 *
 * RANK / STATS: a roll counts for a seat only if one of its bets was decided; the anti-farming rule
 * compares the net with the stake of the bets DECIDED by the roll (`counters.actionCents`), not with
 * the money that left the board (winning bets stay up). Counters (profile gameStats.craps.counters):
 * actionCents, pointsMade (as the shooter), hardways (hardway wins), longShots (2, 3, 11, 12 hits);
 * `highlight: 'jackpot'` on a 15:1 / 30:1 hit.
 */
import type { Cents, EpochMs, Uid } from '../types';

export const CRAPS_POWER_IDS = ['safetyNet'] as const;
export const CRAPS_MARKET_KINDS = ['crapsSeven', 'crapsPoint'] as const;
export const CRAPS_REASONS = ['NOT_SHOOTER', 'MUST_BET_LINE', 'BET_NOT_OPEN'] as const;

export type CrapsPowerId = (typeof CRAPS_POWER_IDS)[number];

/** Point numbers (place numbers, come numbers). */
export const CRAPS_POINTS = [4, 5, 6, 8, 9, 10] as const;
export type CrapsPoint = (typeof CRAPS_POINTS)[number];
export const CRAPS_HARDWAYS = [4, 6, 8, 10] as const;
export type CrapsHardway = (typeof CRAPS_HARDWAYS)[number];

/** One-roll spots (field and propositions). */
export const CRAPS_ONE_ROLL_SPOTS = ['field', 'any7', 'anyCraps', 'two', 'three', 'yo', 'twelve'] as const;
export type CrapsOneRollSpot = (typeof CRAPS_ONE_ROLL_SPOTS)[number];

/** Every bet spot id (see header). */
export const CRAPS_SPOT_IDS: readonly string[] = [
  'pass', 'dontPass', 'come', 'dontCome',
  ...CRAPS_POINTS.map((n) => `come${n}`), ...CRAPS_POINTS.map((n) => `dontCome${n}`),
  'odds:pass', 'odds:dontPass', ...CRAPS_POINTS.map((n) => `odds:come${n}`), ...CRAPS_POINTS.map((n) => `odds:dontCome${n}`),
  ...CRAPS_POINTS.map((n) => `place${n}`),
  ...CRAPS_HARDWAYS.map((n) => `hard${n}`),
  ...CRAPS_ONE_ROLL_SPOTS,
];

/** A payout ratio [numerator, denominator] of the stake (winnings only). */
export type CrapsRatio = readonly [number, number];

/** Payouts (winnings per stake). */
export const CRAPS_PAYOUTS = {
  line: [1, 1] as CrapsRatio,
  place: { 4: [9, 5], 5: [7, 5], 6: [7, 6], 8: [7, 6], 9: [7, 5], 10: [9, 5] } as Record<CrapsPoint, CrapsRatio>,
  /** True odds behind pass / come. */
  odds: { 4: [2, 1], 5: [3, 2], 6: [6, 5], 8: [6, 5], 9: [3, 2], 10: [2, 1] } as Record<CrapsPoint, CrapsRatio>,
  /** Lay odds behind don't pass / don't come. */
  lay: { 4: [1, 2], 5: [2, 3], 6: [5, 6], 8: [5, 6], 9: [2, 3], 10: [1, 2] } as Record<CrapsPoint, CrapsRatio>,
  /** Field: 3, 4, 9, 10, 11 pay 1:1, 2 pays 2:1, 12 pays 3:1. */
  field: [1, 1] as CrapsRatio,
  field2: [2, 1] as CrapsRatio,
  field12: [3, 1] as CrapsRatio,
  hard: { 4: [7, 1], 6: [9, 1], 8: [9, 1], 10: [7, 1] } as Record<CrapsHardway, CrapsRatio>,
  any7: [4, 1] as CrapsRatio,
  anyCraps: [7, 1] as CrapsRatio,
  two: [30, 1] as CrapsRatio,
  three: [15, 1] as CrapsRatio,
  yo: [15, 1] as CrapsRatio,
  twelve: [30, 1] as CrapsRatio,
} as const;

/** Maximum odds behind pass / come, as a multiple of the flat bet (3-4-5×). */
export const CRAPS_ODDS_MULTIPLE: Record<CrapsPoint, number> = { 4: 3, 5: 4, 6: 5, 8: 5, 9: 4, 10: 3 };
/** Maximum lay odds behind don't pass / don't come, as a multiple of the flat bet. */
export const CRAPS_LAY_MULTIPLE = 6;
/** Increment (cents) of place 6/8 and of lay odds on 5, 9, 6, 8. */
export const CRAPS_INCREMENT_CENTS = 300;
/** Maximum total on one seat's board (`limits.maxRoundCents`), as a multiple of limits.maxBetCents. */
export const CRAPS_MAX_ROUND_MULTIPLE = 20;

/** Durations (ms). */
export const CRAPS_TIMING = {
  /** Betting window of a human shooter before the automatic roll. */
  shooterMs: 15_000,
  /** Window when the shooter is a bot (or nobody can shoot) and a human is seated. */
  botShooterMs: 8_000,
  /** Window when only bots are seated. */
  botsOnlyMs: 5_000,
  /** The shooter cannot throw earlier than this after the window opened. */
  minWindowMs: 3_000,
  /** Between the throw gesture and the dice being out (bets close). */
  diceOutMs: 600,
  /** Live phase: dice flying, bouncing on the back wall and landing. */
  rollMs: 2_800,
  /** Settled phase after a roll (payouts, puck). */
  settledMs: 2_600,
  /** Settled phase of a round without a roll (the dice passed on). */
  noRollSettledMs: 1_200,
} as const;

/** What a roll did to the line, from the point before the roll. */
export type CrapsVerdict =
  /** come-out 7 / 11 */
  | 'natural'
  /** come-out 2 / 3 / 12 */
  | 'craps'
  /** come-out 4–10: the point is set (puck ON) */
  | 'pointOn'
  /** point rolled: pass wins, puck OFF */
  | 'pointMade'
  /** 7 during the point: don't pass wins, the dice pass to the next shooter */
  | 'sevenOut'
  /** any other roll during the point */
  | 'roll';

export interface CrapsRoll {
  d1: number;
  d2: number;
  total: number;
  /** Point before the roll (null = come-out roll). */
  pointBefore: CrapsPoint | null;
  verdict: CrapsVerdict;
}

/** `gameTables/{id}.g` — public state. */
export interface CrapsPublic {
  /** Current point, null on the come-out. The puck is ON iff `point !== null`. */
  point: CrapsPoint | null;
  /** Seat of the shooter (null when no active seat can shoot: the house rolls for pending bets). */
  shooter: number | null;
  shooterUid: Uid | null;
  /** Rolls thrown by the current shooter, and the points they made. */
  shooterRolls: number;
  shooterPoints: number;
  /** The dice pass to the next player when the next round opens (set by a seven-out / a declined come-out). */
  passDice: 'sevenOut' | 'declined' | null;
  /** The shooter threw: dice out (bets closed) at this time, else null. */
  rollAt: EpochMs | null;
  /** The roll of the current round (phases live / settled), null while betting. */
  roll: CrapsRoll | null;
  /** Last dice shown on the layout ([d1, d2]), null before the first roll. */
  dice: [number, number] | null;
  /** Last rolls, most recent last (max CRAPS_HISTORY). */
  rolls: Array<{ d1: number; d2: number; round: number }>;
  /** Number of crapsPoint markets created (series number of the last one). */
  pointSeries: number;
}
export const CRAPS_HISTORY = 20;

/** `gameTables/{id}.seats[i].g` — seat state. */
export interface CrapsSeat {
  /** Power safetyNet armed on this seat's Pass Line bet (see header). */
  safetyNet: boolean;
}

/** `gameTables/{id}/private/state.g` — nothing secret: the dice are drawn from the round seed. */
export type CrapsPrivate = Record<string, never>;

/** Game action (besides the kernel's setBets): the shooter throws the dice. */
export type CrapsAction = { type: 'roll' };

/**
 * EVENTS (`table.events`, reset each round; kernel events join / leave / … too)
 *  - 'shooter'  {uid, reason: 'start' | 'sevenOut' | 'declined' | 'left'}  seat = new shooter (null: none)
 *  - 'throw'    {at}                     seat = shooter: the gesture; dice out at `at` (ms)
 *  - 'power'    {power: 'safetyNet'}     seat: its safety net is armed (betting closed)
 *  - 'noRoll'   {reason: 'noLineBet'}    seat = shooter who declined; no roll this round
 *  - 'roll'     {d1, d2, total, pointBefore, verdict}  dice drawn (live phase starts)
 *  - 'pay'      {wins: {spot: cents won}, lost: [spot], pushed: [spot], moved: {from: to},
 *                returned: [spot], net, safetyNet: cents refunded}   seat: what the roll did to its board
 *  - 'puck'     {point: N | null}        the puck moves (ON on N / OFF)
 *  - 'point'    {point}                  seat = shooter who made the point
 */
export type CrapsEventType = 'shooter' | 'throw' | 'power' | 'noRoll' | 'roll' | 'pay' | 'puck' | 'point';

/** `rounds/{n}.result` of a craps round. */
export interface CrapsRoundResult {
  /** [d1, d2], null when no roll happened (`noRoll`). */
  dice: [number, number] | null;
  total: number | null;
  pointBefore: CrapsPoint | null;
  pointAfter: CrapsPoint | null;
  verdict: CrapsVerdict | null;
  shooter: number | null;
  noRoll: boolean;
}

/** Settlement of one bet by a roll (engine output). */
export interface CrapsBetOutcome {
  spot: string;
  stake: Cents;
  /**
   * win (winnings paid; stake stays up or comes back, see header), lose, push (stake comes back),
   * travel (moved to `to`), refund (stake comes back undecided: leaving seat, safety net).
   */
  outcome: 'win' | 'lose' | 'push' | 'travel' | 'refund';
  /** Winnings (win only). */
  wonCents: Cents;
  /** The stake stays on the board (under `to` for a travel). */
  stays: boolean;
  to?: string;
}
