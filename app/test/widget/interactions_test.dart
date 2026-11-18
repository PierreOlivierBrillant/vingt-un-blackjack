import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/bootstrap/backend_config.dart';
import 'package:vingtun/core/settings/settings_controller.dart';
import 'package:vingtun/data/fake/fake_repositories.dart';
import 'package:vingtun/data/providers.dart';
import 'package:vingtun/domain/card_style.dart';
import 'package:vingtun/data/repositories.dart';
import 'package:vingtun/domain/lmsr.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/features/ads/ads_demo_screen.dart';
import 'package:vingtun/features/auth/login_screen.dart';
import 'package:vingtun/features/auth/server_screen.dart';
import 'package:vingtun/features/customize/customize_screen.dart';
import 'package:vingtun/features/kyc/kyc_screen.dart';
import 'package:vingtun/features/markets/market_detail_screen.dart';
import 'package:vingtun/features/settings/settings_screen.dart';
import 'package:vingtun/features/wallet/payment_sheet.dart';
import 'package:vingtun/features/wallet/wallet_screen.dart';

import '../helpers.dart';

void main() {
  testWidgets('login validates input and signs in through the repository', (tester) async {
    usePhoneSurface(tester);
    final c = await pumpScreen(tester, const LoginScreen(), signedIn: false);
    final l = l10nOf(const Locale('fr'));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text(l.validationEmail), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-email')), 'demo@vingt-un.test');
    await tester.enterText(find.byKey(const Key('login-password')), 'secret123');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(c.read(authRepositoryProvider).currentUser?.email, 'demo@vingt-un.test');
  });

  testWidgets('server screen: rejects bad host, tests and saves a good one', (tester) async {
    usePhoneSurface(tester);
    final probe = FakeProbe(up: false);
    final c = await pumpScreen(tester, const ServerScreen(), signedIn: false, probe: probe);
    final l = l10nOf(const Locale('fr'));
    await tester.enterText(find.byKey(const Key('server-host')), 'http://x:1');
    await tester.tap(find.byKey(const Key('server-test')));
    await tester.pump();
    expect(find.text(l.serverHostInvalid), findsOneWidget);
    expect(probe.calls, isEmpty);

    await tester.enterText(find.byKey(const Key('server-host')), '192.168.1.20');
    await tester.tap(find.byKey(const Key('server-test')));
    await tester.pump();
    await tester.pump();
    expect(probe.calls, ['192.168.1.20']);
    expect(find.text(l.serverUnreachable), findsNWidgets(3));
    expect(find.text(l.serverSomeDown), findsOneWidget);

    await tester.tap(find.byKey(const Key('server-save')));
    await tester.pump();
    expect(c.read(backendConfigProvider).host, '192.168.1.20');
    expect(c.read(sharedPreferencesProvider).getString('backend.host'), '192.168.1.20');
  });

  testWidgets('deposit sheet: card number is pre-filled, read-only, and deposit credits the wallet', (tester) async {
    usePhoneSurface(tester);
    final c = await pumpScreen(tester, const WalletScreen());
    final before = (await c.read(walletRepositoryProvider).watchWallet().first).balanceCents;
    await tester.tap(find.byKey(const Key('wallet-deposit')));
    await tester.pumpAndSettle();

    final cardField = tester.widget<EditableText>(
      find.descendant(of: find.byKey(const Key('payment-card-number')), matching: find.byType(EditableText)),
    );
    expect(cardField.controller.text, SimulatedPaymentDetails.cardNumber);
    expect(cardField.readOnly, isTrue);
    expect(find.text(l10nOf(const Locale('fr')).paymentSimulationBanner), findsOneWidget);

    await tester.enterText(find.byKey(const Key('payment-amount')), '25,50');
    await tester.tap(find.byKey(const Key('payment-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final after = (await c.read(walletRepositoryProvider).watchWallet().first).balanceCents;
    expect(after - before, 2550);
  });

  testWidgets('deposit/withdraw are disabled until KYC is verified', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(
      tester,
      const WalletScreen(),
      auth: FakeAuthRepository(signedIn: FakeAuthRepository.demoUser.copyWith(kycStatus: KycStatus.none)),
    );
    final btn = tester.widget<ButtonStyleButton>(find.byKey(const Key('wallet-deposit')));
    expect(btn.onPressed, isNull);
    expect(find.text(l10nOf(const Locale('fr')).walletKycNeeded), findsOneWidget);
  });

  testWidgets('KYC: scan animation then verified for an adult', (tester) async {
    usePhoneSurface(tester);
    final auth = FakeAuthRepository(signedIn: FakeAuthRepository.demoUser.copyWith(kycStatus: KycStatus.none));
    await pumpScreen(
      tester,
      const KycScreen(scanDuration: Duration(milliseconds: 400)),
      auth: auth,
      overrides: [kycRepositoryProvider.overrideWithValue(FakeKycRepository(auth, reviewDelay: Duration.zero))],
      locale: const Locale('en'),
    );
    final l = l10nOf(const Locale('en'));
    await tester.tap(find.byKey(const Key('kyc-start')));
    await tester.pump();
    expect(find.text(l.kycFormIncomplete), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Ada Lovelace');
    await tester.tap(find.text(l.kycChooseDate));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kyc-start')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(l.kycScanning), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l.kycVerified), findsOneWidget);
    expect(auth.currentUser!.kycStatus, KycStatus.verified);
  });

  testWidgets('customise: picking neon + felt updates the preview and equips on save', (tester) async {
    usePhoneSurface(tester);
    final c = await pumpScreen(tester, const CustomizeScreen());
    await tester.tap(find.byKey(const Key('face-neon')));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('felt-purple')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('felt-purple')));
    await tester.pump();
    final preview = tester.widget<CardStylePreview>(find.byType(CardStylePreview));
    expect(preview.style.face, CardFaceStyle.neon);
    expect(preview.style.felt, FeltColor.purple);

    await tester.tap(find.byKey(const Key('customize-save')));
    await tester.pump();
    await tester.pump();
    final equipped = await c.read(cosmeticsRepositoryProvider).watchEquipped().first;
    expect(equipped.face, CardFaceStyle.neon);
    expect(equipped.felt, FeltColor.purple);
  });

  testWidgets('settings: theme and language switches persist', (tester) async {
    usePhoneSurface(tester);
    final c = await pumpScreen(tester, const SettingsScreen());
    await tester.tap(find.text(l10nOf(const Locale('fr')).themeLight));
    await tester.pump();
    expect(c.read(settingsProvider).themeMode, ThemeMode.light);
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(c.read(settingsProvider).locale, const Locale('en'));
    expect(c.read(sharedPreferencesProvider).getString('settings.locale'), 'en');
  });

  testWidgets('order ticket: changing shares refreshes the LMSR estimate', (tester) async {
    usePhoneSurface(tester);
    final c = await pumpScreen(tester, const MarketDetailScreen(marketId: 'm-cobalt1-205-bust'));
    await tester.scrollUntilVisible(find.byKey(const Key('shares-plus')), 200);
    expect(find.text('10'), findsWidgets);
    final market = await c.read(marketsRepositoryProvider).watchMarket('m-cobalt1-205-bust').first;
    final state = LmsrState.ofMarket(market);
    final costBefore = TradeQuote.compute(state, Outcome.yes, 10, buy: true).costCents;
    await tester.tap(find.byKey(const Key('shares-plus')));
    await tester.pump();
    await tester.pump();
    expect(find.text('15'), findsOneWidget);
    final costAfter = TradeQuote.compute(state, Outcome.yes, 15, buy: true).costCents;
    expect(costAfter, greaterThan(costBefore));
    // The repository quote is exactly the server LMSR amount.
    final repoQuote = await c.read(marketsRepositoryProvider).quote(market.id, Outcome.yes, 15, buy: true);
    expect(repoQuote.amountCents, lmsrQuoteBuy(state, Outcome.yes, 15).amountCents);
  });

  testWidgets('interstitial ad can only be closed after its countdown', (tester) async {
    usePhoneSurface(tester);
    await pumpScreen(tester, const AdsDemoScreen());
    await tester.scrollUntilVisible(find.byKey(const Key('ads-interstitial')), 200);
    await tester.tap(find.byKey(const Key('ads-interstitial')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ad-close')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('ad-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ad-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ad-close')), findsNothing);
  });
}
