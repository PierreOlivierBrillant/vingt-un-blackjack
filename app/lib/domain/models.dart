/// Client models mirroring the backend documents and callable responses of
/// `firebase/functions/src/shared/types.ts` (single source of truth).
///
/// Every DTO has a tolerant `fromDoc` (Firestore map) or `fromResponse`
/// (callable result) parser: missing / mistyped fields fall back to safe
/// values. Fakes, the Firebase layer and the tests all go through these
/// parsers. Enum names equal the wire values unless a `wire`/`fromWire`
/// mapping is given (e.g. `MarketStatus.voided` ⇔ `'void'`).
///
/// Money: integer cents. Time: [DateTime] built from epoch-ms integers.
/// The live table state lives in `table_state.dart` (mirror of `TableDoc`).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'backend_constants.dart';
import 'card_style.dart';
import 'game_table.dart' show GameStats;
import 'games.dart';
import 'table_state.dart' show ServerTablePhase;
import 'wire.dart';

// ---------------------------------------------------------------- avatars --

/// Hue (0..359) of a procedural avatar id `avatar01`..`avatar24`
/// (15° per avatar). Unknown ids get a stable hue from their text.
int avatarHueOf(String avatarId) {
  final n = int.tryParse(avatarId.replaceFirst('avatar', ''));
  if (n != null && n >= 1 && n <= 24) return ((n - 1) * 15) % 360;
  return avatarId.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xFFFF) % 360;
}

/// Online indicator rule of `ProfileDoc.lastSeenAtMs`.
bool isOnlineAt(DateTime? lastSeen, DateTime now) =>
    lastSeen != null && now.difference(lastSeen) < Backend.onlineWindow;

// ---------------------------------------------------------------- account --

enum KycStatus { none, pending, verified, rejected }

/// Wire values of `KycDocType` (passport | idCard | driverLicense).
enum IdDocumentType { idCard, passport, driverLicense }

enum RankTier { bronze, silver, gold, platinum, diamond }

/// `ProfileStats`.
@immutable
class PlayerStats {
  const PlayerStats({
    this.handsPlayed = 0,
    this.handsWon = 0,
    this.handsLost = 0,
    this.handsPushed = 0,
    this.blackjacks = 0,
    this.netCents = 0,
    this.biggestWinCents = 0,
  });

  factory PlayerStats.fromDoc(Map<String, Object?> d) => PlayerStats(
        handsPlayed: asInt(d['handsPlayed']),
        handsWon: asInt(d['handsWon']),
        handsLost: asInt(d['handsLost']),
        handsPushed: asInt(d['handsPushed']),
        blackjacks: asInt(d['blackjacks']),
        netCents: asInt(d['netCents']),
        biggestWinCents: asInt(d['biggestWinCents']),
      );

  final int handsPlayed;
  final int handsWon;
  final int handsLost;
  final int handsPushed;
  final int blackjacks;

  /// Sum of (return − stake) over all settled hands.
  final int netCents;
  final int biggestWinCents;

  /// handsWon / handsPlayed (0 when no hand played).
  double get winRate => handsPlayed == 0 ? 0 : handsWon / handsPlayed;
}

/// `profiles/{uid}` — public profile (humans and bots).
@immutable
class PlayerProfile {
  const PlayerProfile({
    required this.uid,
    required this.username,
    this.avatar = 'avatar01',
    this.isBot = false,
    this.rankPoints = 0,
    this.rankTier = RankTier.bronze,
    this.weeklyPoints = 0,
    this.weekId = '',
    this.stats = const PlayerStats(),
    this.currentTableId,
    this.lastSeenAt,
    this.kycVerified = false,
    this.createdAt,
    this.gameStats = const {},
    this.title,
  });

  factory PlayerProfile.fromDoc(Map<String, Object?> d, {String? id}) => PlayerProfile(
        uid: asString(d['uid']) ?? id ?? '',
        username: asString(d['username']) ?? '?',
        avatar: asString(d['avatar']) ?? 'avatar01',
        isBot: asBool(d['isBot']),
        rankPoints: asInt(d['rankPoints']),
        rankTier: enumByName(RankTier.values, d['rankTier']) ?? rankTierForPoints(asInt(d['rankPoints'])),
        weeklyPoints: asInt(d['weeklyPoints']),
        weekId: asString(d['weekId']) ?? '',
        stats: PlayerStats.fromDoc(asMap(d['stats'])),
        currentTableId: asString(d['currentTableId']),
        lastSeenAt: asTime(d['lastSeenAtMs']),
        kycVerified: asBool(d['kycVerified']),
        createdAt: asTime(d['createdAtMs']),
        gameStats: {
          for (final e in asMap(d['gameStats']).entries)
            if (GameId.fromWire(e.key) case final g? when g.isKernel && e.value is Map) g: GameStats.fromDoc(asMap(e.value)),
        },
        title: asString(d['title']),
      );

  final String uid;
  final String username;

  /// `avatar01`..`avatar24`.
  final String avatar;
  final bool isBot;
  final int rankPoints;
  final RankTier rankTier;

  /// Points of [weekId]; only meaningful when [weekId] is the current week.
  final int weeklyPoints;

  /// ISO week, e.g. "2026-W47".
  final String weekId;
  final PlayerStats stats;

  /// Table the player is seated or queued at.
  final String? currentTableId;
  final DateTime? lastSeenAt;
  final bool kycVerified;
  final DateTime? createdAt;

  /// Sprint 2: `gameStats` of the kernel-driven games (blackjack keeps [stats]).
  final Map<GameId, GameStats> gameStats;

  /// Equipped public title (`TITLE_IDS`, e.g. `rv_camille_title`), null = none.
  final String? title;

  /// Statistics of [game] in one shape (blackjack adapted from [stats]).
  GameStats statsFor(GameId game) => game == GameId.blackjack
      ? GameStats(
          rounds: stats.handsPlayed,
          won: stats.handsWon,
          lost: stats.handsLost,
          netCents: stats.netCents,
          biggestWinCents: stats.biggestWinCents,
          counters: {'blackjacks': stats.blackjacks, 'pushes': stats.handsPushed},
        )
      : gameStats[game] ?? const GameStats();

  int get avatarHue => avatarHueOf(avatar);

  /// now − lastSeen < 120 s.
  bool onlineAt(DateTime now) => isOnlineAt(lastSeenAt, now);
}

/// The signed-in account as the app shell needs it (Firebase Auth user +
/// `profiles/{uid}` + `users/{uid}/private/kyc`).
@immutable
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.username,
    this.avatar = 'avatar01',
    this.rankTier = RankTier.bronze,
    this.kycStatus = KycStatus.none,
    this.profileComplete = true,
  });

  /// [profile] null = Auth account exists but `completeProfile` was not
  /// called yet ([profileComplete] false).
  factory AppUser.fromProfile({
    required String uid,
    required String email,
    PlayerProfile? profile,
    KycStatus kycStatus = KycStatus.none,
  }) =>
      AppUser(
        uid: uid,
        email: email,
        username: profile?.username ?? '',
        avatar: profile?.avatar ?? 'avatar01',
        rankTier: profile?.rankTier ?? RankTier.bronze,
        kycStatus: profile != null && profile.kycVerified ? KycStatus.verified : kycStatus,
        profileComplete: profile != null,
      );

  final String uid;
  final String email;
  final String username;

  /// `avatar01`..`avatar24` (procedural; no uploaded images).
  final String avatar;
  final RankTier rankTier;
  final KycStatus kycStatus;

  /// False until `completeProfile` succeeded (route to the profile setup).
  final bool profileComplete;

  int get avatarHue => avatarHueOf(avatar);

  AppUser copyWith({
    KycStatus? kycStatus,
    String? username,
    String? avatar,
    RankTier? rankTier,
    bool? profileComplete,
  }) =>
      AppUser(
        uid: uid,
        email: email,
        username: username ?? this.username,
        avatar: avatar ?? this.avatar,
        rankTier: rankTier ?? this.rankTier,
        kycStatus: kycStatus ?? this.kycStatus,
        profileComplete: profileComplete ?? this.profileComplete,
      );
}

/// What the KYC form submits. ONLY [documentType] and [birthDate] travel
/// (`submitKyc{docType, birthDate}`); no name or document number exists in
/// the contract and the server stores neither.
@immutable
class KycSubmission {
  const KycSubmission({required this.documentType, required this.birthDate});

  final IdDocumentType documentType;
  final DateTime birthDate;

  /// Callable payload (without requestId).
  Map<String, Object?> toRequest() => {'docType': documentType.name, 'birthDate': calendarDateId(birthDate)};
}

enum KycRejection { underage }

/// `users/{uid}/private/kyc` (or a `SubmitKycResponse`).
@immutable
class KycState {
  const KycState({
    this.status = KycStatus.none,
    this.docType,
    this.submittedAt,
    this.verifyAfter,
    this.verifiedAt,
    this.rejection,
  });

  factory KycState.fromDoc(Map<String, Object?> d) => KycState(
        status: enumByName(KycStatus.values, d['status']) ?? KycStatus.none,
        docType: enumByName(IdDocumentType.values, d['docType']),
        submittedAt: asTime(d['submittedAtMs']),
        verifyAfter: asTime(d['verifyAfterMs']),
        verifiedAt: asTime(d['verifiedAtMs']),
        rejection: enumByName(KycRejection.values, d['rejectionReason']),
      );

  /// `SubmitKycResponse {status, verifyAfterMs, rejectionReason}`.
  factory KycState.fromResponse(Map<String, Object?> r) => KycState.fromDoc(r);

  final KycStatus status;
  final IdDocumentType? docType;
  final DateTime? submittedAt;

  /// While pending: after this instant, `submitKyc{refresh:true}` (or a
  /// deposit/withdraw) flips the status to verified.
  final DateTime? verifyAfter;
  final DateTime? verifiedAt;

  /// Set when rejected (final).
  final KycRejection? rejection;

  bool get isVerified => status == KycStatus.verified;
}

/// Auth failures (Firebase Auth + `completeProfile`), localized by
/// `localizeError`.
enum AuthFailure {
  invalidCredentials,
  invalidEmail,
  emailInUse,
  weakPassword,
  usernameTaken,
  invalidUsername,
  profileExists,
  tooManyRequests,
  network,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.failure, [this.message]);
  final AuthFailure failure;
  final String? message;
  @override
  String toString() => 'AuthException($failure${message == null ? '' : ': $message'})';
}

/// `users/{uid}` theme setting.
enum ThemePreference { dark, light, system }

/// `users/{uid}` — the only client-writable document (whitelisted fields).
@immutable
class UserSettings {
  const UserSettings({
    this.theme = ThemePreference.dark,
    this.language = 'fr',
    this.style = CardStyle.serverDefault,
    this.updatedAt,
  });

  factory UserSettings.fromDoc(Map<String, Object?> d) => UserSettings(
        theme: enumByName(ThemePreference.values, d['theme']) ?? ThemePreference.dark,
        language: d['language'] == 'en' ? 'en' : 'fr',
        style: CardStyle.fromWire(cardBack: d['cardBack'], cardFace: d['cardFace'], felt: d['felt']),
        updatedAt: asTime(d['updatedAtMs']),
      );

  final ThemePreference theme;

  /// `fr` | `en`.
  final String language;

  /// cardBack + cardFace + felt (always one of the 6 server backs).
  final CardStyle style;
  final DateTime? updatedAt;

  /// Whitelisted write of `users/{uid}`.
  Map<String, Object?> toDoc(DateTime now) => {
        'theme': theme.name,
        'language': language,
        ...style.toWire(),
        'updatedAtMs': now.millisecondsSinceEpoch,
      };
}

/// `CompleteProfileResponse`.
@immutable
class CompleteProfileResult {
  const CompleteProfileResult({required this.uid, required this.username, required this.balanceCents});
  factory CompleteProfileResult.fromResponse(Map<String, Object?> r) => CompleteProfileResult(
        uid: asString(r['uid']) ?? '',
        username: asString(r['username']) ?? '',
        balanceCents: asInt(r['balanceCents']),
      );
  final String uid;
  final String username;
  final int balanceCents;
}

// ----------------------------------------------------------------- wallet --

/// Wire values of `PaymentMethod`.
enum PaymentMethod { card, crypto, bankTransfer }

/// Exactly the backend `LEDGER_TYPES`.
enum LedgerKind {
  welcomeBonus,
  deposit,
  withdrawal,
  bet,
  double,
  split,
  insurance,
  payout,
  refund,
  powerPurchase,
  marketBuy,
  marketSell,
  marketPayout,
  adReward,
  // Sprint 2
  buyIn,
  cashOut,
  gift,
  reservation,
}

/// `users/{uid}/ledger/{entryId}` (append-only).
@immutable
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.at,
    required this.balanceAfterCents,
    this.tableId,
    this.handNumber,
    this.marketId,
    this.power,
    this.method,
    this.detail,
  });

  /// Null for an unknown ledger type (forward compatible: skip it).
  static LedgerEntry? fromDoc(Map<String, Object?> d, {String? id}) {
    final kind = enumByName(LedgerKind.values, d['type']);
    if (kind == null) return null;
    return LedgerEntry(
      id: asString(d['entryId']) ?? id ?? '',
      kind: kind,
      amountCents: asInt(d['amountCents']),
      balanceAfterCents: asInt(d['balanceAfterCents']),
      at: asTimeOr0(d['createdAtMs']),
      tableId: asString(d['tableId']),
      handNumber: asIntOrNull(d['handNumber']),
      marketId: asString(d['marketId']),
      power: enumByName(PowerType.values, d['powerId']),
      method: enumByName(PaymentMethod.values, d['method']),
    );
  }

  final String id;
  final LedgerKind kind;

  /// Signed: debit < 0, credit > 0.
  final int amountCents;
  final DateTime at;
  final int balanceAfterCents;
  final String? tableId;
  final int? handNumber;
  final String? marketId;
  final PowerType? power;
  final PaymentMethod? method;

  /// Optional client-side label (e.g. table name joined by the repository).
  final String? detail;

  LedgerEntry withDetail(String? detail) => LedgerEntry(
        id: id,
        kind: kind,
        amountCents: amountCents,
        at: at,
        balanceAfterCents: balanceAfterCents,
        tableId: tableId,
        handNumber: handNumber,
        marketId: marketId,
        power: power,
        method: method,
        detail: detail,
      );
}

/// `users/{uid}/private/wallet`.
@immutable
class WalletSnapshot {
  const WalletSnapshot({
    required this.balanceCents,
    this.lockedCents = 0,
    this.depositLimitCents = Backend.depositDailyCapCents,
    this.depositedTodayCents = 0,
    this.totalDepositedCents = 0,
    this.totalWithdrawnCents = 0,
    this.updatedAt,
  });

  /// [now] decides whether `dailyDeposit` is today's (UTC day).
  factory WalletSnapshot.fromDoc(Map<String, Object?> d, {required DateTime now}) {
    final daily = asMap(d['dailyDeposit']);
    return WalletSnapshot(
      balanceCents: asInt(d['balanceCents']),
      totalDepositedCents: asInt(d['totalDepositedCents']),
      totalWithdrawnCents: asInt(d['totalWithdrawnCents']),
      depositedTodayCents: daily['day'] == utcDayId(now) ? asInt(daily['amountCents']) : 0,
      updatedAt: asTime(d['updatedAtMs']),
    );
  }

  final int balanceCents;

  /// Client-side estimate of money on the felt / in open positions (not part
  /// of WalletDoc; 0 unless a repository computes it).
  final int lockedCents;

  /// DEPOSIT_DAILY_CAP_CENTS.
  final int depositLimitCents;
  final int depositedTodayCents;
  final int totalDepositedCents;
  final int totalWithdrawnCents;
  final DateTime? updatedAt;

  int get depositRemainingTodayCents => (depositLimitCents - depositedTodayCents).clamp(0, depositLimitCents);

  WalletSnapshot copyWith({int? balanceCents, int? depositedTodayCents, int? totalDepositedCents, int? totalWithdrawnCents, DateTime? updatedAt}) =>
      WalletSnapshot(
        balanceCents: balanceCents ?? this.balanceCents,
        lockedCents: lockedCents,
        depositLimitCents: depositLimitCents,
        depositedTodayCents: depositedTodayCents ?? this.depositedTodayCents,
        totalDepositedCents: totalDepositedCents ?? this.totalDepositedCents,
        totalWithdrawnCents: totalWithdrawnCents ?? this.totalWithdrawnCents,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// `DepositResponse` / `WithdrawResponse`.
@immutable
class WalletMoveResult {
  const WalletMoveResult({required this.balanceCents, required this.ledgerEntryId});
  factory WalletMoveResult.fromResponse(Map<String, Object?> r) =>
      WalletMoveResult(balanceCents: asInt(r['balanceCents']), ledgerEntryId: asString(r['ledgerEntryId']) ?? '');
  final int balanceCents;
  final String ledgerEntryId;
}

// ------------------------------------------------------------------ lobby --

/// A stake level (`low` | `mid` | `high`) with its live counters.
@immutable
class StakeTier {
  const StakeTier({
    required this.id,
    required this.minBetCents,
    required this.maxBetCents,
    required this.tablesLive,
    required this.playersOnline,
    required this.accent,
  });

  /// Tier [id] with STAKE_TIER_LIMITS and counters aggregated from [tables].
  factory StakeTier.of(String id, {List<LiveTable> tables = const []}) {
    final (min, max) = Backend.stakeTierLimits[id] ?? (100, 10000);
    final mine = tables.where((t) => t.tierId == id);
    return StakeTier(
      id: id,
      minBetCents: min,
      maxBetCents: max,
      tablesLive: mine.length,
      playersOnline: mine.fold(0, (a, t) => a + t.humans),
      accent: tierAccents[id] ?? const Color(0xFF00E701),
    );
  }

  /// The 3 backend tiers, counters derived from the public table list.
  static List<StakeTier> allFrom(List<LiveTable> tables) => [for (final id in Backend.stakeTiers) StakeTier.of(id, tables: tables)];

  static const tierAccents = <String, Color>{
    'low': Color(0xFF00E701),
    'mid': Color(0xFF1475E1),
    'high': Color(0xFFB57BFF),
  };

  /// `low` | `mid` | `high` — localized in the UI.
  final String id;
  final int minBetCents;
  final int maxBetCents;
  final int tablesLive;

  /// Humans seated at the tier's public tables.
  final int playersOnline;
  final Color accent;
}

/// One row of the lobby: `tables/{id}` (public, open) reduced to what the
/// list needs.
@immutable
class LiveTable {
  const LiveTable({
    required this.id,
    required this.name,
    required this.tierId,
    required this.minBetCents,
    required this.maxBetCents,
    required this.handNumber,
    this.phase = ServerTablePhase.idle,
    this.humans = 0,
    this.bots = 0,
    this.queueLength = 0,
    this.isPrivate = false,
    this.closed = false,
    this.seatsTotal = Backend.seatsPerTable,
    this.hasMarket = false,
    this.rankTier = RankTier.bronze,
    this.updatedAt,
    this.game = GameId.blackjack,
  });

  /// `tables/{id}` (blackjack) or `gameTables/{id}` (Sprint 2 games: limits
  /// nested in `limits`, `round` instead of `handNumber`, markets as
  /// `{round, series}`, kernel phase `live` shown as [ServerTablePhase.playerTurns]).
  factory LiveTable.fromDoc(Map<String, Object?> d, {String? id}) {
    final tableId = asString(d['tableId']) ?? id ?? '';
    final game = GameId.fromWire(d['game']) ?? gameOfTableId(tableId);
    final markets = asMap(d['markets']);
    final limits = asMap(d['limits']);
    final hasMarket = markets['dealerBust'] is String ||
        markets['natural'] is String ||
        markets['shoe'] is String ||
        asMap(markets['players']).isNotEmpty ||
        asMap(markets['round']).isNotEmpty ||
        asMap(markets['series']).isNotEmpty;
    final seats = asList(d['seats']);
    final seatedBots = seats.where((s) => s is Map && s['isBot'] == true).length;
    final seatedHumans = seats.where((s) => s is Map && s['isBot'] != true).length;
    return LiveTable(
      game: game,
      id: tableId,
      name: asString(d['name']) ?? id ?? '',
      tierId: asString(d['stakeTier']) ?? 'low',
      minBetCents: asInt(d['minBetCents'], asInt(limits['minBetCents'], 100)),
      maxBetCents: asInt(d['maxBetCents'], asInt(limits['maxBetCents'], 10000)),
      handNumber: asInt(d['handNumber'], asInt(d['round'])),
      seatsTotal: game.isKernel ? (seats.length > game.seats ? seats.length : game.seats) : Backend.seatsPerTable,
      phase: enumByName(ServerTablePhase.values, d['phase']) ??
          (d['phase'] == 'live' ? ServerTablePhase.playerTurns : ServerTablePhase.idle),
      humans: d['humanCount'] is num ? asInt(d['humanCount']) : seatedHumans,
      bots: d['botCount'] is num ? asInt(d['botCount']) : seatedBots,
      queueLength: asList(d['queue']).length,
      isPrivate: asBool(d['isPrivate']),
      closed: d['status'] == 'closed',
      hasMarket: hasMarket,
      rankTier: enumByName(RankTier.values, d['rankTier']) ?? RankTier.bronze,
      updatedAt: asTime(d['updatedAtMs']),
    );
  }

  final String id;
  final String name;

  /// `low` | `mid` | `high`.
  final String tierId;
  final int minBetCents;
  final int maxBetCents;
  final int handNumber;
  final ServerTablePhase phase;
  final int humans;
  final int bots;
  final int queueLength;
  final bool isPrivate;
  final bool closed;
  final int seatsTotal;
  final bool hasMarket;
  final RankTier rankTier;
  final DateTime? updatedAt;

  /// Game of the table (from `game`, else the id prefix).
  final GameId game;

  int get seatsTaken => humans + bots;

  /// Seats a human can get now (bots yield their seat at the next round).
  int get seatsForHumans => seatsTotal - humans;
}

/// `FeedEntryDoc.kind` (`jackpot`: game-specific big hit, Sprint 2).
enum WinKind { blackjack, bigWin, market, jackpot }

/// `feed/{entryId}` — "recent wins" ticker.
@immutable
class RecentWin {
  const RecentWin({
    required this.id,
    required this.username,
    required this.amountCents,
    required this.kind,
    this.avatar = 'avatar01',
    this.isBot = false,
    this.tableId,
    this.at,
    this.game = GameId.blackjack,
  });

  /// Null for an unknown kind.
  static RecentWin? fromDoc(Map<String, Object?> d, {String id = ''}) {
    final kind = enumByName(WinKind.values, d['kind']);
    if (kind == null) return null;
    return RecentWin(
      game: GameId.fromWire(d['game']) ?? GameId.blackjack,
      id: id,
      username: asString(d['username']) ?? '?',
      avatar: asString(d['avatar']) ?? 'avatar01',
      isBot: asBool(d['isBot']),
      kind: kind,
      amountCents: asInt(d['amountCents']),
      tableId: asString(d['tableId']),
      at: asTime(d['createdAtMs']),
    );
  }

  final String id;
  final String username;
  final String avatar;
  final bool isBot;
  final WinKind kind;
  final int amountCents;
  final String? tableId;
  final DateTime? at;

  /// Game where it happened (Sprint 2; older entries are blackjack).
  final GameId game;
}

// ------------------------------------------------------------------ table --

// The live table state is in `table_state.dart` (mirror of `TableDoc`).

/// Wire values of `PLAYER_ACTIONS`.
enum PlayerAction { hit, stand, double, split, surrender, insurance, peek }

// ----------------------------------------------------------------- powers --

/// Wire values of `POWER_IDS`.
enum PowerType {
  freeSplit,
  freeDouble,
  freeInsurance,
  peek,
  secondChance,
  // Sprint 2 (POWER_GAME): roulette, baccarat, craps
  zeroShield,
  freeCommission,
  safetyNet;

  /// POWER_PRICES_CENTS.
  int get priceCents => Backend.powerPricesCents[this]!;

  /// `POWER_GAME`: the game whose tables accept this power.
  GameId get game => switch (this) {
        PowerType.freeSplit ||
        PowerType.freeDouble ||
        PowerType.freeInsurance ||
        PowerType.peek ||
        PowerType.secondChance =>
          GameId.blackjack,
        PowerType.zeroShield => GameId.roulette,
        PowerType.freeCommission => GameId.baccarat,
        PowerType.safetyNet => GameId.craps,
      };
}

/// `users/{uid}/inventory/{powerId}`.
@immutable
class InventoryItem {
  const InventoryItem({required this.power, required this.quantity, this.updatedAt});

  /// Null for an unknown power id.
  static InventoryItem? fromDoc(Map<String, Object?> d, {String? id}) {
    final p = enumByName(PowerType.values, d['powerId'] ?? id);
    if (p == null) return null;
    return InventoryItem(power: p, quantity: asInt(d['quantity']), updatedAt: asTime(d['updatedAtMs']));
  }

  final PowerType power;
  final int quantity;
  final DateTime? updatedAt;
}

/// A shop line: price from POWER_PRICES_CENTS, [owned] from the inventory.
@immutable
class PowerOffer {
  const PowerOffer({required this.type, required this.priceCents, required this.owned});

  /// One offer per power, in POWER_IDS order.
  static List<PowerOffer> fromInventory(Iterable<InventoryItem> inventory) {
    final owned = {for (final i in inventory) i.power: i.quantity};
    return [for (final t in PowerType.values) PowerOffer(type: t, priceCents: t.priceCents, owned: owned[t] ?? 0)];
  }

  final PowerType type;
  final int priceCents;
  final int owned;

  /// Max quantity buyable in one purchase given the inventory cap.
  int get maxBuyable => (Backend.powerMaxInventory - owned).clamp(0, Backend.powerMaxQuantityPerPurchase);
}

/// `BuyPowerResponse` — [quantity] is the new owned quantity.
@immutable
class BuyPowerResult {
  const BuyPowerResult({required this.quantity, required this.balanceCents});
  factory BuyPowerResult.fromResponse(Map<String, Object?> r) =>
      BuyPowerResult(quantity: asInt(r['quantity']), balanceCents: asInt(r['balanceCents']));
  final int quantity;
  final int balanceCents;
}

// ------------------------------------------------------------ leaderboard --

enum LeaderboardScope { global, friends, weekly }

@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.uid,
    required this.username,
    required this.points,
    required this.tier,
    required this.handsPlayed,
    required this.winRate,
    this.rankPoints = 0,
    this.weeklyPoints = 0,
    this.avatar = 'avatar01',
    this.isBot = false,
    this.isMe = false,
  });

  /// [points] = weeklyPoints for [LeaderboardScope.weekly] (0 when the
  /// profile's weekId is not [currentWeekId]), else rankPoints.
  factory LeaderboardEntry.fromProfile(
    PlayerProfile p, {
    required int rank,
    required LeaderboardScope scope,
    String? myUid,
    String? currentWeekId,
  }) {
    final weekly = currentWeekId == null || p.weekId == currentWeekId ? p.weeklyPoints : 0;
    return LeaderboardEntry(
      rank: rank,
      uid: p.uid,
      username: p.username,
      avatar: p.avatar,
      isBot: p.isBot,
      tier: p.rankTier,
      rankPoints: p.rankPoints,
      weeklyPoints: weekly,
      points: scope == LeaderboardScope.weekly ? weekly : p.rankPoints,
      handsPlayed: p.stats.handsPlayed,
      winRate: p.stats.winRate,
      isMe: p.uid == myUid,
    );
  }

  final int rank;
  final String uid;
  final String username;
  final String avatar;
  final bool isBot;

  /// Score of the scope (rankPoints or weeklyPoints).
  final int points;
  final int rankPoints;
  final int weeklyPoints;
  final RankTier tier;
  final int handsPlayed;

  /// 0..1.
  final double winRate;
  final bool isMe;

  int get avatarHue => avatarHueOf(avatar);
}

// ---------------------------------------------------------------- friends --

@immutable
class Friend {
  const Friend({
    required this.uid,
    required this.username,
    required this.online,
    required this.tier,
    this.avatar = 'avatar01',
    this.isBot = false,
    this.rankPoints = 0,
    this.lastSeen,
    this.tableId,
    this.tableName,
    this.since,
  });

  /// [now] evaluates the 120 s online rule; [tableName] is joined from the
  /// table doc when [PlayerProfile.currentTableId] is set.
  factory Friend.fromProfile(PlayerProfile p, {required DateTime now, String? tableName, DateTime? since}) => Friend(
        uid: p.uid,
        username: p.username,
        avatar: p.avatar,
        isBot: p.isBot,
        tier: p.rankTier,
        rankPoints: p.rankPoints,
        online: p.onlineAt(now),
        lastSeen: p.lastSeenAt,
        tableId: p.currentTableId,
        tableName: p.currentTableId == null ? null : tableName,
        since: since,
      );

  final String uid;
  final String username;
  final String avatar;
  final bool isBot;
  final bool online;
  final RankTier tier;
  final int rankPoints;
  final DateTime? lastSeen;

  /// Table the friend sits/queues at ("watch his table").
  final String? tableId;
  final String? tableName;

  /// Friendship start.
  final DateTime? since;

  int get avatarHue => avatarHueOf(avatar);
}

/// `friendRequests/{fromUid}_{toUid}` (pending).
@immutable
class FriendRequest {
  const FriendRequest({
    required this.fromUid,
    required this.toUid,
    required this.fromUsername,
    required this.toUsername,
    required this.incoming,
    this.fromAvatar = 'avatar01',
    this.createdAt,
  });

  factory FriendRequest.fromDoc(Map<String, Object?> d, {required String myUid}) {
    final to = asString(d['toUid']) ?? '';
    return FriendRequest(
      fromUid: asString(d['fromUid']) ?? '',
      toUid: to,
      fromUsername: asString(d['fromUsername']) ?? '?',
      toUsername: asString(d['toUsername']) ?? '?',
      fromAvatar: asString(d['fromAvatar']) ?? 'avatar01',
      createdAt: asTime(d['createdAtMs']),
      incoming: to == myUid,
    );
  }

  static String idFor(String fromUid, String toUid) => '${fromUid}_$toUid';

  /// Document id `{fromUid}_{toUid}`.
  String get id => idFor(fromUid, toUid);
  final String fromUid;
  final String toUid;
  final String fromUsername;
  final String toUsername;
  final String fromAvatar;
  final DateTime? createdAt;

  /// true = received by me (answer with `respondFriend{fromUid}`).
  final bool incoming;

  String get otherUid => incoming ? fromUid : toUid;
  String get otherUsername => incoming ? fromUsername : toUsername;
  int get avatarHue => avatarHueOf(fromAvatar);
}

/// `friendships/{uidA}_{uidB}` (uids sorted ascending).
@immutable
class Friendship {
  const Friendship({required this.uids, required this.usernames, this.since});
  factory Friendship.fromDoc(Map<String, Object?> d) => Friendship(
        uids: asStringList(d['uids']),
        usernames: {for (final e in asMap(d['usernames']).entries) if (e.value is String) e.key: e.value! as String},
        since: asTime(d['sinceMs']),
      );

  static String idFor(String a, String b) => a.compareTo(b) <= 0 ? '${a}_$b' : '${b}_$a';

  final List<String> uids;
  final Map<String, String> usernames;
  final DateTime? since;

  String? otherUid(String myUid) {
    for (final u in uids) {
      if (u != myUid) return u;
    }
    return null;
  }
}

/// `users/{uid}/private/suggestions`.
@immutable
class FriendSuggestions {
  const FriendSuggestions({this.uids = const [], this.updatedAt});
  factory FriendSuggestions.fromDoc(Map<String, Object?> d) =>
      FriendSuggestions(uids: asStringList(d['uids']), updatedAt: asTime(d['updatedAtMs']));
  final List<String> uids;
  final DateTime? updatedAt;
}

/// `FriendRequestResponse`.
@immutable
class FriendRequestOutcome {
  const FriendRequestOutcome({required this.accepted, required this.toUid});
  factory FriendRequestOutcome.fromResponse(Map<String, Object?> r) =>
      FriendRequestOutcome(accepted: r['status'] == 'accepted', toUid: asString(r['toUid']) ?? '');

  /// true = became friends immediately (the other had already asked).
  final bool accepted;
  final String toUid;
}

// ---------------------------------------------------------------- markets --

/// Wire values of `MARKET_KINDS` (blackjack, then the Sprint 2 games).
enum MarketKind {
  dealerBust,
  playerWins,
  natural,
  shoeDealerBustRate,
  // roulette
  rouletteRed,
  rouletteZero,
  rouletteDozen3,
  rouletteZeroSeries,
  // baccarat
  baccaratBanker,
  baccaratTie,
  baccaratPair,
  baccaratBankerShoe,
  // hold'em
  holdemBoardAce,
  holdemBoardFlush,
  // craps
  crapsSeven,
  crapsPoint;

  /// `SERIES_MARKET_KINDS`: long markets, not tied to one round.
  bool get isSeries => switch (this) {
        MarketKind.shoeDealerBustRate ||
        MarketKind.rouletteZeroSeries ||
        MarketKind.baccaratBankerShoe ||
        MarketKind.crapsPoint =>
          true,
        _ => false,
      };

  /// Game of the market.
  GameId get game => switch (this) {
        MarketKind.dealerBust ||
        MarketKind.playerWins ||
        MarketKind.natural ||
        MarketKind.shoeDealerBustRate =>
          GameId.blackjack,
        MarketKind.rouletteRed ||
        MarketKind.rouletteZero ||
        MarketKind.rouletteDozen3 ||
        MarketKind.rouletteZeroSeries =>
          GameId.roulette,
        MarketKind.baccaratBanker ||
        MarketKind.baccaratTie ||
        MarketKind.baccaratPair ||
        MarketKind.baccaratBankerShoe =>
          GameId.baccarat,
        MarketKind.holdemBoardAce || MarketKind.holdemBoardFlush => GameId.holdem,
        MarketKind.crapsSeven || MarketKind.crapsPoint => GameId.craps,
      };
}

/// `MarketStatus`; [voided] is the wire value `'void'` (Dart keyword).
enum MarketStatus {
  open('open'),
  closed('closed'),
  resolved('resolved'),
  voided('void');

  const MarketStatus(this.wire);
  final String wire;
  static MarketStatus? fromWire(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}

/// `MarketSide` (wire 'yes' | 'no').
enum Outcome { yes, no }

typedef MarketSide = Outcome;

@immutable
class LocalizedText {
  const LocalizedText({this.fr = '', this.en = ''});
  factory LocalizedText.fromDoc(Map<String, Object?> d) =>
      LocalizedText(fr: asString(d['fr']) ?? '', en: asString(d['en']) ?? '');
  final String fr;
  final String en;

  /// Text for [languageCode] (`fr` default), falling back to the other one.
  String of(String languageCode) {
    final t = languageCode == 'en' ? en : fr;
    return t.isNotEmpty ? t : (languageCode == 'en' ? fr : en);
  }
}

/// `markets/{marketId}` — binary LMSR market.
@immutable
class Market {
  const Market({
    required this.id,
    required this.kind,
    this.kindWire,
    this.game,
    required this.tableId,
    required this.tableName,
    required this.status,
    required this.priceYes,
    this.handNumber,
    this.shoeNumber = 1,
    this.subjectUid,
    this.subjectUsername,
    this.subjectSeatIndex,
    this.question = const LocalizedText(),
    this.outcome,
    this.b = 60,
    this.qYes = 0,
    this.qNo = 0,
    this.volumeCents = 0,
    this.tradeCount = 0,
    this.payoutsDone = false,
    this.createdAt,
    this.closedAt,
    this.resolvedAt,
  });

  /// Never fails and never hides a market: a kind this client does not know
  /// yet is kept ([kind] null, [kindWire] = the server value) and shown with
  /// its server-written [question]. (Nullable return type kept for source
  /// compatibility; it is never null.)
  static Market? fromDoc(Map<String, Object?> d, {String? id}) {
    final kind = enumByName(MarketKind.values, d['kind']);
    final tableId = asString(d['tableId']) ?? '';
    return Market(
      id: asString(d['marketId']) ?? id ?? '',
      tableId: tableId,
      tableName: asString(d['tableName']) ?? '',
      kind: kind,
      kindWire: asString(d['kind']),
      game: GameId.fromWire(d['game']),
      handNumber: asIntOrNull(d['handNumber']),
      shoeNumber: asInt(d['shoeNumber'], 1),
      subjectUid: asString(d['subjectUid']),
      subjectUsername: asString(d['subjectUsername']),
      subjectSeatIndex: asIntOrNull(d['subjectSeatIndex']),
      question: LocalizedText.fromDoc(asMap(d['question'])),
      status: MarketStatus.fromWire(d['status']) ?? MarketStatus.closed,
      outcome: enumByName(Outcome.values, d['outcome']),
      b: asDouble(d['b'], (kind == null ? null : Backend.marketLiquidity[kind]) ?? 60),
      qYes: asDouble(d['qYes']),
      qNo: asDouble(d['qNo']),
      priceYes: asDouble(d['priceYes'], 0.5).clamp(0.0, 1.0),
      volumeCents: asInt(d['volumeCents']),
      tradeCount: asInt(d['tradeCount']),
      payoutsDone: asBool(d['payoutsDone']),
      createdAt: asTime(d['createdAtMs']),
      closedAt: asTime(d['closedAtMs']),
      resolvedAt: asTime(d['resolvedAtMs']),
    );
  }

  final String id;

  /// Null for a kind unknown to this client (see [kindWire]).
  final MarketKind? kind;

  /// Raw `kind` of the document (also set for known kinds).
  final String? kindWire;

  /// `MarketDoc.game` (absent on older blackjack markets), see [gameOf].
  final GameId? game;
  final String tableId;
  final String tableName;

  /// Game of the market: [game], else the kind's, else the table id prefix.
  GameId get gameOf => game ?? kind?.game ?? gameOfTableId(tableId);

  /// Long market (not tied to one round): a series kind, or (unknown kind)
  /// no round number.
  bool get isSeries => kind?.isSeries ?? handNumber == null;

  /// Per-hand markets; null for the shoe market.
  final int? handNumber;
  final int shoeNumber;

  /// playerWins subject.
  final String? subjectUid;
  final String? subjectUsername;
  final int? subjectSeatIndex;
  final LocalizedText question;
  final MarketStatus status;

  /// Set when [MarketStatus.resolved].
  final Outcome? outcome;

  /// LMSR liquidity and outstanding shares.
  final double b;
  final double qYes;
  final double qNo;

  /// Current YES price in [0,1] (display ×100 as ¢).
  final double priceYes;
  final int volumeCents;
  final int tradeCount;
  final bool payoutsDone;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final DateTime? resolvedAt;

  double get yesPrice => priceYes;
  double get noPrice => 1 - priceYes;
  double priceOf(Outcome o) => o == Outcome.yes ? priceYes : 1 - priceYes;
  bool get isOpen => status == MarketStatus.open;
  bool get isFinal => status == MarketStatus.resolved || status == MarketStatus.voided;

  /// For [MarketKind.playerWins].
  String? get playerName => subjectUsername;
}

/// `markets/{id}/priceHistory/{pointId}`.
@immutable
class PricePoint {
  const PricePoint(this.t, this.yes);
  factory PricePoint.fromDoc(Map<String, Object?> d) => PricePoint(asTimeOr0(d['atMs']), asDouble(d['priceYes'], 0.5));
  final DateTime t;
  final double yes;
}

enum PositionStatus {
  open('open'),
  won('won'),
  lost('lost'),
  voided('void');

  const PositionStatus(this.wire);
  final String wire;
  static PositionStatus? fromWire(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}

/// `users/{uid}/positions/{marketId}` — ONE doc holds both sides.
@immutable
class MarketPosition {
  const MarketPosition({
    required this.marketId,
    this.tableId = '',
    this.kind,
    this.question = const LocalizedText(),
    this.yesShares = 0,
    this.noShares = 0,
    this.costCents = 0,
    this.proceedsCents = 0,
    this.payoutCents = 0,
    this.status = PositionStatus.open,
    this.updatedAt,
  });

  factory MarketPosition.fromDoc(Map<String, Object?> d, {String? id}) => MarketPosition(
        marketId: asString(d['marketId']) ?? id ?? '',
        tableId: asString(d['tableId']) ?? '',
        kind: enumByName(MarketKind.values, d['kind']),
        question: LocalizedText.fromDoc(asMap(d['question'])),
        yesShares: asInt(d['yesShares']),
        noShares: asInt(d['noShares']),
        costCents: asInt(d['costCents']),
        proceedsCents: asInt(d['proceedsCents']),
        payoutCents: asInt(d['payoutCents']),
        status: PositionStatus.fromWire(d['status']) ?? PositionStatus.open,
        updatedAt: asTime(d['updatedAtMs']),
      );

  final String marketId;
  final String tableId;

  /// Null for a kind unknown to this client (its [question] is always shown).
  final MarketKind? kind;
  final LocalizedText question;
  final int yesShares;
  final int noShares;

  /// Total cents spent buying / received selling / paid at resolution.
  final int costCents;
  final int proceedsCents;
  final int payoutCents;
  final PositionStatus status;
  final DateTime? updatedAt;

  int sharesOf(Outcome o) => o == Outcome.yes ? yesShares : noShares;
  int get totalShares => yesShares + noShares;
  bool get isOpen => status == PositionStatus.open;

  /// Net money put in (cost − proceeds).
  int get netCostCents => costCents - proceedsCents;

  /// Mark-to-market value at [priceYes] (open), or the payout (final).
  int valueCents(double priceYes) => isOpen
      ? (yesShares * priceYes * 100 + noShares * (1 - priceYes) * 100).round()
      : payoutCents;

  /// Profit/loss: value (or payout) − net cost.
  int pnlCents(double priceYes) => valueCents(priceYes) - netCostCents;

  /// Average net cost per share held, in dollars (0..1); 0 when none held.
  double get avgPrice => totalShares == 0 ? 0 : netCostCents / totalShares / 100;
}

/// `markets/{id}/trades/{tradeId}`.
@immutable
class MarketTrade {
  const MarketTrade({
    required this.username,
    required this.outcome,
    required this.isBuy,
    required this.shares,
    required this.amountCents,
    required this.at,
    this.id = '',
    this.uid = '',
    this.isBot = false,
    this.priceYesAfter = 0.5,
  });

  static MarketTrade? fromDoc(Map<String, Object?> d, {String? id}) {
    final side = enumByName(Outcome.values, d['side']);
    if (side == null) return null;
    return MarketTrade(
      id: asString(d['tradeId']) ?? id ?? '',
      uid: asString(d['uid']) ?? '',
      username: asString(d['username']) ?? '?',
      isBot: asBool(d['isBot']),
      outcome: side,
      isBuy: d['direction'] != 'sell',
      shares: asInt(d['shares']),
      amountCents: asInt(d['amountCents']),
      priceYesAfter: asDouble(d['priceYesAfter'], 0.5),
      at: asTimeOr0(d['createdAtMs']),
    );
  }

  final String id;
  final String uid;
  final String username;
  final bool isBot;
  final Outcome outcome;
  final bool isBuy;
  final int shares;

  /// Cents paid (buy) or received (sell).
  final int amountCents;
  final double priceYesAfter;
  final DateTime at;

  /// Average price per share of this trade (0..1).
  double get price => shares == 0 ? 0 : amountCents / shares / 100;
}

/// `TradeSharesResponse`.
@immutable
class TradeResult {
  const TradeResult({
    required this.amountCents,
    required this.priceYes,
    required this.balanceCents,
    required this.yesShares,
    required this.noShares,
  });
  factory TradeResult.fromResponse(Map<String, Object?> r) {
    final pos = asMap(r['position']);
    return TradeResult(
      amountCents: asInt(r['amountCents']),
      priceYes: asDouble(r['priceYes'], 0.5),
      balanceCents: asInt(r['balanceCents']),
      yesShares: asInt(pos['yesShares']),
      noShares: asInt(pos['noShares']),
    );
  }
  final int amountCents;
  final double priceYes;
  final int balanceCents;
  final int yesShares;
  final int noShares;
}

// -------------------------------------------------------------------- ads --

enum AdFormat { banner, interstitial, rewarded }

@immutable
class ParodyAd {
  const ParodyAd({
    required this.id,
    required this.brand,
    required this.color,
  });

  /// One of `coin`, `bank`, `ai`, `nft` — the tagline, call-to-action and
  /// icon are chosen from it in the UI (localized). Sent as `adId`.
  final String id;
  final String brand;
  final Color color;
}

/// `ClaimAdRewardResponse`.
@immutable
class AdRewardResult {
  const AdRewardResult({required this.rewardCents, required this.balanceCents, required this.remainingToday});
  factory AdRewardResult.fromResponse(Map<String, Object?> r) => AdRewardResult(
        rewardCents: asInt(r['rewardCents']),
        balanceCents: asInt(r['balanceCents']),
        remainingToday: asInt(r['remainingToday']),
      );
  final int rewardCents;
  final int balanceCents;
  final int remainingToday;
}

/// `users/{uid}/private/ads`.
@immutable
class AdState {
  const AdState({this.day = '', this.claimedToday = 0, this.lastClaimAt});
  factory AdState.fromDoc(Map<String, Object?> d) => AdState(
        day: asString(d['day']) ?? '',
        claimedToday: asInt(d['claimedToday']),
        lastClaimAt: asTime(d['lastClaimAtMs']),
      );
  final String day;
  final int claimedToday;
  final DateTime? lastClaimAt;

  int remainingAt(DateTime now) =>
      day == utcDayId(now) ? (Backend.adRewardDailyMax - claimedToday).clamp(0, Backend.adRewardDailyMax) : Backend.adRewardDailyMax;

  /// When the next claim is allowed (cooldown), null if allowed now.
  DateTime? nextClaimAt(DateTime now) {
    final last = lastClaimAt;
    if (last == null) return null;
    final next = last.add(const Duration(milliseconds: Backend.adRewardCooldownMs));
    return next.isAfter(now) ? next : null;
  }
}
