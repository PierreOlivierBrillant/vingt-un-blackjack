/**
 * Pure engine of the European roulette (no Firebase, no clock, no randomness of its own):
 * wheel order and colours, the bet spot grammar (shared/games/roulette.ts), payouts exact to the
 * cent, board validation against the per-type caps, the zero shield ("la partage") and the
 * French call bets (annonces) used by the bots — the client computes its own (Dart mirror,
 * checked against the shared vectors app/assets/fairness/roulette_vectors.json).
 */
import { fail } from '../../shared/errors';
import type { BetMap, GameLimits } from '../../shared/games/common';
import {
  ROULETTE_EVEN_SPOTS, ROULETTE_LIMIT_KEYS, ROULETTE_PAYOUTS, type RouletteColor, type RouletteSpotType,
} from '../../shared/games/roulette';
import { STAKE_TIER_LIMITS, type StakeTier } from '../../shared/types';

/** The 37 pockets clockwise from the zero, as on a real European wheel. */
export const WHEEL_ORDER: readonly number[] = Object.freeze([
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
]);

export const RED_NUMBERS: readonly number[] = Object.freeze([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]);
const RED = new Set(RED_NUMBERS);

export function colorOf(n: number): RouletteColor {
  if (n === 0) return 'green';
  return RED.has(n) ? 'red' : 'black';
}

export interface SpotDef {
  id: string;
  type: RouletteSpotType;
  /** Numbers covered (ascending). */
  numbers: readonly number[];
}

function buildSpots(): Map<string, SpotDef> {
  const m = new Map<string, SpotDef>();
  const add = (id: string, type: RouletteSpotType, numbers: number[]) => {
    m.set(id, { id, type, numbers: Object.freeze([...numbers].sort((a, b) => a - b)) });
  };
  for (let n = 0; n <= 36; n++) add(`n${n}`, 'straight', [n]);
  for (const b of [1, 2, 3]) add(`sp0-${b}`, 'split', [0, b]);
  for (let a = 1; a <= 36; a++) {
    if (a % 3 !== 0) add(`sp${a}-${a + 1}`, 'split', [a, a + 1]);
    if (a + 3 <= 36) add(`sp${a}-${a + 3}`, 'split', [a, a + 3]);
  }
  for (let a = 1; a <= 34; a += 3) add(`st${a}`, 'street', [a, a + 1, a + 2]);
  add('tr0-1-2', 'trio', [0, 1, 2]);
  add('tr0-2-3', 'trio', [0, 2, 3]);
  for (let a = 1; a <= 32; a++) if (a % 3 !== 0) add(`co${a}`, 'corner', [a, a + 1, a + 3, a + 4]);
  add('first4', 'firstFour', [0, 1, 2, 3]);
  for (let a = 1; a <= 31; a += 3) add(`ln${a}`, 'line', [a, a + 1, a + 2, a + 3, a + 4, a + 5]);
  const range = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => from + i);
  for (const d of [1, 2, 3]) add(`dozen${d}`, 'dozen', range(12 * d - 11, 12 * d));
  for (const c of [1, 2, 3]) add(`col${c}`, 'column', range(1, 36).filter((n) => (n - c) % 3 === 0));
  add('red', 'even', [...RED_NUMBERS]);
  add('black', 'even', range(1, 36).filter((n) => !RED.has(n)));
  add('odd', 'even', range(1, 36).filter((n) => n % 2 === 1));
  add('even', 'even', range(1, 36).filter((n) => n % 2 === 0));
  add('low', 'even', range(1, 18));
  add('high', 'even', range(19, 36));
  return m;
}

/** Every valid spot id → its definition (157 spots). */
export const SPOTS: ReadonlyMap<string, SpotDef> = buildSpots();
const EVEN_IDS = new Set<string>(ROULETTE_EVEN_SPOTS);

export function spotOf(id: string): SpotDef | null {
  return SPOTS.get(id) ?? null;
}

export function isEvenMoney(id: string): boolean {
  return EVEN_IDS.has(id);
}

/** Return (stake included) of `stakeCents` on `spot` for the drawn number `n`. */
export function spotReturn(spot: SpotDef, stakeCents: number, n: number, shield = false): number {
  if (spot.numbers.includes(n)) return stakeCents * (ROULETTE_PAYOUTS[spot.type] + 1);
  if (shield && n === 0 && spot.type === 'even') return stakeCents / 2; // whole dollars: always a whole cent
  return 0;
}

export interface BoardOutcome {
  /** Total returned to the player (winning stakes included). */
  returnCents: number;
  /** Winning spot ids (stake × (payout + 1)), in board order. */
  wins: string[];
  /** A plein won. */
  straightHit: boolean;
  /** Cents given back by the zero shield. */
  shieldCents: number;
}

/** Settles a whole board for the number `n` (spots must be valid). */
export function settleBoard(board: BetMap, n: number, shield = false): BoardOutcome {
  let ret = 0;
  let shieldCents = 0;
  const wins: string[] = [];
  let straightHit = false;
  for (const [id, cents] of Object.entries(board)) {
    if (cents <= 0) continue;
    const spot = SPOTS.get(id);
    if (!spot) throw new Error(`roulette: unknown spot ${id}`);
    const r = spotReturn(spot, cents, n, shield);
    if (spot.numbers.includes(n)) {
      wins.push(id);
      if (spot.type === 'straight') straightHit = true;
    } else if (r > 0) {
      shieldCents += r;
    }
    ret += r;
  }
  return { returnCents: ret, wins, straightHit, shieldCents };
}

// ------------------------------------------------------------------------------------------
// limits

/** Per-spot cap of each type for a tier (fraction of the tier's maximum, see rouletteLimits). */
const CAP_FRACTION: Record<string, number> = {
  straightMaxCents: 0.25, splitMaxCents: 0.5, streetMaxCents: 0.75, cornerMaxCents: 1, lineMaxCents: 1, dozenMaxCents: 1, evenMaxCents: 1,
};

/**
 * Table limits of a tier: STAKE_TIER_LIMITS (min $1 / $5 / $25, max per spot $100 / $500 /
 * $2,500 on the outside bets), inside bets capped by the numbers they cover (plein ¼ of the
 * maximum, cheval ½, transversale ¾, carré and above the maximum), 5 × the maximum per round.
 */
export function rouletteLimits(tier: StakeTier): GameLimits {
  const t = STAKE_TIER_LIMITS[tier];
  const extra: Record<string, number> = {};
  for (const [key, f] of Object.entries(CAP_FRACTION)) extra[key] = Math.round((t.maxBetCents * f) / 100) * 100;
  return { minBetCents: t.minBetCents, maxBetCents: t.maxBetCents, maxRoundCents: t.maxBetCents * 5, extra };
}

/** Cap of one spot of `type` under `limits` (falls back to maxBetCents if a key is missing). */
export function spotCap(type: RouletteSpotType, limits: GameLimits): number {
  return Math.min(limits.extra[ROULETTE_LIMIT_KEYS[type]] ?? limits.maxBetCents, limits.maxBetCents);
}

/**
 * Validates a whole board (spot ids, per-spot min / per-type max). The kernel checks whole
 * dollars, the round total and the money. Returns a copy without zero entries.
 */
export function validateBoard(board: BetMap, limits: GameLimits): BetMap {
  const out: BetMap = {};
  for (const [id, cents] of Object.entries(board)) {
    const spot = SPOTS.get(id);
    if (!spot) throw fail.invalid('BAD_BET_SPOT', `unknown roulette spot ${id}`);
    if (cents === 0) continue;
    if (!Number.isSafeInteger(cents) || cents < limits.minBetCents || cents > spotCap(spot.type, limits)) {
      throw fail.invalid('BET_OUT_OF_RANGE', `${id}: ${cents}`);
    }
    out[id] = cents;
  }
  return out;
}

export function hasEvenMoney(board: BetMap): boolean {
  return Object.entries(board).some(([id, v]) => v > 0 && EVEN_IDS.has(id));
}

// ------------------------------------------------------------------------------------------
// call bets (annonces) — units per spot; the client multiplies by its chip

export const ANNOUNCE_IDS = ['voisins', 'tiers', 'orphelins', 'jeuZero'] as const;
export type AnnounceId = (typeof ANNOUNCE_IDS)[number];

export const ANNOUNCES: Readonly<Record<AnnounceId, Readonly<Record<string, number>>>> = Object.freeze({
  // Voisins du zéro: 17 numbers, 9 chips (trio 0-2-3 and the corner 25-29 take two).
  voisins: { 'tr0-2-3': 2, 'sp4-7': 1, 'sp12-15': 1, 'sp18-21': 1, 'sp19-22': 1, 'sp32-35': 1, co25: 2 },
  // Tiers du cylindre: 12 numbers, 6 splits.
  tiers: { 'sp5-8': 1, 'sp10-11': 1, 'sp13-16': 1, 'sp23-24': 1, 'sp27-30': 1, 'sp33-36': 1 },
  // Orphelins: 8 numbers, 5 chips.
  orphelins: { n1: 1, 'sp6-9': 1, 'sp14-17': 1, 'sp17-20': 1, 'sp31-34': 1 },
  // Jeu zéro: 7 numbers, 4 chips.
  jeuZero: { 'sp0-3': 1, 'sp12-15': 1, n26: 1, 'sp32-35': 1 },
});

/** `n` and its `k` neighbours on each side of the wheel, in wheel order (2k + 1 pleins). */
export function wheelNeighbours(n: number, k = 2): number[] {
  const i = WHEEL_ORDER.indexOf(n);
  if (i < 0) throw new RangeError(`not a roulette number: ${n}`);
  const out: number[] = [];
  for (let d = -k; d <= k; d++) out.push(WHEEL_ORDER[(i + d + 37 * (k + 1)) % 37]);
  return out;
}

/** Board of a call bet with `unitCents` per chip (neighbours: `n` and k = 2). */
export function announceBoard(id: AnnounceId | 'neighbours', unitCents: number, n = 0): BetMap {
  const out: BetMap = {};
  if (id === 'neighbours') {
    for (const x of wheelNeighbours(n, 2)) out[`n${x}`] = unitCents;
    return out;
  }
  for (const [spot, units] of Object.entries(ANNOUNCES[id])) out[spot] = units * unitCents;
  return out;
}

/** Numbers covered by a board (sorted). */
export function coveredNumbers(board: BetMap): number[] {
  const s = new Set<number>();
  for (const [id, v] of Object.entries(board)) if (v > 0) for (const n of SPOTS.get(id)?.numbers ?? []) s.add(n);
  return [...s].sort((a, b) => a - b);
}

/** Adds `b` into `a` (new board). */
export function addBoards(a: BetMap, b: BetMap): BetMap {
  const out: BetMap = { ...a };
  for (const [k, v] of Object.entries(b)) out[k] = (out[k] ?? 0) + v;
  return out;
}
