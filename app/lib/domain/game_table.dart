/// Client mirror of the kernel-driven game tables (Sprint 2): roulette,
/// baccarat, Texas hold'em and craps, `gameTables/{id}` and its
/// sub-collections, exactly as documented in
/// `firebase/functions/src/shared/games/common.ts` (the frozen contract).
///
/// Everything game-specific stays RAW here (`g` maps of the table and of each
/// seat, event payloads `d`, round `result`): each game parses its own shapes
/// in `lib/features/games/<jeu>/` (documented in `shared/games/<jeu>.ts`).
/// Parsing is tolerant like `TableState.fromDoc`: a missing or mistyped field
/// falls back to a safe value, never throws.
library;

import 'package:flutter/foundation.dart';

import 'games.dart';
import 'models.dart' show MarketKind, PowerType, RankTier;
import 'table_state.dart' show FairnessInfo;
import 'wire.dart';

/// `GAME_PHASES` (kernel phases; the game's sub-step is [GameTableState.step]).
enum GamePhase { idle, betting, live, settled, closed }

/// `GAME_TIMING` (ms) — kernel defaults, modules may use their own per step.
abstract final class GameTiming {
  static const bettingMs = 20000;
  static const decisionMs = 20000;
  static const settledMs = 6000;
  static const botMinMs = 700;
  static const botMaxMs = 1800;

  /// `GAME_MISSED_ROUNDS_LIMIT`.
  static const missedRoundsLimit = 5;

  /// `GAME_EVENTS_CAP`.
  static const eventsCap = 200;

  /// Poke the table when `now > deadline + pokeGraceMs` (server grace for
  /// humans + margin), like the blackjack table.
  static const pokeGraceMs = 3000;
}

/// `GAME_RANK_POINTS` / `RANK_POINTS_DAILY_CAP_PER_GAME` (shared ladder of the kernel games).
abstract final class GameRankPoints {
  static const bigWin = 15;
  static const win = 10;
  static const lose = -4;
  static const dailyCapPerGame = 250;
}

/// `GameLimits` (whole dollars, in cents). [extra] holds the game-specific
/// limits (hold'em: smallBlindCents, bigBlindCents, minBuyInCents, maxBuyInCents).
@immutable
class GameLimits {
  const GameLimits({this.minBetCents = 100, this.maxBetCents = 10000, this.maxRoundCents = 10000, this.extra = const {}});
  factory GameLimits.fromDoc(Map<String, Object?> d) => GameLimits(
        minBetCents: asInt(d['minBetCents'], 100),
        maxBetCents: asInt(d['maxBetCents'], 10000),
        maxRoundCents: asInt(d['maxRoundCents'], asInt(d['maxBetCents'], 10000)),
        extra: {for (final e in asMap(d['extra']).entries) if (e.value is num) e.key: (e.value! as num).toInt()},
      );
  final int minBetCents;
  final int maxBetCents;
  final int maxRoundCents;
  final Map<String, int> extra;
}

/// `GameSeatDoc.status`.
enum GameSeatStatus { active, leaving, sittingOut }

/// One seat (`GameSeatDoc`); [g] is the game-specific seat state.
@immutable
class GameSeat {
  const GameSeat({
    required this.seatIndex,
    required this.uid,
    required this.username,
    this.avatar = 'avatar01',
    this.isBot = false,
    this.rankTier = RankTier.bronze,
    this.status = GameSeatStatus.active,
    this.joinedAt,
    this.missedRounds = 0,
    this.stakeCents = 0,
    this.stackCents,
    this.powerUsed,
    this.roundNetCents,
    this.g = const {},
  });

  factory GameSeat.fromDoc(Map<String, Object?> d, {int? index}) => GameSeat(
        seatIndex: asInt(d['seatIndex'], index ?? 0),
        uid: asString(d['uid']) ?? '',
        username: asString(d['username']) ?? '?',
        avatar: asString(d['avatar']) ?? 'avatar01',
        isBot: asBool(d['isBot']),
        rankTier: enumByName(RankTier.values, d['rankTier']) ?? RankTier.bronze,
        status: enumByName(GameSeatStatus.values, d['status']) ?? GameSeatStatus.active,
        joinedAt: asTime(d['joinedAtMs']),
        missedRounds: asInt(d['missedRounds']),
        stakeCents: asInt(d['stakeCents']),
        stackCents: asIntOrNull(d['stackCents']),
        powerUsed: enumByName(PowerType.values, d['powerUsed']),
        roundNetCents: asIntOrNull(d['roundNetCents']),
        g: asMap(d['g']),
      );

  final int seatIndex;
  final String uid;
  final String username;
  final String avatar;
  final bool isBot;
  final RankTier rankTier;
  final GameSeatStatus status;
  final DateTime? joinedAt;
  final int missedRounds;

  /// Total staked this round (frozen when betting closes).
  final int stakeCents;

  /// Hold'em chips in front of the player (null for bet-board games).
  final int? stackCents;
  final PowerType? powerUsed;

  /// Set at settlement: total return − total stake of the round.
  final int? roundNetCents;

  /// Game-specific seat state (`shared/games/<jeu>.ts`).
  final Map<String, Object?> g;

  bool get leaving => status == GameSeatStatus.leaving;
  bool get sittingOut => status == GameSeatStatus.sittingOut;
}

/// `GameEvent` — animation log of the current round, by [seq].
@immutable
class GameEvent {
  const GameEvent({required this.seq, required this.type, this.seatIndex, this.at, this.d = const {}});
  factory GameEvent.fromDoc(Map<String, Object?> d) => GameEvent(
        seq: asInt(d['seq']),
        type: asString(d['type']) ?? '',
        seatIndex: asIntOrNull(d['seatIndex']),
        at: asTime(d['atMs']),
        d: asMap(d['d']),
      );
  final int seq;

  /// Game-specific type, or a kernel type: join, leave, sitOut, sitIn, timeout, power, shuffle.
  final String type;
  final int? seatIndex;
  final DateTime? at;
  final Map<String, Object?> d;

  @override
  String toString() => 'GameEvent#$seq($type${seatIndex == null ? '' : ' seat$seatIndex'})';
}

/// `GameQueueEntry`.
@immutable
class GameQueueEntry {
  const GameQueueEntry({required this.uid, required this.username, this.buyInCents});
  factory GameQueueEntry.fromDoc(Map<String, Object?> d) =>
      GameQueueEntry(uid: asString(d['uid']) ?? '', username: asString(d['username']) ?? '?', buyInCents: asIntOrNull(d['buyInCents']));
  final String uid;
  final String username;

  /// Hold'em: buy-in already debited at gameJoin.
  final int? buyInCents;
}

/// `GameMarketsPublic`: kind → marketId for the current round and the long
/// series markets. Unknown kinds are KEPT (raw wire names) so a newer server
/// never hides a market from the client.
@immutable
class GameTableMarkets {
  const GameTableMarkets({this.round = const {}, this.series = const {}});
  factory GameTableMarkets.fromDoc(Map<String, Object?> d) {
    Map<String, String> ids(Object? v) => {for (final e in asMap(v).entries) if (e.value is String) e.key: e.value! as String};
    return GameTableMarkets(round: ids(d['round']), series: ids(d['series']));
  }

  /// Wire kind → market id.
  final Map<String, String> round;
  final Map<String, String> series;

  List<String> get all => [...round.values, ...series.values];
  bool get isEmpty => round.isEmpty && series.isEmpty;
  String? of(MarketKind kind) => round[kind.name] ?? series[kind.name];
}

/// `gameTables/{tableId}` — public state of a kernel-driven table.
@immutable
class GameTableState {
  const GameTableState({
    required this.id,
    required this.game,
    this.name = '',
    this.stakeTier = 'low',
    this.limits = const GameLimits(),
    this.isPrivate = false,
    this.simManaged = false,
    this.closed = false,
    this.phase = GamePhase.idle,
    this.step,
    this.phaseStartedAt,
    this.deadline,
    this.round = 0,
    this.turnSeat,
    this.seats = const [],
    this.queue = const [],
    this.seatedUids = const [],
    this.humanCount = 0,
    this.botCount = 0,
    this.rankTier = RankTier.bronze,
    required this.dealerCharacterId,
    this.fairness = const FairnessInfo(),
    this.events = const [],
    this.eventSeq = 0,
    this.markets = const GameTableMarkets(),
    this.g = const {},
    this.createdAt,
    this.updatedAt,
    this.fromCache = false,
  });

  factory GameTableState.fromDoc(String id, Map<String, Object?> d, {bool fromCache = false}) {
    final game = GameId.fromWire(d['game']) ?? gameOfTableId(id);
    final rawSeats = asList(d['seats']);
    final count = rawSeats.length > game.seats ? rawSeats.length : game.seats;
    final seats = <GameSeat?>[
      for (var i = 0; i < count; i++)
        i < rawSeats.length && rawSeats[i] is Map ? GameSeat.fromDoc(asMap(rawSeats[i]), index: i) : null,
    ];
    final turn = asMap(d['turn']);
    return GameTableState(
      id: asString(d['tableId']) ?? id,
      game: game,
      name: asString(d['name']) ?? id,
      stakeTier: asString(d['stakeTier']) ?? 'low',
      limits: GameLimits.fromDoc(asMap(d['limits'])),
      isPrivate: asBool(d['isPrivate']),
      simManaged: asBool(d['simManaged']),
      closed: d['status'] == 'closed' || d['phase'] == 'closed',
      phase: enumByName(GamePhase.values, d['phase']) ?? GamePhase.idle,
      step: asString(d['step']),
      phaseStartedAt: asTime(d['phaseStartedAtMs']),
      deadline: asTime(d['deadlineMs']),
      round: asInt(d['round']),
      turnSeat: asIntOrNull(turn['seatIndex']),
      seats: seats,
      queue: [for (final q in asList(d['queue'])) if (q is Map) GameQueueEntry.fromDoc(asMap(q))],
      seatedUids: asStringList(d['seatedUids']),
      humanCount: d['humanCount'] is num ? asInt(d['humanCount']) : seats.where((s) => s != null && !s.isBot).length,
      botCount: d['botCount'] is num ? asInt(d['botCount']) : seats.where((s) => s != null && s.isBot).length,
      rankTier: enumByName(RankTier.values, d['rankTier']) ?? RankTier.bronze,
      dealerCharacterId: asString(asMap(d['dealer'])['characterId']) ?? game.dealerCharacterId,
      fairness: FairnessInfo.fromDoc(asMap(d['fairness'])),
      events: [for (final e in asList(d['events'])) if (e is Map) GameEvent.fromDoc(asMap(e))]..sort((a, b) => a.seq.compareTo(b.seq)),
      eventSeq: asInt(d['eventSeq']),
      markets: GameTableMarkets.fromDoc(asMap(d['markets'])),
      g: asMap(d['g']),
      createdAt: asTime(d['createdAtMs']),
      updatedAt: asTime(d['updatedAtMs']),
      fromCache: fromCache,
    );
  }

  final String id;
  final GameId game;
  final String name;

  /// `low` | `mid` | `high`.
  final String stakeTier;
  final GameLimits limits;
  final bool isPrivate;
  final bool simManaged;
  final bool closed;
  final GamePhase phase;

  /// Game-specific sub-step (e.g. 'spinning', 'preflop', 'comeOut').
  final String? step;
  final DateTime? phaseStartedAt;
  final DateTime? deadline;

  /// +1 each time a round opens; send it with gameAction.
  final int round;

  /// Seat whose decision is pending (hold'em player, craps shooter).
  final int? turnSeat;

  /// Always [GameId.seats] long (null = empty seat).
  final List<GameSeat?> seats;
  final List<GameQueueEntry> queue;
  final List<String> seatedUids;
  final int humanCount;
  final int botCount;
  final RankTier rankTier;

  /// Croupier character (`dealer.characterId`, Rendez-vous meta).
  final String dealerCharacterId;
  final FairnessInfo fairness;

  /// Current round's events, sorted by seq.
  final List<GameEvent> events;
  final int eventSeq;
  final GameTableMarkets markets;

  /// Game-specific public state (`shared/games/<jeu>.ts`).
  final Map<String, Object?> g;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Served from the local cache (offline).
  final bool fromCache;

  GameSeat? seatOf(String? uid) => uid == null ? null : seats.firstWhere((s) => s?.uid == uid, orElse: () => null);
  int queuePositionOf(String? uid) => uid == null ? -1 : queue.indexWhere((q) => q.uid == uid);
  bool isQueued(String? uid) => queuePositionOf(uid) >= 0;
  int get seatsTaken => seats.whereType<GameSeat>().length;
  GameSeat? get turnSeatState => turnSeat == null || turnSeat! >= seats.length ? null : seats[turnSeat!];

  /// Time left before [deadline] (zero when past or none).
  Duration remainingAt(DateTime now) {
    final d = deadline;
    if (d == null) return Duration.zero;
    final r = d.difference(now);
    return r.isNegative ? Duration.zero : r;
  }

  /// Fraction of the current phase elapsed (0..1), for timer bars.
  double phaseProgressAt(DateTime now) {
    final start = phaseStartedAt, end = deadline;
    if (start == null || end == null || !end.isAfter(start)) return 0;
    return (now.difference(start).inMilliseconds / end.difference(start).inMilliseconds).clamp(0.0, 1.0);
  }

  /// Whether the client should ask the server to apply an overdue deadline.
  bool shouldPokeAt(DateTime now) =>
      !closed && deadline != null && now.isAfter(deadline!.add(const Duration(milliseconds: GameTiming.pokeGraceMs)));

  /// Events after [seq] (animation catch-up).
  Iterable<GameEvent> eventsAfter(int seq) => events.where((e) => e.seq > seq);
}

/// `gameTables/{id}/bets/{uid}` — one seat's bet board (bet-board games).
@immutable
class GameBet {
  const GameBet({
    required this.uid,
    this.seatIndex = 0,
    this.isBot = false,
    this.round = 0,
    this.bets = const {},
    this.totalCents = 0,
    this.power,
    this.previous = const {},
    this.updatedAt,
  });

  factory GameBet.fromDoc(Map<String, Object?> d, {String? id}) {
    Map<String, int> board(Object? v) => {for (final e in asMap(v).entries) if (e.value is num) e.key: (e.value! as num).toInt()};
    final bets = board(d['bets']);
    return GameBet(
      uid: asString(d['uid']) ?? id ?? '',
      seatIndex: asInt(d['seatIndex']),
      isBot: asBool(d['isBot']),
      round: asInt(d['round']),
      bets: bets,
      totalCents: d['totalCents'] is num ? asInt(d['totalCents']) : bets.values.fold(0, (a, b) => a + b),
      power: enumByName(PowerType.values, d['power']),
      previous: board(d['previous']),
      updatedAt: asTime(d['updatedAtMs']),
    );
  }

  final String uid;
  final int seatIndex;
  final bool isBot;
  final int round;

  /// spotId → cents (spot ids are game-specific).
  final Map<String, int> bets;
  final int totalCents;
  final PowerType? power;

  /// Board of the previous round ("Rejouer").
  final Map<String, int> previous;
  final DateTime? updatedAt;

  /// Whether this board belongs to [round] (older boards are leftovers).
  bool isFor(int tableRound) => round == tableRound;
}

/// `gameTables/{id}/holes/{uid}` — hold'em hole cards (wire codes, `T` = ten).
@immutable
class GameHole {
  const GameHole({this.round = 0, this.cards = const [], this.createdAt});
  factory GameHole.fromDoc(Map<String, Object?> d) =>
      GameHole(round: asInt(d['round']), cards: asStringList(d['cards']), createdAt: asTime(d['createdAtMs']));
  final int round;
  final List<String> cards;
  final DateTime? createdAt;
}

/// One seat of a finished round.
@immutable
class GameRoundSeat {
  const GameRoundSeat({
    required this.seatIndex,
    required this.uid,
    required this.username,
    this.isBot = false,
    this.stakedCents = 0,
    this.netCents = 0,
  });
  final int seatIndex;
  final String uid;
  final String username;
  final bool isBot;
  final int stakedCents;
  final int netCents;
}

/// Fairness proof of a finished round (`GameRoundDoc.fairness`).
@immutable
class GameRoundFairness {
  const GameRoundFairness({this.commit = '', this.seed = '', this.remainingBefore, this.dealt, this.decks});
  factory GameRoundFairness.fromDoc(Map<String, Object?> d) => GameRoundFairness(
        commit: asString(d['commit']) ?? '',
        seed: asString(d['seed']) ?? '',
        remainingBefore: d['remainingBefore'] is List ? asStringList(d['remainingBefore']) : null,
        dealt: d['dealt'] is List ? asStringList(d['dealt']) : null,
        decks: asIntOrNull(d['decks']),
      );
  final String commit;
  final String seed;

  /// Card games: canonical input of fairDealOrder and the dealt prefix.
  final List<String>? remainingBefore;
  final List<String>? dealt;
  final int? decks;
}

/// `gameTables/{id}/rounds/{round8}` — history + fairness proof.
@immutable
class GameRound {
  const GameRound({
    required this.tableId,
    required this.game,
    required this.round,
    this.startedAt,
    this.endedAt,
    this.seats = const [],
    this.result = const {},
    this.fairness = const GameRoundFairness(),
  });

  factory GameRound.fromDoc(Map<String, Object?> d, {String? id}) {
    final tableId = asString(d['tableId']) ?? '';
    return GameRound(
      tableId: tableId,
      game: GameId.fromWire(d['game']) ?? gameOfTableId(tableId),
      round: asInt(d['round'], int.tryParse(id ?? '') ?? 0),
      startedAt: asTime(d['startedAtMs']),
      endedAt: asTime(d['endedAtMs']),
      seats: [
        for (final s in asList(d['seats']))
          if (s is Map)
            GameRoundSeat(
              seatIndex: asInt(s['seatIndex']),
              uid: asString(s['uid']) ?? '',
              username: asString(s['username']) ?? '?',
              isBot: asBool(s['isBot']),
              stakedCents: asInt(s['stakedCents']),
              netCents: asInt(s['netCents']),
            ),
      ],
      result: asMap(d['result']),
      fairness: GameRoundFairness.fromDoc(asMap(d['fairness'])),
    );
  }

  final String tableId;
  final GameId game;
  final int round;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<GameRoundSeat> seats;

  /// Game-specific result (number, cards, dice, pots…).
  final Map<String, Object?> result;
  final GameRoundFairness fairness;

  GameRoundSeat? seatOf(String? uid) => seats.where((s) => s.uid == uid).firstOrNull;

  /// Document id of a round (`rounds/{round8}`).
  static String docId(int round) => round.toString().padLeft(8, '0');
}

/// `GameJoinRequest.mode` (same modes as blackjack's `joinMatchmaking`).
enum GameJoinMode { quick, createPrivate, joinCode }

/// `GameJoinResponse`: [game] may differ from the requested one for
/// `joinCode` (a code of another game, blackjack included).
@immutable
class GameJoinResult {
  const GameJoinResult({required this.tableId, required this.game, required this.seated, this.seatIndex, this.code});
  factory GameJoinResult.fromResponse(Map<String, Object?> r) {
    final id = asString(r['tableId']) ?? '';
    return GameJoinResult(
      tableId: id,
      game: GameId.fromWire(r['game']) ?? gameOfTableId(id),
      seated: r['status'] == 'seated',
      seatIndex: asIntOrNull(r['seatIndex']),
      code: asString(r['code']),
    );
  }
  final String tableId;
  final GameId game;

  /// false = queued.
  final bool seated;
  final int? seatIndex;
  final String? code;
}

/// `GameLeaveResponse`.
@immutable
class GameLeaveResult {
  const GameLeaveResult({this.refundedCents = 0, this.cashOutCents = 0, this.deferred = false});
  factory GameLeaveResult.fromResponse(Map<String, Object?> r) => GameLeaveResult(
        refundedCents: asInt(r['refundedCents']),
        cashOutCents: asInt(r['cashOutCents']),
        deferred: asBool(r['deferred']),
      );
  final int refundedCents;
  final int cashOutCents;

  /// Hold'em: left mid-hand, the stack is cashed out after the hand.
  final bool deferred;
}

/// `GameActionResponse`.
@immutable
class GameActionResult {
  const GameActionResult({this.phase = GamePhase.idle, this.round = 0, this.balanceCents = 0, this.stackCents, this.data});
  factory GameActionResult.fromResponse(Map<String, Object?> r) => GameActionResult(
        phase: enumByName(GamePhase.values, r['phase']) ?? GamePhase.idle,
        round: asInt(r['round']),
        balanceCents: asInt(r['balanceCents']),
        stackCents: asIntOrNull(r['stackCents']),
        data: r['data'] is Map ? asMap(r['data']) : null,
      );
  final GamePhase phase;
  final int round;
  final int balanceCents;
  final int? stackCents;
  final Map<String, Object?>? data;
}

/// `GamePokeResponse`.
@immutable
class GamePokeResult {
  const GamePokeResult({this.phase = GamePhase.idle, this.round = 0, this.deadline, this.advanced = false});
  factory GamePokeResult.fromResponse(Map<String, Object?> r) => GamePokeResult(
        phase: enumByName(GamePhase.values, r['phase']) ?? GamePhase.idle,
        round: asInt(r['round']),
        deadline: asTime(r['deadlineMs']),
        advanced: asBool(r['advanced']),
      );
  final GamePhase phase;
  final int round;
  final DateTime? deadline;
  final bool advanced;
}

/// `profiles/{uid}.gameStats[game]` (`GameStatsDoc`). Blackjack keeps its own
/// `stats` ([GameStats.fromBlackjack] adapts them for the profile).
@immutable
class GameStats {
  const GameStats({this.rounds = 0, this.won = 0, this.lost = 0, this.netCents = 0, this.biggestWinCents = 0, this.counters = const {}});
  factory GameStats.fromDoc(Map<String, Object?> d) => GameStats(
        rounds: asInt(d['rounds']),
        won: asInt(d['won']),
        lost: asInt(d['lost']),
        netCents: asInt(d['netCents']),
        biggestWinCents: asInt(d['biggestWinCents']),
        counters: {for (final e in asMap(d['counters']).entries) if (e.value is num) e.key: (e.value! as num).toInt()},
      );
  final int rounds;
  final int won;
  final int lost;
  final int netCents;
  final int biggestWinCents;

  /// Game-specific counters (e.g. straightUps, pots).
  final Map<String, int> counters;

  double get winRate => rounds == 0 ? 0 : won / rounds;
  bool get isEmpty => rounds == 0;
}
