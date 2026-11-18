/**
 * Provably-fair dealing.
 *
 * Protocol (per hand):
 *  1. Before the hand, the server draws `seed` = 32 bytes from the CSPRNG (hex) and publishes
 *     `commit = SHA-256(seed)` (hex) on the public table document.
 *  2. The deal order of the hand is `fairDealOrder(remaining, seed)`: the cards still in the
 *     shoe are sorted canonically (rank "A23456789TJQK", then suit "SHDC") and shuffled with
 *     Fisher-Yates driven by `seededRng(seed)`. Cards are dealt from index 0 upward.
 *  3. After the hand, the server reveals `seed` and the pre-hand `remaining` multiset; anybody
 *     can check SHA-256(seed) == commit and recompute the exact card order.
 *
 * Re-permuting the undealt cards before each hand does not change the probability of any
 * event for a player who does not know the order, and it keeps card-composition effects
 * (cards already dealt from the shoe are gone), while making every hand independently
 * verifiable without leaking future cards.
 */
import { createHash } from 'node:crypto';
import type { CardCode } from '../shared/types';
import { buildShoe, canonicalSort } from './cards';
import { seededRng, shuffleInPlace } from './rng';

export function sha256Hex(s: string): string {
  return createHash('sha256').update(s).digest('hex');
}

export function commitForSeed(seedHex: string): string {
  return sha256Hex(seedHex);
}

/**
 * Deal order for one hand. In the (practically unreachable) case where a hand needs more
 * cards than remain, dealing continues into a fresh full shoe shuffled with
 * `seededRng(seed + ":refill")`, so the order stays fully determined by the seed.
 */
export function fairDealOrder(remaining: readonly CardCode[], seedHex: string, decks = 6): CardCode[] {
  const main = shuffleInPlace(canonicalSort(remaining), seededRng(seedHex));
  const refill = shuffleInPlace(buildShoe(decks), seededRng(`${seedHex}:refill`));
  return main.concat(refill);
}

export interface FairnessProof {
  commit: string;
  seed: string;
  /** Undealt cards before the hand (any order; canonicalised by the verifier). */
  remainingBefore: CardCode[];
  /** Cards in the order they were actually dealt during the hand. */
  dealt: CardCode[];
  decks?: number;
}

export function verifyFairness(p: FairnessProof): boolean {
  if (commitForSeed(p.seed) !== p.commit) return false;
  const order = fairDealOrder(p.remainingBefore, p.seed, p.decks ?? 6);
  if (p.dealt.length > order.length) return false;
  return p.dealt.every((c, i) => order[i] === c);
}
