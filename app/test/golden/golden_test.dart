@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/theme/app_theme.dart';
import 'package:vingtun/domain/card_style.dart';
import 'package:vingtun/domain/cards.dart';
import 'package:vingtun/features/cards/card_painters.dart';
import 'package:vingtun/features/customize/customize_screen.dart';
import 'package:vingtun/features/dealer/dealer_controller.dart';
import 'package:vingtun/features/dealer/dealer_stage.dart';
import 'package:vingtun/features/dealer/demo_round.dart';
import 'package:vingtun/features/lobby/lobby_screen.dart';
import 'package:vingtun/features/markets/market_detail_screen.dart';
import 'package:vingtun/features/markets/markets_screen.dart';
import 'package:vingtun/features/wallet/wallet_screen.dart';

import '../helpers.dart';

/// Regenerate with: flutter test --update-goldens --tags golden
void main() {
  final screens = <String, Widget Function()>{
    'lobby': () => const LobbyScreen(),
    'wallet': () => const WalletScreen(),
    'markets': () => const MarketsScreen(),
    'market_detail': () => const MarketDetailScreen(marketId: 'm-onyx1-76-luna'),
    'customize': () => const CustomizeScreen(),
  };

  for (final mode in const [ThemeMode.dark, ThemeMode.light]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} ${mode.name}', (tester) async {
        usePhoneSurface(tester);
        await pumpScreen(tester, e.value(), themeMode: mode);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${e.key}_${mode.name}.png'));
      });
    }
  }

  testWidgets('dealer mid-round (deterministic frame)', (tester) async {
    usePhoneSurface(tester, size: const Size(411, 560));
    final c = DealerController();
    addTearDown(c.dispose);
    enqueueDemoRound(c);
    await pumpScreen(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFF0A1620),
        body: Center(child: DealerStage(controller: c, style: const CardStyle(), seats: kDemoSeats, drive: false)),
      ),
    );
    // 14.2 s into the script: split hands dealt, bust badge, turn ring on.
    for (var i = 0; i < 14200 ~/ 20; i++) {
      c.advance(const Duration(milliseconds: 20));
    }
    await tester.pump();
    await expectLater(find.byType(DealerStage), matchesGoldenFile('goldens/dealer_mid_round.png'));
  });

  testWidgets('card faces and backs', (tester) async {
    usePhoneSurface(tester, size: const Size(411, 620));
    const cards = [
      PlayingCard(Rank.ace, Suit.spades),
      PlayingCard(Rank.ten, Suit.hearts),
      PlayingCard(Rank.queen, Suit.diamonds),
      PlayingCard(Rank.seven, Suit.clubs),
    ];
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.palette.background,
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                for (final face in CardFaceStyle.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [for (final card in cards) PlayingCardView(card: card, style: CardStyle(face: face), width: 70)],
                    ),
                  ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < CardBackDesign.values.length; i++)
                      PlayingCardView(
                        card: null,
                        faceUp: false,
                        style: CardStyle(back: CardBackDesign.values[i], backColorIndex: i),
                        width: 70,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/cards.png'));
  });
}
