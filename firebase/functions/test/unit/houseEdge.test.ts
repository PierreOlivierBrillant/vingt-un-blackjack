/**
 * Fixed-seed Monte-Carlo regression: perfect basic strategy over a real 6-deck shoe (cut card at
 * 75 %) must give a house edge in the expected band for these rules (≈0.3–0.7 %).
 * Same seed ⇒ same number every run: any change in the measured value means the rules or the
 * payout logic changed.
 */
import { describe, expect, it } from 'vitest';
import { fastRng, simulateBasicStrategy } from '../../src/engine';

const HANDS = Number(process.env.HOUSE_EDGE_HANDS ?? 2_000_000);
const SEED = 20261118;

describe('house edge (Monte-Carlo, fixed seed)', () => {
  it(`basic strategy over ${HANDS} hands is within 0.3%–0.7%`, () => {
    const t0 = Date.now();
    const r = simulateBasicStrategy(fastRng(SEED), HANDS);
    const ms = Date.now() - t0;
    const se = 1.15 / Math.sqrt(HANDS);
    console.log(`[house-edge] hands=${r.hands} net=${r.netCents}c edge=${(r.houseEdge * 100).toFixed(3)}% ±${(se * 100).toFixed(3)}% (1σ) in ${ms} ms`);
    expect(r.houseEdge).toBeGreaterThan(0.003);
    expect(r.houseEdge).toBeLessThan(0.007);
    // CPU-bound (~4 s on a quiet machine): generous timeout for loaded CI / busy dev boxes.
  }, 120_000);
});
