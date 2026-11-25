import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/cards.dart';
import 'package:vingtun/features/dealer/dealer_controller.dart';
import 'package:vingtun/features/dealer/dealer_painters.dart';
import 'package:vingtun/features/dealer/dealer_stage.dart';

String label(List<String> cards, {bool dealer = false}) {
  final parsed = [for (final c in cards) PlayingCard.parse(c)];
  return handTotalLabel(handTotal(parsed), cardCount: parsed.length, dealer: dealer);
}

double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('hand total pill', () {
    test('a lone ace reads 11, never 1/11 (dealer up card, first card dealt)', () {
      expect(label(['AS']), '11');
      expect(label(['AS'], dealer: true), '11');
    });

    test('soft player hands of two cards or more show both totals', () {
      expect(label(['AS', '6D']), '7/17');
      expect(label(['AS', '2C', '3H']), '6/16');
    });

    test('soft 21 and hard hands show a single total', () {
      expect(label(['AS', 'KD']), '21');
      expect(label(['AS', '5D', '5C']), '21');
      expect(label(['TS', '6D']), '16');
      expect(label(['TS', '6D', '9C']), '25');
    });

    test('the dealer never uses the soft notation (S17)', () {
      expect(label(['AS', '6D'], dealer: true), '17');
      expect(label(['AS', '2D'], dealer: true), '13');
    });
  });

  test('every seat badge is readable on the felt (WCAG contrast ≥ 4.5)', () {
    for (final b in SeatBadge.values) {
      final (bg, fg) = stageBadgeColors(b);
      expect(contrast(bg, fg), greaterThanOrEqualTo(4.5), reason: '$b');
    }
  });
  group('felt lettering follows the printed (elliptical) lines', () {
    test('on a circle, moving by an arc length s turns by s / r', () {
      const r = Offset(400, 400);
      expect(FeltPainter.advance(r, math.pi / 2, 100), closeTo(math.pi / 2 - 100 / 400, 1e-6));
    });
    test('advancing then coming back returns to the start, on the ellipse too', () {
      final t = FeltPainter.advance(FeltPainter.outerArc, math.pi / 2, 230);
      expect(FeltPainter.advance(FeltPainter.outerArc, t, -230), closeTo(math.pi / 2, 1e-3));
    });
    test('both text lines sit outside the outer printed line, never on it', () {
      for (final off in const [Offset(30, 30), Offset(70, 70)]) {
        final r = FeltPainter.outerArc + off;
        for (var t = 0.6; t < math.pi - 0.6; t += 0.05) {
          final p = FeltPainter.ellipsePoint(FeltPainter.arcCenter, r, t);
          final d = p - FeltPainter.arcCenter;
          final onOuter = math.pow(d.dx / FeltPainter.outerArc.dx, 2) + math.pow(d.dy / FeltPainter.outerArc.dy, 2);
          expect(onOuter, greaterThan(1.1), reason: 't=$t');
        }
      }
    });
  });
}
