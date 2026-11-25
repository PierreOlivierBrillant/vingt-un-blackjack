// End-to-end journey on an Android emulator (AVD) against the Firebase
// emulators running on the host (tools\run_emulators.ps1 or
// tools\start_classroom.ps1; seeded, simulation loop running so that sim
// tables, their shoe markets and the bots' friend suggestions exist).
//
//   flutter test integration_test -d emulator-5554 --dart-define=BACKEND_HOST=<host IP>
//
// The app talks to the backend baked at build time (BACKEND_HOST, default
// 10.0.2.2 = the host seen from the AVD). Every run creates a NEW account
// (unique e-mail), so it can be repeated on the same database.
//
// Reliability rules (the backend is live and shared with the simulation):
//  - the hand is played at a PRIVATE table created by the test: no bots, the deal starts as
//    soon as the test bets, and only the test's own decisions (20 s each) drive the pace;
//  - the spectator bet goes to a shoe market ("Par sabot"), which stays open for many hands;
//  - every tap waits until its target is on screen, enabled, not moving and not covered
//    (snackbars persist across routes and covered the bet button once), and a tap that would
//    miss is a failure (hitTestWarningShouldBeFatal) instead of a silent no-op.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vingtun/l10n/gen/app_localizations.dart';
import 'package:vingtun/main.dart' as app;

/// What is on screen (route + visible texts), appended to every timeout so a failure says where
/// the app was.
String screenSummary() {
  final texts = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final s = (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isNotEmpty && !texts.contains(s)) texts.add(s);
    if (texts.length >= 40) break;
  }
  String route = '?';
  final scaffolds = find.byType(Scaffold).evaluate();
  if (scaffolds.isNotEmpty) {
    final r = GoRouter.maybeOf(scaffolds.first);
    if (r != null) route = r.routerDelegate.currentConfiguration.last.matchedLocation;
  }
  return '[route $route] ${texts.join(' | ')}';
}

/// Snackbar texts already logged (they say why a call failed, and fade before a timeout dump).
final _snacksSeen = <String>{};

void logNewSnackBars() {
  for (final e in find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)).evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (s.isNotEmpty && _snacksSeen.add(s)) debugPrint('[it] snackbar: $s');
  }
}

/// Pumps one frame after [d], logging any new snackbar.
Future<void> pumpLogged(WidgetTester tester, Duration d) async {
  await tester.pump(d);
  logNewSnackBars();
}

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
    await pumpLogged(tester, const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for ${reason ?? finder}' '\n  screen: ${screenSummary()}');
}

/// Like [pumpUntil] but returns false instead of failing.
Future<bool> pumpUntilOrFalse(WidgetTester tester, Finder finder, Duration timeout) async {
  try {
    await pumpUntil(tester, finder, timeout: timeout);
    return true;
  } on TestFailure {
    return false;
  }
}

Future<void> pumpUntilGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 40), String? reason}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await pumpLogged(tester, const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for ${reason ?? finder} to disappear' '\n  screen: ${screenSummary()}');
}

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await pumpLogged(tester, const Duration(milliseconds: 100));
  }
}

/// Whether the first widget of [f] would react to a tap (buttons and tiles can be disabled).
bool isEnabled(WidgetTester tester, Finder f) {
  final w = tester.widget(f.first);
  return switch (w) {
    ButtonStyleButton() => w.enabled,
    IconButton() => w.onPressed != null,
    ListTile() => w.enabled && w.onTap != null,
    InkWell() => w.onTap != null,
    _ => true,
  };
}

/// Removes every snackbar at once (they stay up across routes and cover the bottom of the screen).
void clearSnackBars(WidgetTester tester) {
  for (final m in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
    m.clearSnackBars();
    m.removeCurrentSnackBar();
  }
}

/// Scrolls [f] to the MIDDLE of its scrollable (the default alignment puts it at the very top,
/// where a pinned app bar or a layout shift can leave it covered).
Future<void> centerInView(WidgetTester tester, Finder f) async {
  final e = f.evaluate().first;
  if (Scrollable.maybeOf(e) != null) {
    await Scrollable.ensureVisible(e, alignment: 0.5);
  }
  await tester.pump();
}

/// Waits for [f] to be present, enabled, still (sheets and the keyboard animate) and reachable
/// by a tap at its centre (clearing snackbars that cover it), then taps it.
Future<void> tapWhenReady(
  WidgetTester tester,
  Finder f, {
  String? reason,
  Duration timeout = const Duration(seconds: 40),
}) async {
  final what = reason ?? f.toString();
  final end = DateTime.now().add(timeout);
  await pumpUntil(tester, f, reason: what, timeout: timeout);
  Rect? last;
  while (true) {
    if (DateTime.now().isAfter(end)) {
      final state = f.evaluate().isEmpty
          ? 'gone'
          : !isEnabled(tester, f)
              ? 'disabled'
              : 'covered or moving';
      throw TestFailure('Could not tap $what ($state)' '\n  screen: ${screenSummary()}');
    }
    if (f.evaluate().isEmpty || !isEnabled(tester, f)) {
      last = null;
      await pumpLogged(tester, const Duration(milliseconds: 200));
      continue;
    }
    await centerInView(tester, f);
    final rect = tester.getRect(f.first);
    if (rect != last) {
      last = rect;
      await tester.pump(const Duration(milliseconds: 150));
      continue;
    }
    if (f.hitTestable().evaluate().isEmpty) {
      clearSnackBars(tester);
      last = null;
      await tester.pump(const Duration(milliseconds: 300));
      continue;
    }
    await tester.tap(f.hitTestable().first);
    await tester.pump(const Duration(milliseconds: 300));
    return;
  }
}

/// Taps [f] if it is there, enabled and reachable right now; returns whether it did.
Future<bool> tapIfReady(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty || !isEnabled(tester, f) || f.hitTestable().evaluate().isEmpty) return false;
  await tester.tap(f.hitTestable().first);
  await tester.pump(const Duration(milliseconds: 300));
  return true;
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
  await pumpFor(tester, const Duration(milliseconds: 800));
}

/// System back until the bottom tabs are on screen again (a page, sheet or dialog may be on
/// top). Never presses back on the tabs themselves: at the root it would close the app.
Future<void> backToTabs(WidgetTester tester) async {
  clearSnackBars(tester);
  final tabs = find.byType(NavigationBar).hitTestable();
  for (var i = 0; i < 5; i++) {
    await pumpLogged(tester, const Duration(milliseconds: 200));
    if (tabs.evaluate().isNotEmpty) break;
    await systemBack(tester);
  }
  await pumpUntil(tester, tabs, reason: 'bottom tabs', timeout: const Duration(seconds: 10));
  await pumpFor(tester, const Duration(milliseconds: 500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fr = lookupAppLocalizations(const Locale('fr'));
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('signup → KYC → deposit → shop → private table hand + peek → spectator bet → friend → theme/language', (tester) async {
    // A tap that would land on another widget fails here, with the widget that was hit.
    WidgetController.hitTestWarningShouldBeFatal = true;
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final email = 'it_$stamp@vingtun.test';
    // Unique per run, at most 12 characters (the base-36 stamp is 8 today).
    final username = 'it${stamp.length > 10 ? stamp.substring(stamp.length - 10) : stamp}';
    void step(String s) => debugPrint('[it] ${DateTime.now().toIso8601String().substring(11, 19)} $s');

    await app.main();
    await tester.pump(const Duration(seconds: 1));
    // Start signed out whatever the previous run left on the device. The app uses one NAMED
    // Firebase app per server address, so sign out of every app, not only the default one.
    for (final a in Firebase.apps) {
      await FirebaseAuth.instanceFor(app: a).signOut();
    }

    // ---------------------------------------------------------------- signup
    step('signup');
    await tapWhenReady(tester, find.text(fr.createAccount), reason: 'login screen');
    await pumpUntil(tester, find.byKey(const Key('signup-email')));
    await tester.enterText(find.byKey(const Key('signup-email')), email);
    await tester.enterText(find.byKey(const Key('signup-password')), 'motdepasse-${stamp}7');
    await tester.enterText(find.byKey(const Key('signup-username')), username);
    await closeKeyboard(tester);
    await tapWhenReady(tester, find.byKey(const Key('signup-adult')));
    await tapWhenReady(tester, find.byKey(const Key('signup-submit')));

    // ------------------------------------------------------------------- KYC
    step('kyc');
    await pumpUntil(tester, find.byKey(const Key('kyc-start')), reason: 'KYC form after signup', timeout: const Duration(seconds: 60));
    await tester.enterText(find.byKey(const Key('kyc-name')), 'Camille Test');
    await closeKeyboard(tester);
    // Birth date: the picker opens 25 years back; accept it.
    await tapWhenReady(tester, find.byKey(const Key('kyc-birth')));
    await tapWhenReady(tester, find.text('OK'), reason: 'date picker');
    await pumpUntilGone(tester, find.text('OK'), reason: 'date picker closed');
    await tapWhenReady(tester, find.byKey(const Key('kyc-start')));
    await tapWhenReady(tester, find.text(fr.kycGoToWallet), reason: 'KYC verified', timeout: const Duration(seconds: 90));

    // --------------------------------------------------------------- deposit
    step('deposit');
    await tapWhenReady(tester, find.byKey(const Key('wallet-deposit')), reason: 'wallet');
    await pumpUntil(tester, find.byKey(const Key('payment-amount')));
    await tester.enterText(find.byKey(const Key('payment-amount')), '250');
    await closeKeyboard(tester);
    await tapWhenReady(tester, find.byKey(const Key('payment-confirm')));
    await pumpUntilGone(tester, find.byKey(const Key('payment-amount')), reason: 'deposit accepted');
    await pumpFor(tester, const Duration(seconds: 2));

    // ------------------------------------------------------ buy a peek power
    step('shop');
    await tapWhenReady(tester, find.text(fr.navProfile));
    await tapWhenReady(tester, find.byKey(const Key('nav-shop')));
    await tapWhenReady(tester, find.byKey(const Key('buy-peek')), reason: 'shop');
    await pumpUntil(tester, find.text(fr.shopBought(fr.powerPeek)), reason: 'power bought');
    await backToTabs(tester);

    // ------------------------------------------- private table + one hand with peek
    step('private table');
    await tapWhenReady(tester, find.text(fr.navLobby));
    await tapWhenReady(tester, find.byKey(const Key('lobby-private')), reason: 'lobby');
    await tapWhenReady(tester, find.byKey(const Key('private-create')), reason: 'private table sheet');
    await pumpUntil(tester, find.byKey(const Key('table-code')), reason: 'private table', timeout: const Duration(seconds: 60));
    // Alone at the table: betting deals at once. A hand can end without a turn for me (my
    // natural, the dealer's natural): then bet on the next one.
    final stand = find.byKey(const Key('action-stand'));
    final betButton = find.byKey(const Key('bet-place'));
    bool myTurn() => stand.evaluate().isNotEmpty && isEnabled(tester, stand);
    var peeked = false;
    for (var hand = 0; hand < 3 && !peeked; hand++) {
      step('bet (hand ${hand + 1})');
      await tapWhenReady(tester, betButton, reason: 'betting phase', timeout: const Duration(seconds: 60));
      await pumpUntilGone(tester, betButton, reason: 'bet accepted', timeout: const Duration(seconds: 20));
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(end) && !myTurn()) {
        // Dealer shows an ace: decline insurance (the peek power needs MY turn).
        await tapIfReady(tester, find.byKey(const Key('insurance-decline')));
        if (betButton.evaluate().isNotEmpty) break; // hand over without a turn: next one is betting
        await pumpLogged(tester, const Duration(milliseconds: 200));
      }
      if (!myTurn()) continue;
      step('peek + stand');
      await tapWhenReady(tester, find.byKey(const Key('table-powers')));
      await tapWhenReady(tester, find.byKey(const Key('power-peek')), reason: 'peek power usable', timeout: const Duration(seconds: 10));
      await pumpUntil(tester, find.byKey(const Key('peek-banner')), reason: 'peek result', timeout: const Duration(seconds: 15));
      peeked = true;
      // The peek is its own call: stand once the action bar is enabled again.
      if (await pumpUntilOrFalse(tester, stand.hitTestable(), const Duration(seconds: 3))) {
        final standEnd = DateTime.now().add(const Duration(seconds: 15));
        while (DateTime.now().isBefore(standEnd) && !myTurn()) {
          await pumpLogged(tester, const Duration(milliseconds: 200));
        }
        if (myTurn()) await tapIfReady(tester, stand);
      }
    }
    expect(peeked, isTrue, reason: 'never got a turn to use the peek power in 3 hands; screen: ${screenSummary()}');
    step('hand settled?');
    final settledText = RegExp('${RegExp.escape(fr.tableSettled)}|${RegExp.escape(fr.tableResult('').trim())}');
    final settleEnd = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(settleEnd) && find.textContaining(settledText).evaluate().isEmpty && betButton.evaluate().isEmpty) {
      await pumpLogged(tester, const Duration(milliseconds: 200));
    }
    expect(find.textContaining(settledText).evaluate().isNotEmpty || betButton.evaluate().isNotEmpty, isTrue, reason: 'hand settled; screen: ${screenSummary()}');
    // Leave once the next hand is betting (the result has been shown; same phase every run).
    await pumpUntil(tester, betButton, reason: 'next hand betting', timeout: const Duration(seconds: 30));
    await pumpFor(tester, const Duration(seconds: 1));
    step('leave table');
    await tapWhenReady(tester, find.byKey(const Key('table-leave')));
    if (await pumpUntilOrFalse(tester, find.byKey(const Key('leave-confirm')), const Duration(seconds: 2))) {
      await tapWhenReady(tester, find.byKey(const Key('leave-confirm')));
    }
    await pumpUntil(tester, find.byType(NavigationBar).hitTestable(), reason: 'back in the lobby after leaving', timeout: const Duration(seconds: 20));
    await pumpFor(tester, const Duration(seconds: 1));

    // ------------------------------------------------- spectator bet (market)
    step('markets');
    await tapWhenReady(tester, find.text(fr.navMarkets));
    // Shoe markets ("Par sabot") stay open for about half a shoe, unlike per-hand markets that
    // close within seconds. If the one we open has just stopped trading, try again; after a few
    // tries, fall back to every market.
    await tapWhenReady(tester, find.text(fr.filterShoe), reason: 'shoe filter');
    final anyMarket = find.byKey(const Key('outcome-yes'));
    var allMarkets = false;
    if (!await pumpUntilOrFalse(tester, anyMarket, const Duration(seconds: 30))) {
      await tapWhenReady(tester, find.text(fr.filterAll), reason: 'all markets filter');
      allMarkets = true;
    }
    var traded = false;
    for (var attempt = 0; attempt < 6 && !traded; attempt++) {
      if (attempt == 3 && !allMarkets) {
        await tapWhenReady(tester, find.text(fr.filterAll), reason: 'all markets filter');
        allMarkets = true;
      }
      step('market attempt ${attempt + 1}');
      await tapWhenReady(tester, find.byKey(const Key('outcome-yes')), reason: 'open market', timeout: const Duration(seconds: 60));
      if (!await pumpUntilOrFalse(tester, find.byKey(const Key('ticket-submit')), const Duration(seconds: 8))) {
        await backToTabs(tester);
        continue;
      }
      await tapWhenReady(tester, find.byKey(const Key('ticket-submit')), reason: 'order ticket');
      traded = await pumpUntilOrFalse(tester, find.text(fr.ticketDone), const Duration(seconds: 20));
      await backToTabs(tester);
    }
    expect(traded, isTrue, reason: 'no open market accepted a trade; screen: ${screenSummary()}');

    // ------------------------------------------------------- friend request
    step('friends');
    await tapWhenReady(tester, find.text(fr.navProfile));
    await tapWhenReady(tester, find.byKey(const Key('nav-friends')));
    // First suggestion that can still be added (a new account has no friends yet).
    final addFriend = find.byWidgetPredicate(
      (w) => w is ButtonStyleButton && w.enabled && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('friend-add-'),
    );
    await tapWhenReady(tester, addFriend, reason: 'friend suggestions');
    final sentPrefix = fr.friendsRequestSent('\u0000').split('\u0000').first;
    await pumpUntil(tester, find.textContaining(sentPrefix), reason: 'friend request sent', timeout: const Duration(seconds: 20));
    await backToTabs(tester);

    // ------------------------------------------------- theme + language
    step('settings');
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
