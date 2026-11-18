/// Lobby (public tables, tiers, feed, matchmaking) and live table.
library;

import '../../core/ids.dart';
import '../../domain/models.dart';
import '../repositories.dart';
import '../server_errors.dart';
import 'backend_api.dart';
import 'firebase_context.dart';
import 'firebase_errors.dart';

class FirebaseLobbyRepository implements LobbyRepository {
  FirebaseLobbyRepository(this._ctx);
  final FirebaseContext _ctx;

  /// `tables` where status == open && isPrivate == false, orderBy
  /// updatedAtMs desc (CLIENT GUIDE).
  Stream<List<LiveTable>> _publicTables() => _ctx.perUser(
        (_) => _ctx
            .queryDocs(_ctx
                .col(FirestorePaths.tables)
                .where('status', isEqualTo: 'open')
                .where('isPrivate', isEqualTo: false)
                .orderBy('updatedAtMs', descending: true)
                .limit(QueryLimits.lobbyTables))
            .map((docs) => [for (final (id, d) in docs) LiveTable.fromDoc(d, id: id)]),
        const [],
      );

  @override
  Stream<List<StakeTier>> watchStakeTiers() => _publicTables().map(StakeTier.allFrom);

  @override
  Stream<List<LiveTable>> watchLiveTables({String? tierId}) =>
      _publicTables().map((l) => tierId == null ? l : l.where((t) => t.tierId == tierId).toList());

  @override
  Stream<List<RecentWin>> watchRecentWins({int limit = QueryLimits.feed}) => _ctx.perUser(
        (_) => _ctx
            .queryDocs(_ctx.col(FirestorePaths.feed).orderBy('createdAtMs', descending: true).limit(limit))
            .map((docs) => [for (final (id, d) in docs) ?RecentWin.fromDoc(d, id: id)]),
        const [],
      );

  @override
  Future<MatchResult> joinMatchmaking({
    required MatchMode mode,
    String stakeTier = 'low',
    String? code,
    required String idempotencyKey,
  }) async =>
      MatchResult.fromResponse(await _ctx.call('joinMatchmaking', Payloads.joinMatchmaking(mode, stakeTier, code),
          idempotencyKey: idempotencyKey));
}

class FirebaseTableRepository implements TableRepository {
  FirebaseTableRepository(this._ctx);
  final FirebaseContext _ctx;

  @override
  String? get myUid => _ctx.uid;

  /// `tables/{id}` with metadata (fromCache → [TableState.fromCache] and the
  /// connection monitor). A missing doc is a notFound error.
  @override
  Stream<TableState> watchTable(String tableId) => guardStream(
        _ctx.doc(FirestorePaths.table(tableId)).snapshots(includeMetadataChanges: true).map((s) {
          final fromCache = s.metadata.isFromCache;
          _ctx.monitor.reportSnapshot(fromCache: fromCache);
          if (!s.exists) {
            throw RepositoryException(
                failureForReason(ServerReason.TABLE_NOT_FOUND), 'table $tableId', ServerReason.TABLE_NOT_FOUND);
          }
          return TableState.fromDoc(tableId, jsonOf(s.data()), fromCache: fromCache);
        }),
      );

  @override
  Future<void> placeBet(String tableId, int handNumber, int amountCents, {required String idempotencyKey}) =>
      _ctx.call('placeBet', Payloads.placeBet(tableId, handNumber, amountCents), idempotencyKey: idempotencyKey);

  @override
  Future<void> act(
    String tableId,
    int handNumber,
    PlayerAction action, {
    int? handIndex,
    int? amountCents,
    PowerType? power,
    required String idempotencyKey,
  }) =>
      _ctx.call(
        'act',
        Payloads.act(tableId, handNumber, action, handIndex: handIndex, amountCents: amountCents, power: power),
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<bool> poke(String tableId) async =>
      PokeResult.fromResponse(await _ctx.call('pokeTable', Payloads.pokeTable(tableId), idempotencyKey: newIdempotencyKey()))
          .advanced;

  @override
  Future<int> leave(String tableId) async {
    final r = await _ctx.call('leaveTable', Payloads.leaveTable(tableId), idempotencyKey: newIdempotencyKey());
    final refunded = r['refundedCents'];
    return refunded is num ? refunded.toInt() : 0;
  }

  @override
  Stream<PeekResult?> watchPeek(String tableId) => _ctx.perUser<PeekResult?>(
        (uid) => _ctx.docData(FirestorePaths.peek(tableId, uid)).map((d) => d == null ? null : PeekResult.fromDoc(d)),
        null,
      );

  @override
  Stream<List<HandHistory>> watchHistory(String tableId, {int limit = 20}) => _ctx
      .queryDocs(_ctx.col(FirestorePaths.hands(tableId)).orderBy('handNumber', descending: true).limit(limit))
      .map((docs) => [for (final (_, d) in docs) HandHistory.fromDoc(d)]);
}
