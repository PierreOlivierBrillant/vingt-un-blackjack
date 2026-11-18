import '../../domain/backend_constants.dart';
import '../../domain/lmsr.dart';
import '../../domain/models.dart';
import '../repositories.dart';
import '../server_errors.dart';
import 'backend_api.dart';
import 'firebase_context.dart';
import 'firebase_errors.dart';

/// Order-ticket quote from a market doc with the exact server LMSR; LMSR
/// errors become the server's reasons (pure; unit-tested).
TradeQuote quoteForMarket(Market m, Outcome outcome, int shares, {required bool buy}) {
  RepositoryException err(ServerReason r) => RepositoryException(failureForReason(r), null, r);
  if (!m.isOpen) throw err(ServerReason.MARKET_CLOSED);
  if (shares < 1 || shares > Backend.marketMaxSharesPerTrade) throw err(ServerReason.INVALID_ARGUMENT);
  try {
    return TradeQuote.compute(LmsrState.ofMarket(m), outcome, shares, buy: buy);
  } on LmsrException catch (e) {
    throw err(e.code == LmsrErrorCode.marketLimit ? ServerReason.MARKET_LIMIT : ServerReason.INVALID_ARGUMENT);
  }
}

class FirebaseMarketsRepository implements MarketsRepository {
  FirebaseMarketsRepository(this._ctx);
  final FirebaseContext _ctx;

  /// Latest market docs seen by any listener (quotes use the live state).
  final _latest = <String, Market>{};

  List<Market> _parse(List<(String, Json)> docs) => [
        for (final (id, d) in docs)
          if (Market.fromDoc(d, id: id) case final m?) _latest[m.id] = m,
      ];

  @override
  Stream<List<Market>> watchMarkets() => _ctx.perUser(
        (_) => _ctx
            .queryDocs(_ctx
                .col(FirestorePaths.markets)
                .where('status', isEqualTo: 'open')
                .orderBy('createdAtMs', descending: true)
                .limit(QueryLimits.openMarkets))
            .map(_parse),
        const [],
      );

  @override
  Stream<List<Market>> watchMarketsForTable(String tableId) => _ctx.perUser(
        (_) => _ctx
            .queryDocs(_ctx
                .col(FirestorePaths.markets)
                .where('tableId', isEqualTo: tableId)
                .orderBy('createdAtMs', descending: true)
                .limit(QueryLimits.tableMarkets))
            .map(_parse),
        const [],
      );

  @override
  Stream<Market> watchMarket(String marketId) => _ctx.docData(FirestorePaths.market(marketId)).map((d) {
        final m = d == null ? null : Market.fromDoc(d, id: marketId);
        if (m == null) {
          throw RepositoryException(
              failureForReason(ServerReason.MARKET_NOT_FOUND), marketId, ServerReason.MARKET_NOT_FOUND);
        }
        return _latest[marketId] = m;
      });

  @override
  Stream<List<PricePoint>> watchPriceHistory(String marketId) => _ctx
      .queryDocs(_ctx.col(FirestorePaths.priceHistory(marketId)).orderBy('atMs').limitToLast(QueryLimits.priceHistory))
      .map((docs) => [for (final (_, d) in docs) PricePoint.fromDoc(d)]);

  @override
  Stream<List<MarketPosition>> watchPositions() => _ctx.perUser(
        (uid) => _ctx.queryDocs(_ctx.col(FirestorePaths.positions(uid))).map((docs) {
          final list = [for (final (id, d) in docs) MarketPosition.fromDoc(d, id: id)]
            ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
          return list;
        }),
        const [],
      );

  @override
  Stream<List<MarketTrade>> watchActivity(String marketId, {int limit = 30}) => _ctx
      .queryDocs(_ctx.col(FirestorePaths.trades(marketId)).orderBy('createdAtMs', descending: true).limit(limit))
      .map((docs) => [for (final (id, d) in docs) ?MarketTrade.fromDoc(d, id: id)]);

  Future<Market> _market(String id) async {
    final cached = _latest[id];
    if (cached != null) return cached;
    try {
      final snap = await _ctx.doc(FirestorePaths.market(id)).get();
      final m = snap.exists ? Market.fromDoc(jsonOf(snap.data()), id: id) : null;
      if (m == null) {
        throw RepositoryException(failureForReason(ServerReason.MARKET_NOT_FOUND), id, ServerReason.MARKET_NOT_FOUND);
      }
      return _latest[id] = m;
    } on Object catch (e) {
      throw toRepositoryException(e);
    }
  }

  @override
  Future<TradeQuote> quote(String marketId, Outcome outcome, int shares, {required bool buy}) async =>
      quoteForMarket(await _market(marketId), outcome, shares, buy: buy);

  /// When the caller gives no guard, the quote at the latest known state is
  /// sent as `maxCostCents` / `minProceedsCents` (SLIPPAGE if it moved).
  @override
  Future<TradeResult> trade(
    String marketId,
    Outcome outcome,
    int shares, {
    required bool buy,
    int? maxCostCents,
    int? minProceedsCents,
    required String idempotencyKey,
  }) async {
    var maxCost = maxCostCents;
    var minProceeds = minProceedsCents;
    if ((buy && maxCost == null) || (!buy && minProceeds == null)) {
      final q = quoteForMarket(await _market(marketId), outcome, shares, buy: buy);
      if (buy) {
        maxCost = q.amountCents;
      } else {
        minProceeds = q.amountCents;
      }
    }
    return TradeResult.fromResponse(await _ctx.call(
      'tradeShares',
      Payloads.tradeShares(marketId, outcome, shares, buy: buy, maxCostCents: maxCost, minProceedsCents: minProceeds),
      idempotencyKey: idempotencyKey,
    ));
  }
}
