import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/money.dart';
import 'package:vingtun/data/providers.dart';
import 'package:vingtun/data/repositories.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/features/friends/friends_screen.dart';
import 'package:vingtun/features/leaderboard/leaderboard_screen.dart';
import 'package:vingtun/features/lobby/lobby_screen.dart';
import 'package:vingtun/features/markets/markets_screen.dart';
import 'package:vingtun/features/shop/shop_screen.dart';

import '../helpers.dart';

class _OneEntryBoard implements LeaderboardRepository {
  @override
  Stream<List<LeaderboardEntry>> watch(LeaderboardScope scope, {int limit = 50}) => Stream.value(const [
        LeaderboardEntry(rank: 1, uid: 'me', username: 'Solo', points: 12, tier: RankTier.bronze, handsPlayed: 3, winRate: 0.5, isMe: true),
      ]);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final l = l10nOf(const Locale('fr'));

  testWidgets('leaderboard lists entries even with fewer than 3 (no podium)', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const LeaderboardScreen(),
        overrides: [leaderboardRepositoryProvider.overrideWithValue(_OneEntryBoard())]);
    expect(find.text('Solo (${l.you})'), findsOneWidget);
  });

  testWidgets('friends: incoming requests, list, suggestions; accept goes through the repository', (tester) async {
    usePhoneSurface(tester);
    final c = await pumpScreen(tester, const FriendsScreen());
    final repo = c.read(friendsRepositoryProvider);
    final incoming = (await repo.watchRequests().first).where((r) => r.incoming).toList();
    expect(incoming, isNotEmpty);
    expect(find.text(l.friendsRequests(incoming.length)), findsOneWidget);
    await tester.tap(find.byKey(Key('friend-accept-${incoming.first.fromUid}')));
    await settle(tester);
    expect(find.text(l.friendsAccepted(incoming.first.fromUsername)), findsOneWidget);
    final after = await repo.watchRequests().first;
    expect(after.where((r) => r.incoming && r.fromUid == incoming.first.fromUid), isEmpty);
  });

  testWidgets('friends: username search shows results with an add button', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const FriendsScreen());
    await tester.enterText(find.byKey(const Key('friends-search')), 'a');
    await settle(tester);
    expect(find.byType(ListTile), findsWidgets);
  });

  testWidgets('shop: rewarded ad tile credits the reward through claimAdReward', (tester) async {
    usePhoneSurface(tester);
    final c = await pumpScreen(tester, const ShopScreen());
    expect(find.text(l.walletWatchAd(formatCents(500, locale: 'fr'))), findsOneWidget);
    final before = (await c.read(walletRepositoryProvider).watchWallet().first).balanceCents;
    await tester.tap(find.byKey(const Key('shop-rewarded-ad')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.byKey(const Key('ad-claim')));
    await settle(tester);
    final after = (await c.read(walletRepositoryProvider).watchWallet().first).balanceCents;
    expect(after - before, 500);
  });

  testWidgets('lobby: private table sheet validates the code then joins', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const LobbyScreen());
    await tester.tap(find.byKey(const Key('lobby-private')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('private-code')), 'AB');
    await tester.tap(find.byKey(const Key('private-join')));
    await settle(tester);
    expect(find.text(l.privateCodeInvalid), findsOneWidget);
    await tester.enterText(find.byKey(const Key('private-code')), 'abc123');
    await tester.tap(find.byKey(const Key('private-join')));
    await settle(tester);
    expect(find.text('route:/table/t-private-abc123'), findsOneWidget);
  });

  testWidgets('lobby: unknown private code shows the server reason', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const LobbyScreen());
    await tester.tap(find.byKey(const Key('lobby-private')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('private-code')), 'ZZZ999');
    await tester.tap(find.byKey(const Key('private-join')));
    await settle(tester);
    expect(find.text(l.errReasonBadCode), findsOneWidget);
  });

  testWidgets('markets: "my positions" lists positions with their status', (tester) async {
    usePhoneSurface(tester);
    final c = await pumpScreen(tester, const MarketsScreen());
    final positions = await c.read(marketsRepositoryProvider).watchPositions().first;
    await tester.ensureVisible(find.text(l.filterMine));
    await tester.tap(find.text(l.filterMine));
    await settle(tester);
    if (positions.isEmpty) {
      expect(find.text(l.marketsEmpty), findsOneWidget);
    } else {
      expect(find.byType(PositionCard), findsWidgets);
    }
  });
}
