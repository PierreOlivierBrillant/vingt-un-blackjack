/// Kernel-driven game tables on Firebase (`shared/games/common.ts`).
library;

import '../../core/ids.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../repositories.dart';
import '../server_errors.dart';
import 'backend_api.dart';
import 'firebase_context.dart';
import 'firebase_errors.dart';

class FirebaseGameTableRepository implements GameTableRepository {
  FirebaseGameTableRepository(this._ctx);
  final FirebaseContext _ctx;

  @override
  String? get myUid => _ctx.uid;

  /// Needs the composite index (game, status, isPrivate, updatedAtMs desc) on
  /// `gameTables` (requested in tools/sprint2/requests/a2.md; the emulator
  /// does not require it).
  @override
  Stream<List<LiveTable>> watchLiveTables(GameId game, {String? tierId}) {
    if (!game.isKernel) return Stream.value(const []);
    return _ctx.perUser(
      (_) => _ctx
          .queryDocs(_ctx
              .col(FirestorePaths.gameTables)
              .where('game', isEqualTo: game.wire)
              .where('status', isEqualTo: 'open')
              .where('isPrivate', isEqualTo: false)
              .orderBy('updatedAtMs', descending: true)
              .limit(QueryLimits.lobbyTables))
          .map((docs) => [
                for (final (id, d) in docs)
                  if (tierId == null || d['stakeTier'] == tierId) LiveTable.fromDoc(d, id: id),
              ]),
      const [],
    );
  }

  @override
  Stream<GameTableState> watchTable(String tableId) => guardStream(
        _ctx.doc(FirestorePaths.gameTable(tableId)).snapshots(includeMetadataChanges: true).map((s) {
          final fromCache = s.metadata.isFromCache;
          _ctx.monitor.reportSnapshot(fromCache: fromCache);
          if (!s.exists) {
            throw RepositoryException(
                failureForReason(ServerReason.TABLE_NOT_FOUND), 'table $tableId', ServerReason.TABLE_NOT_FOUND);
          }
          return GameTableState.fromDoc(tableId, jsonOf(s.data()), fromCache: fromCache);
        }),
      );

  @override
  Stream<List<GameBet>> watchBets(String tableId) => _ctx
      .queryDocs(_ctx.col(FirestorePaths.gameBets(tableId)))
      .map((docs) => [for (final (id, d) in docs) GameBet.fromDoc(d, id: id)]);

  @override
  Stream<GameHole?> watchMyHole(String tableId) => _ctx.perUser<GameHole?>(
        (uid) => _ctx.docData(FirestorePaths.gameHole(tableId, uid)).map((d) => d == null ? null : GameHole.fromDoc(d)),
        null,
      );

  @override
  Stream<List<GameRound>> watchRounds(String tableId, {int limit = 20}) => _ctx
      .queryDocs(_ctx.col(FirestorePaths.gameRounds(tableId)).orderBy('round', descending: true).limit(limit))
      .map((docs) => [for (final (id, d) in docs) GameRound.fromDoc(d, id: id)]);

  @override
  Future<GameJoinResult> join({
    required GameId game,
    required GameJoinMode mode,
    String stakeTier = 'low',
    String? code,
    int? buyInCents,
    required String idempotencyKey,
  }) async =>
      GameJoinResult.fromResponse(await _ctx.call(
        'gameJoin',
        Payloads.gameJoin(game, mode, stakeTier, code: code, buyInCents: buyInCents),
        idempotencyKey: idempotencyKey,
      ));

  @override
  Future<GameLeaveResult> leave(String tableId) async => GameLeaveResult.fromResponse(
      await _ctx.call('gameLeave', Payloads.gameLeave(tableId), idempotencyKey: newIdempotencyKey()));

  @override
  Future<GameActionResult> act(String tableId, int round, Map<String, Object?> action, {required String idempotencyKey}) async =>
      GameActionResult.fromResponse(
          await _ctx.call('gameAction', Payloads.gameAction(tableId, round, action), idempotencyKey: idempotencyKey));

  @override
  Future<GameActionResult> setBets(String tableId, int round, Map<String, int> bets, {PowerType? power, required String idempotencyKey}) =>
      act(tableId, round, Payloads.setBetsAction(bets, power: power), idempotencyKey: idempotencyKey);

  @override
  Future<GamePokeResult> poke(String tableId) async => GamePokeResult.fromResponse(
      await _ctx.call('gamePoke', Payloads.gamePoke(tableId), idempotencyKey: newIdempotencyKey()));
}
