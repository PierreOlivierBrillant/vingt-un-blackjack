/// In-memory [GameTableRepository] (Sprint 2 kernel-driven games), for the
/// app without a backend and for every widget/golden test. It follows the
/// contract of `shared/games/common.ts` closely enough for the generic
/// screens (lobby, scaffold, joins, bet boards); game rules are NOT simulated.
library;

import 'dart:async';

import '../../domain/games.dart';
import '../../domain/models.dart';
import '../live.dart';
import '../repositories.dart';
import 'fake_data.dart';
import 'fake_game_data.dart';
import 'fake_repositories.dart' show FakeWalletRepository, serverError;

class FakeGameTableRepository implements GameTableRepository {
  /// [docs] replace / add `gameTables/{id}` documents (tests). When [wallet]
  /// is given, buy-ins and bet boards are debited from it.
  FakeGameTableRepository({
    this.myUid = FakeData.demoUid,
    DateTime Function()? now,
    Map<String, Map<String, Object?>> docs = const {},
    this.wallet,
  }) : _now = now ?? DateTime.now {
    final start = _now();
    _tables = Live({
      for (final d in FakeGameData.tableDocs(start)) d['tableId']! as String: d,
      ...docs,
    });
  }

  @override
  final String? myUid;
  final DateTime Function() _now;
  final FakeWalletRepository? wallet;
  late final Live<Map<String, Map<String, Object?>>> _tables;
  final _boards = <String, Map<String, Map<String, Object?>>>{}; // tableId → uid → bet doc
  final _results = <String, Object?>{};
  final _codes = <String, String>{'RLT123': 'rl-private-rlt123', 'ABC123': 't-private-abc123'};
  var _seq = 0;

  /// Every call made, e.g. `join:roulette/quick/low`, `setBets:rl-sim-01#42 {red: 500}`,
  /// `act:ho-sim-01#42 fold`, `poke:…`, `leave:…` (for tests).
  final calls = <String>[];

  Future<T> _once<T>(String key, FutureOr<T> Function() body) async {
    if (_results.containsKey(key)) return _results[key] as T;
    final r = await body();
    _results[key] = r;
    return r;
  }

  Map<String, Object?> _doc(String id) => _tables.value[id] ?? FakeGameData.tableDoc(id, _now());

  void _put(Map<String, Object?> doc) => _tables.value = {..._tables.value, doc['tableId']! as String: doc};

  @override
  Stream<List<LiveTable>> watchLiveTables(GameId game, {String? tierId}) => _tables.stream.map((all) => [
        for (final d in all.values)
          if (d['game'] == game.wire && d['isPrivate'] != true && d['status'] == 'open' && (tierId == null || d['stakeTier'] == tierId))
            LiveTable.fromDoc(d),
      ]);

  @override
  Stream<GameTableState> watchTable(String tableId) =>
      _tables.stream.map((all) => GameTableState.fromDoc(tableId, all[tableId] ?? FakeGameData.tableDoc(tableId, _now())));

  @override
  Stream<List<GameBet>> watchBets(String tableId) => _tables.stream.map((all) {
        final table = all[tableId] ?? FakeGameData.tableDoc(tableId, _now());
        final mine = _boards[tableId] ?? const {};
        return [
          for (final d in FakeGameData.betDocs(table))
            if (!mine.containsKey(d['uid'])) GameBet.fromDoc(d),
          for (final d in mine.values) GameBet.fromDoc(d),
        ];
      });

  @override
  Stream<GameHole?> watchMyHole(String tableId) => watchTable(tableId).map((t) {
        final me = t.seatOf(myUid);
        if (t.game != GameId.holdem || me == null || t.phase != GamePhase.live) return null;
        return GameHole(round: t.round, cards: const ['AS', 'KD']);
      });

  @override
  Stream<List<GameRound>> watchRounds(String tableId, {int limit = 20}) =>
      watchTable(tableId).map((_) => FakeGameData.rounds(_doc(tableId), _now()).take(limit).toList());

  Map<String, Object?> _seatMe(Map<String, Object?> doc, {int? stackCents}) {
    final seats = [...(doc['seats']! as List).cast<Map<String, Object?>?>()];
    if (seats.any((s) => s?['uid'] == myUid)) return doc;
    final free = seats.indexWhere((s) => s == null || s['isBot'] == true);
    if (free < 0) throw serverError(ServerReason.TABLE_FULL);
    seats[free] = {
      'seatIndex': free,
      'uid': myUid,
      'username': FakeData.demoUsername,
      'avatar': FakeData.demoAvatar,
      'isBot': false,
      'rankTier': 'silver',
      'status': 'active',
      'joinedAtMs': _now().millisecondsSinceEpoch,
      'missedRounds': 0,
      'stakeCents': 0,
      'stackCents': stackCents,
      'powerUsed': null,
      'roundNetCents': null,
      'g': <String, Object?>{},
    };
    final taken = seats.whereType<Map<String, Object?>>();
    return {
      ...doc,
      'seats': seats,
      'seatedUids': [for (final s in taken) s['uid']],
      'humanCount': taken.where((s) => s['isBot'] != true).length,
      'botCount': taken.where((s) => s['isBot'] == true).length,
    };
  }

  int? _checkBuyIn(GameId game, Map<String, Object?> doc, int? buyInCents) {
    if (game != GameId.holdem) return null;
    final limits = GameLimits.fromDoc((doc['limits'] as Map?)?.cast<String, Object?>() ?? const {});
    final min = limits.extra['minBuyInCents'] ?? 0, max = limits.extra['maxBuyInCents'] ?? 0;
    if (buyInCents == null || buyInCents < min || buyInCents > max || buyInCents % 100 != 0) {
      throw serverError(ServerReason.BUY_IN_OUT_OF_RANGE);
    }
    wallet?.move(-buyInCents, LedgerKind.buyIn, tableId: doc['tableId'] as String?);
    return buyInCents;
  }

  @override
  Future<GameJoinResult> join({
    required GameId game,
    required GameJoinMode mode,
    String stakeTier = 'low',
    String? code,
    int? buyInCents,
    required String idempotencyKey,
  }) =>
      _once(idempotencyKey, () {
        calls.add('join:${game.wire}/${mode.name}/$stakeTier${code == null ? '' : '/$code'}${buyInCents == null ? '' : '/$buyInCents'}');
        if (!game.isKernel) throw serverError(ServerReason.INVALID_ARGUMENT);
        switch (mode) {
          case GameJoinMode.quick:
            final candidates = _tables.value.values
                .where((d) => d['game'] == game.wire && d['stakeTier'] == stakeTier && d['isPrivate'] != true && d['status'] == 'open')
                .toList();
            final doc = candidates.isEmpty
                ? FakeGameData.tableDoc('${game.prefix}-new-$stakeTier', _now(), tier: stakeTier, bots: 2, phase: 'idle')
                : candidates.first;
            final stack = _checkBuyIn(game, doc, buyInCents);
            final seated = _seatMe(doc, stackCents: stack);
            _put(seated);
            final me = GameTableState.fromDoc(seated['tableId']! as String, seated).seatOf(myUid);
            return GameJoinResult(tableId: seated['tableId']! as String, game: game, seated: true, seatIndex: me?.seatIndex);
          case GameJoinMode.createPrivate:
            final c = '${game.prefix!.toUpperCase()}${(1000 + _codes.length * 7919 % 9000)}'.padRight(6, '0').substring(0, 6);
            final id = '${game.prefix}-p-${c.toLowerCase()}';
            _codes[c] = id;
            final base = FakeGameData.tableDoc(id, _now(), name: 'Table privée', tier: stakeTier, bots: 0, phase: 'idle', isPrivate: true, round: 0);
            final stack = _checkBuyIn(game, base, buyInCents);
            _put(_seatMe(base, stackCents: stack));
            return GameJoinResult(tableId: id, game: game, seated: true, seatIndex: 0, code: c);
          case GameJoinMode.joinCode:
            final c = code?.trim().toUpperCase();
            if (c == null || !RegExp(r'^[A-Z0-9]{6}$').hasMatch(c)) throw serverError(ServerReason.INVALID_ARGUMENT);
            final id = _codes[c];
            if (id == null) throw serverError(ServerReason.BAD_CODE);
            final g = gameOfTableId(id);
            if (!g.isKernel) return GameJoinResult(tableId: id, game: g, seated: true, seatIndex: 1, code: c);
            final doc = _doc(id);
            final stack = _checkBuyIn(g, doc, buyInCents);
            _put(_seatMe({...doc, 'isPrivate': true}, stackCents: stack));
            return GameJoinResult(tableId: id, game: g, seated: true, seatIndex: 1, code: c);
        }
      });

  @override
  Future<GameLeaveResult> leave(String tableId) async {
    calls.add('leave:$tableId');
    final doc = _doc(tableId);
    final seats = [...(doc['seats']! as List).cast<Map<String, Object?>?>()];
    final i = seats.indexWhere((s) => s?['uid'] == myUid);
    final stack = i < 0 ? null : seats[i]!['stackCents'] as int?;
    if (i >= 0) seats[i] = null;
    _put({...doc, 'seats': seats});
    final board = _boards[tableId]?.remove(myUid);
    final refunded = board == null ? 0 : (board['totalCents'] as int? ?? 0);
    if (refunded > 0) wallet?.move(refunded, LedgerKind.refund, tableId: tableId);
    if (stack != null && stack > 0) wallet?.move(stack, LedgerKind.cashOut, tableId: tableId);
    return GameLeaveResult(refundedCents: refunded, cashOutCents: stack ?? 0);
  }

  @override
  Future<GameActionResult> act(String tableId, int round, Map<String, Object?> action, {required String idempotencyKey}) =>
      _once(idempotencyKey, () {
        final doc = _doc(tableId);
        final t = GameTableState.fromDoc(tableId, doc);
        calls.add('act:$tableId#$round ${action['type']}');
        if (round != t.round) throw serverError(ServerReason.STALE_HAND);
        if (t.seatOf(myUid) == null) throw serverError(ServerReason.NOT_SEATED);
        if (action['type'] == 'setBets') return _setBets(t, action);
        return GameActionResult(phase: t.phase, round: t.round, balanceCents: wallet?.balanceCents ?? 0);
      });

  GameActionResult _setBets(GameTableState t, Map<String, Object?> action) {
    if (t.phase != GamePhase.betting && t.game != GameId.craps) throw serverError(ServerReason.BAD_PHASE);
    final raw = action['bets'];
    final bets = <String, int>{
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value is int && (e.value as int) > 0) e.key.toString(): e.value as int,
    };
    var total = 0;
    for (final v in bets.values) {
      if (v % 100 != 0 || v < t.limits.minBetCents || v > t.limits.maxBetCents) throw serverError(ServerReason.BET_OUT_OF_RANGE);
      total += v;
    }
    if (total > t.limits.maxRoundCents) throw serverError(ServerReason.BET_OUT_OF_RANGE);
    final boards = _boards[t.id] ??= {};
    final before = (boards[myUid]?['totalCents'] as int?) ?? 0;
    final delta = total - before;
    if (delta != 0) wallet?.move(-delta, delta > 0 ? LedgerKind.bet : LedgerKind.refund, tableId: t.id, handNumber: t.round);
    final mine = t.seatOf(myUid)!;
    boards[myUid!] = {
      'uid': myUid,
      'seatIndex': mine.seatIndex,
      'isBot': false,
      'round': t.round,
      'bets': bets,
      'totalCents': total,
      'power': action['power'],
      'previous': boards[myUid]?['previous'] ?? <String, Object?>{},
      'updatedAtMs': _now().millisecondsSinceEpoch + ++_seq,
    };
    _tables.value = {..._tables.value}; // re-emit
    return GameActionResult(phase: t.phase, round: t.round, balanceCents: wallet?.balanceCents ?? 0, data: {'bets': bets});
  }

  @override
  Future<GameActionResult> setBets(String tableId, int round, Map<String, int> bets, {PowerType? power, required String idempotencyKey}) {
    calls.add('setBets:$tableId#$round $bets${power == null ? '' : ' +${power.name}'}');
    return act(tableId, round, {'type': 'setBets', 'bets': bets, 'power': ?power?.name}, idempotencyKey: idempotencyKey);
  }

  @override
  Future<GamePokeResult> poke(String tableId) async {
    calls.add('poke:$tableId');
    final t = GameTableState.fromDoc(tableId, _doc(tableId));
    return GamePokeResult(phase: t.phase, round: t.round, deadline: t.deadline);
  }
}
