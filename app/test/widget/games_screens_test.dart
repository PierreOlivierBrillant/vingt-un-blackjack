// Sprint 2 screens: the 4 game tables (placeholders on GameTableScaffold), the
// Rendez-vous hub, the 5-tab shell, the lobby game selector, shop groups,
// profile stats and markets by game — FR / EN, small phone included.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/settings/settings_controller.dart';
import 'package:vingtun/core/theme/app_theme.dart';
import 'package:vingtun/data/fake/fake_game_data.dart';
import 'package:vingtun/data/fake/fake_game_repository.dart';
import 'package:vingtun/data/fake/fake_repositories.dart';
import 'package:vingtun/data/providers.dart';
import 'package:vingtun/domain/games.dart';
import 'package:vingtun/features/games/registry.dart';
import 'package:vingtun/features/lobby/lobby_screen.dart';
import 'package:vingtun/features/markets/markets_screen.dart';
import 'package:vingtun/features/profile/profile_screen.dart';
import 'package:vingtun/features/romance/romance_hub_screen.dart';
import 'package:vingtun/features/shop/shop_screen.dart';
import 'package:vingtun/l10n/gen/app_localizations.dart';
import 'package:vingtun/router.dart';

import '../helpers.dart';

const gameTables = {
  GameId.roulette: 'rl-sim-01',
  GameId.baccarat: 'bc-sim-01',
  GameId.holdem: 'ho-sim-01',
  GameId.craps: 'cr-sim-01',
};

/// The stages and the scaffold's clock never settle: pump a few frames instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

FakeGameTableRepository seatedRepo(String tableId, {String phase = 'betting'}) => FakeGameTableRepository(
      now: () => kTestNow,
      docs: {tableId: FakeGameData.tableDoc(tableId, kTestNow, name: 'Ma table', seatDemo: true, phase: phase, bots: 2)},
    );

void main() {
  for (final locale in const [Locale('fr'), Locale('en')]) {
    group('${locale.languageCode.toUpperCase()} ·', () {
      for (final e in gameTables.entries) {
        testWidgets('${e.key.wire} table renders (spectator) without overflow', (tester) async {
          usePhoneSurface(tester);
          await pumpScreen(tester, tableScreenFor(e.value), locale: locale);
          final l = l10nOf(locale);
          expect(find.textContaining(gameUi(e.key).name(l)), findsWidgets);
          expect(find.byKey(const Key('game-placeholder')), findsOneWidget);
          expect(find.text(l.tableSpectating), findsOneWidget);
          expect(find.byKey(const Key('game-seats')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('Rendez-vous hub renders the 9 characters', (tester) async {
        usePhoneSurface(tester);
        await pumpScreen(tester, const RomanceHubScreen(), locale: locale);
        final l = l10nOf(locale);
        expect(find.text(l.romanceHubTitle), findsWidgets);
        expect(find.byKey(const Key('character-lucas')), findsOneWidget);
        await tester.scrollUntilVisible(find.byKey(const Key('romance-dating')), 200);
        expect(find.byKey(const Key('character-hugo')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('new screens fit a small phone (360 × 640) in French', (tester) async {
    for (final w in [for (final id in gameTables.values) tableScreenFor(id), const RomanceHubScreen()]) {
      usePhoneSurface(tester, size: const Size(360, 640));
      await pumpScreen(tester, w);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: '$w');
    }
  });

  testWidgets('scaffold sheets: rules, history (rounds), fairness verifies the last round', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, tableScreenFor('cr-sim-01'));
    final l = l10nOf(const Locale('fr'));
    await tester.tap(find.byKey(const Key('game-rules')));
    await settle(tester);
    expect(find.byKey(const Key('game-rules-sheet')), findsOneWidget);
    expect(find.text(l.crapsRulesSummary), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('game-rules-sheet')))).pop();
    await settle(tester);

    await tester.tap(find.byKey(const Key('game-history')));
    await settle(tester);
    expect(find.byKey(const Key('round-41')), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('game-history-sheet')))).pop();
    await settle(tester);

    await tester.tap(find.byKey(const Key('game-fairness')));
    await settle(tester);
    expect(find.text(l.gameFairLastRound(41)), findsOneWidget);
    await tester.tap(find.byKey(const Key('game-fair-verify')));
    await tester.pump();
    expect(find.text(l.gameFairCommitOnly), findsOneWidget);
  });

  testWidgets('seated: seat panel, status countdown, leave asks then calls gameLeave', (tester) async {
    usePhoneSurface(tester);
    final repo = seatedRepo('rl-seat');
    await pumpScreen(tester, tableScreenFor('rl-seat'), overrides: [gameTableRepositoryProvider.overrideWithValue(repo)]);
    final l = l10nOf(const Locale('fr'));
    expect(find.text(l.gameSeatedAt(1)), findsOneWidget);
    expect(find.text(l.gamePhaseBetting(14)), findsOneWidget);
    expect(find.text(l.gameYou), findsWidgets);
    await tester.tap(find.byKey(const Key('game-leave')));
    await settle(tester);
    expect(find.text(l.gameLeaveConfirm), findsOneWidget);
    await tester.tap(find.byKey(const Key('game-leave-confirm')));
    await settle(tester);
    expect(repo.calls, contains('leave:rl-seat'));
  });

  testWidgets('overdue deadline: the scaffold pokes the table', (tester) async {
    usePhoneSurface(tester);
    final repo = FakeGameTableRepository(now: () => kTestNow, docs: {
      'bc-late': {...FakeGameData.tableDoc('bc-late', kTestNow), 'deadlineMs': kTestNow.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch},
    });
    await pumpScreen(tester, tableScreenFor('bc-late'), overrides: [gameTableRepositoryProvider.overrideWithValue(repo)]);
    await tester.pump(const Duration(seconds: 1));
    expect(repo.calls, contains('poke:bc-late'));
  });

  testWidgets('lobby: picking a game shows its hero, tables and disabled play while not playable', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const LobbyScreen());
    final l = l10nOf(const Locale('fr'));
    expect(find.byKey(const Key('game-selector')), findsOneWidget);
    expect(find.text(l.lobbyHeroTitle), findsOneWidget); // blackjack by default
    await tester.tap(find.byKey(const Key('game-chip-roulette')));
    await settle(tester);
    expect(find.text(l.gameHeroTitle(l.gameRoulette)), findsOneWidget);
    expect(find.text(l.gameComingSoon), findsWidgets);
    final play = tester.widget<ButtonStyleButton>(find.byKey(const Key('lobby-play')));
    expect(play.enabled, isFalse);
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Roulette Rubis'), 300, scrollable: page);
    expect(find.text('Roulette Rubis'), findsOneWidget);
    // Rules of the game from the hero.
    await tester.scrollUntilVisible(find.byKey(const Key('lobby-rules')), -300, scrollable: page);
    await tester.tap(find.byKey(const Key('lobby-rules')));
    await settle(tester);
    expect(find.text(l.rouletteRulesPayouts), findsOneWidget);
  });

  testWidgets('shop: one group per game, hold\'em explains it has no power', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const ShopScreen());
    final l = l10nOf(const Locale('fr'));
    for (final g in GameId.values) {
      await tester.scrollUntilVisible(find.byKey(Key('shop-group-${g.wire}')), 200);
      expect(find.byKey(Key('shop-group-${g.wire}')), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text(l.shopNoPowers), 200);
    expect(find.byKey(const Key('buy-zeroShield')), findsOneWidget);
  });

  testWidgets('profile: title, stats by game, leaderboard shortcut', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const ProfileScreen());
    final l = l10nOf(const Locale('fr'));
    expect(find.text(titleLabel(l, 'rv_camille_title')), findsOneWidget);
    expect(find.text(l.titleCharacter('Camille')), findsOneWidget);
    expect(find.byKey(const Key('profile-stats-roulette')), findsOneWidget);
    expect(find.textContaining(l.profileStatsRounds(42, 17)), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('nav-leaderboard')), 200);
    await tester.tap(find.byKey(const Key('nav-leaderboard')));
    await settle(tester);
    expect(find.text('route:/leaderboard'), findsOneWidget);
  });

  testWidgets('markets: chips per game filter the list, unknown kinds keep their server question', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const MarketsScreen());
    final l = l10nOf(const Locale('fr'));
    expect(find.byKey(const Key('markets-games')), findsOneWidget);
    await tester.tap(find.byKey(const Key('markets-game-roulette')));
    await settle(tester);
    expect(find.text(l.mqRouletteRed), findsOneWidget);
    expect(find.text(l.mqDealerBusts), findsNothing);
    await tester.tap(find.byKey(const Key('markets-game-all')));
    await settle(tester);
    expect(find.text(l.mqDealerBusts), findsWidgets);
  });

  testWidgets('5 tabs: Casino · Marchés · Rendez-vous · Portefeuille · Profil (ranking out of the tabs)', (tester) async {
    usePhoneSurface(tester);
    final prefs = await testPrefs();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => kTestNow),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(signedIn: FakeAuthRepository.demoUser)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(routerProvider),
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    final l = l10nOf(const Locale('fr'));
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect([for (final d in bar.destinations) (d as NavigationDestination).label], [l.navLobby, l.navMarkets, l.navRomance, l.navWallet, l.navProfile]);
    expect(kTabPaths, ['/lobby', '/markets', '/romance', '/wallet', '/profile']);
    expect(l.navLobby, 'Casino');
    await tester.tap(find.text(l.navRomance));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('romance-hub')), findsOneWidget);
    await tester.tap(find.text(l.navLobby));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('game-selector')), findsOneWidget);
    // /table/:id picks the game's screen.
    unawaited(container.read(routerProvider).push('/table/ho-sim-01'));
    await settle(tester);
    expect(find.byKey(const Key('game-placeholder')), findsOneWidget);
    container.read(routerProvider).pop();
    await tester.pump(const Duration(milliseconds: 400));
    // Leave the tree clean (tickers, timers).
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
