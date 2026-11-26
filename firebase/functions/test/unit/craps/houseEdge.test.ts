/**
 * House edge of every craps bet, through the engine itself:
 *  - EXACT: value iteration over the 36 dice combinations (Markov chain of the point), each roll
 *    settled by `settleBoard`; the expected net of one decision of the bet must equal the known
 *    edge (Pass 7/495 ≈ 1.414 %, Don't Pass 3/220 ≈ 1.364 %, odds 0, place 6/8 1/66, …);
 *  - MONTE-CARLO (fixed seed, deterministic): Pass Line and Don't Pass over 4 000 000 decisions (σ ≈ 0.05 %) with
 *    the provably-fair dice function (`rollDice`, `nextInt(6)+1` twice) on a fast PRNG.
 */
import { describe, expect, it } from 'vitest';
import { fastRng } from '../../../src/engine';
import { pointAfter, rollDice, settleBoard } from '../../../src/games/craps/engine';
import type { BetMap } from '../../../src/shared/games/common';
import type { CrapsPoint } from '../../../src/shared/games/craps';

/**
 * Expected net (in units of the stake) of ONE decision of `spot` (win, loss or push of that bet; a
 * come bet travelling to its number goes on) placed with the line point `point`.
 */
function exactEdge(spot: string, point: CrapsPoint | null, extra: BetMap = {}): number {
  const stake = 600; // divisible by every payout denominator
  type State = { p: CrapsPoint | null; b: BetMap; t: string };
  const key = (s: State) => `${s.p}|${s.t}|${JSON.stringify(Object.entries(s.b).sort())}`;
  const states = new Map<string, State>();
  const trans = new Map<string, Array<{ prob: number; net: number; next: string | null }>>();
  const explore = (s: State): string => {
    const k = key(s);
    if (states.has(k)) return k;
    states.set(k, s);
    const out: Array<{ prob: number; net: number; next: string | null }> = [];
    trans.set(k, out);
    for (let d1 = 1; d1 <= 6; d1++) {
      for (let d2 = 1; d2 <= 6; d2++) {
        const st = settleBoard(s.b, { pointBefore: s.p, d1, d2, safetyNet: false, leaving: false });
        const o = st.outcomes.find((x) => x.spot === s.t);
        const p2 = pointAfter(s.p, d1 + d2);
        if (!o || o.outcome === 'travel') {
          out.push({ prob: 1 / 36, net: 0, next: explore({ p: p2, b: st.carry, t: o?.to ?? s.t }) });
        } else {
          const net = o.outcome === 'win' ? o.wonCents : o.outcome === 'lose' ? -o.stake : 0;
          out.push({ prob: 1 / 36, net: net / stake, next: null });
        }
      }
    }
    return k;
  };
  const start = explore({ p: point, b: { [spot]: stake, ...extra }, t: spot });
  const v = new Map<string, number>([...states.keys()].map((k) => [k, 0]));
  for (let it = 0; it < 400; it++) {
    for (const [k, list] of trans) {
      let e = 0;
      for (const t of list) e += t.prob * (t.net + (t.next ? v.get(t.next)! : 0));
      v.set(k, e);
    }
  }
  return v.get(start)!;
}

describe('exact house edge of every bet (engine + Markov chain)', () => {
  const cases: Array<[string, string, CrapsPoint | null, number]> = [
    ['Pass Line', 'pass', null, -7 / 495],
    ["Don't Pass (bar 12)", 'dontPass', null, -3 / 220],
    ['Come', 'come', 6, -7 / 495],
    ["Don't Come", 'dontCome', 9, -3 / 220],
    ['odds on 4 (2:1)', 'odds:pass', 4, 0],
    ['odds on 5 (3:2)', 'odds:pass', 5, 0],
    ['odds on 6 (6:5)', 'odds:pass', 6, 0],
    ['lay odds on 4 (1:2)', 'odds:dontPass', 10, 0],
    ['lay odds on 9 (2:3)', 'odds:dontPass', 9, 0],
    ['lay odds on 8 (5:6)', 'odds:dontPass', 8, 0],
    ['place 4 (9:5)', 'place4', 6, -1 / 15],
    ['place 5 (7:5)', 'place5', 6, -1 / 25],
    ['place 6 (7:6)', 'place6', 8, -1 / 66],
    ['place 8 (7:6)', 'place8', 6, -1 / 66],
    ['place 9 (7:5)', 'place9', 4, -1 / 25],
    ['place 10 (9:5)', 'place10', 5, -1 / 15],
    ['field (2 pays 2:1, 12 pays 3:1)', 'field', null, -1 / 36],
    ['any 7 (4:1)', 'any7', null, -1 / 6],
    ['any craps (7:1)', 'anyCraps', 8, -1 / 9],
    ['two (30:1)', 'two', null, -5 / 36],
    ['twelve (30:1)', 'twelve', 6, -5 / 36],
    ['three (15:1)', 'three', null, -1 / 9],
    ['yo (15:1)', 'yo', 5, -1 / 9],
    ['hard 4 (7:1)', 'hard4', 9, -1 / 9],
    ['hard 10 (7:1)', 'hard10', 5, -1 / 9],
    ['hard 6 (9:1)', 'hard6', 8, -1 / 11],
    ['hard 8 (9:1)', 'hard8', 5, -1 / 11],
  ];
  for (const [name, spot, point, edge] of cases) {
    it(`${name}: ${(edge * 100).toFixed(3)} %`, () => {
      expect(exactEdge(spot, point)).toBeCloseTo(edge, 10);
    });
  }

  it('come odds work on a point and are off on the come-out (still 0 edge)', () => {
    expect(exactEdge('odds:come5', 9, { come5: 600 })).toBeCloseTo(0, 10);
    expect(exactEdge('odds:dontCome6', 9, { dontCome6: 600 })).toBeCloseTo(0, 10);
  });
});

const DECISIONS = Number(process.env.CRAPS_MC_DECISIONS ?? 4_000_000);
const SEED = 20261126;

describe('Monte-Carlo (fixed seed)', () => {
  it(`Pass Line ≈ 1.41 % and Don't Pass ≈ 1.36 % over ${DECISIONS} decisions`, () => {
    const t0 = Date.now();
    const rng = fastRng(SEED);
    let passNet = 0;
    let dontNet = 0;
    let rolls = 0;
    let point: CrapsPoint | null = null;
    const stake = 100;
    for (let n = 0; n < DECISIONS;) {
      const [d1, d2] = rollDice(rng);
      rolls++;
      const st = settleBoard({ pass: stake, dontPass: stake }, { pointBefore: point, d1, d2, safetyNet: false, leaving: false });
      const after = pointAfter(point, d1 + d2);
      const decided = st.outcomes.some((o) => o.spot === 'pass');
      if (decided) {
        for (const o of st.outcomes) {
          const net = o.outcome === 'win' ? o.wonCents : o.outcome === 'lose' ? -o.stake : 0;
          if (o.spot === 'pass') passNet += net;
          else dontNet += net;
        }
        n++;
      }
      point = after;
    }
    const pass = -passNet / (DECISIONS * stake);
    const dont = -dontNet / (DECISIONS * stake);
    const se = 1 / Math.sqrt(DECISIONS);
    console.log(`[craps-mc] decisions=${DECISIONS} rolls=${rolls} pass=${(pass * 100).toFixed(3)}% dontPass=${(dont * 100).toFixed(3)}% ±${(se * 100).toFixed(3)}% (1σ) in ${Date.now() - t0} ms`);
    expect(Math.abs(pass - 7 / 495)).toBeLessThan(3 * se);
    expect(Math.abs(dont - 3 / 220)).toBeLessThan(3 * se);
    expect(rolls / DECISIONS).toBeGreaterThan(3.3); // 557/165 ≈ 3.376 rolls per decision
    expect(rolls / DECISIONS).toBeLessThan(3.45);
  }, 180_000);
});
