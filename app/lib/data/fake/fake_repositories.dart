/// In-memory implementations of every repository interface. Used by the app
/// until the Firebase phase, and by all widget/golden tests afterwards.
///
/// They follow the server rules of `types.ts` (limits, error reasons,
/// idempotency per key) closely enough for screens to exercise every path,
/// and build their state from the backend-shaped docs of [FakeData].
library;

import 'dart:async';

import '../../domain/backend_constants.dart';
import '../../domain/card_style.dart';
import '../../domain/lmsr.dart';
import '../../domain/models.dart';
import '../../domain/wire.dart';
import '../live.dart';
import '../repositories.dart';
import '../server_errors.dart';
import 'fake_data.dart';

export '../live.dart' show Live;

/// The exception the real backend would produce for [reason].
RepositoryException serverError(ServerReason reason) => RepositoryException(failureForReason(reason), null, reason);

/// Replays the first result of each idempotency key (like the server).
class _Idempotency {
  final _results = <String, Object?>{};
  Future<T> run<T>(String key, FutureOr<T> Function() body) async {
    if (_results.containsKey(key)) return _results[key] as T;
    final r = await body();
    _results[key] = r;
    return r;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? signedIn, DateTime Function()? now})
      : _user = Live(signedIn),
        _now = now ?? DateTime.now;
  final Live<AppUser?> _user;
  final DateTime Function() _now;
  final _taken = {'thecountess', 'lunariver', 'admin'};

  static const demoUser = AppUser(
    uid: FakeData.demoUid,
    email: 'demo@vingt-un.test',
    username: FakeData.demoUsername,
    avatar: FakeData.demoAvatar,
    rankTier: RankTier.silver,
    kycStatus: KycStatus.verified,
  );

  @override
  AppUser? get currentUser => _user.value;

  @override
  Stream<AppUser?> authStateChanges() => _user.stream;

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    if (!email.contains('@')) throw const AuthException(AuthFailure.invalidEmail);
    if (password.length < 6) throw const AuthException(AuthFailure.invalidCredentials);
    final u = AppUser(
      uid: 'u-${email.hashCode.abs()}',
      email: email,
      username: email.split('@').first,
      kycStatus: KycStatus.verified,
    );
    _user.value = u;
    return u;
  }

  @override
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String username,
    String avatar = 'avatar01',
    String? language,
  }) async {
    if (!email.contains('@')) throw const AuthException(AuthFailure.invalidEmail);
    if (password.length < 8) throw const AuthException(AuthFailure.weakPassword);
    _checkUsername(username);
    final u = AppUser(uid: 'u-new', email: email, username: username, avatar: avatar);
    _user.value = u;
    return u;
  }

  void _checkUsername(String username) {
    if (!Backend.usernamePattern.hasMatch(username)) throw const AuthException(AuthFailure.invalidUsername);
    if (_taken.contains(username.toLowerCase())) throw const AuthException(AuthFailure.usernameTaken);
  }

  @override
  Future<AppUser> completeProfile({
    required String username,
    required String avatar,
    String? language,
    required String idempotencyKey,
  }) async {
    final u = _user.value;
    if (u == null) throw serverError(ServerReason.UNAUTHENTICATED);
    if (u.profileComplete && u.username.isNotEmpty) throw const AuthException(AuthFailure.profileExists);
    _checkUsername(username);
    final done = u.copyWith(username: username, avatar: avatar, profileComplete: true);
    _user.value = done;
    return done;
  }

  @override
  Stream<PlayerProfile?> watchProfile(String uid) {
    final known = FakeData.profile(uid, _now());
    if (known != null) return Stream.value(known);
    return _user.stream.map((u) => u == null || u.uid != uid || !u.profileComplete
        ? null
        : PlayerProfile(uid: u.uid, username: u.username, avatar: u.avatar, rankTier: u.rankTier, kycVerified: u.kycStatus == KycStatus.verified, lastSeenAt: _now()));
  }

  @override
  Future<void> signOut() async => _user.value = null;

  void setKyc(KycStatus s) {
    final u = _user.value;
    if (u != null) _user.value = u.copyWith(kycStatus: s);
  }
}

class FakeKycRepository implements KycRepository {
  FakeKycRepository(this._auth, {this.reviewDelay = const Duration(seconds: 2), DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final FakeAuthRepository _auth;
  final DateTime Function() _now;

  /// Fake review time (server: KYC_REVIEW_MS ≈ 3 s). Zero = instant.
  final Duration reviewDelay;
  late final _state = Live<KycState>(KycState(status: _auth.currentUser?.kycStatus ?? KycStatus.none));
  final _keys = _Idempotency();

  @override
  Stream<KycState> watchKyc() => _state.stream;

  void _set(KycState s) {
    _state.value = s;
    _auth.setKyc(s.status);
  }

  @override
  Future<KycState> submit(KycSubmission s, {required String idempotencyKey}) => _keys.run(idempotencyKey, () async {
        final cur = _state.value;
        if (cur.status == KycStatus.verified) throw serverError(ServerReason.KYC_ALREADY_VERIFIED);
        if (cur.status == KycStatus.rejected) throw serverError(ServerReason.KYC_REJECTED);
        if (cur.status == KycStatus.pending) return cur;
        final now = _now();
        if (s.birthDate.isAfter(now) || s.birthDate.year < 1900) throw serverError(ServerReason.INVALID_ARGUMENT);
        var age = now.year - s.birthDate.year;
        if (now.month < s.birthDate.month || (now.month == s.birthDate.month && now.day < s.birthDate.day)) age--;
        if (age < Backend.kycMinAgeYears) {
          final r = KycState(status: KycStatus.rejected, docType: s.documentType, submittedAt: now, rejection: KycRejection.underage);
          _set(r);
          return r;
        }
        _set(KycState(status: KycStatus.pending, docType: s.documentType, submittedAt: now, verifyAfter: now.add(reviewDelay)));
        if (reviewDelay > Duration.zero) await Future<void>.delayed(reviewDelay);
        final v = KycState(status: KycStatus.verified, docType: s.documentType, submittedAt: now, verifiedAt: _now());
        _set(v);
        return v;
      });

  @override
  Future<KycState> refresh({required String idempotencyKey}) async {
    final cur = _state.value;
    final after = cur.verifyAfter;
    if (cur.status == KycStatus.pending && (after == null || !_now().isBefore(after))) {
      _set(KycState(status: KycStatus.verified, docType: cur.docType, submittedAt: cur.submittedAt, verifiedAt: _now()));
    }
    return _state.value;
  }
}

class FakeWalletRepository implements WalletRepository {
  FakeWalletRepository(DateTime Function() now)
      : _now = now,
        _ledger = Live(FakeData.ledger(now())),
        _wallet = Live(WalletSnapshot.fromDoc(FakeData.walletDoc(now()), now: now()));

  final DateTime Function() _now;
  final Live<List<LedgerEntry>> _ledger;
  final Live<WalletSnapshot> _wallet;
  final _keys = _Idempotency();
  var _seq = 0;

  int get balanceCents => _wallet.value.balanceCents;

  @override
  Stream<WalletSnapshot> watchWallet() => _wallet.stream;

  @override
  Stream<List<LedgerEntry>> watchLedger({int limit = 50}) => _ledger.stream.map((l) => l.take(limit).toList());

  /// Applies a server-side money movement (used by the other fakes too).
  /// Throws INSUFFICIENT_FUNDS when the balance would go negative.
  WalletMoveResult move(int delta, LedgerKind kind, {String? tableId, int? handNumber, String? marketId, PowerType? power, PaymentMethod? method}) {
    final w = _wallet.value;
    final balance = w.balanceCents + delta;
    if (balance < 0) throw serverError(ServerReason.INSUFFICIENT_FUNDS);
    final today = kind == LedgerKind.deposit ? w.depositedTodayCents + delta : w.depositedTodayCents;
    _wallet.value = w.copyWith(
      balanceCents: balance,
      depositedTodayCents: today,
      totalDepositedCents: kind == LedgerKind.deposit ? w.totalDepositedCents + delta : null,
      totalWithdrawnCents: kind == LedgerKind.withdrawal ? w.totalWithdrawnCents - delta : null,
      updatedAt: _now(),
    );
    final entry = LedgerEntry(
      id: 'fake-${++_seq}',
      kind: kind,
      amountCents: delta,
      at: _now(),
      balanceAfterCents: balance,
      tableId: tableId,
      handNumber: handNumber,
      marketId: marketId,
      power: power,
      method: method,
    );
    _ledger.value = [entry.withDetail(FakeData.ledgerDetail(entry, _now())), ..._ledger.value];
    return WalletMoveResult(balanceCents: balance, ledgerEntryId: entry.id);
  }

  @override
  Future<WalletMoveResult> deposit({
    required int amountCents,
    required PaymentMethod method,
    required String idempotencyKey,
  }) =>
      _keys.run(idempotencyKey, () {
        if (amountCents <= 0) throw serverError(ServerReason.INVALID_ARGUMENT);
        final w = _wallet.value;
        if (amountCents < Backend.depositMinCents ||
            amountCents > Backend.depositMaxCents ||
            w.depositedTodayCents + amountCents > w.depositLimitCents) {
          throw serverError(ServerReason.DEPOSIT_LIMIT);
        }
        return move(amountCents, LedgerKind.deposit, method: method);
      });

  @override
  Future<WalletMoveResult> withdraw({
    required int amountCents,
    required PaymentMethod method,
    required String idempotencyKey,
  }) =>
      _keys.run(idempotencyKey, () {
        if (amountCents < Backend.withdrawMinCents || amountCents > Backend.withdrawMaxCents) {
          throw serverError(ServerReason.INVALID_ARGUMENT);
        }
        if (amountCents > _wallet.value.balanceCents) throw serverError(ServerReason.INSUFFICIENT_FUNDS);
        return move(-amountCents, LedgerKind.withdrawal, method: method);
      });
}

class FakeLobbyRepository implements LobbyRepository {
  FakeLobbyRepository([DateTime Function()? now]) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _keys = _Idempotency();
  final _privateCodes = <String, String>{'ABC123': 't-private-abc123'};

  @override
  Stream<List<StakeTier>> watchStakeTiers() => Stream.value(StakeTier.allFrom(FakeData.tables));

  @override
  Stream<List<LiveTable>> watchLiveTables({String? tierId}) => Stream.value(
        FakeData.tables.where((t) => tierId == null || t.tierId == tierId).toList(),
      );

  @override
  Stream<List<RecentWin>> watchRecentWins({int limit = 20}) => Stream.value(FakeData.recentWins(_now()).take(limit).toList());

  @override
  Future<MatchResult> joinMatchmaking({
    required MatchMode mode,
    String stakeTier = 'low',
    String? code,
    required String idempotencyKey,
  }) =>
      _keys.run(idempotencyKey, () {
        switch (mode) {
          case MatchMode.quick:
            if (!Backend.stakeTiers.contains(stakeTier)) throw serverError(ServerReason.INVALID_ARGUMENT);
            final candidates = FakeData.tables.where((t) => t.tierId == stakeTier && t.seatsForHumans > 0).toList()
              ..sort((a, b) => b.humans.compareTo(a.humans));
            if (candidates.isEmpty) return MatchResult(tableId: 't-new-$stakeTier', seated: true, seatIndex: 0);
            final t = candidates.first;
            final free = t.seatsTaken < t.seatsTotal;
            return MatchResult(tableId: t.id, seated: free, seatIndex: free ? t.seatsTaken : null);
          case MatchMode.createPrivate:
            final c = 'P${(_privateCodes.length * 7919 % 99999).toString().padLeft(5, '0')}';
            _privateCodes[c] = 't-private-${c.toLowerCase()}';
            return MatchResult(tableId: _privateCodes[c]!, seated: true, seatIndex: 0, code: c);
          case MatchMode.joinCode:
            final c = code?.toUpperCase();
            if (c == null || !Backend.tableCodePattern.hasMatch(c)) throw serverError(ServerReason.INVALID_ARGUMENT);
            final id = _privateCodes[c];
            if (id == null) throw serverError(ServerReason.BAD_CODE);
            return MatchResult(tableId: id, seated: true, seatIndex: 1, code: c);
        }
      });
}

class FakeTableRepository implements TableRepository {
  FakeTableRepository({this.myUid = FakeData.demoUid, this.doc});
  final Map<String, Object?>? doc;

  /// Every call made, e.g. `act:hit`, `bet:2500`, `poke`, `leave` (for tests).
  final calls = <String>[];

  @override
  final String? myUid;

  @override
  Stream<TableState> watchTable(String tableId) =>
      Stream.value(TableState.fromDoc(tableId, doc ?? FakeData.tableDoc(tableId)));

  @override
  Future<void> placeBet(String tableId, int handNumber, int amountCents, {required String idempotencyKey}) async =>
      calls.add('bet:$amountCents');

  @override
  Future<void> act(String tableId, int handNumber, PlayerAction action,
          {int? handIndex, int? amountCents, PowerType? power, required String idempotencyKey}) async =>
      calls.add('act:${action.name}${power == null ? '' : '+${power.name}'}');

  @override
  Future<bool> poke(String tableId) async {
    calls.add('poke');
    return false;
  }

  @override
  Future<int> leave(String tableId) async {
    calls.add('leave');
    return 0;
  }

  @override
  Stream<PeekResult?> watchPeek(String tableId) => Stream.value(null);

  @override
  Stream<List<HandHistory>> watchHistory(String tableId, {int limit = 20}) => Stream.value(const []);
}

class FakeShopRepository implements ShopRepository {
  /// When [wallet] is given, purchases are debited from it (ledger
  /// `powerPurchase`, INSUFFICIENT_FUNDS).
  FakeShopRepository({this.wallet, DateTime Function()? now})
      : _inventory = Live({
          for (final d in FakeData.inventoryDocs((now ?? DateTime.now)()))
            if (InventoryItem.fromDoc(d) case final i?) i.power: i.quantity,
        });
  final FakeWalletRepository? wallet;
  final Live<Map<PowerType, int>> _inventory;
  final _keys = _Idempotency();

  @override
  Stream<List<PowerOffer>> watchOffers() => _inventory.stream.map(
        (inv) => PowerOffer.fromInventory([for (final e in inv.entries) InventoryItem(power: e.key, quantity: e.value)]),
      );

  @override
  Future<BuyPowerResult> buy(PowerType type, {int quantity = 1, required String idempotencyKey}) =>
      _keys.run(idempotencyKey, () {
        if (quantity < 1 || quantity > Backend.powerMaxQuantityPerPurchase) throw serverError(ServerReason.INVALID_ARGUMENT);
        final owned = _inventory.value[type] ?? 0;
        if (owned + quantity > Backend.powerMaxInventory) throw serverError(ServerReason.INVENTORY_FULL);
        final balance = wallet?.move(-type.priceCents * quantity, LedgerKind.powerPurchase, power: type).balanceCents ?? 0;
        _inventory.value = {..._inventory.value, type: owned + quantity};
        return BuyPowerResult(quantity: owned + quantity, balanceCents: balance);
      });
}

class FakeCosmeticsRepository implements CosmeticsRepository {
  FakeCosmeticsRepository([DateTime Function()? now])
      : _now = now ?? DateTime.now,
        _settings = Live(UserSettings.fromDoc(FakeData.userSettingsDoc((now ?? DateTime.now)())));
  final DateTime Function() _now;
  final Live<UserSettings> _settings;

  @override
  Stream<CardStyle> watchEquipped() => _settings.stream.map((s) => s.style);

  @override
  Stream<UserSettings> watchSettings() => _settings.stream;

  @override
  Future<CardStyle> equip(CardStyle style, {required String idempotencyKey}) async {
    final s = _settings.value;
    // Round trip through the wire enums, exactly like the server would.
    final w = style.toWire();
    final normalized = CardStyle.fromWire(cardBack: w['cardBack'], cardFace: w['cardFace'], felt: w['felt']);
    _settings.value = UserSettings(theme: s.theme, language: s.language, style: normalized, updatedAt: _now());
    return normalized;
  }

  @override
  Future<void> saveSettings({ThemePreference? theme, String? language}) async {
    final s = _settings.value;
    _settings.value = UserSettings(
      theme: theme ?? s.theme,
      language: language == 'en' || language == 'fr' ? language! : s.language,
      style: s.style,
      updatedAt: _now(),
    );
  }
}

class FakeLeaderboardRepository implements LeaderboardRepository {
  FakeLeaderboardRepository({this.myUid = FakeData.demoUid, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final String myUid;
  final DateTime Function() _now;

  @override
  Stream<List<LeaderboardEntry>> watch(LeaderboardScope scope, {int limit = 50}) {
    var list = FakeData.profiles(_now());
    switch (scope) {
      case LeaderboardScope.global:
        list.sort((a, b) => b.rankPoints.compareTo(a.rankPoints));
      case LeaderboardScope.weekly:
        list = list.where((p) => p.weekId == FakeData.currentWeekId).toList()
          ..sort((a, b) => b.weeklyPoints.compareTo(a.weeklyPoints));
      case LeaderboardScope.friends:
        final ids = {...FakeData.friendUids, myUid};
        list = list.where((p) => ids.contains(p.uid)).toList()..sort((a, b) => b.rankPoints.compareTo(a.rankPoints));
    }
    return Stream.value([
      for (final (i, p) in list.take(limit).indexed)
        LeaderboardEntry.fromProfile(p, rank: i + 1, scope: scope, myUid: myUid, currentWeekId: FakeData.currentWeekId),
    ]);
  }
}

class FakeFriendsRepository implements FriendsRepository {
  FakeFriendsRepository({this.myUid = FakeData.demoUid, DateTime Function()? now}) : _now = now ?? DateTime.now {
    final n = _now();
    _friendships.value = [for (final d in FakeData.friendshipDocs(n)) Friendship.fromDoc(d)];
    _requests.value = [for (final d in FakeData.friendRequestDocs(n)) FriendRequest.fromDoc(d, myUid: myUid)];
  }
  final String myUid;
  final DateTime Function() _now;
  final _friendships = Live<List<Friendship>>(const []);
  final _requests = Live<List<FriendRequest>>(const []);
  final _keys = _Idempotency();

  Map<String, PlayerProfile> get _profiles => {for (final p in FakeData.profiles(_now())) p.uid: p};

  Set<String> get _friendUids => {for (final f in _friendships.value) ?f.otherUid(myUid)};

  @override
  Stream<List<Friend>> watchFriends() => _friendships.stream.map((list) {
        final profiles = _profiles;
        final now = _now();
        return [
          for (final f in list)
            if (profiles[f.otherUid(myUid)] case final p?)
              Friend.fromProfile(
                p,
                now: now,
                since: f.since,
                tableName: FakeData.tables.where((t) => t.id == p.currentTableId).firstOrNull?.name,
              ),
        ];
      });

  @override
  Stream<List<FriendRequest>> watchRequests() => _requests.stream;

  @override
  Stream<List<PlayerProfile>> watchSuggestions() {
    final profiles = _profiles;
    final ids = FriendSuggestions.fromDoc(FakeData.suggestionsDoc(_now())).uids;
    return Stream.value([for (final id in ids) ?profiles[id]]);
  }

  @override
  Future<List<PlayerProfile>> search(String usernamePrefix, {int limit = 20}) async {
    final q = usernamePrefix.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return FakeData.profiles(_now())
        .where((p) => p.uid != myUid && p.username.toLowerCase().startsWith(q))
        .take(limit)
        .toList();
  }

  @override
  Future<FriendRequestOutcome> sendRequest({String? toUid, String? toUsername, required String idempotencyKey}) =>
      _keys.run(idempotencyKey, () {
        if ((toUid == null) == (toUsername == null)) throw serverError(ServerReason.INVALID_ARGUMENT);
        final profiles = _profiles.values;
        final target = profiles
            .where((p) => toUid != null ? p.uid == toUid : p.username.toLowerCase() == toUsername!.toLowerCase())
            .firstOrNull;
        if (target == null) throw serverError(ServerReason.USER_NOT_FOUND);
        if (target.uid == myUid) throw serverError(ServerReason.SELF_FRIEND);
        if (_friendUids.contains(target.uid)) throw serverError(ServerReason.ALREADY_FRIENDS);
        final reqs = _requests.value;
        if (reqs.any((r) => !r.incoming && r.toUid == target.uid)) throw serverError(ServerReason.REQUEST_EXISTS);
        if (reqs.any((r) => r.incoming && r.fromUid == target.uid)) {
          _accept(target.uid, target.username);
          return FriendRequestOutcome(accepted: true, toUid: target.uid);
        }
        _requests.value = [
          FriendRequest(
            fromUid: myUid,
            toUid: target.uid,
            fromUsername: FakeData.demoUsername,
            toUsername: target.username,
            fromAvatar: FakeData.demoAvatar,
            createdAt: _now(),
            incoming: false,
          ),
          ...reqs,
        ];
        return FriendRequestOutcome(accepted: false, toUid: target.uid);
      });

  void _accept(String otherUid, String otherName) {
    _requests.value = _requests.value.where((r) => r.otherUid != otherUid).toList();
    _friendships.value = [
      Friendship(uids: [myUid, otherUid]..sort(), usernames: {myUid: FakeData.demoUsername, otherUid: otherName}, since: _now()),
      ..._friendships.value,
    ];
  }

  @override
  Future<bool> respond(String fromUid, {required bool accept, required String idempotencyKey}) =>
      _keys.run(idempotencyKey, () {
        final req = _requests.value.where((r) => r.incoming && r.fromUid == fromUid).firstOrNull;
        if (req == null) throw serverError(ServerReason.REQUEST_NOT_FOUND);
        if (accept) {
          _accept(fromUid, req.fromUsername);
        } else {
          _requests.value = _requests.value.where((r) => r != req).toList();
        }
        return accept;
      });

  @override
  Future<void> remove(String friendUid, {required String idempotencyKey}) => _keys.run(idempotencyKey, () {
        if (!_friendUids.contains(friendUid)) throw serverError(ServerReason.NOT_FRIENDS);
        _friendships.value = _friendships.value.where((f) => !f.uids.contains(friendUid)).toList();
      });
}

class FakeMarketsRepository implements MarketsRepository {
  /// When [wallet] is given, trades are debited/credited (ledger
  /// marketBuy/marketSell). [myTableId] = table I sit at (OWN_TABLE_MARKET).
  FakeMarketsRepository(this._now, {this.wallet, this.myTableId}) {
    final n = _now();
    _markets.value = {for (final m in FakeData.markets(n)) m.id: m};
    _positions.value = {for (final p in FakeData.positions(n)) p.marketId: p};
  }
  final DateTime Function() _now;
  final FakeWalletRepository? wallet;
  final String? myTableId;
  final _markets = Live<Map<String, Market>>(const {});
  final _positions = Live<Map<String, MarketPosition>>(const {});
  final _extraTrades = <String, List<MarketTrade>>{};
  final _extraPoints = <String, List<PricePoint>>{};
  final _keys = _Idempotency();
  final _tick = Live<int>(0);

  Market _find(String id) {
    final m = _markets.value[id];
    if (m == null) throw serverError(ServerReason.MARKET_NOT_FOUND);
    return m;
  }

  List<Market> _sorted(Iterable<Market> list) =>
      list.toList()..sort((a, b) => (b.createdAt ?? epochZero).compareTo(a.createdAt ?? epochZero));

  static final epochZero = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Stream<List<Market>> watchMarkets() => _markets.stream.map((m) => _sorted(m.values.where((x) => x.isOpen)));

  @override
  Stream<List<Market>> watchMarketsForTable(String tableId) =>
      _markets.stream.map((m) => _sorted(m.values.where((x) => x.tableId == tableId)));

  @override
  Stream<Market> watchMarket(String marketId) => _markets.stream.map((_) => _find(marketId));

  @override
  Stream<List<PricePoint>> watchPriceHistory(String marketId) => _tick.stream.map((_) {
        final m = _find(marketId);
        return [...FakeData.priceHistory(m, _now()), ...?_extraPoints[marketId]];
      });

  @override
  Stream<List<MarketPosition>> watchPositions() => _positions.stream.map((p) => p.values.toList());

  @override
  Stream<List<MarketTrade>> watchActivity(String marketId, {int limit = 30}) => _tick.stream.map((_) {
        final m = _find(marketId);
        return [...?_extraTrades[marketId]?.reversed, ...FakeData.activity(m, _now())].take(limit).toList();
      });

  @override
  Future<TradeQuote> quote(String marketId, Outcome outcome, int shares, {required bool buy}) async =>
      _quote(_find(marketId), outcome, shares, buy: buy);

  TradeQuote _quote(Market m, Outcome outcome, int shares, {required bool buy}) {
    if (shares < 1 || shares > Backend.marketMaxSharesPerTrade) throw serverError(ServerReason.INVALID_ARGUMENT);
    try {
      return TradeQuote.compute(LmsrState.ofMarket(m), outcome, shares, buy: buy);
    } on LmsrException catch (e) {
      throw serverError(e.code == LmsrErrorCode.marketLimit ? ServerReason.MARKET_LIMIT : ServerReason.INVALID_ARGUMENT);
    }
  }

  @override
  Future<TradeResult> trade(
    String marketId,
    Outcome outcome,
    int shares, {
    required bool buy,
    int? maxCostCents,
    int? minProceedsCents,
    required String idempotencyKey,
  }) =>
      _keys.run(idempotencyKey, () {
        final m = _find(marketId);
        if (!m.isOpen) throw serverError(ServerReason.MARKET_CLOSED);
        if (myTableId != null && m.tableId == myTableId) throw serverError(ServerReason.OWN_TABLE_MARKET);
        final pos = _positions.value[marketId] ??
            MarketPosition(marketId: marketId, tableId: m.tableId, kind: m.kind, question: m.question);
        if (!buy && pos.sharesOf(outcome) < shares) throw serverError(ServerReason.INSUFFICIENT_SHARES);
        final q = _quote(m, outcome, shares, buy: buy);
        if (buy && maxCostCents != null && q.amountCents > maxCostCents) throw serverError(ServerReason.SLIPPAGE);
        if (!buy && minProceedsCents != null && q.amountCents < minProceedsCents) throw serverError(ServerReason.SLIPPAGE);
        final balance = wallet
                ?.move(buy ? -q.amountCents : q.amountCents, buy ? LedgerKind.marketBuy : LedgerKind.marketSell, marketId: marketId)
                .balanceCents ??
            0;
        final d = buy ? shares : -shares;
        final yes = pos.yesShares + (outcome == Outcome.yes ? d : 0);
        final no = pos.noShares + (outcome == Outcome.no ? d : 0);
        _positions.value = {
          ..._positions.value,
          marketId: MarketPosition(
            marketId: marketId,
            tableId: pos.tableId,
            kind: pos.kind,
            question: pos.question,
            yesShares: yes,
            noShares: no,
            costCents: pos.costCents + (buy ? q.amountCents : 0),
            proceedsCents: pos.proceedsCents + (buy ? 0 : q.amountCents),
            updatedAt: _now(),
          ),
        };
        final dq = outcome == Outcome.yes ? (d.toDouble(), 0.0) : (0.0, d.toDouble());
        _markets.value = {
          ..._markets.value,
          marketId: Market(
            id: m.id,
            kind: m.kind,
            tableId: m.tableId,
            tableName: m.tableName,
            status: m.status,
            priceYes: q.priceYesAfter,
            handNumber: m.handNumber,
            shoeNumber: m.shoeNumber,
            subjectUid: m.subjectUid,
            subjectUsername: m.subjectUsername,
            subjectSeatIndex: m.subjectSeatIndex,
            question: m.question,
            b: m.b,
            qYes: m.qYes + dq.$1,
            qNo: m.qNo + dq.$2,
            volumeCents: m.volumeCents + q.amountCents,
            tradeCount: m.tradeCount + 1,
            createdAt: m.createdAt,
          ),
        };
        (_extraTrades[marketId] ??= []).add(MarketTrade(
          username: FakeData.demoUsername,
          uid: FakeData.demoUid,
          outcome: outcome,
          isBuy: buy,
          shares: shares,
          amountCents: q.amountCents,
          priceYesAfter: q.priceYesAfter,
          at: _now(),
        ));
        (_extraPoints[marketId] ??= []).add(PricePoint(_now(), q.priceYesAfter));
        _tick.value++;
        return TradeResult(amountCents: q.amountCents, priceYes: q.priceYesAfter, balanceCents: balance, yesShares: yes, noShares: no);
      });
}

class FakeAdsRepository implements AdsRepository {
  /// When [wallet] is given, rewards are credited to it (ledger `adReward`).
  FakeAdsRepository({this.wallet, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final FakeWalletRepository? wallet;
  final DateTime Function() _now;
  final _state = Live<AdState>(const AdState());
  final _keys = _Idempotency();

  static const rewardCents = Backend.adRewardCents;
  static const dailyCap = Backend.adRewardDailyMax;
  static const cooldown = Duration(milliseconds: Backend.adRewardCooldownMs);

  int get claimedToday => _state.value.day == utcDayId(_now()) ? _state.value.claimedToday : 0;

  @override
  List<ParodyAd> inventory(AdFormat format) => FakeData.ads;

  @override
  Stream<AdState> watchAdState() => _state.stream;

  @override
  Future<AdRewardResult> claimReward(String adId, {required String idempotencyKey}) => _keys.run(idempotencyKey, () {
        final now = _now();
        if (claimedToday >= dailyCap) throw serverError(ServerReason.AD_DAILY_LIMIT);
        if (_state.value.nextClaimAt(now) != null) throw serverError(ServerReason.AD_COOLDOWN);
        final claimed = claimedToday + 1;
        _state.value = AdState(day: utcDayId(now), claimedToday: claimed, lastClaimAt: now);
        final balance = wallet?.move(rewardCents, LedgerKind.adReward).balanceCents ?? 0;
        return AdRewardResult(rewardCents: rewardCents, balanceCents: balance, remainingToday: dailyCap - claimed);
      });
}
