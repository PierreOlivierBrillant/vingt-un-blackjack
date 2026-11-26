/**
 * Hold'em hand evaluator: the best 5-card poker hand among 5, 6 or 7 cards. Pure, no I/O.
 * Ported to Dart line for line (app/lib/features/games/holdem/holdem_evaluator.dart) and checked
 * against the shared vectors (app/assets/fairness/holdem_vectors.json).
 *
 * Score (see shared/games/holdem.ts): `category × 16^5 + Σ rank(best[i]) × 16^(4−i)`, ranks 2..14
 * (ace 14, except the ace of a wheel A-2-3-4-5 which counts 1). Equal scores = exact tie.
 * `best` lists the 5 cards in significance order (equal ranks: suits S, H, D, C).
 */
import type { CardCode } from '../../shared/types';
import { HOLDEM_HAND_CATEGORIES, type HoldemHandCategory } from '../../shared/games/holdem';

export interface HandValue {
  category: HoldemHandCategory;
  score: number;
  best: CardCode[];
}

const RANK_VALUE: Record<string, number> = { A: 14, K: 13, Q: 12, J: 11, T: 10, '9': 9, '8': 8, '7': 7, '6': 6, '5': 5, '4': 4, '3': 3, '2': 2 };
const SUIT_ORDER = 'SHDC';

export const rankValue = (c: CardCode): number => RANK_VALUE[c[0]];
const suitIndex = (c: CardCode): number => SUIT_ORDER.indexOf(c[1]);

/** Rank descending, then suit S, H, D, C. */
function byStrength(a: CardCode, b: CardCode): number {
  return rankValue(b) - rankValue(a) || suitIndex(a) - suitIndex(b);
}

function scoreOf(category: HoldemHandCategory, best: CardCode[], wheel: boolean): number {
  let s = HOLDEM_HAND_CATEGORIES.indexOf(category);
  for (let i = 0; i < 5; i++) {
    const r = wheel && i === 4 ? 1 : rankValue(best[i]);
    s = s * 16 + r;
  }
  return s;
}

/** Highest straight among `sorted` (rank desc): 5 cards top-down (wheel 5-4-3-2-A), or null. */
function straightOf(sorted: CardCode[]): { cards: CardCode[]; wheel: boolean } | null {
  const firstOfRank = new Map<number, CardCode>();
  for (const c of sorted) if (!firstOfRank.has(rankValue(c))) firstOfRank.set(rankValue(c), c);
  for (let top = 14; top >= 6; top--) {
    const run: CardCode[] = [];
    for (let r = top; r > top - 5; r--) {
      const c = firstOfRank.get(r);
      if (!c) break;
      run.push(c);
    }
    if (run.length === 5) return { cards: run, wheel: false };
  }
  const wheel = [5, 4, 3, 2, 14].map((r) => firstOfRank.get(r));
  if (wheel.every((c) => c !== undefined)) return { cards: wheel as CardCode[], wheel: true };
  return null;
}

function make(category: HoldemHandCategory, best: CardCode[], wheel = false): HandValue {
  return { category, score: scoreOf(category, best, wheel), best };
}

/** Best hand of 5 to 7 distinct cards. */
export function evaluateHand(cards: readonly CardCode[]): HandValue {
  if (cards.length < 5 || cards.length > 7) throw new Error(`evaluateHand: ${cards.length} cards`);
  const sorted = [...cards].sort(byStrength);

  // Flush / straight flush.
  let flush: CardCode[] | null = null;
  for (const s of SUIT_ORDER) {
    const suited = sorted.filter((c) => c[1] === s);
    if (suited.length >= 5) { flush = suited; break; }
  }
  if (flush) {
    const sf = straightOf(flush);
    if (sf) return make('straightFlush', sf.cards, sf.wheel);
  }

  // Groups of equal rank: count desc, then rank desc (cards inside a group in suit order).
  const groups = new Map<number, CardCode[]>();
  for (const c of sorted) {
    const g = groups.get(rankValue(c));
    if (g) g.push(c);
    else groups.set(rankValue(c), [c]);
  }
  const ordered = [...groups.values()].sort((a, b) => b.length - a.length || rankValue(b[0]) - rankValue(a[0]));
  const kickers = (used: CardCode[], n: number) => sorted.filter((c) => !used.includes(c)).slice(0, n);

  const top = ordered[0];
  if (top.length === 4) return make('quads', [...top, ...kickers(top, 1)]);

  if (top.length === 3) {
    const pair = ordered.slice(1).find((g) => g.length >= 2);
    if (pair) return make('fullHouse', [...top, ...pair.slice(0, 2)]);
  }
  if (flush) return make('flush', flush.slice(0, 5));

  const st = straightOf(sorted);
  if (st) return make('straight', st.cards, st.wheel);

  if (top.length === 3) return make('trips', [...top, ...kickers(top, 2)]);
  if (top.length === 2) {
    const second = ordered[1];
    if (second && second.length === 2) {
      const used = [...top, ...second];
      return make('twoPair', [...used, ...kickers(used, 1)]);
    }
    return make('pair', [...top, ...kickers(top, 3)]);
  }
  return make('highCard', sorted.slice(0, 5));
}

/** Brute force over every 5-card subset (reference implementation for the tests). */
export function evaluateHandBrute(cards: readonly CardCode[]): HandValue {
  let best: HandValue | null = null;
  const n = cards.length;
  for (let a = 0; a < n; a++) for (let b = a + 1; b < n; b++) for (let c = b + 1; c < n; c++)
    for (let d = c + 1; d < n; d++) for (let e = d + 1; e < n; e++) {
      const v = evaluateHand([cards[a], cards[b], cards[c], cards[d], cards[e]]);
      if (!best || v.score > best.score) best = v;
    }
  return best!;
}
