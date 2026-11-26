/**
 * Fairness / evaluator vectors shared with the Dart verifier: app/assets/fairness/holdem_vectors.json
 * (regenerate deliberately with `npx vitest run --config vitest.unit.config.mts test/unit/holdem/vectors.test.ts -u`).
 * Each deal: fairDealOrder(buildShoe(1), seed, 1), fixed positions (holdemDeckLayout), every hole
 * card, the board, each player's best hand and the winners. Plus standalone 7-card evaluations.
 */
import { describe, expect, it } from 'vitest';
import { buildShoe, commitForSeed, fairDealOrder, fastRng, sha256Hex, shuffleInPlace } from '../../../src/engine';
import { evaluateHand } from '../../../src/games/holdem/engineHand';
import { holdemDeckLayout } from '../../../src/shared/games/holdem';

function deal(seed: string, order: number[]) {
  const n = order.length;
  const L = holdemDeckLayout(n);
  const dealt = fairDealOrder(buildShoe(1), seed, 1).slice(0, L.total);
  const holes: Record<string, string[]> = {};
  order.forEach((seat, k) => { holes[String(seat)] = [dealt[L.hole(k, 0)], dealt[L.hole(k, 1)]]; });
  const board = [...L.flop.map((i) => dealt[i]), dealt[L.turn], dealt[L.river]];
  const hands: Record<string, { category: string; score: number; best: string[] }> = {};
  for (const seat of order) hands[String(seat)] = evaluateHand([...holes[String(seat)], ...board]);
  const top = Math.max(...Object.values(hands).map((h) => h.score));
  return {
    seed, commit: commitForSeed(seed), players: n, order, dealt, holes, burns: L.burns.map((i) => dealt[i]), board, hands,
    winners: order.filter((s) => hands[String(s)].score === top).sort((a, b) => a - b),
  };
}

export function holdemVectors() {
  const deals = [];
  const orders = [[0, 1], [1, 0], [3, 5, 0], [2, 3, 4, 5], [5, 0, 1, 2, 3], [1, 2, 3, 4, 5, 0]];
  for (let i = 0; i < 12; i++) deals.push(deal(sha256Hex(`holdem-vector-${i}`), orders[i % orders.length]));
  const rng = fastRng(2026);
  const hands = [];
  // classic and tricky 7-card hands, then random ones
  const fixed: string[][] = [
    ['AS', 'KS', 'QS', 'JS', 'TS', '2H', '3D'], // royal flush
    ['5H', '4H', '3H', '2H', 'AH', 'KD', 'KC'], // steel wheel
    ['9C', '9D', '9H', '9S', 'KD', 'KC', '2S'], // quads, king kicker
    ['QS', 'QH', 'QD', '7C', '7D', '7S', '2C'], // two trips: full house queens over sevens
    ['AS', 'AH', 'KD', 'KC', 'QS', 'QH', 'JD'], // three pairs: aces and kings, queen kicker
    ['AS', '2D', '3C', '4H', '5S', '9D', 'KC'], // wheel
    ['AS', 'KD', 'QC', 'JH', 'TS', '9D', '8C'], // broadway
    ['2S', '7S', '9S', 'JS', 'KS', 'AS', '3H'], // six-card flush
    ['8D', '8C', '4S', '4H', '2D', '2C', 'AS'], // two pair + third pair
    ['TS', 'TH', '3D', '6C', '8S', 'QD', 'KH'], // pair
    ['2C', '4D', '6H', '8S', 'TC', 'QD', 'AH'], // high card
  ];
  for (const f of fixed) hands.push({ cards: f, ...evaluateHand(f) });
  for (let i = 0; i < 40; i++) {
    const deck = shuffleInPlace(buildShoe(1), rng);
    const cards = deck.slice(0, 5 + (i % 3));
    hands.push({ cards, ...evaluateHand(cards) });
  }
  return {
    about: 'Hold\'em vectors computed by firebase/functions (fairDealOrder(buildShoe(1), seed, 1), holdemDeckLayout, evaluateHand). Do not edit by hand.',
    deals,
    hands,
  };
}

describe('hold\'em shared vectors (TypeScript ⇄ Dart)', () => {
  it('matches app/assets/fairness/holdem_vectors.json', async () => {
    await expect(JSON.stringify(holdemVectors(), null, 1) + '\n').toMatchFileSnapshot('../../../../../app/assets/fairness/holdem_vectors.json');
  });
});
