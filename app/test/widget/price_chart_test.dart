import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/features/markets/market_detail_screen.dart';

import '../helpers.dart';

void main() {
  // Regression: a brand-new market (one price point, or several in the same second) gave the
  // time axis an interval of 0 and fl_chart asserted while the market screen was open.
  final t0 = DateTime(2026, 11, 25, 20, 15);
  final cases = <String, List<PricePoint>>{
    'one point': [PricePoint(t0, 0.5)],
    'same second': [PricePoint(t0, 0.5), PricePoint(t0.add(const Duration(milliseconds: 400)), 0.56)],
    'normal': [PricePoint(t0, 0.5), PricePoint(t0.add(const Duration(minutes: 3)), 0.7)],
  };
  for (final MapEntry(key: name, value: points) in cases.entries) {
    testWidgets('price chart renders: $name', (tester) async {
      usePhoneSurface(tester);
      await pumpScreen(
        tester,
        Scaffold(body: SizedBox(height: 240, child: PriceChart(points: points))),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(PriceChart), findsOneWidget);
    });
  }
}
