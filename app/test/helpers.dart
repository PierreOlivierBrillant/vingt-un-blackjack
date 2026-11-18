import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vingtun/bootstrap/backend_config.dart';
import 'package:vingtun/bootstrap/backend_probe.dart';
import 'package:vingtun/core/settings/settings_controller.dart';
import 'package:vingtun/core/theme/app_theme.dart';
import 'package:vingtun/data/fake/fake_repositories.dart';
import 'package:vingtun/data/providers.dart';
import 'package:vingtun/data/repositories.dart';
import 'package:vingtun/l10n/gen/app_localizations.dart';

/// Fixed "now" so relative times and price histories are deterministic.
final kTestNow = DateTime(2026, 11, 18, 20, 30);

class FakeProbe implements BackendProbe {
  FakeProbe({this.up = true});
  bool up;
  final calls = <String>[];
  @override
  Future<List<ProbeResult>> probe(BackendConfig config) async {
    calls.add(config.host);
    return [
      for (final s in BackendService.values)
        ProbeResult(s, ok: up, latency: up ? const Duration(milliseconds: 12) : null, error: up ? null : 'refused'),
    ];
  }
}

/// Phone-sized surface (Pixel-like 411 × 914 dp).
void usePhoneSurface(WidgetTester tester, {Size size = const Size(411, 914)}) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = size * 2.0;
  addTearDown(tester.view.reset);
}

Future<SharedPreferences> testPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

/// Pumps [screen] inside the real theme + localizations + a GoRouter whose
/// other routes render a placeholder (so `context.push` works in tests).
Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Locale locale = const Locale('fr'),
  ThemeMode themeMode = ThemeMode.dark,
  List<Override> overrides = const [],
  bool signedIn = true,
  AuthRepository? auth,
  BackendProbe? probe,
}) async {
  final prefs = await testPrefs();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => kTestNow),
    authRepositoryProvider.overrideWithValue(
      auth ?? FakeAuthRepository(signedIn: signedIn ? FakeAuthRepository.demoUser : null),
    ),
    backendProbeProvider.overrideWithValue(probe ?? FakeProbe()),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/:rest(.*)', builder: (_, s) => Scaffold(body: Text('route:${s.uri.path}'))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    ),
  );
  // Streams resolve in microtasks; a few frames is enough. Several screens
  // run endless animations (ticker, dealer idle), so never pumpAndSettle.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

AppLocalizations l10nOf(Locale locale) => lookupAppLocalizations(locale);
