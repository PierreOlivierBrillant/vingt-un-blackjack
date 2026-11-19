import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/features/ads/ads_demo_screen.dart';
import 'package:vingtun/features/auth/login_screen.dart';
import 'package:vingtun/features/auth/server_screen.dart';
import 'package:vingtun/features/auth/signup_screen.dart';
import 'package:vingtun/features/customize/customize_screen.dart';
import 'package:vingtun/features/dealer/dealer_demo_screen.dart';
import 'package:vingtun/features/friends/friends_screen.dart';
import 'package:vingtun/features/kyc/kyc_screen.dart';
import 'package:vingtun/features/leaderboard/leaderboard_screen.dart';
import 'package:vingtun/features/lobby/lobby_screen.dart';
import 'package:vingtun/features/markets/market_detail_screen.dart';
import 'package:vingtun/features/markets/markets_screen.dart';
import 'package:vingtun/features/profile/profile_screen.dart';
import 'package:vingtun/features/settings/settings_screen.dart';
import 'package:vingtun/features/shop/shop_screen.dart';
import 'package:vingtun/features/table/table_screen.dart';
import 'package:vingtun/features/wallet/wallet_screen.dart';
import 'package:vingtun/l10n/gen/app_localizations.dart';

import '../helpers.dart';

typedef TextOf = String Function(AppLocalizations l);

class ScreenCase {
  const ScreenCase(this.name, this.build, this.expectText, {this.signedIn = true});
  final String name;
  final Widget Function() build;
  final TextOf expectText;
  final bool signedIn;
}

final cases = <ScreenCase>[
  ScreenCase('login', () => const LoginScreen(), (l) => l.loginTitle, signedIn: false),
  ScreenCase('signup', () => const SignupScreen(), (l) => l.authUsernameRule, signedIn: false),
  ScreenCase('server', () => const ServerScreen(), (l) => l.serverHostLabel, signedIn: false),
  ScreenCase('kyc', () => const KycScreen(), (l) => l.kycStartScan),
  ScreenCase('lobby', () => const LobbyScreen(), (l) => l.lobbyLiveTables),
  ScreenCase('wallet', () => const WalletScreen(), (l) => l.walletBalance),
  ScreenCase('markets', () => const MarketsScreen(), (l) => l.mqDealerBusts),
  ScreenCase('market detail', () => const MarketDetailScreen(marketId: 'm-cobalt1-205-bust'), (l) => l.ticketAvgPrice),
  ScreenCase('leaderboard', () => const LeaderboardScreen(), (l) => l.lbGlobal),
  ScreenCase('profile', () => const ProfileScreen(), (l) => l.shopTitle),
  ScreenCase('shop', () => const ShopScreen(), (l) => l.powerPeek),
  ScreenCase('customize', () => const CustomizeScreen(), (l) => l.customizeFaces),
  ScreenCase('friends', () => const FriendsScreen(), (l) => l.friendsList),
  ScreenCase('settings', () => const SettingsScreen(), (l) => l.settingsTheme),
  ScreenCase('ads', () => const AdsDemoScreen(), (l) => l.adsShowInterstitial),
  ScreenCase('table', () => const TableScreen(tableId: 't-saphir-1'), (l) => l.actionHit),
  ScreenCase('dealer demo', () => const DealerDemoScreen(), (l) => l.dealerPlayRound),
];

void main() {
  for (final locale in const [Locale('fr'), Locale('en')]) {
    group('${locale.languageCode.toUpperCase()} ·', () {
      for (final c in cases) {
        testWidgets('${c.name} renders without overflow', (tester) async {
          usePhoneSurface(tester);
          await pumpScreen(tester, c.build(), locale: locale, signedIn: c.signedIn);
          final l = l10nOf(locale);
          expect(find.textContaining(c.expectText(l), findRichText: true), findsWidgets);
          expect(tester.takeException(), isNull);
          // Let any running animation advance a bit more, still no errors.
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
        });
      }
    });
  }

  testWidgets('screens also fit a small phone (360 × 640) in French', (tester) async {
    for (final c in cases) {
      usePhoneSurface(tester, size: const Size(360, 640));
      await pumpScreen(tester, c.build(), signedIn: c.signedIn);
      expect(tester.takeException(), isNull, reason: c.name);
    }
  });
}
