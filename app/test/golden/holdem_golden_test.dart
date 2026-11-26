@Tags(['golden'])
library;

// Goldens of the hold'em table (light / dark): my turn on the flop (Alex,
// cards, bets, pot, dealer button, raise slider) and a settled showdown
// (hand names, winning cards highlighted). Regenerate with:
// flutter test --update-goldens test/golden/holdem_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/data/providers.dart';
import 'package:vingtun/features/games/holdem/holdem_screen.dart';

import '../helpers.dart';
import '../holdem_fixtures.dart';

void main() {
  final scenes = <String, Map<String, Object?> Function()>{
    'holdem_turn': holdemFlopDoc,
    'holdem_showdown': holdemShowdownDoc,
  };
  for (final mode in const [ThemeMode.dark, ThemeMode.light]) {
    for (final e in scenes.entries) {
      testWidgets('${e.key} ${mode.name}', (tester) async {
        usePhoneSurface(tester);
        final repo = HoldemTestRepo(e.value());
        await pumpScreen(
          tester,
          const HoldemScreen(tableId: kHoldemTableId),
          themeMode: mode,
          overrides: [gameTableRepositoryProvider.overrideWithValue(repo)],
        );
        await tester.pump(const Duration(milliseconds: 600));
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${e.key}_${mode.name}.png'));
      });
    }
  }
}
