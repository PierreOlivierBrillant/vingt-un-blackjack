/**
 * Baccarat house edge.
 *  1. Exact (combinatorial, 8 decks, no replacement): Banker 1.06 %, Player 1.24 %, Tie 14.36 %,
 *     pairs 10.36 % — and the constants of the engine (fair estimates) are these exact values.
 *  2. Fixed-seed Monte-Carlo over REAL shoes played by the engine (8 decks shuffled, burn on the first
 *     coup, cut card 16 from the end): every spot is settled by `spotReturn`, i.e. the code that pays
 *     the tables. Same seed ⇒ same numbers every run.
 */
import { describe, expect, it } from 'vitest';
import { buildShoe } from '../../../src/engine/cards';
import { fastRng, shuffleInPlace } from '../../../src/engine/rng';
import {
  BANKER_WIN_P, coupOdds, cutCardOut, dealCoup, PAIR_P, pairOdds, PLAYER_WIN_P, rankCounts, spotReturn, TIE_P, valueCounts,
} from '../../../src/games/baccarat/engine';
import { BACCARAT_SHOE_SIZE, BACCARAT_SPOTS, type BaccaratSpot } from '../../../src/shared/games/baccarat';

const COUPS = Number(process.env.BACCARAT_EDGE_COUPS ?? 2_000_000);
const SEED = 20261126;

describe('baccarat house edge — exact', () => {
  it('8 decks: Banker 1.06 %, Player 1.24 %, Tie 14.36 %, pairs 10.36 %', () => {
    const o = coupOdds(valueCounts(8));
    expect(o.banker + o.player + o.tie).toBeCloseTo(1, 10);
    const banker = 1 - (1.95 * o.banker + o.tie);
    const player = 1 - (2 * o.player + o.tie);
    const tie = 1 - 9 * o.tie;
    const pair = 1 - 12 * (31 / 415);
    expect(banker).toBeCloseTo(0.010579, 6);
    expect(player).toBeCloseTo(0.012351, 6);
    expect(tie).toBeCloseTo(0.143596, 6);
    expect(pair).toBeCloseTo(0.103614, 6);
    // the engine's constants (fair estimates of the markets) are these exact values
    expect([BANKER_WIN_P, PLAYER_WIN_P, TIE_P]).toEqual([o.banker, o.player, o.tie]);
    expect(PAIR_P).toBe(pairOdds(rankCounts(8)));
    // P(Player pair) = P(Banker pair) = 31/415; both at once ≈ 0.56 %
    const both = 2 * (31 / 415) - PAIR_P;
    expect(both).toBeGreaterThan(0.005);
    expect(both).toBeLessThan(0.006);
  });

  it('a single deck gives the textbook values too (Banker 1.01 %, Player 1.29 %)', () => {
    const o = coupOdds(valueCounts(1));
    expect(1 - (1.95 * o.banker + o.tie)).toBeCloseTo(0.0101, 4);
    expect(1 - (2 * o.player + o.tie)).toBeCloseTo(0.0129, 4);
  });
});

describe('baccarat house edge — Monte-Carlo (fixed seed, real shoes)', () => {
  it(`${COUPS} coups: Banker ≈ 1.06 %, Player ≈ 1.24 %, Tie ≈ 14.4 %`, () => {
    const t0 = Date.now();
    const rng = fastRng(SEED);
    const staked: Record<BaccaratSpot, number> = { player: 0, banker: 0, tie: 0, playerPair: 0, bankerPair: 0 };
    const returned: Record<BaccaratSpot, number> = { player: 0, banker: 0, tie: 0, playerPair: 0, bankerPair: 0 };
    let shoe = shuffleInPlace(buildShoe(8), rng);
    let pos = 0;
    let burn = true;
    let shoes = 1;
    const BET = 100;
    for (let n = 0; n < COUPS; n++) {
      if (cutCardOut(BACCARAT_SHOE_SIZE - pos)) {
        shoe = shuffleInPlace(buildShoe(8), rng);
        pos = 0;
        burn = true;
        shoes++;
      }
      const c = dealCoup(shoe.slice(pos, pos + 17), { burn });
      pos += c.dealt.length;
      burn = false;
      for (const spot of BACCARAT_SPOTS) {
        staked[spot] += BET;
        returned[spot] += spotReturn(spot, BET, c);
      }
    }
    const edge = (s: BaccaratSpot) => 1 - returned[s] / staked[s];
    const ms = Date.now() - t0;
    const pct = (x: number) => `${(x * 100).toFixed(3)} %`;
    console.log(
      `[baccarat-edge] coups=${COUPS} shoes=${shoes} banker=${pct(edge('banker'))} player=${pct(edge('player'))} ` +
        `tie=${pct(edge('tie'))} playerPair=${pct(edge('playerPair'))} bankerPair=${pct(edge('bankerPair'))} in ${ms} ms`,
    );
    // 1σ ≈ 0.066 % (Banker / Player), 0.19 % (Tie), 0.22 % (pairs) at 2 M coups
    expect(Math.abs(edge('banker') - 0.0106)).toBeLessThan(0.0025);
    expect(Math.abs(edge('player') - 0.0124)).toBeLessThan(0.0025);
    expect(Math.abs(edge('tie') - 0.1436)).toBeLessThan(0.01);
    expect(Math.abs(edge('playerPair') - 0.1036)).toBeLessThan(0.012);
    expect(Math.abs(edge('bankerPair') - 0.1036)).toBeLessThan(0.012);
  }, 120_000);
});
