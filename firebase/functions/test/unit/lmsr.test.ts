import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import {
  cost, LmsrError, MAX_LOGIT, maxLossCents, payoutCents, priceOf, priceYes, quoteBuy, quoteSell, type LmsrState,
} from '../../src/market/lmsr';
import type { MarketSide } from '../../src/shared/types';

const fresh = (b = 60): LmsrState => ({ b, qYes: 0, qNo: 0 });

describe('LMSR basics', () => {
  it('starts at 50/50 and C(0,0) = b ln 2', () => {
    expect(priceYes(fresh())).toBe(0.5);
    expect(cost(fresh(60))).toBeCloseTo(60 * Math.LN2, 12);
  });
  it('buying YES raises the YES price; costs between p·Δ before and after', () => {
    const q = quoteBuy(fresh(), 'yes', 10);
    expect(q.priceYesAfter).toBeGreaterThan(0.5);
    expect(q.amountCents).toBeGreaterThan(500);
    expect(q.amountCents).toBeLessThanOrEqual(Math.ceil(q.priceYesAfter * 1000));
  });
  it('rejects zero, negative, decimal, huge shares', () => {
    for (const n of [0, -1, 1.5, Number.NaN, 2 ** 60]) {
      expect(() => quoteBuy(fresh(), 'yes', n)).toThrow(LmsrError);
    }
  });
  it('refuses trades pushing the price to the edges', () => {
    expect(() => quoteBuy(fresh(10), 'yes', 10 * MAX_LOGIT + 1)).toThrow(/MARKET_LIMIT/);
  });
  it('payout is 100 cents per winning share', () => {
    expect(payoutCents({ yesShares: 7, noShares: 3 }, 'yes')).toBe(700);
    expect(payoutCents({ yesShares: 7, noShares: 3 }, 'no')).toBe(300);
  });
});

const side = fc.constantFrom<MarketSide>('yes', 'no');
const trade = fc.record({ side, shares: fc.integer({ min: 1, max: 300 }), sell: fc.boolean() });

describe('LMSR properties', () => {
  it('prices in ]0,1[ and YES + NO = 1 for any reachable state', () => {
    fc.assert(fc.property(fc.array(fc.record({ side, shares: fc.integer({ min: 1, max: 1000 }) }), { maxLength: 30 }), (trades) => {
      let s = fresh();
      for (const t of trades) {
        try { s = quoteBuy(s, t.side, t.shares).after; } catch { /* market limit */ }
        const p = priceYes(s);
        expect(p).toBeGreaterThan(0);
        expect(p).toBeLessThan(1);
        expect(priceOf(s, 'yes') + priceOf(s, 'no')).toBeCloseTo(1, 12);
      }
    }));
  });

  it('a buy then sell round trip never earns money (cost ≥ 0)', () => {
    fc.assert(fc.property(fc.array(trade, { maxLength: 10 }), side, fc.integer({ min: 1, max: 1000 }), (pre, sd, n) => {
      let s = fresh();
      for (const t of pre) { try { s = quoteBuy(s, t.side, t.shares).after; } catch { /* limit */ } }
      let buy;
      try { buy = quoteBuy(s, sd, n); } catch { return; }
      const sell = quoteSell(buy.after, sd, n);
      expect(buy.amountCents - sell.amountCents).toBeGreaterThanOrEqual(0);
      expect(sell.after.qYes).toBeCloseTo(s.qYes, 9);
    }));
  });

  it('house loss is bounded by b·ln2 for any trade sequence and either outcome', () => {
    fc.assert(fc.property(fc.integer({ min: 5, max: 300 }), fc.array(trade, { maxLength: 40 }), side, (b, trades, outcome) => {
      let s = fresh(b);
      let collected = 0;
      // traders hold what they bought; sells only of shares outstanding for that side
      const held = { yes: 0, no: 0 };
      for (const t of trades) {
        try {
          if (t.sell) {
            const n = Math.min(t.shares, held[t.side]);
            if (n === 0) continue;
            const q = quoteSell(s, t.side, n);
            collected -= q.amountCents; held[t.side] -= n; s = q.after;
          } else {
            const q = quoteBuy(s, t.side, t.shares);
            collected += q.amountCents; held[t.side] += t.shares; s = q.after;
          }
        } catch (e) { expect(e).toBeInstanceOf(LmsrError); }
      }
      const paid = payoutCents({ yesShares: held.yes, noShares: held.no }, outcome);
      expect(paid - collected).toBeLessThanOrEqual(maxLossCents(b) + 1e-6);
    }), { numRuns: 300 });
  });

  it('settlement pays exactly the winning side', () => {
    fc.assert(fc.property(fc.integer({ min: 0, max: 500 }), fc.integer({ min: 0, max: 500 }), side, (y, n, outcome) => {
      const p = payoutCents({ yesShares: y, noShares: n }, outcome);
      expect(p).toBe(outcome === 'yes' ? 100 * y : 100 * n);
      expect(Number.isInteger(p)).toBe(true);
    }));
  });

  it('all quotes are non-negative integer cents', () => {
    fc.assert(fc.property(fc.array(trade, { maxLength: 20 }), (trades) => {
      let s = fresh();
      for (const t of trades) {
        try {
          const q = t.sell && s[t.side === 'yes' ? 'qYes' : 'qNo'] >= t.shares ? quoteSell(s, t.side, t.shares) : quoteBuy(s, t.side, t.shares);
          expect(Number.isSafeInteger(q.amountCents)).toBe(true);
          expect(q.amountCents).toBeGreaterThanOrEqual(0);
          s = q.after;
        } catch { /* limit */ }
      }
    }));
  });
});
