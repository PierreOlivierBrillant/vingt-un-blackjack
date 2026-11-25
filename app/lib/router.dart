import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/audio/sfx.dart';
import 'core/audio/sound_providers.dart';
import 'data/providers.dart';
import 'domain/models.dart';
import 'features/ads/ads_demo_screen.dart';
import 'features/auth/complete_profile_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/server_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/customize/customize_screen.dart';
import 'features/dealer/dealer_demo_screen.dart';
import 'features/friends/friends_screen.dart';
import 'features/kyc/kyc_screen.dart';
import 'features/leaderboard/leaderboard_screen.dart';
import 'features/lobby/lobby_screen.dart';
import 'features/markets/market_detail_screen.dart';
import 'features/markets/markets_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/shop/shop_screen.dart';
import 'features/table/table_screen.dart';
import 'features/wallet/wallet_screen.dart';

const _publicPaths = {'/login', '/signup', '/server'};

/// Auth gate: signed out → `/login`; signed in without profile
/// ([AppUser.profileComplete] false) → `/complete-profile`; signed in with a
/// profile never sees the auth screens.
String? authRedirect(AppUser? user, String path) {
  if (user == null) return _publicPaths.contains(path) ? null : '/login';
  // During sign-up the account exists before its profile (completeProfile
  // callable in flight): stay on the sign-up screen meanwhile, then continue
  // to the KYC step (the screen's own navigation may be pre-empted by this).
  if (!user.profileComplete) {
    return path == '/complete-profile' || path == '/server' || path == '/signup' ? null : '/complete-profile';
  }
  if (path == '/signup') return '/kyc';
  if (path == '/login' || path == '/complete-profile') return '/lobby';
  return null;
}

/// What [authRedirect] depends on. The router is refreshed only when this changes: the user
/// stream also emits on every profile snapshot (balance, current table...), and a refresh that
/// lands while a page is being popped makes go_router re-parse its last reported location and
/// push that page back (leaving a table showed the closed table again).
(String?, bool) authRedirectKey(AppUser? user) => (user?.uid, user?.profileComplete ?? false);

final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final auth = ref.watch(authRepositoryProvider);
  final refresh = ValueNotifier<int>(0);
  var redirectKey = authRedirectKey(auth.currentUser);
  final sub = auth.authStateChanges().listen((u) {
    final key = authRedirectKey(u);
    if (key == redirectKey) return;
    redirectKey = key;
    refresh.value++;
  });
  ref.onDispose(() {
    sub.cancel();
    refresh.dispose();
  });

  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/lobby',
    refreshListenable: refresh,
    observers: [
      SoundNavigatorObserver(
        () => ref.read(soundProvider).play(Sfx.navSwoosh),
        onPopup: () => ref.read(soundProvider).play(Sfx.cardFlip1, volume: 0.8),
      ),
    ],
    redirect: (context, state) => authRedirect(auth.currentUser, state.uri.path),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(path: '/complete-profile', builder: (_, _) => const CompleteProfileScreen()),
      GoRoute(path: '/server', builder: (_, _) => const ServerScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/lobby', builder: (_, _) => const LobbyScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/markets',
              builder: (_, _) => const MarketsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: rootKey,
                  builder: (_, s) => MarketDetailScreen(marketId: s.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/leaderboard', builder: (_, _) => const LeaderboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/wallet', builder: (_, _) => const WalletScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/table/:id',
        parentNavigatorKey: rootKey,
        builder: (_, s) => TableScreen(tableId: s.pathParameters['id']!, privateCode: s.uri.queryParameters['code']),
      ),
      GoRoute(path: '/dealer-demo', parentNavigatorKey: rootKey, builder: (_, _) => const DealerDemoScreen()),
      GoRoute(path: '/kyc', parentNavigatorKey: rootKey, builder: (_, _) => const KycScreen()),
      GoRoute(path: '/shop', parentNavigatorKey: rootKey, builder: (_, _) => const ShopScreen()),
      GoRoute(path: '/customize', parentNavigatorKey: rootKey, builder: (_, _) => const CustomizeScreen()),
      GoRoute(path: '/friends', parentNavigatorKey: rootKey, builder: (_, _) => const FriendsScreen()),
      GoRoute(path: '/settings', parentNavigatorKey: rootKey, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/ads', parentNavigatorKey: rootKey, builder: (_, _) => const AdsDemoScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});


/// "Swoosh" on every full-screen page change (not dialogs / sheets).
class SoundNavigatorObserver extends NavigatorObserver {
  SoundNavigatorObserver(this._swoosh, {this.onPopup});
  final VoidCallback _swoosh;

  /// Dialogs and bottom sheets opening (a card flicked onto the felt).
  final VoidCallback? onPopup;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute != null) _swoosh();
    if (route is PopupRoute) onPopup?.call();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _swoosh();
  }
}