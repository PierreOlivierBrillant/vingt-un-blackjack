import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/bootstrap/backend_config.dart';
import 'package:vingtun/bootstrap/firebase_backend.dart';
import 'package:vingtun/core/ids.dart';
import 'package:vingtun/core/settings/settings_controller.dart';
import 'package:vingtun/data/fake/fake_data.dart';
import 'package:vingtun/data/fake/fake_repositories.dart';
import 'package:vingtun/data/repositories.dart';
import 'package:vingtun/domain/lmsr.dart';
import 'package:vingtun/domain/models.dart';

import '../helpers.dart';

void main() {
  group('backend host', () {
    test('validation accepts IPs and host names only', () {
      for (final ok in ['10.0.2.2', '192.168.1.20', 'localhost', 'prof-pc.local', 'a']) {
        expect(isValidBackendHost(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'http://10.0.2.2', '10.0.2.2:8080', '300.1.1.1', 'a b', '-x.com', '10.0.2.2/path']) {
        expect(isValidBackendHost(bad), isFalse, reason: bad);
      }
    });

    test('default comes from --dart-define (10.0.2.2 when absent)', () {
      expect(kDefaultBackendHost, '10.0.2.2');
      expect(const BackendConfig(host: 'h').authUri.toString(), 'http://h:9099/');
      expect(const BackendConfig(host: 'h').firestoreUri.port, 8080);
      expect(const BackendConfig(host: 'h').functionsUri.port, 5001);
    });

    test('custom host is persisted and can be reset', () async {
      final prefs = await testPrefs();
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      expect(c.read(backendConfigProvider).host, kDefaultBackendHost);
      await c.read(backendConfigProvider.notifier).setHost(' 192.168.0.42 ');
      expect(c.read(backendConfigProvider), const BackendConfig(host: '192.168.0.42', isCustom: true));
      expect(prefs.getString('backend.host'), '192.168.0.42');

      final c2 = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      expect(c2.read(backendConfigProvider).host, '192.168.0.42', reason: 'survives restart');

      await expectLater(c.read(backendConfigProvider.notifier).setHost('http://evil'), throwsArgumentError);
      await c.read(backendConfigProvider.notifier).resetToDefault();
      expect(c.read(backendConfigProvider).isCustom, isFalse);
      expect(prefs.getString('backend.host'), isNull);
    });

    test('a corrupted saved host falls back to the default', () async {
      final prefs = await testPrefs({'backend.host': 'not a host!'});
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      expect(c.read(backendConfigProvider).host, kDefaultBackendHost);
    });

    test('firebase options point at the demo project only', () {
      expect(kDemoFirebaseOptions.projectId, 'demo-blackjack');
      expect(FirebaseBootstrap.appNameFor('192.168.1.2'), 'vingtun-192-168-1-2');
    });
  });

  test('settings persist theme, locale and feedback toggles', () async {
    final prefs = await testPrefs();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).themeMode, ThemeMode.dark, reason: 'dark by default');
    expect(c.read(settingsProvider).locale, const Locale('fr'), reason: 'French by default');
    await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.light);
    await c.read(settingsProvider.notifier).setLocale(const Locale('en'));
    await c.read(settingsProvider.notifier).setHaptics(false);
    final c2 = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c2.dispose);
    expect(c2.read(settingsProvider).themeMode, ThemeMode.light);
    expect(c2.read(settingsProvider).locale, const Locale('en'));
    expect(c2.read(settingsProvider).hapticsOn, isFalse);
  });

  test('idempotency keys are random 32-hex; stableHash is stable', () {
    final a = newIdempotencyKey(), b = newIdempotencyKey();
    expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a, isNot(b));
    expect(stableHash('abc'), 440920331);
  });

  group('fake wallet', () {
    test('deposit is idempotent per key and respects the per-deposit and daily limits', () async {
      final w = FakeWalletRepository(() => kTestNow);
      final start = (await w.watchWallet().first).balanceCents;
      await w.deposit(amountCents: 5000, method: PaymentMethod.card, idempotencyKey: 'k1');
      await w.deposit(amountCents: 5000, method: PaymentMethod.card, idempotencyKey: 'k1');
      expect((await w.watchWallet().first).balanceCents, start + 5000);
      await expectLater(
        w.deposit(amountCents: 300000, method: PaymentMethod.card, idempotencyKey: 'k2'),
        throwsA(isA<RepositoryException>()
            .having((e) => e.failure, 'failure', RepositoryFailure.limitExceeded)
            .having((e) => e.reason, 'reason', ServerReason.DEPOSIT_LIMIT)),
      );
      final ledger = await w.watchLedger().first;
      expect(ledger.first.kind, LedgerKind.deposit);
      // Daily cap 5 000 $: 5 + 4 × 1 000 $ fit, the next 1 000 $ does not.
      for (var i = 0; i < 4; i++) {
        await w.deposit(amountCents: 100000, method: PaymentMethod.crypto, idempotencyKey: 'd$i');
      }
      expect((await w.watchWallet().first).depositedTodayCents, 405000);
      await expectLater(
        w.deposit(amountCents: 100000, method: PaymentMethod.card, idempotencyKey: 'd4'),
        throwsA(isA<RepositoryException>().having((e) => e.reason, 'reason', ServerReason.DEPOSIT_LIMIT)),
      );
    });

    test('withdraw cannot exceed balance; non-positive amounts refused', () async {
      final w = FakeWalletRepository(() => kTestNow);
      expect((await w.watchWallet().first).balanceCents, lessThan(400000));
      await expectLater(
        w.withdraw(amountCents: 400000, method: PaymentMethod.bankTransfer, idempotencyKey: 'x'),
        throwsA(isA<RepositoryException>().having((e) => e.failure, 'f', RepositoryFailure.insufficientFunds)),
      );
      await expectLater(
        w.deposit(amountCents: 0, method: PaymentMethod.card, idempotencyKey: 'y'),
        throwsA(isA<RepositoryException>()),
      );
    });
  });

  test('fake KYC refuses minors (final) and verifies adults; only docType + birthDate are submitted', () async {
    final minor = DateTime.now().subtract(const Duration(days: 365 * 17));
    final kidAuth = FakeAuthRepository(signedIn: FakeAuthRepository.demoUser.copyWith(kycStatus: KycStatus.none));
    final kidKyc = FakeKycRepository(kidAuth, reviewDelay: Duration.zero);
    final rejected = await kidKyc.submit(KycSubmission(documentType: IdDocumentType.passport, birthDate: minor), idempotencyKey: 'kyc-1');
    expect(rejected.status, KycStatus.rejected);
    expect(rejected.rejection, KycRejection.underage);
    await expectLater(
      kidKyc.submit(KycSubmission(documentType: IdDocumentType.passport, birthDate: DateTime(1990)), idempotencyKey: 'kyc-2'),
      throwsA(isA<RepositoryException>().having((e) => e.reason, 'reason', ServerReason.KYC_REJECTED)),
    );

    final auth = FakeAuthRepository(signedIn: FakeAuthRepository.demoUser.copyWith(kycStatus: KycStatus.none));
    final kyc = FakeKycRepository(auth, reviewDelay: Duration.zero);
    final ok = await kyc.submit(KycSubmission(documentType: IdDocumentType.idCard, birthDate: DateTime(1990, 3, 7)), idempotencyKey: 'kyc-3');
    expect(ok.status, KycStatus.verified);
    expect(auth.currentUser!.kycStatus, KycStatus.verified);
    expect(KycSubmission(documentType: IdDocumentType.idCard, birthDate: DateTime(1990, 3, 7)).toRequest(),
        {'docType': 'idCard', 'birthDate': '1990-03-07'});
  });

  test('fake auth: sign-in/out stream, username taken, weak password', () async {
    final auth = FakeAuthRepository();
    expect(await auth.authStateChanges().first, isNull);
    await expectLater(auth.signUp(email: 'a@b.c', password: 'short', username: 'x'), throwsA(isA<AuthException>()));
    await expectLater(
      auth.signUp(email: 'a@b.c', password: 'longenough1', username: 'TheCountess'),
      throwsA(isA<AuthException>().having((e) => e.failure, 'f', AuthFailure.usernameTaken)),
    );
    await expectLater(
      auth.signUp(email: 'a@b.c', password: 'longenough1', username: 'bad name!'),
      throwsA(isA<AuthException>().having((e) => e.failure, 'f', AuthFailure.invalidUsername)),
    );
    await auth.signIn(email: 'demo@vingt-un.test', password: 'secret123');
    expect(auth.currentUser, isNotNull);
    await auth.signOut();
    expect(auth.currentUser, isNull);
  });

  group('LMSR quote (exact server formula)', () {
    // State with a YES price of exactly p: qYes − qNo = b·ln(p / (1 − p)).
    LmsrState at(double p, {double b = 60}) => LmsrState(b: b, qYes: b * log(p / (1 - p)), qNo: 0);

    test('buying YES costs between p and 1 per share and raises the price', () {
      final q = TradeQuote.compute(at(0.3), Outcome.yes, 10, buy: true);
      expect(q.avgPrice, greaterThan(0.3));
      expect(q.avgPrice, lessThan(1));
      expect(q.priceAfter, greaterThan(0.3));
      expect(q.maxPayoutCents, 1000);
    });
    test('buying NO lowers the YES price; selling returns money', () {
      final no = TradeQuote.compute(at(0.6), Outcome.no, 20, buy: true);
      expect(no.priceYesAfter, lessThan(0.6));
      final sell = TradeQuote.compute(at(0.6), Outcome.yes, 20, buy: false);
      expect(sell.costCents, isNegative);
      expect(sell.priceYesAfter, lessThan(0.6));
    });
    test('round trip never makes money', () {
      for (final p in [0.05, 0.3, 0.5, 0.8, 0.95]) {
        final s = at(p);
        final buy = lmsrQuoteBuy(s, Outcome.yes, 50);
        final sell = lmsrQuoteSell(buy.after, Outcome.yes, 50);
        expect(buy.amountCents - sell.amountCents, greaterThanOrEqualTo(0), reason: 'p=$p');
      }
    });
  });

  test('fake ledger adds up: each balance = previous balance + amount, starting at 0', () {
    final l = FakeData.ledger(kTestNow);
    expect(l.first.balanceAfterCents, FakeData.walletBalanceCents);
    for (var i = 0; i < l.length - 1; i++) {
      expect(l[i].balanceAfterCents, l[i + 1].balanceAfterCents + l[i].amountCents, reason: l[i].id);
    }
    expect(l.last.balanceAfterCents - l.last.amountCents, 0);
    expect((WalletSnapshot.fromDoc(FakeData.walletDoc(kTestNow), now: kTestNow)).balanceCents, FakeData.walletBalanceCents);
  });

  test('fake ads reward is capped per day and needs the cooldown', () async {
    var now = kTestNow;
    final ads = FakeAdsRepository(now: () => now);
    for (var i = 0; i < FakeAdsRepository.dailyCap; i++) {
      final r = await ads.claimReward('coin', idempotencyKey: 'ad-$i');
      expect(r.rewardCents, FakeAdsRepository.rewardCents);
      expect(r.remainingToday, FakeAdsRepository.dailyCap - i - 1);
      if (i == 0) {
        await expectLater(
          ads.claimReward('coin', idempotencyKey: 'ad-too-soon'),
          throwsA(isA<RepositoryException>().having((e) => e.reason, 'reason', ServerReason.AD_COOLDOWN)),
        );
      }
      now = now.add(const Duration(seconds: 31));
    }
    await expectLater(
      ads.claimReward('coin', idempotencyKey: 'ad-over'),
      throwsA(isA<RepositoryException>().having((e) => e.reason, 'reason', ServerReason.AD_DAILY_LIMIT)),
    );
  });
}
