/// Repository bindings.
///
/// * [useFirebaseProvider] false (default, all tests): in-memory fakes.
/// * true (overridden in `main.dart`): Firebase repositories built from the
///   connected `firebaseBackendProvider`; they are rebuilt (and the old ones
///   disposed) when the backend host changes on the Server screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap/firebase_backend.dart';
import '../domain/card_style.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import 'connection_status.dart';
import 'fake/fake_game_repository.dart';
import 'fake/fake_repositories.dart';
import 'firebase/firebase_repositories.dart';
import 'repositories.dart';

export 'connection_status.dart' show ConnectionStatus, ConnectionMonitor;

/// Injectable clock so relative times ("il y a 4 min") are testable.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Overridden to `true` by `main.dart`. Tests keep the fakes.
final useFirebaseProvider = Provider<bool>((ref) => false);

/// Reachability fed by the Firebase repositories (always online with fakes).
final connectionMonitorProvider = Provider<ConnectionMonitor>((ref) {
  final m = ConnectionMonitor();
  ref.onDispose(m.dispose);
  return m;
});

/// online / offline (Firestore served from cache) / unreachable (last
/// callable could not reach the server). Show a banner when not online.
final connectionStatusProvider =
    StreamProvider<ConnectionStatus>((ref) => ref.watch(connectionMonitorProvider).changes);

/// The Firebase repositories of the current backend, or null with fakes.
/// Throws [RepositoryException] unavailable if Firebase never connected.
final firebaseRepositoriesProvider = Provider<FirebaseRepositories?>((ref) {
  if (!ref.watch(useFirebaseProvider)) return null;
  // Rebuild only when the backend instance changes (not on loading states).
  final backend = ref.watch(firebaseBackendProvider.select((a) => a.value));
  if (backend == null) {
    throw const RepositoryException(RepositoryFailure.unavailable, 'Firebase is not connected');
  }
  final repos = FirebaseRepositories(backend, monitor: ref.watch(connectionMonitorProvider), now: ref.watch(clockProvider));
  ref.onDispose(repos.dispose);
  return repos;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(firebaseRepositoriesProvider)?.auth ?? FakeAuthRepository(now: ref.watch(clockProvider)),
);

final kycRepositoryProvider = Provider<KycRepository>((ref) {
  final fb = ref.watch(firebaseRepositoriesProvider);
  if (fb != null) return fb.kyc;
  final auth = ref.watch(authRepositoryProvider);
  return FakeKycRepository(auth is FakeAuthRepository ? auth : FakeAuthRepository(), now: ref.watch(clockProvider));
});

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => ref.watch(firebaseRepositoriesProvider)?.wallet ?? FakeWalletRepository(ref.watch(clockProvider)),
);

FakeWalletRepository? _fakeWallet(Ref ref) {
  final w = ref.watch(walletRepositoryProvider);
  return w is FakeWalletRepository ? w : null;
}

final lobbyRepositoryProvider = Provider<LobbyRepository>(
  (ref) => ref.watch(firebaseRepositoriesProvider)?.lobby ?? FakeLobbyRepository(ref.watch(clockProvider)),
);
final tableRepositoryProvider = Provider<TableRepository>(
  (ref) => ref.watch(firebaseRepositoriesProvider)?.table ?? FakeTableRepository(),
);
/// Sprint 2: roulette, baccarat, hold'em and craps tables (`gameTables`).
final gameTableRepositoryProvider = Provider<GameTableRepository>(
  (ref) =>
      ref.watch(firebaseRepositoriesProvider)?.games ??
      FakeGameTableRepository(wallet: _fakeWallet(ref), now: ref.watch(clockProvider)),
);
final shopRepositoryProvider = Provider<ShopRepository>(
  (ref) =>
      ref.watch(firebaseRepositoriesProvider)?.shop ??
      FakeShopRepository(wallet: _fakeWallet(ref), now: ref.watch(clockProvider)),
);
final cosmeticsRepositoryProvider = Provider<CosmeticsRepository>(
  (ref) => ref.watch(firebaseRepositoriesProvider)?.cosmetics ?? FakeCosmeticsRepository(ref.watch(clockProvider)),
);
final leaderboardRepositoryProvider = Provider<LeaderboardRepository>(
  (ref) =>
      ref.watch(firebaseRepositoriesProvider)?.leaderboard ?? FakeLeaderboardRepository(now: ref.watch(clockProvider)),
);
final friendsRepositoryProvider = Provider<FriendsRepository>(
  (ref) => ref.watch(firebaseRepositoriesProvider)?.friends ?? FakeFriendsRepository(now: ref.watch(clockProvider)),
);
final marketsRepositoryProvider = Provider<MarketsRepository>(
  (ref) =>
      ref.watch(firebaseRepositoriesProvider)?.markets ??
      FakeMarketsRepository(ref.watch(clockProvider), wallet: _fakeWallet(ref)),
);
final adsRepositoryProvider = Provider<AdsRepository>(
  (ref) =>
      ref.watch(firebaseRepositoriesProvider)?.ads ??
      FakeAdsRepository(wallet: _fakeWallet(ref), now: ref.watch(clockProvider)),
);

// ------------------------------------------------- stream view providers --

final authStateProvider =
    StreamProvider<AppUser?>((ref) => ref.watch(authRepositoryProvider).authStateChanges());
final profileProvider = StreamProvider.family<PlayerProfile?, String>(
  (ref, uid) => ref.watch(authRepositoryProvider).watchProfile(uid),
);
final kycStateProvider = StreamProvider<KycState>((ref) => ref.watch(kycRepositoryProvider).watchKyc());
final kycStatusProvider =
    StreamProvider<KycStatus>((ref) => ref.watch(kycRepositoryProvider).watchKyc().map((s) => s.status));
final walletProvider =
    StreamProvider<WalletSnapshot>((ref) => ref.watch(walletRepositoryProvider).watchWallet());
final ledgerProvider =
    StreamProvider<List<LedgerEntry>>((ref) => ref.watch(walletRepositoryProvider).watchLedger());
final tiersProvider =
    StreamProvider<List<StakeTier>>((ref) => ref.watch(lobbyRepositoryProvider).watchStakeTiers());
final liveTablesProvider = StreamProvider.family<List<LiveTable>, String?>(
  (ref, tierId) => ref.watch(lobbyRepositoryProvider).watchLiveTables(tierId: tierId),
);
final recentWinsProvider =
    StreamProvider<List<RecentWin>>((ref) => ref.watch(lobbyRepositoryProvider).watchRecentWins());
final tableViewProvider = StreamProvider.family<TableState, String>(
  (ref, id) => ref.watch(tableRepositoryProvider).watchTable(id),
);
/// `tables/{id}/peeks/{me}` (peek power result), null when none.
final peekProvider = StreamProvider.family<PeekResult?, String>(
  (ref, id) => ref.watch(tableRepositoryProvider).watchPeek(id),
);

/// Finished hands of a table (provably-fair proofs), newest first.
final tableHistoryProvider = StreamProvider.family<List<HandHistory>, String>(
  (ref, id) => ref.watch(tableRepositoryProvider).watchHistory(id, limit: 10),
);
// ------------------------------------------------ Sprint 2: game tables --

/// Public open tables of one kernel game (`(game, tier)`; tier null = all).
final gameLiveTablesProvider = StreamProvider.family<List<LiveTable>, (GameId, String?)>(
  (ref, k) => ref.watch(gameTableRepositoryProvider).watchLiveTables(k.$1, tierId: k.$2),
);

/// `gameTables/{id}`.
final gameTableProvider = StreamProvider.family<GameTableState, String>(
  (ref, id) => ref.watch(gameTableRepositoryProvider).watchTable(id),
);

/// `gameTables/{id}/bets/*` (all boards; filter by round with [GameBet.isFor]).
final gameBetsProvider = StreamProvider.family<List<GameBet>, String>(
  (ref, id) => ref.watch(gameTableRepositoryProvider).watchBets(id),
);

/// `gameTables/{id}/holes/{me}` (hold'em).
final gameHoleProvider = StreamProvider.family<GameHole?, String>(
  (ref, id) => ref.watch(gameTableRepositoryProvider).watchMyHole(id),
);

/// Finished rounds (`rounds/*`, newest first): history + fairness proofs.
final gameRoundsProvider = StreamProvider.family<List<GameRound>, String>(
  (ref, id) => ref.watch(gameTableRepositoryProvider).watchRounds(id, limit: 10),
);

final powerOffersProvider =
    StreamProvider<List<PowerOffer>>((ref) => ref.watch(shopRepositoryProvider).watchOffers());
final equippedStyleProvider =
    StreamProvider<CardStyle>((ref) => ref.watch(cosmeticsRepositoryProvider).watchEquipped());
final userSettingsProvider =
    StreamProvider<UserSettings>((ref) => ref.watch(cosmeticsRepositoryProvider).watchSettings());
final leaderboardProvider = StreamProvider.family<List<LeaderboardEntry>, LeaderboardScope>(
  (ref, scope) => ref.watch(leaderboardRepositoryProvider).watch(scope),
);
final friendsProvider =
    StreamProvider<List<Friend>>((ref) => ref.watch(friendsRepositoryProvider).watchFriends());
final friendRequestsProvider = StreamProvider<List<FriendRequest>>(
  (ref) => ref.watch(friendsRepositoryProvider).watchRequests(),
);
final friendSuggestionsProvider = StreamProvider<List<PlayerProfile>>(
  (ref) => ref.watch(friendsRepositoryProvider).watchSuggestions(),
);
final marketsProvider =
    StreamProvider<List<Market>>((ref) => ref.watch(marketsRepositoryProvider).watchMarkets());
final tableMarketsProvider = StreamProvider.family<List<Market>, String>(
  (ref, tableId) => ref.watch(marketsRepositoryProvider).watchMarketsForTable(tableId),
);
final marketProvider = StreamProvider.family<Market, String>(
  (ref, id) => ref.watch(marketsRepositoryProvider).watchMarket(id),
);
final priceHistoryProvider = StreamProvider.family<List<PricePoint>, String>(
  (ref, id) => ref.watch(marketsRepositoryProvider).watchPriceHistory(id),
);
final positionsProvider = StreamProvider<List<MarketPosition>>(
  (ref) => ref.watch(marketsRepositoryProvider).watchPositions(),
);
final marketActivityProvider = StreamProvider.family<List<MarketTrade>, String>(
  (ref, id) => ref.watch(marketsRepositoryProvider).watchActivity(id),
);
final adStateProvider = StreamProvider<AdState>((ref) => ref.watch(adsRepositoryProvider).watchAdState());
