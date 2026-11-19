import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/money.dart';
import 'package:vingtun/data/error_messages.dart';
import 'package:vingtun/data/fake/fake_repositories.dart';
import 'package:vingtun/data/providers.dart';
import 'package:vingtun/data/server_errors.dart';
import 'package:vingtun/domain/backend_constants.dart';
import 'package:vingtun/domain/fairness.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/domain/table_state.dart';
import 'package:vingtun/features/table/table_screen.dart';

import '../helpers.dart';
import '../table_fixtures.dart';

final _nowMs = kTestNow.millisecondsSinceEpoch;

class _RejectingTableRepository extends FakeTableRepository {
  _RejectingTableRepository({super.doc}) : super(myUid: 'me');
  @override
  Future<void> act(String tableId, int handNumber, PlayerAction action,
      {int? handIndex, int? amountCents, PowerType? power, required String idempotencyKey}) async {
    calls.add('act:${action.name}');
    throw mapServerError('failed-precondition', {'reason': 'NOT_YOUR_TURN'});
  }
}

/// One finished hand whose proof is the backend-computed vector of
/// `fairness_and_wire_test.dart`.
class _HistoryTableRepository extends FakeTableRepository {
  _HistoryTableRepository({super.doc}) : super(myUid: 'me');
  @override
  Stream<List<HandHistory>> watchHistory(String tableId, {int limit = 20}) {
    final shoe = buildWireShoe(6);
    final remaining = [for (var i = 0; i < shoe.length; i++) if (i % 3 != 0) shoe[i]].take(120).toList().reversed.toList();
    return Stream.value([
      HandHistory.fromDoc({
        'tableId': 'tbl', 'handNumber': 7, 'startedAtMs': 1, 'endedAtMs': 2, 'dealerCards': ['8S'], 'dealerTotal': 8,
        'seats': <Object?>[],
        'fairness': {
          'commit': '1309f953015195d9eadc0455c1e42a5cfc463d4cad90c0cc940ff77b5f1633bd',
          'seed': 'a3f1c2d4e5b60718293a4b5c6d7e8f90112233445566778899aabbccddeeff00',
          'remainingBefore': remaining,
          'dealt': ['8S', '2S', '6H', '5S', '8S', '2D', 'JD', '8S', '9H', 'KC', '8C', 'QD'],
        },
      }),
    ]);
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<FakeTableRepository> pumpTable(WidgetTester tester, Map<String, Object?> doc,
    {String myUid = 'me', FakeTableRepository? repo}) async {
  usePhoneSurface(tester);
  final r = repo ?? FakeTableRepository(myUid: myUid, doc: doc);
  await pumpScreen(
    tester,
    const TableScreen(tableId: 'tbl', interstitialEvery: 0),
    overrides: [tableRepositoryProvider.overrideWithValue(r)],
  );
  return r;
}

Map<String, Object?> myTurn(List<String> cards, {String phase = 'playerTurns'}) => tableDoc(
      phase: phase,
      seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(cards)])],
      dealerCards: ['9D'],
      holeHidden: true,
      turn: {'seatIndex': 0, 'handIndex': 0},
      deadlineMs: _nowMs + 15000,
      eventSeq: 9,
    );

void main() {
  final l = l10nOf(const Locale('fr'));

  testWidgets('betting: chips add up and the bet is sent in whole dollars', (tester) async {
    final repo = await pumpTable(
      tester,
      tableDoc(seats: [seatDoc(0, 'me')], deadlineMs: _nowMs + 12000, eventSeq: 3),
    );
    expect(find.textContaining(l.tableBetting(12)), findsOneWidget);
    await tester.tap(find.byKey(const Key('chip-500')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('chip-500')));
    await tester.pump();
    expect(find.text(l.tablePlaceBet(formatCents(1000, locale: 'fr'))), findsOneWidget);
    await tester.tap(find.byKey(const Key('bet-place')));
    await tester.pump();
    expect(repo.calls, ['bet:1000']);
  });

  testWidgets('my turn on a pair: split / double / surrender are enabled', (tester) async {
    final repo = await pumpTable(tester, myTurn(['8S', '8H']));
    for (final a in ['hit', 'stand', 'double', 'split', 'surrender']) {
      expect(tester.widget<ButtonStyleButton>(find.byKey(Key('action-$a'))).onPressed, isNotNull, reason: a);
    }
    await tester.tap(find.byKey(const Key('action-split')));
    await tester.pump();
    expect(repo.calls, ['act:split']);
  });

  testWidgets('three cards: only hit and stand', (tester) async {
    await pumpTable(tester, myTurn(['5S', '3H', '2C']));
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('action-hit'))).onPressed, isNotNull);
    for (final a in ['double', 'split', 'surrender']) {
      expect(tester.widget<ButtonStyleButton>(find.byKey(Key('action-$a'))).onPressed, isNull, reason: a);
    }
  });

  testWidgets('an armed power is sent with the next compatible action', (tester) async {
    final repo = await pumpTable(tester, myTurn(['8S', '8H']));
    await tester.tap(find.byKey(const Key('table-powers')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('power-freeSplit')));
    await settle(tester);
    expect(find.text(l.tablePowerArmed(l.powerFreeSplit)), findsOneWidget);
    await tester.tap(find.byKey(const Key('action-hit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('action-split')));
    await tester.pump();
    // Not applicable to hit; consumed by split.
    expect(repo.calls, ['act:hit', 'act:split+freeSplit']);
  });

  testWidgets('insurance: take the maximum or decline', (tester) async {
    final repo = await pumpTable(
      tester,
      tableDoc(
        phase: 'insurance',
        seats: [
          seatDoc(0, 'me', bet: 1000, hands: [handDoc(['9S', '7H'])], insurance: {'betCents': 0, 'stakedCents': 0, 'decided': false, 'result': null}),
        ],
        dealerCards: ['AD'],
        holeHidden: true,
        deadlineMs: _nowMs + 15000,
        eventSeq: 9,
      ),
    );
    expect(find.text(l.tableInsuranceTake(formatCents(500, locale: 'fr'))), findsOneWidget);
    await tester.tap(find.byKey(const Key('insurance-take')));
    await tester.pump();
    expect(repo.calls, ['act:insurance']);
  });

  testWidgets('spectator: no action bar, markets of the table instead', (tester) async {
    await pumpTable(tester, myTurn(['8S', '8H']), myUid: 'someone-else');
    expect(find.text(l.tableSpectating), findsOneWidget);
    expect(find.byKey(const Key('action-hit')), findsNothing);
    expect(find.byKey(const Key('spectator-markets')), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget); // closes without leaving
  });

  testWidgets('queued player sees the queue notice', (tester) async {
    await pumpTable(
      tester,
      tableDoc(
        phase: 'playerTurns',
        seats: [seatDoc(0, 'bot', bot: true, bet: 500, hands: [handDoc(['8S', '8H'], bet: 500)])],
        queue: [{'uid': 'me', 'username': 'Moi'}],
        deadlineMs: _nowMs + 1000,
        eventSeq: 4,
      ),
    );
    expect(find.text(l.tableQueued), findsOneWidget);
  });

  testWidgets('overdue deadline: the client pokes the table', (tester) async {
    final repo = await pumpTable(tester, myTurn(['8S', '8H'])..['deadlineMs'] = _nowMs - Backend.pokeGraceMs - 500);
    await settle(tester);
    expect(repo.calls, contains('poke'));
  });

  testWidgets('server refusal is shown, localized', (tester) async {
    final doc = myTurn(['8S', '8H']);
    await pumpTable(tester, doc, repo: _RejectingTableRepository(doc: doc));
    await tester.tap(find.byKey(const Key('action-stand')));
    await tester.pump();
    await tester.pump();
    expect(find.text(localizeError(l, mapServerError('failed-precondition', {'reason': 'NOT_YOUR_TURN'}))), findsOneWidget);
    expect(find.text(l.errReasonNotYourTurn), findsOneWidget);
  });

  testWidgets('fairness sheet re-computes the last hand locally', (tester) async {
    final doc = myTurn(['8S', '8H']);
    await pumpTable(tester, doc, repo: _HistoryTableRepository(doc: doc));
    await tester.tap(find.byKey(const Key('table-fairness')));
    await settle(tester);
    expect(find.text(l.fairLastHand(7)), findsOneWidget);
    await tester.tap(find.byKey(const Key('fair-verify')));
    await settle(tester);
    expect(find.text(l.fairVerified(12)), findsOneWidget);
  });

  testWidgets('fairness sheet shows the current commitment', (tester) async {
    await pumpTable(tester, myTurn(['8S', '8H']));
    await tester.tap(find.byKey(const Key('table-fairness')));
    await settle(tester);
    expect(find.text('abc'), findsOneWidget);
    expect(find.text(l.fairNoHistory), findsOneWidget);
  });
}
