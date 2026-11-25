// End-to-end journey on an Android emulator (AVD) against the Firebase
// emulators running on the host (tools\run_emulators.ps1 or
// tools\start_classroom.ps1; seeded, simulation loop running so that sim
// tables and markets exist).
//
//   powershell -ExecutionPolicy Bypass -File tools\test_flutter.ps1 -Integration
//
// The app talks to the backend baked at build time (BACKEND_HOST, default
// 10.0.2.2 = the host seen from the AVD). Every run creates a NEW account
// (unique e-mail), so it can be repeated on the same database.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vingtun/l10n/gen/app_localizations.dart';
import 'package:vingtun/main.dart' as app;

/// Pumps frames until [finder] matches (never pumpAndSettle: the lobby
/// marquee and the dealer's idle animation never settle).
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for ${reason ?? finder}');
}

Future<void> pumpUntilGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 40), String? reason}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for ${reason ?? finder} to disappear');
}

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapWhenReady(WidgetTester tester, Finder f, {String? reason, Duration timeout = const Duration(seconds: 40)}) async {
  await pumpUntil(tester, f, reason: reason, timeout: timeout);
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Hides the soft keyboard and waits for its animation: a tap during it lands on a
/// widget that is still moving (the layout shrinks while the keyboard slides in).
Future<void> closeKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFor(tester, const Duration(milliseconds: 1200));
}

/// Android system back (what a player presses); pageBack() needs a specific BackButton widget.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await pumpFor(tester, const Duration(milliseconds: 600));
}

/// System back until the bottom tabs show again (a sheet or dialog may still be open on top).
Future<void> backToTabs(WidgetTester tester, String tabLabel) async {
  for (var i = 0; i < 4 && find.text(tabLabel).evaluate().isEmpty; i++) {
    await systemBack(tester);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fr = lookupAppLocalizations(const Locale('fr'));
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('signup → KYC → deposit → table hand + power → spectator bet → friend → theme/language', (tester) async {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final email = 'it_$stamp@vingtun.test';
    // Unique per run, at most 12 characters (the base-36 stamp is 8 today).
    final username = 'it${stamp.length > 10 ? stamp.substring(stamp.length - 10) : stamp}';

    await app.main();
    await tester.pump(const Duration(seconds: 1));
    // Start signed out whatever the previous run left on the device. The app uses one NAMED
    // Firebase app per server address, so sign out of every app, not only the default one.
    for (final a in Firebase.apps) {
      await FirebaseAuth.instanceFor(app: a).signOut();
    }

    // ---------------------------------------------------------------- signup
    await tapWhenReady(tester, find.text(fr.createAccount), reason: 'login screen');
    await pumpUntil(tester, find.byKey(const Key('signup-email')));
    await tester.enterText(find.byKey(const Key('signup-email')), email);
    await tester.enterText(find.byKey(const Key('signup-password')), 'motdepasse-${stamp}7');
    await tester.enterText(find.byKey(const Key('signup-username')), username);
    await closeKeyboard(tester);
    await tester.pump();
    await tapWhenReady(tester, find.byKey(const Key('signup-adult')));
    await tapWhenReady(tester, find.byKey(const Key('signup-submit')));

    // ------------------------------------------------------------------- KYC
    await pumpUntil(tester, find.byKey(const Key('kyc-start')), reason: 'KYC form after signup');
    await tester.enterText(find.byKey(const Key('kyc-name')), 'Camille Test');
    await closeKeyboard(tester);
    await tester.pump();
    // Birth date: the picker opens 25 years back; accept it.
    await tester.tap(find.byKey(const Key('kyc-birth')));
    await pumpUntil(tester, find.text('OK'));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 500));
    await tapWhenReady(tester, find.byKey(const Key('kyc-start')));
    await tapWhenReady(tester, find.text(fr.kycGoToWallet), reason: 'KYC verified', timeout: const Duration(seconds: 90));

    // --------------------------------------------------------------- deposit
    await tapWhenReady(tester, find.byKey(const Key('wallet-deposit')), reason: 'wallet');
    await pumpUntil(tester, find.byKey(const Key('payment-amount')));
    await tester.enterText(find.byKey(const Key('payment-amount')), '250');
    await closeKeyboard(tester);
    await tester.pump();
    await tapWhenReady(tester, find.byKey(const Key('payment-confirm')));
    await pumpUntilGone(tester, find.byKey(const Key('payment-amount')), reason: 'deposit accepted');
    await pumpFor(tester, const Duration(seconds: 3));

    // ------------------------------------------------------ buy a peek power
    await tapWhenReady(tester, find.text(fr.navProfile));
    await tapWhenReady(tester, find.byKey(const Key('nav-shop')));
    await tapWhenReady(tester, find.byKey(const Key('buy-peek')), reason: 'shop');
    await pumpUntil(tester, find.text(fr.shopBought(fr.powerPeek)), reason: 'power bought');
    await backToTabs(tester, fr.navProfile);
    await tester.pump(const Duration(milliseconds: 500));

    // ------------------------------------------------- matchmaking + a hand
    await tapWhenReady(tester, find.text(fr.navLobby));
    await tapWhenReady(tester, find.byKey(const Key('lobby-play')), reason: 'lobby');
    await pumpUntil(tester, find.byKey(const Key('table-status')), reason: 'table', timeout: const Duration(seconds: 60));
    // Bet as soon as betting opens (the hand may be running when we arrive), then wait for MY
    // turn (the powers button is also visible before it, e.g. during insurance, when peek is not
    // usable yet). A hand can end without a turn for me (natural): bet again on the next one.
    final stand = find.byKey(const Key('action-stand'));
    bool myTurn() => stand.evaluate().isNotEmpty && tester.widget<FilledButton>(stand).onPressed != null;
    var peeked = false;
    for (var hand = 0; hand < 3 && !peeked; hand++) {
      await tapWhenReady(tester, find.byKey(const Key('bet-place')), reason: 'betting phase', timeout: const Duration(seconds: 120));
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(end) && !myTurn()) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (!myTurn()) continue;
      // My turn: peek at the hole card with the power, then stand.
      await tapWhenReady(tester, find.byKey(const Key('table-powers')));
      await tapWhenReady(tester, find.byKey(const Key('power-peek')));
      await pumpUntil(tester, find.byKey(const Key('peek-banner')), reason: 'peek result', timeout: const Duration(seconds: 20));
      peeked = true;
      if (myTurn()) await tester.tap(stand);
    }
    expect(peeked, isTrue, reason: 'never got a turn to use the peek power');
    await pumpUntil(
      tester,
      find.textContaining(RegExp('${RegExp.escape(fr.tableSettled)}|Résultat|${RegExp.escape(fr.tableWaitingNextHand)}')),
      reason: 'hand settled',
      timeout: const Duration(seconds: 90),
    );
    await pumpFor(tester, const Duration(seconds: 3));
    await tapWhenReady(tester, find.byKey(const Key('table-leave')));
    final confirm = find.byKey(const Key('leave-confirm'));
    await tester.pump(const Duration(milliseconds: 500));
    if (confirm.evaluate().isNotEmpty) await tester.tap(confirm);
    await pumpFor(tester, const Duration(seconds: 2));

    // ------------------------------------------------- spectator bet (market)
    await tapWhenReady(tester, find.text(fr.navMarkets));
    // Per-hand markets close within seconds (before the dealer reveals): if the one we open has
    // just closed, come back and try the next one.
    var traded = false;
    for (var attempt = 0; attempt < 6 && !traded; attempt++) {
      await tapWhenReady(tester, find.byKey(const Key('outcome-yes')), reason: 'open market');
      try {
        await pumpUntil(tester, find.byKey(const Key('ticket-submit')), timeout: const Duration(seconds: 6));
      } on TestFailure {
        await systemBack(tester);
        await pumpFor(tester, const Duration(seconds: 2));
        continue;
      }
      await tester.tap(find.byKey(const Key('ticket-submit')));
      await pumpUntil(tester, find.text(fr.ticketDone), reason: 'trade done');
      traded = true;
    }
    expect(traded, isTrue, reason: 'no open market accepted a trade');
    await backToTabs(tester, fr.navProfile);
    await tester.pump(const Duration(milliseconds: 500));

    // ------------------------------------------------------- friend request
    await tapWhenReady(tester, find.text(fr.navProfile));
    await tapWhenReady(tester, find.byKey(const Key('nav-friends')));
    await tapWhenReady(tester, find.text(fr.friendsAdd), reason: 'friend suggestions');
    await pumpFor(tester, const Duration(seconds: 2));
    await backToTabs(tester, fr.navProfile);
    await tester.pump(const Duration(milliseconds: 500));

    // ------------------------------------------------- theme + language
    await tapWhenReady(tester, find.byKey(const Key('nav-settings')));
    await tapWhenReady(tester, find.text(fr.themeLight));
    await tapWhenReady(tester, find.text('English'));
    await pumpUntil(tester, find.text(en.settingsTitle), reason: 'English UI');
    // Restore the defaults for the next run on this device.
    await tapWhenReady(tester, find.text(en.themeDark));
    await tapWhenReady(tester, find.text('Français'));
    await pumpUntil(tester, find.text(fr.settingsTitle));
    // ignore: avoid_print
    print('INTEGRATION FLOW COMPLETE');

    // Tear the app down ourselves and let the last frame-driven animations (lobby marquee, dealer
    // idle loop, chip tweens) run out, so the end-of-test invariant does not see them pending.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpFor(tester, const Duration(seconds: 3));
  });
}
