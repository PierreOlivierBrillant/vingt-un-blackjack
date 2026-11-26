// Backend-shaped hold'em documents (shared/games/holdem.ts) for the hold'em
// unit, widget and golden tests, and a repository whose table can be pushed
// snapshot by snapshot (animations) and whose rounds / hole cards are set.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vingtun/data/fake/fake_data.dart';
import 'package:vingtun/data/fake/fake_game_repository.dart';
import 'package:vingtun/domain/fairness.dart';
import 'package:vingtun/domain/game_table.dart';
import 'package:vingtun/features/games/holdem/holdem_evaluator.dart';

import 'helpers.dart';

const kHoldemTableId = 'ho-test';

/// The shared TypeScript ⇄ Dart vectors.
Map<String, Object?> holdemVectors() {
  final f = [File('assets/fairness/holdem_vectors.json'), File('app/assets/fairness/holdem_vectors.json')].firstWhere((f) => f.existsSync());
  return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
}

int _ms(DateTime t) => t.millisecondsSinceEpoch;

Map<String, Object?> _seat(int i, String uid, String name, {bool bot = false, int stack = 20000, String status = 'active', Map<String, Object?> g = const {}, int? net}) => {
      'seatIndex': i,
      'uid': uid,
      'username': name,
      'avatar': 'avatar0${(i % 8) + 1}',
      'isBot': bot,
      'rankTier': 'silver',
      'status': status,
      'joinedAtMs': _ms(kTestNow.subtract(Duration(minutes: 10 + i))),
      'missedRounds': 0,
      'stakeCents': 0,
      'stackCents': stack,
      'powerUsed': null,
      'roundNetCents': net,
      'g': {
        'inHand': true,
        'folded': false,
        'allIn': false,
        'betCents': 0,
        'committedCents': 200,
        'acted': false,
        'actSeq': 0,
        'actLevel': 0,
        'lastAction': null,
        'waitBB': false,
        'timeouts': 0,
        'handsOut': 0,
        'shown': null,
        ...g,
      },
    };

Map<String, Object?> _table({
  required String phase,
  required String? step,
  required List<Map<String, Object?>?> seats,
  required Map<String, Object?> g,
  int? turn,
  int round = 7,
  List<Map<String, Object?>> events = const [],
  Duration deadlineIn = const Duration(seconds: 14),
  String id = kHoldemTableId,
}) {
  final taken = seats.whereType<Map<String, Object?>>().toList();
  return {
    'tableId': id,
    'game': 'holdem',
    'name': "Hold'em Onyx",
    'stakeTier': 'low',
    'limits': {
      'minBetCents': 200,
      'maxBetCents': 20000,
      'maxRoundCents': 20000,
      'extra': {'smallBlindCents': 100, 'bigBlindCents': 200, 'minBuyInCents': 8000, 'maxBuyInCents': 20000},
    },
    'isPrivate': false,
    'simManaged': false,
    'status': 'open',
    'phase': phase,
    'step': step,
    'phaseStartedAtMs': _ms(kTestNow.subtract(const Duration(seconds: 6))),
    'deadlineMs': phase == 'idle' ? null : _ms(kTestNow.add(deadlineIn)),
    'round': round,
    'turn': turn == null ? null : {'seatIndex': turn},
    'seats': seats,
    'queue': <Object?>[],
    'seatedUids': [for (final s in taken) s['uid']],
    'humanCount': taken.where((s) => s['isBot'] != true).length,
    'botCount': taken.where((s) => s['isBot'] == true).length,
    'rankTier': 'silver',
    'dealer': {'characterId': 'alex'},
    'fairness': {
      'currentCommit': sha256Hex('seed-$round'),
      'currentHandNumber': round,
      'lastHandNumber': phase == 'settled' ? round : round - 1,
      'lastCommit': sha256Hex('seed-${round - 1}'),
      'lastSeed': 'seed-${round - 1}',
    },
    'events': [
      for (var i = 0; i < events.length; i++) {'seq': i + 1, 'atMs': _ms(kTestNow.subtract(Duration(seconds: 20 - i))), 'seatIndex': null, 'd': null, ...events[i]},
    ],
    'eventSeq': events.length,
    'markets': {
      'round': {'holdemBoardAce': '${id}__r${round}__holdemBoardAce'},
      'series': <String, Object?>{},
    },
    'g': g,
    'createdAtMs': _ms(kTestNow.subtract(const Duration(hours: 1))),
    'updatedAtMs': _ms(kTestNow.subtract(const Duration(seconds: 2))),
  };
}

/// Preflop events of the fixture hand (button 3, SB 5, BB 0 = me).
const kHoldemPreflopEvents = <Map<String, Object?>>[
  {'type': 'button', 'd': {'button': 3, 'sb': 5, 'bb': 0, 'order': [5, 0, 1, 2, 3]}},
  {'type': 'blind', 'seatIndex': 5, 'd': {'kind': 'sb', 'cents': 100, 'allIn': false}},
  {'type': 'blind', 'seatIndex': 0, 'd': {'kind': 'bb', 'cents': 200, 'allIn': false}},
  {'type': 'deal', 'd': {'order': [5, 0, 1, 2, 3]}},
  {'type': 'call', 'seatIndex': 1, 'd': {'cents': 200, 'toCents': 200, 'allIn': false}},
  {'type': 'call', 'seatIndex': 2, 'd': {'cents': 200, 'toCents': 200, 'allIn': false}},
  {'type': 'call', 'seatIndex': 3, 'd': {'cents': 200, 'toCents': 200, 'allIn': false}},
  {'type': 'call', 'seatIndex': 5, 'd': {'cents': 100, 'toCents': 200, 'allIn': false}},
  {'type': 'check', 'seatIndex': 0},
];

/// Flop events after [kHoldemPreflopEvents]: collect, burn, flop, seat 5 bets $6.
const kHoldemFlopEvents = <Map<String, Object?>>[
  {'type': 'collect', 'd': {'potCents': 1000, 'pots': [{'cents': 1000, 'eligible': [5, 0, 1, 2, 3]}]}},
  {'type': 'burn', 'd': {'street': 'flop'}},
  {'type': 'flop', 'd': {'cards': ['AH', '7C', '2D']}},
  {'type': 'bet', 'seatIndex': 5, 'd': {'cents': 600, 'toCents': 600, 'allIn': false}},
];

List<Map<String, Object?>?> _flopSeats({String myStatus = 'active', bool meInHand = true}) => [
      _seat(0, FakeData.demoUid, FakeData.demoUsername, stack: 19800, status: myStatus, g: {'inHand': meInHand, 'lastAction': 'check', 'committedCents': 200}),
      _seat(1, 'bot_7', 'Ada', bot: true, stack: 15400, g: {'lastAction': 'call'}),
      _seat(2, 'u-guest-luna', 'LunaRiver', stack: 9800, g: {'lastAction': 'call'}),
      _seat(3, 'bot_14', 'soft17', bot: true, stack: 31000, g: {'lastAction': 'call'}),
      null,
      _seat(5, 'bot_21', 'rouge_noir', bot: true, stack: 12200, g: {'lastAction': 'bet', 'betCents': 600, 'committedCents': 800, 'acted': true, 'actSeq': 1, 'actLevel': 600}),
    ];

/// The flop, my turn facing a $6 bet (pot $10): call $6, raise $12..$198.
Map<String, Object?> holdemFlopDoc({int round = 7, bool myTurn = true}) => _table(
      phase: 'live',
      step: 'flop',
      turn: myTurn ? 0 : 1,
      round: round,
      seats: _flopSeats(),
      events: [...kHoldemPreflopEvents, ...kHoldemFlopEvents],
      g: {
        'button': 3,
        'sb': 5,
        'bb': 0,
        'order': [5, 0, 1, 2, 3],
        'board': ['AH', '7C', '2D'],
        'potCents': 1000,
        'pots': [
          {'cents': 1000, 'eligible': [5, 0, 1, 2, 3]},
        ],
        'currentBetCents': 600,
        'minRaiseCents': 600,
        'fullRaiseSeq': 1,
        'toAct': myTurn ? {'seat': 0, 'callCents': 600, 'kind': 'raise', 'minToCents': 1200, 'maxToCents': 19800} : {'seat': 1, 'callCents': 600, 'kind': 'raise', 'minToCents': 1200, 'maxToCents': 15400},
        'result': null,
      },
    );

/// The same table one snapshot earlier (preflop, before the flop events).
Map<String, Object?> holdemPreflopDoc({int round = 7}) {
  final d = holdemFlopDoc(round: round);
  final g = {...(d['g']! as Map).cast<String, Object?>()};
  g
    ..['board'] = <String>[]
    ..['potCents'] = 0
    ..['pots'] = <Object?>[]
    ..['currentBetCents'] = 200
    ..['minRaiseCents'] = 200
    ..['toAct'] = {'seat': 0, 'callCents': 0, 'kind': 'raise', 'minToCents': 400, 'maxToCents': 20000};
  final seats = [
    for (final s in (d['seats']! as List).cast<Map<String, Object?>?>())
      if (s == null) null else {...s, 'g': {...(s['g']! as Map).cast<String, Object?>(), 'betCents': 200, 'lastAction': s['seatIndex'] == 0 ? 'bb' : 'call'}},
  ];
  final events = (d['events']! as List).take(kHoldemPreflopEvents.length - 1).toList();
  return {...d, 'step': 'preflop', 'g': g, 'seats': seats, 'events': events, 'eventSeq': events.length};
}

/// A settled showdown: me (A♠ K♦) beats LunaRiver (Q♥ Q♠) on A♥ 7♣ 2♦ K♣ 9♠.
Map<String, Object?> holdemShowdownDoc() {
  const board = ['AH', '7C', '2D', 'KC', '9S'];
  final mine = evaluateHoldemHand(['AS', 'KD', ...board]);
  final luna = evaluateHoldemHand(['QH', 'QS', ...board]);
  Map<String, Object?> hand(HandValue v, List<String> cards) => {'cards': cards, 'category': v.category.name, 'score': v.score, 'best': v.best};
  return _table(
    phase: 'settled',
    step: 'showdown',
    deadlineIn: const Duration(seconds: 6),
    seats: [
      _seat(0, FakeData.demoUid, FakeData.demoUsername, stack: 22800, net: 2200, g: {'lastAction': 'call', 'committedCents': 2200, 'shown': ['AS', 'KD']}),
      _seat(1, 'bot_7', 'Ada', bot: true, stack: 15200, net: -200, g: {'folded': true, 'lastAction': 'fold'}),
      _seat(2, 'u-guest-luna', 'LunaRiver', stack: 7800, net: -2200, g: {'lastAction': 'bet', 'committedCents': 2200, 'shown': ['QH', 'QS']}),
      null,
      null,
      _seat(5, 'bot_21', 'rouge_noir', bot: true, stack: 11800, net: -200, g: {'folded': true, 'lastAction': 'fold'}),
    ],
    events: [
      ...kHoldemPreflopEvents.take(4),
      {'type': 'showdown', 'd': {'hands': {'0': hand(mine, ['AS', 'KD']), '2': hand(luna, ['QH', 'QS'])}}},
      {'type': 'win', 'seatIndex': 0, 'd': {'cents': 4800, 'pot': 0, 'category': mine.category.name}},
    ],
    g: {
      'button': 3,
      'sb': 5,
      'bb': 0,
      'order': [5, 0, 1, 2],
      'board': board,
      'potCents': 0,
      'pots': <Object?>[],
      'currentBetCents': 0,
      'minRaiseCents': 200,
      'fullRaiseSeq': 0,
      'toAct': null,
      'result': {
        'button': 3,
        'sb': 5,
        'bb': 0,
        'smallBlindCents': 100,
        'bigBlindCents': 200,
        'order': [5, 0, 1, 2],
        'board': board,
        'boardShown': 5,
        'potCents': 4800,
        'pots': [
          {'cents': 4800, 'eligible': [0, 2], 'winners': [0]},
        ],
        'hands': {'0': hand(mine, ['AS', 'KD']), '2': hand(luna, ['QH', 'QS'])},
        'winners': [0],
        'showdown': true,
      },
    },
  );
}

/// Step 'waiting': I am out of chips, a bot waits (rebuy available).
Map<String, Object?> holdemWaitingDoc() => _table(
      phase: 'live',
      step: 'waiting',
      seats: [
        _seat(0, FakeData.demoUid, FakeData.demoUsername, stack: 0, g: {'inHand': false, 'committedCents': 0}),
        _seat(1, 'bot_7', 'Ada', bot: true, stack: 24000, g: {'inHand': false, 'committedCents': 0}),
        null,
        null,
        null,
        null,
      ],
      events: [
        {'type': 'waiting', 'd': <String, Object?>{}},
      ],
      g: {
        'button': 1,
        'sb': 1,
        'bb': 0,
        'order': <int>[],
        'board': <String>[],
        'potCents': 0,
        'pots': <Object?>[],
        'currentBetCents': 0,
        'minRaiseCents': 200,
        'fullRaiseSeq': 0,
        'toAct': null,
        'result': null,
      },
    );

/// A finished round built from a shared vector deal (every hand at the showdown).
Map<String, Object?> holdemRoundFromVector(Map<String, Object?> v, {int round = 6, String tableId = kHoldemTableId}) {
  final order = [for (final s in v['order']! as List) s as int];
  final hands = (v['hands']! as Map).cast<String, Object?>();
  final holes = (v['holes']! as Map).cast<String, Object?>();
  final winners = [for (final s in v['winners']! as List) s as int];
  final names = ['Joueur21', 'Ada', 'LunaRiver', 'soft17', 'max_dbl', 'rouge_noir'];
  return {
    'tableId': tableId,
    'game': 'holdem',
    'round': round,
    'startedAtMs': _ms(kTestNow.subtract(const Duration(minutes: 2))),
    'endedAtMs': _ms(kTestNow.subtract(const Duration(minutes: 1))),
    'seats': [
      for (final s in order)
        {
          'seatIndex': s,
          'uid': s == 0 ? FakeData.demoUid : 'u-$s',
          'username': names[s],
          'isBot': s.isOdd,
          'stakedCents': 1000,
          'netCents': winners.contains(s) ? 1000 * (order.length - winners.length) ~/ winners.length : -1000,
        },
    ],
    'result': {
      'button': order.last,
      'sb': order.first,
      'bb': order[1],
      'smallBlindCents': 100,
      'bigBlindCents': 200,
      'order': order,
      'board': v['board'],
      'boardShown': 5,
      'potCents': 1000 * order.length,
      'pots': [
        {'cents': 1000 * order.length, 'eligible': order, 'winners': winners},
      ],
      'hands': {
        for (final s in order)
          '$s': {...(hands['$s']! as Map).cast<String, Object?>(), 'cards': holes['$s']},
      },
      'winners': winners,
      'showdown': true,
    },
    'fairness': {
      'commit': v['commit'],
      'seed': v['seed'],
      'remainingBefore': buildWireShoe(1),
      'dealt': v['dealt'],
      'decks': 1,
    },
  };
}

/// A [FakeGameTableRepository] whose table snapshots are pushed by the test.
class HoldemTestRepo extends FakeGameTableRepository {
  HoldemTestRepo(Map<String, Object?> doc, {this.hole = const ['AS', 'KD'], this.rounds = const []})
      : _doc = doc,
        super(now: () => kTestNow, docs: {doc['tableId']! as String: doc});

  Map<String, Object?> _doc;
  final List<String>? hole;
  final List<Map<String, Object?>> rounds;
  final _ctl = StreamController<GameTableState>.broadcast();

  /// Every action sent (whole maps).
  final actions = <Map<String, Object?>>[];

  @override
  Stream<GameTableState> watchTable(String tableId) async* {
    yield GameTableState.fromDoc(tableId, _doc);
    yield* _ctl.stream;
  }

  /// A new server snapshot.
  void push(Map<String, Object?> doc) {
    _doc = doc;
    _ctl.add(GameTableState.fromDoc(doc['tableId']! as String, doc));
  }

  @override
  Stream<GameHole?> watchMyHole(String tableId) =>
      Stream.value(hole == null ? null : GameHole(round: (_doc['round'] as int?) ?? 0, cards: hole!));

  @override
  Stream<List<GameRound>> watchRounds(String tableId, {int limit = 20}) => Stream.value([for (final r in rounds) GameRound.fromDoc(r)]);

  @override
  Future<GameActionResult> act(String tableId, int round, Map<String, Object?> action, {required String idempotencyKey}) {
    actions.add(action);
    return super.act(tableId, round, action, idempotencyKey: idempotencyKey);
  }
}
