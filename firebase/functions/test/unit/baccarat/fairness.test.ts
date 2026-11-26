/**
 * Fairness vectors shared with the Dart verifier (app/lib/features/games/baccarat/baccarat_fairness.dart,
 * test app/test/unit/baccarat_fairness_test.dart): seed + shoe (+ burn) → deal order → coup.
 * Written to app/assets/fairness/baccarat_vectors.json (one vector per line). Regenerate
 * deliberately with `npx vitest run --config vitest.unit.config.mts test/unit/baccarat/fairness.test.ts -u`.
 */
import { describe, expect, it } from 'vitest';
import { buildShoe, canonicalSort } from '../../../src/engine/cards';
import { commitForSeed, fairDealOrder, sha256Hex, verifyFairness } from '../../../src/engine/fair';
import { dealCoup, type DealtCoup } from '../../../src/games/baccarat/engine';
import type { CardCode } from '../../../src/shared/types';

interface Vector {
  name: string;
  seed: string;
  commit: string;
  decks: number;
  burn: boolean;
  remainingBefore: CardCode[];
  expected: Omit<DealtCoup, 'burn'> & { burn: DealtCoup['burn'] };
}

function vector(name: string, seed: string, remainingBefore: CardCode[], burn: boolean): Vector {
  const coup = dealCoup(fairDealOrder(remainingBefore, seed, 8), { burn });
  return { name, seed, commit: commitForSeed(seed), decks: 8, burn, remainingBefore: canonicalSort(remainingBefore), expected: coup };
}

/** First seed `${prefix}-k` whose coup satisfies `pred`. */
function find(prefix: string, remaining: CardCode[], burn: boolean, pred: (c: DealtCoup) => boolean): string {
  for (let k = 0; k < 10_000; k++) {
    const seed = sha256Hex(`${prefix}-${k}`);
    if (pred(dealCoup(fairDealOrder(remaining, seed, 8), { burn }))) return seed;
  }
  throw new Error(`no seed for ${prefix}`);
}

function vectors(): Vector[] {
  const fresh = buildShoe(8);
  const out: Vector[] = [];
  const first = vector('fresh shoe, burn', sha256Hex('baccarat-vector-1'), fresh, true);
  out.push(first);
  // the next coup of the same shoe: the remaining cards, no burn
  const order = fairDealOrder(fresh, first.seed, 8);
  const rest = order.slice(first.expected.dealt.length, fresh.length);
  out.push(vector('second coup of the shoe', sha256Hex('baccarat-vector-2'), rest, false));
  // near the cut card: 20 cards left
  out.push(vector('20 cards left', sha256Hex('baccarat-vector-3'), rest.slice(0, 20), false));
  const cases: Array<[string, boolean, (c: DealtCoup) => boolean]> = [
    ['burn of ten cards (face card)', true, (c) => c.burn!.count === 10],
    ['burn of one card (ace)', true, (c) => c.burn!.count === 1],
    ['natural 9 against 8', false, (c) => c.natural && c.player.length === 2 && Math.max(c.playerTotal, c.bankerTotal) === 9 && Math.min(c.playerTotal, c.bankerTotal) === 8],
    ['tie', false, (c) => c.winner === 'tie' && !c.natural],
    ['Player draws, Banker 3 stands on an 8', false, (c) => c.player.length === 3 && c.banker.length === 2 && c.player[2][0] === '8' && (c.bankerTotal === 3)],
    ['Player stands, Banker draws', false, (c) => c.player.length === 2 && c.banker.length === 3],
    ['both pairs', false, (c) => c.playerPair && c.bankerPair],
    ['six cards, Banker wins', false, (c) => c.player.length === 3 && c.banker.length === 3 && c.winner === 'banker'],
  ];
  for (const [name, burn, pred] of cases) out.push(vector(name, find(name, fresh, burn, pred), fresh, burn));
  return out;
}

describe('baccarat fairness vectors (shared with Dart)', () => {
  it('every vector re-deals and verifies; the file matches', async () => {
    const list = vectors();
    for (const v of list) {
      expect(verifyFairness({ commit: v.commit, seed: v.seed, remainingBefore: v.remainingBefore, dealt: v.expected.dealt, decks: 8 })).toBe(true);
      expect(v.expected.dealt.length).toBe((v.expected.burn ? 1 + v.expected.burn.count : 0) + v.expected.player.length + v.expected.banker.length);
    }
    const json = '[\n' + list.map((v) => ' ' + JSON.stringify(v)).join(',\n') + '\n]\n';
    await expect(json).toMatchFileSnapshot('../../../../../app/assets/fairness/baccarat_vectors.json');
  });
});
