// The hold'em table screen: FR / EN, small phone, my turn (fold / call /
// raise slider and presets), between hands (rebuy, sit out), waiting, the
// showdown, snapshots animated one after the other, the "last hand" sheet
// (every hole card rebuilt from the revealed seed) and the rules sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/data/providers.dart';
import 'package:vingtun/features/games/holdem/holdem_screen.dart';

import '../helpers.dart';
import '../holdem_fixtures.dart';

Future<void> frames(WidgetTester tester, {int n = 8, int ms = 100}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

Future<HoldemTestRepo> pumpHoldem(WidgetTester tester, Map<String, Object?> doc, {Locale locale = const Locale('fr'), List<Map<String, Object?>> rounds = const [], List<String>? hole = const ['AS', 'KD'], Size? size}) async {
  usePhoneSurface(tester, size: size ?? const Size(411, 914));
  final repo = HoldemTestRepo(doc, rounds: rounds, hole: hole);
  await pumpScreen(tester, const HoldemScreen(tableId: kHoldemTableId), locale: locale, overrides: [gameTableRepositoryProvider.overrideWithValue(repo)]);
  await frames(tester, n: 4);
  return repo;
}

void main() {
  for (final locale in const [Locale('fr'), Locale('en')]) {
    group('${locale.languageCode.toUpperCase()} ·', () {
      testWidgets('my turn on the flop: hand, call, raise slider within min raise and stack', (tester) async {
        final repo = await pumpHoldem(tester, holdemFlopDoc(), locale: locale);
        final l = l10nOf(locale);
        expect(tester.takeException(), isNull);
        expect(find.text(l.holdemMyHand(locale.languageCode == 'fr' ? "Paire d'as" : 'Pair of aces')), findsOneWidget);
        expect(find.byKey(const Key('holdem-fold')), findsOneWidget);
        expect(find.text(locale.languageCode == 'fr' ? 'Suivre 6 \$' : 'Call \$6'), findsOneWidget);
        expect(find.byKey(const Key('holdem-slider')), findsOneWidget);
        expect(find.text(locale.languageCode == 'fr' ? 'Relancer à 12 \$' : 'Raise to \$12'), findsOneWidget);
        expect(find.textContaining(l.holdemStreetFlop), findsWidgets);
        expect(find.byKey(const Key('holdem-pots')), findsOneWidget);
        expect(find.byKey(const Key('holdem-button')), findsOneWidget);
        expect(find.byKey(const Key('holdem-bet-5')), findsOneWidget);
        // Pot preset: call 6 then the pot after the call (10 + 6 + 6) → raise to 28.
        await tester.tap(find.byKey(const Key('holdem-preset-pot')));
        await tester.pump();
        expect(find.text(locale.languageCode == 'fr' ? '28 \$' : '\$28'), findsOneWidget);
        await tester.tap(find.byKey(const Key('holdem-raise')));
        await frames(tester, n: 2);
        expect(repo.actions.last, {'type': 'raise', 'toCents': 2800});
        // All-in preset → the action is an all-in.
        await tester.tap(find.byKey(const Key('holdem-preset-allIn')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('holdem-raise')));
        await frames(tester, n: 2);
        expect(repo.actions.last, {'type': 'allIn'});
        await tester.tap(find.byKey(const Key('holdem-call')));
        await frames(tester, n: 2);
        expect(repo.actions.last, {'type': 'call'});
        await tester.tap(find.byKey(const Key('holdem-fold')));
        await frames(tester, n: 2);
        expect(repo.actions.last, {'type': 'fold'});
        expect(tester.takeException(), isNull);
      });

      testWidgets('waiting for chips: rebuy dialog sends the amount, sit out / back', (tester) async {
        final repo = await pumpHoldem(tester, holdemWaitingDoc(), locale: locale, hole: null);
        final l = l10nOf(locale);
        expect(find.byKey(const Key('holdem-waiting')), findsOneWidget);
        expect(find.text(l.holdemNoChips), findsOneWidget);
        await tester.tap(find.byKey(const Key('holdem-rebuy')));
        await frames(tester, n: 3);
        expect(find.byKey(const Key('holdem-rebuy-slider')), findsOneWidget);
        await tester.tap(find.byKey(const Key('holdem-rebuy-confirm')));
        await frames(tester, n: 3);
        expect(repo.actions.last, {'type': 'rebuy', 'cents': 20000});
        await tester.tap(find.byKey(const Key('holdem-sit-out')));
        await frames(tester, n: 2);
        expect(repo.actions.last, {'type': 'sitOut'});
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('showdown: hand names, the result and the winner glow', (tester) async {
    await pumpHoldem(tester, holdemShowdownDoc());
    expect(find.byKey(const Key('holdem-hand-0')), findsOneWidget);
    expect(find.byKey(const Key('holdem-hand-2')), findsOneWidget);
    expect(find.text('Deux paires, as et rois'), findsOneWidget);
    expect(find.text('Paire de dames'), findsOneWidget);
    expect(find.byKey(const Key('holdem-result')), findsOneWidget);
    expect(find.byKey(const Key('holdem-fold')), findsNothing);
    // Stack 228 $ over the 200 $ maximum: no rebuy.
    expect(find.byKey(const Key('holdem-rebuy')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('not my turn: waiting message, no decision buttons, a bet can be raised later', (tester) async {
    await pumpHoldem(tester, holdemFlopDoc(myTurn: false));
    final l = l10nOf(const Locale('fr'));
    expect(find.text(l.holdemWaitTurn('Ada')), findsOneWidget);
    expect(find.byKey(const Key('holdem-fold')), findsNothing);
    expect(find.byKey(const Key('holdem-slider')), findsNothing);
  });

  testWidgets('snapshots pushed one by one animate without error (deal, flop, showdown, next hand)', (tester) async {
    final repo = await pumpHoldem(tester, holdemPreflopDoc());
    repo.push(holdemFlopDoc());
    await frames(tester, n: 40, ms: 50);
    expect(tester.takeException(), isNull);
    repo.push(holdemShowdownDoc());
    await frames(tester, n: 60, ms: 50);
    expect(find.byKey(const Key('holdem-result')), findsOneWidget);
    repo.push(holdemPreflopDoc(round: 8));
    await frames(tester, n: 80, ms: 50);
    expect(find.byKey(const Key('holdem-result')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last hand: every hole card from the revealed seed, verified', (tester) async {
    final deal = (holdemVectors()['deals']! as List).cast<Map<String, Object?>>()[2];
    await pumpHoldem(tester, holdemFlopDoc(), rounds: [holdemRoundFromVector(deal)]);
    final l = l10nOf(const Locale('fr'));
    await tester.tap(find.byKey(const Key('holdem-last-hand')));
    await frames(tester, n: 4);
    expect(find.byKey(const Key('holdem-last-hand-sheet')), findsOneWidget);
    expect(find.text(l.holdemLastHandBody), findsOneWidget);
    expect(find.text(l.holdemLastHandVerified), findsOneWidget);
    for (final s in deal['order']! as List) {
      expect(find.byKey(Key('holdem-reveal-$s')), findsOneWidget);
    }
  });

  testWidgets('rules sheet states that folded cards are visible', (tester) async {
    await pumpHoldem(tester, holdemFlopDoc());
    final l = l10nOf(const Locale('fr'));
    await tester.tap(find.byKey(const Key('game-rules')));
    await frames(tester, n: 4);
    expect(find.byKey(const Key('holdem-rules')), findsOneWidget);
    expect(find.textContaining('joueurs couchés, qui sont donc visibles par tous'), findsOneWidget);
    expect(find.text(l.holdemRulesAllIn), findsOneWidget);
  });

  testWidgets('every state fits a small phone (360 × 640) in French and English', (tester) async {
    for (final locale in const [Locale('fr'), Locale('en')]) {
      for (final doc in [holdemFlopDoc(), holdemFlopDoc(myTurn: false), holdemShowdownDoc(), holdemWaitingDoc(), holdemPreflopDoc()]) {
        await pumpHoldem(tester, doc, locale: locale, size: const Size(360, 640));
        await frames(tester, n: 3);
        expect(tester.takeException(), isNull, reason: '${doc['step']} ${locale.languageCode}');
      }
    }
  });

  testWidgets('spectator of a table without hold\'em state (fake sim table) renders', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const HoldemScreen(tableId: 'ho-sim-01'));
    await frames(tester, n: 4);
    expect(tester.takeException(), isNull);
  });
}
