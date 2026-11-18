/**
 * Logarithmic Market Scoring Rule (Hanson) for binary YES/NO markets. Pure module.
 *
 *   C(qY, qN) = b · ln(e^(qY/b) + e^(qN/b))           (in dollars; one share pays $1)
 *   price(YES) = e^(qY/b) / (e^(qY/b) + e^(qN/b))       ∈ ]0,1[, price(YES)+price(NO) = 1
 *   cost of buying Δ YES = C(qY+Δ, qN) − C(qY, qN)
 *
 * Starting from q = (0,0) the market maker's worst-case loss is b·ln 2 dollars.
 * Amounts in cents: buys are rounded UP, sells DOWN, so rounding always favours the house and a
 * buy-then-sell round trip never makes money.
 */
import type { MarketSide } from '../shared/types';

export interface LmsrState {
  b: number;
  qYes: number;
  qNo: number;
}

/** Largest allowed |qYes − qNo| / b. Keeps prices strictly inside ]0,1[ in float64 (≈ 2e-9 from the edges). */
export const MAX_LOGIT = 20;

export class LmsrError extends Error {
  constructor(public readonly code: 'BAD_SHARES' | 'MARKET_LIMIT' | 'INSUFFICIENT_LIQUIDITY') {
    super(code);
    this.name = 'LmsrError';
  }
}

/** C(q) in dollars, numerically stable (log-sum-exp). */
export function cost(s: LmsrState): number {
  const a = s.qYes / s.b;
  const c = s.qNo / s.b;
  const m = Math.max(a, c);
  return s.b * (m + Math.log(Math.exp(a - m) + Math.exp(c - m)));
}

export function priceYes(s: LmsrState): number {
  return 1 / (1 + Math.exp((s.qNo - s.qYes) / s.b));
}

export function priceOf(s: LmsrState, side: MarketSide): number {
  const p = priceYes(s);
  return side === 'yes' ? p : 1 - p;
}

function moved(s: LmsrState, side: MarketSide, delta: number): LmsrState {
  return side === 'yes' ? { ...s, qYes: s.qYes + delta } : { ...s, qNo: s.qNo + delta };
}

function checkShares(shares: number): void {
  if (!Number.isSafeInteger(shares) || shares <= 0) throw new LmsrError('BAD_SHARES');
}

function checkBounds(s: LmsrState): void {
  if (Math.abs(s.qYes - s.qNo) / s.b > MAX_LOGIT) throw new LmsrError('MARKET_LIMIT');
}

export interface Quote {
  /** Cents paid (buy) or received (sell). */
  amountCents: number;
  after: LmsrState;
  priceYesAfter: number;
}

/** Quote buying `shares` of `side`. Cost in cents, rounded up. */
export function quoteBuy(s: LmsrState, side: MarketSide, shares: number): Quote {
  checkShares(shares);
  const after = moved(s, side, shares);
  checkBounds(after);
  const dollars = cost(after) - cost(s);
  return { amountCents: Math.ceil(dollars * 100), after, priceYesAfter: priceYes(after) };
}

/** Quote selling `shares` of `side` back to the market maker. Proceeds in cents, rounded down. */
export function quoteSell(s: LmsrState, side: MarketSide, shares: number): Quote {
  checkShares(shares);
  const after = moved(s, side, -shares);
  checkBounds(after);
  const dollars = cost(s) - cost(after);
  return { amountCents: Math.max(0, Math.floor(dollars * 100)), after, priceYesAfter: priceYes(after) };
}

/** Worst-case loss of the market maker (cents) for a market started at q = (0,0). */
export function maxLossCents(b: number): number {
  return b * Math.LN2 * 100;
}

/** Payout (cents) of a position at resolution: 100 per winning share. */
export function payoutCents(position: { yesShares: number; noShares: number }, outcome: MarketSide): number {
  return 100 * (outcome === 'yes' ? position.yesShares : position.noShares);
}
