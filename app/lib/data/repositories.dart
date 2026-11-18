/// Repository interfaces — THE seam between the UI and the backend.
///
/// Phase 1 binds every interface to an in-memory fake (`data/fake/`). The
/// Firebase phase implements each one on top of `firebaseBackendProvider`
/// (Auth streams, Firestore snapshots, callables) and swaps the bindings in
/// `data/providers.dart`. Screens only ever depend on these interfaces.
///
/// Rules every implementation must respect (server-authoritative design,
/// `firebase/functions/src/shared/types.ts`):
/// * the client never writes money, cards, bets or ranks — mutations are
///   callables. Every mutating method takes an `idempotencyKey` (sent as
///   `requestId`; reuse the SAME key when the user retries the same logical
///   operation) or, where noted, generates one internally;
/// * failures are thrown as [RepositoryException] (with the exact
///   [ServerReason] when the server sent one) or [AuthException], localized
///   by `localizeError` (`data/error_messages.dart`);
/// * streams emit the current value first, then every change.
library;

import '../domain/card_style.dart';
import '../domain/lmsr.dart';
import '../domain/models.dart';
import '../domain/table_state.dart';
import 'server_errors.dart';

export '../domain/table_state.dart';
export 'server_errors.dart' show ServerReason;

/// Generic failure for non-auth repositories (maps callable error codes).
enum RepositoryFailure {
  /// Server unreachable / offline / timeout.
  unavailable,
  permissionDenied,
  invalidArgument,
  insufficientFunds,
  kycRequired,
  limitExceeded,
  rateLimited,
  notFound,
  unknown,
}

class RepositoryException implements Exception {
  const RepositoryException(this.failure, [this.message, this.reason]);
  final RepositoryFailure failure;
  final String? message;

  /// Exact server reason (`HttpsError.details.reason`) when the server sent one.
  final ServerReason? reason;
  @override
  String toString() =>
      'RepositoryException($failure${reason == null ? '' : '/${reason!.name}'}${message == null ? '' : ': $message'})';
}

abstract interface class AuthRepository {
  /// Emits the signed-in user (with profile) or `null`; emits the current
  /// value immediately on listen. A user whose [AppUser.profileComplete] is
  /// false must call [completeProfile].
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;

  /// Firebase Auth email/password.
  Future<AppUser> signIn({required String email, required String password});

  /// Firebase Auth sign-up + callable `completeProfile` (welcome bonus).
  /// [username]: 3..16 chars [A-Za-z0-9_]; [avatar]: `avatar01`..`avatar24`.
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String username,
    String avatar = 'avatar01',
    String? language,
  });

  /// Callable `completeProfile` for an Auth account without profile.
  /// Errors: AuthFailure.usernameTaken / profileExists / invalidUsername.
  Future<AppUser> completeProfile({
    required String username,
    required String avatar,
    String? language,
    required String idempotencyKey,
  });

  /// `profiles/{uid}` (any user), null while it does not exist.
  Stream<PlayerProfile?> watchProfile(String uid);

  Future<void> signOut();
}

abstract interface class KycRepository {
  /// `users/{me}/private/kyc` (status none when the doc does not exist).
  Stream<KycState> watchKyc();

  /// Callable `submitKyc{docType, birthDate}` — ONLY those two travel.
  /// Under 18 → returns status rejected (no error). Otherwise pending with
  /// `verifyAfter` (≈3 s), then verified.
  Future<KycState> submit(KycSubmission submission, {required String idempotencyKey});

  /// Callable `submitKyc{refresh:true}`: completes a due review.
  Future<KycState> refresh({required String idempotencyKey});
}

abstract interface class WalletRepository {
  /// `users/{me}/private/wallet`.
  Stream<WalletSnapshot> watchWallet();

  /// `users/{me}/ledger` newest first.
  Stream<List<LedgerEntry>> watchLedger({int limit = 50});

  /// Callable `deposit`: ONLY amount + method + idempotency key travel. The
  /// card number shown in the UI is a fixed test value and is never sent.
  /// Amount DEPOSIT_MIN..DEPOSIT_MAX, daily cap 5 000 $ (DEPOSIT_LIMIT).
  Future<WalletMoveResult> deposit({
    required int amountCents,
    required PaymentMethod method,
    required String idempotencyKey,
  });

  /// Callable `withdraw` (WITHDRAW_MIN..WITHDRAW_MAX, ≤ balance).
  Future<WalletMoveResult> withdraw({
    required int amountCents,
    required PaymentMethod method,
    required String idempotencyKey,
  });
}

abstract interface class LobbyRepository {
  /// The 3 tiers (`low|mid|high`, STAKE_TIER_LIMITS) with counters
  /// aggregated from the public open tables.
  Stream<List<StakeTier>> watchStakeTiers();

  /// `tables` where status == open && isPrivate == false (newest first),
  /// optionally filtered by tier client-side.
  Stream<List<LiveTable>> watchLiveTables({String? tierId});

  /// `feed` newest first.
  Stream<List<RecentWin>> watchRecentWins({int limit = 20});

  /// Callable `joinMatchmaking`. [stakeTier] is ignored for
  /// [MatchMode.joinCode]; [code] (6 chars) is required for it.
  /// Errors: BAD_CODE, TABLE_FULL, ALREADY_SEATED, PROFILE_REQUIRED.
  Future<MatchResult> joinMatchmaking({
    required MatchMode mode,
    String stakeTier = 'low',
    String? code,
    required String idempotencyKey,
  });
}

abstract interface class TableRepository {
  /// uid of the signed-in player (to find "my" seat), null if signed out.
  String? get myUid;

  /// Real-time `tables/{tableId}`. Errors: [RepositoryException] notFound.
  Stream<TableState> watchTable(String tableId);

  /// Callable `placeBet` (phase betting, whole dollars).
  Future<void> placeBet(String tableId, int handNumber, int amountCents, {required String idempotencyKey});

  /// Callable `act` on MY seat. [handIndex] should be `table.turn.handIndex`;
  /// [amountCents] only for insurance (0 = decline).
  Future<void> act(
    String tableId,
    int handNumber,
    PlayerAction action, {
    int? handIndex,
    int? amountCents,
    PowerType? power,
    required String idempotencyKey,
  });

  /// Callable `pokeTable` (generates its own requestId; harmless to repeat):
  /// asks the server to apply overdue deadlines. Returns true when the
  /// table advanced.
  Future<bool> poke(String tableId);

  /// Callable `leaveTable` (generates its own requestId); returns the
  /// refunded cents.
  Future<int> leave(String tableId);

  /// `tables/{id}/peeks/{myUid}` (peek power result), null when none.
  Stream<PeekResult?> watchPeek(String tableId);

  /// Last finished hands (`tables/{id}/hands`, newest first).
  Stream<List<HandHistory>> watchHistory(String tableId, {int limit = 20});
}

abstract interface class ShopRepository {
  /// One offer per power (POWER_PRICES_CENTS) with the owned quantity from
  /// `users/{me}/inventory`.
  Stream<List<PowerOffer>> watchOffers();

  /// Callable `buyPower` ([quantity] 1..10, inventory max 99).
  /// Errors: INSUFFICIENT_FUNDS, INVENTORY_FULL.
  Future<BuyPowerResult> buy(PowerType type, {int quantity = 1, required String idempotencyKey});
}

abstract interface class CosmeticsRepository {
  /// cardBack / cardFace / felt of `users/{me}` (server defaults when absent).
  Stream<CardStyle> watchEquipped();

  /// `users/{me}` settings (theme, language, style).
  Stream<UserSettings> watchSettings();

  /// Callable `equipCardStyle`. The back is sent as [CardStyle.serverBack]
  /// (one of the 6 server backs); the equipped style is normalized to it.
  Future<CardStyle> equip(CardStyle style, {required String idempotencyKey});

  /// Mirrors the device theme / language into `users/{me}` (direct
  /// whitelisted write + `updatedAtMs`). No-op when signed out.
  Future<void> saveSettings({ThemePreference? theme, String? language});
}

abstract interface class LeaderboardRepository {
  /// global = rankPoints desc; weekly = current weekId, weeklyPoints desc;
  /// friends = me + my friends by rankPoints.
  Stream<List<LeaderboardEntry>> watch(LeaderboardScope scope, {int limit = 50});
}

abstract interface class FriendsRepository {
  /// My friendships joined with the friends' profiles.
  Stream<List<Friend>> watchFriends();

  /// Pending requests I received ([FriendRequest.incoming]) and sent.
  Stream<List<FriendRequest>> watchRequests();

  /// `users/{me}/private/suggestions` joined with profiles.
  Stream<List<PlayerProfile>> watchSuggestions();

  /// Username prefix search on `profiles.usernameLower` (excludes me).
  Future<List<PlayerProfile>> search(String usernamePrefix, {int limit = 20});

  /// Callable `friendRequest` — give exactly one of [toUid] / [toUsername].
  /// Errors: USER_NOT_FOUND, SELF_FRIEND, ALREADY_FRIENDS, REQUEST_EXISTS.
  Future<FriendRequestOutcome> sendRequest({String? toUid, String? toUsername, required String idempotencyKey});

  /// Callable `respondFriend` on a request I received from [fromUid].
  /// Returns true when accepted. Errors: REQUEST_NOT_FOUND.
  Future<bool> respond(String fromUid, {required bool accept, required String idempotencyKey});

  /// Callable `removeFriend`. Errors: NOT_FRIENDS.
  Future<void> remove(String friendUid, {required String idempotencyKey});
}

/// What the order ticket shows and sends. Computed with the exact server
/// LMSR ([lmsrQuoteBuy] / [lmsrQuoteSell]) from the market's current state.
class TradeQuote {
  const TradeQuote({
    required this.buy,
    required this.outcome,
    required this.shares,
    required this.amountCents,
    required this.priceYesAfter,
  });

  /// Throws [LmsrException] (badShares / marketLimit).
  factory TradeQuote.compute(LmsrState state, Outcome outcome, int shares, {required bool buy}) {
    final q = buy ? lmsrQuoteBuy(state, outcome, shares) : lmsrQuoteSell(state, outcome, shares);
    return TradeQuote(buy: buy, outcome: outcome, shares: shares, amountCents: q.amountCents, priceYesAfter: q.priceYesAfter);
  }

  final bool buy;
  final Outcome outcome;
  final int shares;

  /// Cents the server will charge (buy, rounded up) or pay (sell, rounded
  /// down) at the quoted state. Send it as `maxCostCents` / `minProceedsCents`.
  final int amountCents;
  final double priceYesAfter;

  /// Positive = you pay, negative = you receive (sell).
  int get costCents => buy ? amountCents : -amountCents;

  /// Average price per share (0..1).
  double get avgPrice => shares == 0 ? 0 : amountCents / shares / 100;

  /// Price of the chosen outcome after the trade.
  double get priceAfter => outcome == Outcome.yes ? priceYesAfter : 1 - priceYesAfter;

  /// Paid if the outcome wins (buy only).
  int get maxPayoutCents => buy ? shares * 100 : 0;
}

abstract interface class MarketsRepository {
  /// Open markets, newest first.
  Stream<List<Market>> watchMarkets();

  /// Markets of one table (all statuses), newest first.
  Stream<List<Market>> watchMarketsForTable(String tableId);
  Stream<Market> watchMarket(String marketId);

  /// `markets/{id}/priceHistory` by time.
  Stream<List<PricePoint>> watchPriceHistory(String marketId);

  /// `users/{me}/positions`.
  Stream<List<MarketPosition>> watchPositions();

  /// `markets/{id}/trades` newest first.
  Stream<List<MarketTrade>> watchActivity(String marketId, {int limit = 30});

  /// LMSR quote at the market's latest known state. Throws
  /// [RepositoryException] (limitExceeded / MARKET_LIMIT, invalidArgument).
  Future<TradeQuote> quote(String marketId, Outcome outcome, int shares, {required bool buy});

  /// Callable `tradeShares` (shares 1..1000). Pass the quoted amount as
  /// [maxCostCents] (buy) / [minProceedsCents] (sell) to get SLIPPAGE
  /// instead of a worse price.
  Future<TradeResult> trade(
    String marketId,
    Outcome outcome,
    int shares, {
    required bool buy,
    int? maxCostCents,
    int? minProceedsCents,
    required String idempotencyKey,
  });
}

abstract interface class AdsRepository {
  List<ParodyAd> inventory(AdFormat format);

  /// `users/{me}/private/ads` (claims today, cooldown).
  Stream<AdState> watchAdState();

  /// Callable `claimAdReward` (+5 $, max 10/day, 30 s apart).
  /// Errors: AD_COOLDOWN, AD_DAILY_LIMIT.
  Future<AdRewardResult> claimReward(String adId, {required String idempotencyKey});
}
