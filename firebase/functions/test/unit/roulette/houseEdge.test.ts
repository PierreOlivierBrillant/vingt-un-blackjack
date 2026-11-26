/**
 * Roulette house edge.
 *  - Exact: over the 37 equally likely numbers every spot returns 36/37 of its stake (edge 1/37 =
 *    2.7027 %), the even chances with the zero shield 73/74 (edge 1/74 = 1.35 %).
 *  - Monte-Carlo with a fixed seed (same numbers every run), drawn EXACTLY like production: one
 *    seed per round, `seededRng(seed).nextInt(37)`. Three players: 1 unit on each of the 157 spots,
 *    the bots' boards (realistic mix, call bets included), red with the zero shield. Plus the
 *    uniformity of the draw (chi-square, 36 degrees of freedom).
 */
import { describe, expect, it } from 'vitest';
import { fastRng, seededRng, sha256Hex } from '../../../src/engine';
import { botBoard } from '../../../src/games/roulette/bots';
import { rouletteLimits, settleBoard, spotReturn, SPOTS } from '../../../src/games/roulette/engine';
import type { BetMap } from '../../../src/shared/games/common';
import { BOTS } from '../../../src/sim/profiles';

const SPINS = Number(process.env.ROULETTE_MC_SPINS ?? 1_000_000);

describe('house edge, exact', () => {
  it('every spot: edge exactly 1/37; even chances with the zero shield: 1/74', () => {
    for (const s of SPOTS.values()) {
      let ret = 0;
      for (let n = 0; n <= 36; n++) ret += spotReturn(s, 3_700, n);
      expect(1 - ret / 37 / 3_700, s.id).toBeCloseTo(1 / 37, 14);
      if (s.type === 'even') {
        let shielded = 0;
        for (let n = 0; n <= 36; n++) shielded += spotReturn(s, 3_700, n, true);
        expect(1 - shielded / 37 / 3_700, s.id).toBeCloseTo(1 / 74, 14);
      }
    }
  });
});

class Acc {
  staked = 0;
  net = 0;
  sumSq = 0;
  n = 0;
  add(staked: number, ret: number) {
    this.staked += staked;
    this.net += ret - staked;
    this.sumSq += (ret - staked) ** 2;
    this.n++;
  }
  get edge() {
    return -this.net / this.staked;
  }
  /** Standard error of the edge (per-spin nets, ratio estimator). */
  get se() {
    const meanStake = this.staked / this.n;
    const meanNet = this.net / this.n;
    const variance = this.sumSq / this.n - meanNet * meanNet;
    return Math.sqrt(variance / this.n) / meanStake;
  }
}

describe('house edge, Monte-Carlo (fixed seed, production draw)', () => {
  it(`${SPINS} spins: 2.70 % on every spot, 1.35 % on red with the shield, uniform draw`, () => {
    const t0 = Date.now();
    const every: BetMap = Object.fromEntries([...SPOTS.keys()].map((id) => [id, 100]));
    const everyTotal = 100 * SPOTS.size;
    // the 157-spot board settles the same way for a given number: settle it once per number
    const everyReturn = Array.from({ length: 37 }, (_, n) => settleBoard(every, n).returnCents);
    const limits = rouletteLimits('low');
    const botRng = fastRng(20261126);
    const all = new Acc();
    const bots = new Acc();
    const shield = new Acc();
    const counts = new Array<number>(37).fill(0);
    for (let i = 0; i < SPINS; i++) {
      const n = seededRng(sha256Hex(`roulette-mc:${i}`)).nextInt(37);
      counts[n]++;
      all.add(everyTotal, everyReturn[n]);
      const b = botBoard(botRng, BOTS[48 + (i % 60)], limits);
      if (b) {
        const total = Object.values(b).reduce((x, y) => x + y, 0);
        bots.add(total, settleBoard(b, n).returnCents);
      }
      shield.add(1_000, settleBoard({ red: 1_000 }, n, true).returnCents);
    }
    const expected = SPINS / 37;
    const chi2 = counts.reduce((acc, c) => acc + (c - expected) ** 2 / expected, 0);
    const pct = (x: number) => `${(x * 100).toFixed(3)}%`;
    console.log(
      `[roulette house edge] spins=${SPINS} every-spot=${pct(all.edge)} ±${pct(all.se)} bots=${pct(bots.edge)} ±${pct(bots.se)} ` +
      `red+shield=${pct(shield.edge)} ±${pct(shield.se)} chi2(36)=${chi2.toFixed(1)} in ${Date.now() - t0} ms`,
    );
    expect(Math.abs(all.edge - 1 / 37)).toBeLessThan(4 * all.se);
    expect(Math.abs(bots.edge - 1 / 37)).toBeLessThan(4 * bots.se);
    expect(Math.abs(shield.edge - 1 / 74)).toBeLessThan(4 * shield.se);
    expect(all.edge).toBeGreaterThan(0.025);
    expect(all.edge).toBeLessThan(0.029);
    expect(chi2).toBeLessThan(70); // 99.9 % quantile of chi-square(36) ≈ 67.985
  }, 180_000);
});
