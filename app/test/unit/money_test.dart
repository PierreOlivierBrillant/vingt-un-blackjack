import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/money.dart';

void main() {
  group('formatCents', () {
    test('French: narrow nbsp groups, comma decimals, suffix symbol', () {
      expect(formatCents(123456), '1 234,56 \$');
      expect(formatCents(5), '0,05 \$');
      expect(formatCents(0), '0,00 \$');
      expect(formatCents(100000000), '1 000 000,00 \$');
    });

    test('English: comma groups, dot decimals, prefix symbol', () {
      expect(formatCents(123456, locale: 'en'), '\$1,234.56');
      expect(formatCents(99, locale: 'en'), '\$0.99');
      expect(formatCents(100, locale: 'en_US'), '\$1.00');
    });

    test('negative and signed amounts', () {
      expect(formatCents(-2500, locale: 'en'), '-\$25.00');
      expect(formatCents(-2500), '-25,00 \$');
      expect(formatCents(2500, locale: 'en', signed: true), '+\$25.00');
      expect(formatCents(0, locale: 'en', signed: true), '\$0.00');
    });

    test('compact drops zero cents only', () {
      expect(formatCents(100000, locale: 'en', compact: true), '\$1,000');
      expect(formatCents(100050, locale: 'en', compact: true), '\$1,000.50');
    });

    test('3:2 blackjack payouts on whole-dollar bets are exact', () {
      for (var bet = 100; bet <= 100000; bet += 100) {
        final pay = bet * 3 ~/ 2;
        expect(pay * 2, bet * 3, reason: 'bet $bet');
      }
      expect(formatCents(2500 * 3 ~/ 2, locale: 'en'), '\$37.50');
    });
  });

  test('groupDigits', () {
    expect(groupDigits(0, ','), '0');
    expect(groupDigits(999, ','), '999');
    expect(groupDigits(1000, ','), '1,000');
    expect(groupDigits(1234567, ' '), '1 234 567');
  });

  test('formatPriceCents clamps sub-cent prices', () {
    expect(formatPriceCents(62.4), '62¢');
    expect(formatPriceCents(0.4), '<1¢');
    expect(formatPriceCents(99.6), '>99¢');
  });

  test('formatPercent', () {
    expect(formatPercent(0.375), '38 %');
    expect(formatPercent(0.375, locale: 'en'), '38%');
  });

  group('parseCents', () {
    test('accepts integers and 1-2 decimals with . or ,', () {
      expect(parseCents('12'), 1200);
      expect(parseCents('12,5'), 1250);
      expect(parseCents('12.05'), 1205);
      expect(parseCents(' 1 000 '), 100000);
      expect(parseCents('7\$'), 700);
    });
    test('rejects junk, negatives and too many decimals', () {
      expect(parseCents(''), isNull);
      expect(parseCents('-5'), isNull);
      expect(parseCents('1.234'), isNull);
      expect(parseCents('abc'), isNull);
      expect(parseCents('1e3'), isNull);
      expect(parseCents('9999999999'), isNull);
    });
  });
}
