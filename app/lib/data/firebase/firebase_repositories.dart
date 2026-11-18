/// The 11 Firebase repositories for one connected [FirebaseBackend]. Built
/// (and disposed) by `firebaseRepositoriesProvider` when the backend host
/// changes.
library;

import '../../bootstrap/firebase_backend.dart';
import '../connection_status.dart';
import 'firebase_account_repositories.dart';
import 'firebase_auth_repository.dart';
import 'firebase_context.dart';
import 'firebase_markets_repository.dart';
import 'firebase_social_repositories.dart';
import 'firebase_table_repositories.dart';

class FirebaseRepositories {
  FirebaseRepositories(FirebaseBackend backend, {required ConnectionMonitor monitor, required DateTime Function() now})
      : context = FirebaseContext(backend, monitor: monitor, now: now);

  final FirebaseContext context;

  late final auth = FirebaseAuthRepository(context);
  late final kyc = FirebaseKycRepository(context);
  late final wallet = FirebaseWalletRepository(context);
  late final lobby = FirebaseLobbyRepository(context);
  late final table = FirebaseTableRepository(context);
  late final shop = FirebaseShopRepository(context);
  late final cosmetics = FirebaseCosmeticsRepository(context);
  late final leaderboard = FirebaseLeaderboardRepository(context);
  late final friends = FirebaseFriendsRepository(context);
  late final markets = FirebaseMarketsRepository(context);
  late final ads = FirebaseAdsRepository(context);

  String get host => context.backend.host;

  Future<void> dispose() async {
    kyc.dispose();
    await auth.dispose();
  }
}
