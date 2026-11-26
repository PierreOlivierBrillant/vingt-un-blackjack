/**
 * Craps — pure engine (no Firebase, no clock, no Math.random): bet spot grammar, board validation
 * (contract bets, odds multiples, $3 increments, the shooter's line bet) and the settlement of one
 * roll for one board, exact to the cent. Rules and spot ids: shared/games/craps.ts.
 */
import type { Rng } from '../../engine/rng';
import { fail } from '../../shared/errors';
import {
  CRAPS_HARDWAYS, CRAPS_INCREMENT_CENTS, CRAPS_LAY_MULTIPLE, CRAPS_ODDS_MULTIPLE, CRAPS_ONE_ROLL_SPOTS, CRAPS_PAYOUTS,
  CRAPS_POINTS, CRAPS_SPOT_IDS,
  type CrapsBetOutcome, type CrapsHardway, type CrapsOneRollSpot, type CrapsPoint, type CrapsRatio, type CrapsVerdict,
} from '../../shared/games/craps';
import type { BetMap } from '../../shared/games/common';

// ============================================================================================
// spots

export type CrapsSpot =
  | { kind: 'pass' }
  | { kind: 'dontPass' }
  | { kind: 'come' }
  | { kind: 'dontCome' }
  | { kind: 'comeN'; n: CrapsPoint }
  | { kind: 'dontComeN'; n: CrapsPoint }
  | { kind: 'oddsPass' }
  | { kind: 'oddsDontPass' }
  | { kind: 'oddsComeN'; n: CrapsPoint }
  | { kind: 'oddsDontComeN'; n: CrapsPoint }
  | { kind: 'place'; n: CrapsPoint }
  | { kind: 'hard'; n: CrapsHardway }
  | { kind: 'oneRoll'; id: CrapsOneRollSpot };

const SPOTS = new Map<string, CrapsSpot>([
  ['pass', { kind: 'pass' }],
  ['dontPass', { kind: 'dontPass' }],
  ['come', { kind: 'come' }],
  ['dontCome', { kind: 'dontCome' }],
  ['odds:pass', { kind: 'oddsPass' }],
  ['odds:dontPass', { kind: 'oddsDontPass' }],
  ...CRAPS_POINTS.flatMap((n): Array<[string, CrapsSpot]> => [
    [`come${n}`, { kind: 'comeN', n }],
    [`dontCome${n}`, { kind: 'dontComeN', n }],
    [`odds:come${n}`, { kind: 'oddsComeN', n }],
    [`odds:dontCome${n}`, { kind: 'oddsDontComeN', n }],
    [`place${n}`, { kind: 'place', n }],
  ]),
  ...CRAPS_HARDWAYS.map((n): [string, CrapsSpot] => [`hard${n}`, { kind: 'hard', n }]),
  ...CRAPS_ONE_ROLL_SPOTS.map((id): [string, CrapsSpot] => [id, { kind: 'oneRoll', id }]),
]);

/** Spot of an id, or null (unknown id). */
export function parseSpot(id: string): CrapsSpot | null {
  return SPOTS.get(id) ?? null;
}

/** Canonical order of the spots (settlement, events, transcripts). */
const ORDER = new Map(CRAPS_SPOT_IDS.map((id, i) => [id, i]));
export function sortSpots(ids: Iterable<string>): string[] {
  return [...ids].sort((a, b) => (ORDER.get(a) ?? 1e9) - (ORDER.get(b) ?? 1e9) || a.localeCompare(b));
}

export const isPoint = (n: number): n is CrapsPoint => (CRAPS_POINTS as readonly number[]).includes(n);
const isOdds = (s: CrapsSpot) => s.kind === 'oddsPass' || s.kind === 'oddsDontPass' || s.kind === 'oddsComeN' || s.kind === 'oddsDontComeN';

/** Number of the 36 dice combinations that total `n`. */
export const waysOf = (n: number): number => (n >= 2 && n <= 12 ? 6 - Math.abs(7 - n) : 0);
/** Probability that point `n` is made before a seven. */
export const pMakePoint = (n: CrapsPoint): number => waysOf(n) / (waysOf(n) + 6);

export const hasLineBet = (b: BetMap): boolean => (b.pass ?? 0) > 0 || (b.dontPass ?? 0) > 0;

/** Contract bets of a board (cannot be taken down): pass once a point is ON, come numbers. */
export function contractBets(board: BetMap, point: CrapsPoint | null): BetMap {
  const out: BetMap = {};
  for (const [id, v] of Object.entries(board)) {
    if (v <= 0) continue;
    const s = parseSpot(id);
    if (!s) continue;
    if ((s.kind === 'pass' && point !== null) || s.kind === 'comeN') out[id] = v;
  }
  return out;
}

/** Base (flat) bet id of an odds spot. */
function oddsBase(s: CrapsSpot): string | null {
  switch (s.kind) {
    case 'oddsPass': return 'pass';
    case 'oddsDontPass': return 'dontPass';
    case 'oddsComeN': return `come${s.n}`;
    case 'oddsDontComeN': return `dontCome${s.n}`;
    default: return null;
  }
}

/** Maximum odds on `s` for flat bet `flat` with the current point (0 when not open). */
export function maxOdds(s: CrapsSpot, flat: number, point: CrapsPoint | null): number {
  switch (s.kind) {
    case 'oddsPass': return point === null ? 0 : flat * CRAPS_ODDS_MULTIPLE[point];
    case 'oddsDontPass': return point === null ? 0 : flat * CRAPS_LAY_MULTIPLE;
    case 'oddsComeN': return flat * CRAPS_ODDS_MULTIPLE[s.n];
    case 'oddsDontComeN': return flat * CRAPS_LAY_MULTIPLE;
    default: return 0;
  }
}

/** Whether amounts on `s` must be multiples of $3 (place 6/8, lay odds on 5, 9, 6, 8). */
export function needsIncrement(s: CrapsSpot, point: CrapsPoint | null): boolean {
  const n = s.kind === 'place' || s.kind === 'oddsDontComeN' ? s.n : s.kind === 'oddsDontPass' ? point : null;
  if (n === null) return false;
  if (s.kind === 'place') return n === 6 || n === 8;
  return n === 5 || n === 9 || n === 6 || n === 8;
}

// ============================================================================================
// validation

export interface BoardRules {
  point: CrapsPoint | null;
  minBetCents: number;
  maxBetCents: number;
  /** The seat is the shooter. */
  shooter: boolean;
}

/**
 * Validates the WHOLE desired board `next` against the `current` one (see the order of the checks in
 * shared/games/craps.ts « BET RULES »). Throws an AppError; returns nothing. Whole dollars and the
 * round total are checked by the kernel.
 */
export function checkBoard(next: BetMap, current: BetMap, r: BoardRules): void {
  const ids = new Set([...Object.keys(next), ...Object.keys(current)]);
  for (const id of Object.keys(next)) if (!parseSpot(id)) throw fail.invalid('BAD_BET_SPOT', `unknown craps spot ${id}`);
  if (r.shooter) {
    const total = Object.values(next).reduce((a, v) => a + v, 0);
    if (r.point === null && total > 0 && !hasLineBet(next)) throw fail.pre('MUST_BET_LINE', 'the shooter bets Pass or Don\'t Pass first');
    if (r.point !== null && hasLineBet(current) && !hasLineBet(next)) throw fail.pre('MUST_BET_LINE', 'the shooter keeps a line bet during the point');
  }
  for (const id of sortSpots(ids)) {
    const s = parseSpot(id);
    if (!s) continue; // unknown ids of `current` (never written by the server) are simply dropped
    const a = next[id] ?? 0;
    const c = current[id] ?? 0;
    switch (s.kind) {
      case 'pass':
        if (r.point !== null && a < c) throw fail.pre('BET_NOT_REMOVABLE', 'the Pass Line is a contract bet once a point is ON');
        if (r.point !== null && a > c) throw fail.pre('BET_NOT_OPEN', 'Pass Line bets are made on the come-out');
        break;
      case 'dontPass':
        if (r.point !== null && a > c) throw fail.pre('BET_NOT_OPEN', 'Don\'t Pass bets are made on the come-out');
        break;
      case 'come':
      case 'dontCome':
        if (r.point === null && a > c) throw fail.pre('BET_NOT_OPEN', 'Come / Don\'t Come bets need a point');
        break;
      case 'comeN':
        if (a > c) throw fail.pre('BET_NOT_OPEN', 'a Come bet reaches its number by itself');
        if (a < c) throw fail.pre('BET_NOT_REMOVABLE', 'a Come bet on its number is a contract bet');
        break;
      case 'dontComeN':
        if (a > c) throw fail.pre('BET_NOT_OPEN', 'a Don\'t Come bet reaches its number by itself');
        break;
      default:
        if (isOdds(s) && a > 0) {
          const base = next[oddsBase(s)!] ?? 0;
          if (base <= 0 || ((s.kind === 'oddsPass' || s.kind === 'oddsDontPass') && r.point === null)) {
            throw fail.pre('BET_NOT_OPEN', 'odds go behind a flat bet with a point');
          }
        }
    }
  }
  for (const id of sortSpots(Object.keys(next))) {
    const s = parseSpot(id)!;
    const a = next[id];
    if (a <= 0) continue;
    if (isOdds(s)) {
      const max = maxOdds(s, next[oddsBase(s)!] ?? 0, r.point);
      if (a < 100 || a > max) throw fail.invalid('BET_OUT_OF_RANGE', `odds on ${id}: at most ${max / 100} $`);
    } else if (a < r.minBetCents || a > r.maxBetCents) {
      throw fail.invalid('BET_OUT_OF_RANGE', `${id}: between ${r.minBetCents / 100} $ and ${r.maxBetCents / 100} $`);
    }
    if (needsIncrement(s, r.point) && a % CRAPS_INCREMENT_CENTS !== 0) {
      throw fail.invalid('BET_INCREMENT', `${id}: by multiples of $3 (place 6/8, lay odds on 5, 9, 6, 8)`);
    }
  }
}

// ============================================================================================
// the roll

/** The two dice of a round: `nextInt(6) + 1` twice from the round's provably-fair stream. */
export function rollDice(rng: Rng): [number, number] {
  const d1 = rng.nextInt(6) + 1;
  const d2 = rng.nextInt(6) + 1;
  return [d1, d2];
}

export function verdictOf(pointBefore: CrapsPoint | null, total: number): CrapsVerdict {
  if (pointBefore === null) {
    if (total === 7 || total === 11) return 'natural';
    if (total === 2 || total === 3 || total === 12) return 'craps';
    return 'pointOn';
  }
  if (total === pointBefore) return 'pointMade';
  if (total === 7) return 'sevenOut';
  return 'roll';
}

export function pointAfter(pointBefore: CrapsPoint | null, total: number): CrapsPoint | null {
  const v = verdictOf(pointBefore, total);
  if (v === 'pointOn') return total as CrapsPoint;
  if (v === 'roll') return pointBefore;
  return null;
}

export interface RollContext {
  pointBefore: CrapsPoint | null;
  d1: number;
  d2: number;
  /** The seat's safety net is armed. */
  safetyNet: boolean;
  /** The seat is leaving: only pending contract bets stay on the board. */
  leaving: boolean;
}

export interface BoardSettlement {
  /** Every bet touched by the roll (undecided bets that simply stay are not listed). */
  outcomes: CrapsBetOutcome[];
  /** What stays on the board. */
  carry: BetMap;
  /** Money that left the board (board − carry). */
  stakedCents: number;
  /** Paid to the wallet (stakes coming back + winnings). */
  returnCents: number;
  netCents: number;
  /** Stake of the bets decided by the roll (won, lost, pushed, refunded by the safety net). */
  actionCents: number;
  hardways: number;
  longShots: number;
  /** Pass Line stake refunded by the safety net (0 if none). */
  safetyNetRefund: number;
  /** The Pass Line bet covered by the net is decided (or gone): the net is spent. */
  safetyNetSpent: boolean;
}

/** Winnings of `stake` at `ratio`, exact to the cent (validation guarantees divisibility). */
export function winnings(stake: number, [num, den]: CrapsRatio): number {
  const w = (stake * num) / den;
  if (!Number.isSafeInteger(w)) throw new Error(`craps: inexact payout ${stake} × ${num}/${den}`);
  return w;
}

type Res =
  | { o: 'win'; w: number; stays: boolean }
  | { o: 'lose' }
  | { o: 'push'; stays: boolean }
  | { o: 'refund' }
  | { o: 'travel'; to: string }
  | { o: 'none' };

const WIN = (stake: number, ratio: CrapsRatio, stays: boolean): Res => ({ o: 'win', w: winnings(stake, ratio), stays });
const LOSE: Res = { o: 'lose' };
const NONE: Res = { o: 'none' };

function resolveSpot(s: CrapsSpot, v: number, r: RollContext): Res {
  const T = r.d1 + r.d2;
  const hard = r.d1 === r.d2;
  const P = r.pointBefore;
  const natural = T === 7 || T === 11;
  const craps = T === 2 || T === 3 || T === 12;
  switch (s.kind) {
    case 'pass':
      if (P === null) return natural ? WIN(v, CRAPS_PAYOUTS.line, true) : craps ? LOSE : NONE;
      if (T === P) return WIN(v, CRAPS_PAYOUTS.line, true);
      if (T === 7) return r.safetyNet ? { o: 'refund' } : LOSE;
      return NONE;
    case 'dontPass':
      if (P === null) {
        if (T === 2 || T === 3) return WIN(v, CRAPS_PAYOUTS.line, true);
        if (T === 12) return { o: 'push', stays: true };
        return natural ? LOSE : NONE;
      }
      if (T === 7) return WIN(v, CRAPS_PAYOUTS.line, true);
      return T === P ? LOSE : NONE;
    case 'come':
      if (natural) return WIN(v, CRAPS_PAYOUTS.line, false);
      if (craps) return LOSE;
      return { o: 'travel', to: `come${T}` };
    case 'dontCome':
      if (T === 2 || T === 3) return WIN(v, CRAPS_PAYOUTS.line, false);
      if (T === 12) return { o: 'push', stays: false };
      if (natural) return LOSE;
      return { o: 'travel', to: `dontCome${T}` };
    case 'comeN':
      if (T === s.n) return WIN(v, CRAPS_PAYOUTS.line, false);
      return T === 7 ? LOSE : NONE;
    case 'dontComeN':
      if (T === 7) return WIN(v, CRAPS_PAYOUTS.line, false);
      return T === s.n ? LOSE : NONE;
    case 'oddsPass':
      if (P === null) return { o: 'refund' }; // never valid on the come-out: comes back
      if (T === P) return WIN(v, CRAPS_PAYOUTS.odds[P], false);
      return T === 7 ? LOSE : NONE;
    case 'oddsDontPass':
      if (P === null) return { o: 'refund' };
      if (T === 7) return WIN(v, CRAPS_PAYOUTS.lay[P], false);
      return T === P ? LOSE : NONE;
    case 'oddsComeN':
      // come odds are OFF on the come-out: returned when their come bet is decided then
      if (T === s.n) return P === null ? { o: 'push', stays: false } : WIN(v, CRAPS_PAYOUTS.odds[s.n], false);
      if (T === 7) return P === null ? { o: 'push', stays: false } : LOSE;
      return NONE;
    case 'oddsDontComeN':
      if (T === 7) return WIN(v, CRAPS_PAYOUTS.lay[s.n], false);
      return T === s.n ? LOSE : NONE;
    case 'place':
      if (P === null) return NONE; // off on the come-out
      if (T === s.n) return WIN(v, CRAPS_PAYOUTS.place[s.n], true);
      return T === 7 ? LOSE : NONE;
    case 'hard':
      if (P === null) return NONE; // off on the come-out
      if (T === s.n) return hard ? WIN(v, CRAPS_PAYOUTS.hard[s.n], true) : LOSE;
      return T === 7 ? LOSE : NONE;
    case 'oneRoll':
      switch (s.id) {
        case 'field':
          if (T === 2) return WIN(v, CRAPS_PAYOUTS.field2, false);
          if (T === 12) return WIN(v, CRAPS_PAYOUTS.field12, false);
          return T === 3 || T === 4 || T === 9 || T === 10 || T === 11 ? WIN(v, CRAPS_PAYOUTS.field, false) : LOSE;
        case 'any7': return T === 7 ? WIN(v, CRAPS_PAYOUTS.any7, false) : LOSE;
        case 'anyCraps': return craps ? WIN(v, CRAPS_PAYOUTS.anyCraps, false) : LOSE;
        case 'two': return T === 2 ? WIN(v, CRAPS_PAYOUTS.two, false) : LOSE;
        case 'three': return T === 3 ? WIN(v, CRAPS_PAYOUTS.three, false) : LOSE;
        case 'yo': return T === 11 ? WIN(v, CRAPS_PAYOUTS.yo, false) : LOSE;
        case 'twelve': return T === 12 ? WIN(v, CRAPS_PAYOUTS.twelve, false) : LOSE;
      }
  }
}

/** Settles one board for one roll (see shared/games/craps.ts « WHAT STAYS UP »). Pure, exact. */
export function settleBoard(board: BetMap, r: RollContext): BoardSettlement {
  const T = r.d1 + r.d2;
  const after = pointAfter(r.pointBefore, T);
  const outcomes: CrapsBetOutcome[] = [];
  const carry: BetMap = {};
  const keep = (id: string, v: number) => { carry[id] = (carry[id] ?? 0) + v; };
  let ret = 0;
  let action = 0;
  let hardways = 0;
  let longShots = 0;
  let netRefund = 0;
  let passDecided = (board.pass ?? 0) <= 0;
  for (const id of sortSpots(Object.keys(board))) {
    const v = board[id];
    const s = parseSpot(id);
    if (!(v > 0)) continue;
    if (!s) { // not a craps spot (never written by the server): give it back
      ret += v;
      outcomes.push({ spot: id, stake: v, outcome: 'refund', wonCents: 0, stays: false });
      continue;
    }
    let res = resolveSpot(s, v, r);
    if (r.leaving) {
      // a player who left keeps only pending contract bets on the board
      if ((res.o === 'win' || res.o === 'push') && res.stays) res = res.o === 'win' ? { ...res, stays: false } : { o: 'push', stays: false };
      else if (res.o === 'none') {
        const contract = (s.kind === 'pass' && after !== null) || s.kind === 'comeN';
        if (!contract) res = { o: 'refund' };
      }
    }
    if (s.kind === 'pass' && res.o !== 'none') passDecided = true;
    switch (res.o) {
      case 'none':
        keep(id, v);
        break;
      case 'travel':
        keep(res.to, v);
        outcomes.push({ spot: id, stake: v, outcome: 'travel', wonCents: 0, stays: true, to: res.to });
        break;
      case 'win':
        ret += res.w + (res.stays ? 0 : v);
        if (res.stays) keep(id, v);
        action += v;
        if (s.kind === 'hard') hardways++;
        if (s.kind === 'oneRoll' && (s.id === 'two' || s.id === 'three' || s.id === 'yo' || s.id === 'twelve')) longShots++;
        outcomes.push({ spot: id, stake: v, outcome: 'win', wonCents: res.w, stays: res.stays });
        break;
      case 'lose':
        action += v;
        outcomes.push({ spot: id, stake: v, outcome: 'lose', wonCents: 0, stays: false });
        break;
      case 'push':
        if (res.stays) keep(id, v);
        else ret += v;
        action += v;
        outcomes.push({ spot: id, stake: v, outcome: 'push', wonCents: 0, stays: res.stays });
        break;
      case 'refund': {
        ret += v;
        // a Pass Line bet is only ever refunded by the safety net (seven-out): a decided bet
        if (s.kind === 'pass') { netRefund = v; action += v; }
        outcomes.push({ spot: id, stake: v, outcome: 'refund', wonCents: 0, stays: false });
        break;
      }
    }
  }
  const before = Object.values(board).reduce((a, v) => a + (v > 0 ? v : 0), 0);
  const kept = Object.values(carry).reduce((a, v) => a + v, 0);
  const staked = before - kept;
  return {
    outcomes, carry, stakedCents: staked, returnCents: ret, netCents: ret - staked, actionCents: action, hardways, longShots,
    safetyNetRefund: netRefund, safetyNetSpent: passDecided,
  };
}
