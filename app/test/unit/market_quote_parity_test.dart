import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/bootstrap/firebase_backend.dart';
import 'package:vingtun/data/firebase/firebase_markets_repository.dart';
import 'package:vingtun/domain/models.dart';

void main() {
  test('order ticket quote = server LMSR on a real shoe market doc (integers from Firestore)', () {
    // Shape read from the emulator (`markets/sim-01__s3__shoe`); the server's
    // `quoteBuy({b:200,qYes:75,qNo:100}, 'yes', 10)` returns 476 cents,
    // priceYesAfter 0.4812587841214648 (computed with lib/market/lmsr.js).
    final m = Market.fromDoc({
      'marketId': 'sim-01__s3__shoe', 'tableId': 'sim-01', 'tableName': 'Monte-Carlo', 'kind': 'shoeDealerBustRate',
      'handNumber': null, 'shoeNumber': 3, 'status': 'open', 'outcome': null, 'b': 200, 'qYes': 75, 'qNo': 100,
      'priceYes': 0.46879062662624377, 'volumeCents': 8797, 'tradeCount': 15, 'payoutsDone': false,
      'createdAtMs': 1795096986194,
    })!;
    final q = quoteForMarket(m, Outcome.yes, 10, buy: true);
    expect(q.amountCents, 476);
    expect(q.priceYesAfter, closeTo(0.4812587841214648, 1e-12));
  });

  test('the demo API key has the shape the Android SDK requires (AIza + 35 chars)', () {
    expect(RegExp(r'^AIza[0-9A-Za-z_-]{35}$').hasMatch(kDemoFirebaseOptions.apiKey), isTrue);
    expect(kDemoFirebaseOptions.projectId, startsWith('demo-'));
  });
}
