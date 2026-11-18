/// Logarithmic Market Scoring Rule — EXACT port of
/// `firebase/functions/src/market/lmsr.ts` (same formulas, same evaluation
/// order, same float64 numerics, same rounding) so the order ticket quotes
/// what the server will charge and can send it as `maxCostCents` /
/// `minProceedsCents`.
///
///   C(qY, qN) = b · ln(e^(qY/b) + e^(qN/b))       (dollars; one share pays $1)
///   price(YES) = 1 / (1 + e^((qN − qY)/b))
///   buy Δ:  ceil((C(after) − C(before)) · 100) cents
///   sell Δ: max(0, floor((C(before) − C(after)) · 100)) cents
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'models.dart' show Market, Outcome;

/// Largest allowed |qYes − qNo| / b (MAX_LOGIT).
const kLmsrMaxLogit = 20;

/// JS `Number.MAX_SAFE_INTEGER`.
const _maxSafeInteger = 9007199254740991;

enum LmsrErrorCode { badShares, marketLimit }

class LmsrException implements Exception {
  const LmsrException(this.code);
  final LmsrErrorCode code;
  @override
  String toString() => 'LmsrException(${code.name})';
}

@immutable
class LmsrState {
  const LmsrState({required this.b, required this.qYes, required this.qNo});
  factory LmsrState.ofMarket(Market m) => LmsrState(b: m.b, qYes: m.qYes, qNo: m.qNo);
  final double b;
  final double qYes;
  final double qNo;

  @override
  bool operator ==(Object other) => other is LmsrState && other.b == b && other.qYes == qYes && other.qNo == qNo;
  @override
  int get hashCode => Object.hash(b, qYes, qNo);
  @override
  String toString() => 'LmsrState(b: $b, qYes: $qYes, qNo: $qNo)';
}

/// C(q) in dollars, numerically stable (log-sum-exp).
double lmsrCost(LmsrState s) {
  final a = s.qYes / s.b;
  final c = s.qNo / s.b;
  final m = math.max(a, c);
  return s.b * (m + math.log(math.exp(a - m) + math.exp(c - m)));
}

double lmsrPriceYes(LmsrState s) => 1 / (1 + math.exp((s.qNo - s.qYes) / s.b));

double lmsrPriceOf(LmsrState s, Outcome side) {
  final p = lmsrPriceYes(s);
  return side == Outcome.yes ? p : 1 - p;
}

LmsrState _moved(LmsrState s, Outcome side, double delta) => side == Outcome.yes
    ? LmsrState(b: s.b, qYes: s.qYes + delta, qNo: s.qNo)
    : LmsrState(b: s.b, qYes: s.qYes, qNo: s.qNo + delta);

void _checkShares(int shares) {
  if (shares <= 0 || shares > _maxSafeInteger) throw const LmsrException(LmsrErrorCode.badShares);
}

void _checkBounds(LmsrState s) {
  if ((s.qYes - s.qNo).abs() / s.b > kLmsrMaxLogit) throw const LmsrException(LmsrErrorCode.marketLimit);
}

@immutable
class LmsrQuote {
  const LmsrQuote({required this.amountCents, required this.after, required this.priceYesAfter});

  /// Cents paid (buy) or received (sell).
  final int amountCents;
  final LmsrState after;
  final double priceYesAfter;
}

/// Buying [shares] of [side]: cost in cents, rounded UP.
LmsrQuote lmsrQuoteBuy(LmsrState s, Outcome side, int shares) {
  _checkShares(shares);
  final after = _moved(s, side, shares.toDouble());
  _checkBounds(after);
  final dollars = lmsrCost(after) - lmsrCost(s);
  return LmsrQuote(amountCents: (dollars * 100).ceil(), after: after, priceYesAfter: lmsrPriceYes(after));
}

/// Selling [shares] of [side] back to the market maker: proceeds in cents,
/// rounded DOWN (never negative).
LmsrQuote lmsrQuoteSell(LmsrState s, Outcome side, int shares) {
  _checkShares(shares);
  final after = _moved(s, side, -shares.toDouble());
  _checkBounds(after);
  final dollars = lmsrCost(s) - lmsrCost(after);
  return LmsrQuote(amountCents: math.max(0, (dollars * 100).floor()), after: after, priceYesAfter: lmsrPriceYes(after));
}

/// Worst-case loss of the market maker (cents) for a market started at (0,0).
double lmsrMaxLossCents(double b) => b * math.ln2 * 100;

/// Payout (cents) of a position at resolution: 100 per winning share.
int lmsrPayoutCents({required int yesShares, required int noShares, required Outcome outcome}) =>
    100 * (outcome == Outcome.yes ? yesShares : noShares);
