/**
 * Cards, shoes and hand values. Pure module: no Firebase, no I/O.
 *
 * A card is a 2-character code `${rank}${suit}`:
 *   rank ∈ "A23456789TJQK" (T = ten), suit ∈ "SHDC" (spades, hearts, diamonds, clubs).
 * Example: "AS" = ace of spades, "TH" = ten of hearts, "QC" = queen of clubs.
 */
import type { CardCode } from '../shared/types';

export const RANKS = 'A23456789TJQK';
export const SUITS = 'SHDC';
export const DECK_SIZE = 52;

const CODE_RE = /^[A23456789TJQK][SHDC]$/;

export function isCardCode(x: unknown): x is CardCode {
  return typeof x === 'string' && CODE_RE.test(x);
}

/** Blackjack point value of a card, ace counted as 1 (1..10). */
export function cardPoints(card: CardCode): number {
  const r = card[0];
  if (r === 'A') return 1;
  if (r === 'T' || r === 'J' || r === 'Q' || r === 'K') return 10;
  return r.charCodeAt(0) - 48;
}

export function isTenValue(card: CardCode): boolean {
  return cardPoints(card) === 10;
}

export function isAce(card: CardCode): boolean {
  return card[0] === 'A';
}

/** One 52-card deck in canonical order (suit-major, rank-minor). */
export function buildDeck(): CardCode[] {
  const out: CardCode[] = [];
  for (const s of SUITS) for (const r of RANKS) out.push(r + s);
  return out;
}

/** A fresh shoe of `decks` decks in canonical order (not shuffled). */
export function buildShoe(decks: number): CardCode[] {
  const out: CardCode[] = [];
  for (let d = 0; d < decks; d++) out.push(...buildDeck());
  return out;
}

/** Canonical total order used by the provably-fair verifier: rank index, then suit index. */
export function compareCards(a: CardCode, b: CardCode): number {
  const ra = RANKS.indexOf(a[0]);
  const rb = RANKS.indexOf(b[0]);
  if (ra !== rb) return ra - rb;
  return SUITS.indexOf(a[1]) - SUITS.indexOf(b[1]);
}

export function canonicalSort(cards: readonly CardCode[]): CardCode[] {
  return [...cards].sort(compareCards);
}

export interface HandValue {
  /** Best total ≤ 21 if possible, else the hard (minimum) total. */
  total: number;
  /** True when an ace is counted as 11 in `total`. */
  soft: boolean;
}

export function handValue(cards: readonly CardCode[]): HandValue {
  let hard = 0;
  let aces = 0;
  for (const c of cards) {
    const p = cardPoints(c);
    hard += p;
    if (p === 1) aces++;
  }
  if (aces > 0 && hard + 10 <= 21) return { total: hard + 10, soft: true };
  return { total: hard, soft: false };
}

/** Two-card 21. Whether it counts as a *natural* also depends on the hand not coming from a split. */
export function isTwoCardTwentyOne(cards: readonly CardCode[]): boolean {
  return cards.length === 2 && handValue(cards).total === 21;
}
