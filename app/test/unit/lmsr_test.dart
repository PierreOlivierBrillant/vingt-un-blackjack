import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/data/repositories.dart';
import 'package:vingtun/domain/lmsr.dart';
import 'package:vingtun/domain/models.dart';

/// Expected values computed by hand from the formulas of
/// `firebase/functions/src/market/lmsr.ts` (float64, same evaluation order):
///   C = b·(m + ln(e^(qY/b − m) + e^(qN/b − m))), m = max(qY/b, qN/b)
///   buy  = ceil((C(after) − C(before))·100)
///   sell = max(0, floor((C(before) − C(after))·100))
void main() {
  LmsrState s(double b, double y, double n) => LmsrState(b: b, qYes: y, qNo: n);

  test('C(0,0) = b·ln2, price 0.5, max loss b·ln2 dollars', () {
    expect(lmsrCost(s(60, 0, 0)), closeTo(60 * ln2, 1e-12));
    expect(lmsrPriceYes(s(60, 0, 0)), 0.5);
    expect(lmsrMaxLossCents(60), closeTo(4158.883083359671, 1e-9));
  });

  test('prices match the TS formula', () {
    expect(lmsrPriceYes(s(60, 10, 64)), closeTo(0.289050497374996, 1e-15));
    expect(lmsrPriceYes(s(200, 160, 62)), closeTo(0.6201064323430902, 1e-15));
    expect(lmsrPriceOf(s(60, 10, 64), Outcome.no), closeTo(1 - 0.289050497374996, 1e-15));
  });

  group('quotes (cents, rounding favours the house)', () {
    // (b, qYes, qNo, side, shares, buy?, expected cents, raw cents, priceYesAfter)
    final cases = <(double, double, double, Outcome, int, bool, int, double, double)>[
      (60, 0, 0, Outcome.yes, 10, true, 521, 520.8092652381524, 0.5415704832167999),
      (60, 0, 0, Outcome.no, 1, true, 51, 50.208330922112765, 0.49583342978127154),
      (60, 10, 64, Outcome.yes, 10, true, 307, 306.56685774206807, 0.3244636770105458),
      (60, 10, 64, Outcome.yes, 15, true, 474, 473.4087658237641, 0.34298953732650117),
      (60, 10, 64, Outcome.yes, 5, false, 140, 140.2947179201533, 0.2722308784006331),
      (60, 10, 64, Outcome.no, 20, true, 1488, 1487.0659518780897, 0.22559854698572143),
      (60, 40, 47, Outcome.no, 25, false, 1192, 1192.954165681509, 0.574442516811659),
      (200, 160, 62, Outcome.yes, 1000, true, 90526, 90525.10394783599, 0.9958891248776695),
      (200, 160, 62, Outcome.yes, 160, false, 8355, 8355.04528335094, 0.42311473886795364),
      (60, 0, 0, Outcome.yes, 1000, true, 95842, 95841.11726330523, 0.9999999422225181),
    ];
    for (final (b, y, n, side, shares, buy, cents, raw, pAfter) in cases) {
      test('${buy ? 'buy' : 'sell'} $shares ${side.name} @ (b=$b, $y, $n)', () {
        final st = s(b, y, n);
        final q = buy ? lmsrQuoteBuy(st, side, shares) : lmsrQuoteSell(st, side, shares);
        expect(q.amountCents, cents);
        expect(q.amountCents, buy ? raw.ceil() : raw.floor());
        expect(q.priceYesAfter, closeTo(pAfter, 1e-13));
        final d = buy ? shares.toDouble() : -shares.toDouble();
        expect(q.after, side == Outcome.yes ? s(b, y + d, n) : s(b, y, n + d));
      });
    }
  });

  test('bad shares and market limit (MAX_LOGIT = 20)', () {
    for (final n in [0, -1, 1 << 60]) {
      expect(() => lmsrQuoteBuy(s(60, 0, 0), Outcome.yes, n),
          throwsA(isA<LmsrException>().having((e) => e.code, 'code', LmsrErrorCode.badShares)));
    }
    expect(() => lmsrQuoteBuy(s(10, 0, 0), Outcome.yes, 10 * kLmsrMaxLogit + 1),
        throwsA(isA<LmsrException>().having((e) => e.code, 'code', LmsrErrorCode.marketLimit)));
    expect(lmsrQuoteBuy(s(10, 0, 0), Outcome.yes, 10 * kLmsrMaxLogit).amountCents, greaterThan(0));
  });

  test('sell proceeds are never negative; payout is 100 per winning share', () {
    expect(lmsrQuoteSell(s(60, 0, 0), Outcome.yes, 1).amountCents, greaterThanOrEqualTo(0));
    expect(lmsrPayoutCents(yesShares: 7, noShares: 3, outcome: Outcome.yes), 700);
    expect(lmsrPayoutCents(yesShares: 7, noShares: 3, outcome: Outcome.no), 300);
  });

  test('a buy then sell round trip never makes money (deterministic sweep)', () {
    final rng = Random(21);
    for (var i = 0; i < 500; i++) {
      final st = s(rng.nextBool() ? 60 : 200, rng.nextInt(400) - 200.0, rng.nextInt(400) - 200.0);
      final side = rng.nextBool() ? Outcome.yes : Outcome.no;
      final n = 1 + rng.nextInt(300);
      final LmsrQuote buy;
      try {
        buy = lmsrQuoteBuy(st, side, n);
      } on LmsrException {
        continue;
      }
      final sell = lmsrQuoteSell(buy.after, side, n);
      expect(sell.amountCents, lessThanOrEqualTo(buy.amountCents), reason: '$st $side $n');
      expect(sell.after.qYes, closeTo(st.qYes, 1e-9));
    }
  });

  test('TradeQuote mirrors the LMSR and exposes the slippage guard amount', () {
    const m = Market(id: 'm', kind: MarketKind.dealerBust, tableId: 't', tableName: 'T', status: MarketStatus.open, priceYes: 0.289, qYes: 10, qNo: 64);
    final q = TradeQuote.compute(LmsrState.ofMarket(m), Outcome.yes, 10, buy: true);
    expect(q.amountCents, 307);
    expect(q.costCents, 307);
    expect(q.avgPrice, closeTo(0.307, 1e-12));
    expect(q.maxPayoutCents, 1000);
    final sell = TradeQuote.compute(LmsrState.ofMarket(m), Outcome.yes, 5, buy: false);
    expect(sell.costCents, -140);
    expect(sell.priceAfter, closeTo(0.2722308784006331, 1e-13));
    final no = TradeQuote.compute(LmsrState.ofMarket(m), Outcome.no, 20, buy: true);
    expect(no.priceAfter, closeTo(1 - 0.22559854698572143, 1e-13));
  });
}
