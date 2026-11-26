// Hold'em client logic: the evaluator and the fairness verifier against the
// vectors computed by the backend (assets/fairness/holdem_vectors.json), the
// raise slider maths, tolerant parsing, hand names, history / profile lines,
// and the stage scene (events → props, reconciliation, cues).
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/fairness.dart';
import 'package:vingtun/domain/game_table.dart';
import 'package:vingtun/domain/models.dart' show PowerType;
import 'package:vingtun/features/games/common/game_table_view.dart';
import 'package:vingtun/features/games/holdem/holdem_evaluator.dart';
import 'package:vingtun/features/games/holdem/holdem_fairness.dart';
import 'package:vingtun/features/games/holdem/holdem_game.dart';
import 'package:vingtun/features/games/holdem/holdem_labels.dart';
import 'package:vingtun/features/games/holdem/holdem_raise.dart';
import 'package:vingtun/features/games/holdem/holdem_stage.dart';
import 'package:vingtun/features/games/holdem/holdem_state.dart';
import 'package:vingtun/features/stage/stage_controller.dart';
import 'package:vingtun/features/table/table_sounds.dart' show CelebrationKind;

import '../helpers.dart';
import '../holdem_fixtures.dart';

List<String> _strs(Object? v) => [for (final x in v! as List) x as String];

class _NoActions implements GameTableActions {
  @override
  final ValueListenable<bool> busy = ValueNotifier(false);
  @override
  Future<bool> act(Map<String, Object?> action) async => true;
  @override
  void celebrate(CelebrationKind kind, {int? cents, String? label}) {}
  @override
  Future<void> leave() async {}
  @override
  Future<bool> setBets(Map<String, int> bets, {PowerType? power}) async => true;
  @override
  Future<bool> sitIn() async => true;
  @override
  Future<bool> sitOut() async => true;
}

GameTableView _view(Map<String, Object?> doc) => GameTableView(
      ui: holdemGame,
      table: GameTableState.fromDoc(doc['tableId']! as String, doc),
      myUid: 'u-demo',
      bets: const [],
      now: kTestNow,
      actions: _NoActions(),
    );

void main() {
  final vectors = holdemVectors();

  group('evaluator (port of engineHand.ts)', () {
    test('every shared 7-card vector: same category, score and best five', () {
      final hands = vectors['hands']! as List;
      expect(hands.length, greaterThan(40));
      for (final h in hands.cast<Map<String, Object?>>()) {
        final v = evaluateHoldemHand(_strs(h['cards']));
        expect(v.category.name, h['category'], reason: '${h['cards']}');
        expect(v.score, h['score'], reason: '${h['cards']}');
        expect(v.best, _strs(h['best']), reason: '${h['cards']}');
      }
    });

    HandValue ev(String s) => evaluateHoldemHand(s.split(' '));

    test('classic hands and their order', () {
      final ladder = [
        ev('2C 4D 6H 8S TC QD AH'), // high card
        ev('TS TH 3D 6C 8S QD KH'), // pair
        ev('8D 8C 4S 4H 2D 3C AS'), // two pair
        ev('QS QH QD 7C 3D 2S 9H'), // trips
        ev('AS 2D 3C 4H 5S 9D KC'), // wheel
        ev('6S 2D 3C 4H 5S 9D KC'), // six-high straight
        ev('2S 7S 9S JS KS AH 3H'), // flush
        ev('QS QH QD 7C 7D 2S 3H'), // full house
        ev('9C 9D 9H 9S KD KC 2S'), // quads
        ev('5H 4H 3H 2H AH KD KC'), // steel wheel
        ev('AS KS QS JS TS 2H 3D'), // royal flush
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(ladder[i].score, greaterThan(ladder[i - 1].score), reason: '${ladder[i]} > ${ladder[i - 1]}');
      }
      expect(ladder[4].category, HoldemCategory.straight);
      expect(ladder[4].best, ['5S', '4H', '3C', '2D', 'AS']);
      expect(ladder[9].royal, isFalse);
      expect(ladder[10].royal, isTrue);
    });

    test('kickers decide; two trips make a full house; three pairs keep the best kicker', () {
      expect(ev('AS AH KD 7C 4S 3D 2C').score, greaterThan(ev('AD AC QD 7H 4C 3S 2D').score));
      expect(ev('QS QH QD 7C 7D 7S 2C').best, ['QS', 'QH', 'QD', '7S', '7D']);
      expect(ev('AS AH KD KC QS QH JD').best, ['AS', 'AH', 'KD', 'KC', 'QS']);
      expect(ev('9C 9D 9H 9S KD QC 2S').best.last, 'KD');
    });

    test('equivalent hands tie exactly (different suits, the board plays)', () {
      expect(ev('AS KD QC JH TS 2D 3C').score, ev('AH KC QD JS TD 4H 5S').score);
      final board = ['5C', '6D', '7H', '8S', '9C'];
      expect(evaluateHoldemHand(['2S', '3S', ...board]).score, evaluateHoldemHand(['2H', 'KD', ...board]).score);
      expect(ev('KS KH 4D 4C 9S 2D 3C').score, ev('KD KC 4S 4H 9H 2S 3D').score);
    });

    test('5 to 7 cards only', () {
      expect(() => evaluateHoldemHand(['AS', 'KS', 'QS', 'JS']), throwsArgumentError);
      expect(evaluateHoldemHand(['AS', 'KS', 'QS', 'JS', 'TS']).royal, isTrue);
    });
  });

  group('fairness (deal order, fixed positions, every hand rebuilt)', () {
    test('each shared deal: commitment, deal order, holes, burns, board, hands, winners', () {
      final deals = (vectors['deals']! as List).cast<Map<String, Object?>>();
      expect(deals, isNotEmpty);
      for (final d in deals) {
        final seed = d['seed']! as String;
        expect(sha256Hex(seed), d['commit']);
        final order = [for (final s in d['order']! as List) s as int];
        final layout = HoldemDeckLayout(order.length);
        final dealt = fairDealOrder(buildWireShoe(1), seed, decks: 1).take(layout.total).toList();
        expect(dealt, _strs(d['dealt']));
        final deal = HoldemDeal.fromSeed(seed, order)!;
        expect(deal.burns, _strs(d['burns']));
        expect(deal.board, _strs(d['board']));
        final holes = (d['holes']! as Map).cast<String, Object?>();
        final hands = (d['hands']! as Map).cast<String, Object?>();
        var top = -1;
        for (final s in order) {
          expect(deal.holes[s], _strs(holes['$s']));
          final h = (hands['$s']! as Map).cast<String, Object?>();
          final v = deal.handOf(s)!;
          expect((v.category.name, v.score, v.best), (h['category'], h['score'], _strs(h['best'])));
          if (v.score > top) top = v.score;
        }
        expect([for (final s in order) if (deal.handOf(s)!.score == top) s]..sort(), [for (final s in d['winners']! as List) s as int]);
      }
    });

    test('verifyRound: a genuine round is verified; tampering is caught', () {
      final v = (vectors['deals']! as List).cast<Map<String, Object?>>()[3];
      final doc = holdemRoundFromVector(v);
      expect(verifyHoldemRound(GameRound.fromDoc(doc)), FairnessVerdict.verified);
      expect(holdemGame.verifyRound(GameRound.fromDoc(doc)), FairnessVerdict.verified);

      Map<String, Object?> patch(void Function(Map<String, Object?> d) f) {
        final c = holdemRoundFromVector(v);
        f(c);
        return c;
      }

      expect(verifyHoldemRound(GameRound.fromDoc(patch((d) => (d['fairness']! as Map)['commit'] = sha256Hex('other')))), FairnessVerdict.badCommit);
      expect(
        verifyHoldemRound(GameRound.fromDoc(patch((d) => ((d['fairness']! as Map)['dealt'] as List)[0] = 'ZZ'))),
        FairnessVerdict.badOrder,
      );
      // A showdown hand that is not the dealt one.
      expect(
        verifyHoldemRound(GameRound.fromDoc(patch((d) {
          final r = d['result']! as Map;
          final hands = r['hands'] as Map;
          final first = hands.keys.first;
          hands[first] = {...(hands[first] as Map), 'cards': ['AS', 'AH']};
        }))),
        FairnessVerdict.badOrder,
      );
      // Wrong winners.
      expect(
        verifyHoldemRound(GameRound.fromDoc(patch((d) {
          final r = d['result']! as Map;
          final order = (r['order'] as List).cast<int>();
          final winners = (r['winners'] as List).cast<int>();
          final loser = order.firstWhere((s) => !winners.contains(s));
          ((r['pots'] as List).first as Map)['winners'] = [loser];
        }))),
        FairnessVerdict.badOrder,
      );
    });

    test('reveal: every hole card from the seed, folded hands included', () {
      final v = (vectors['deals']! as List).cast<Map<String, Object?>>()[5];
      final doc = holdemRoundFromVector(v);
      // Only the first player went to the showdown: the others folded.
      final result = doc['result']! as Map;
      final order = (result['order'] as List).cast<int>();
      result['hands'] = {'${order.first}': (result['hands'] as Map)['${order.first}']};
      result['winners'] = [order.first];
      result['showdown'] = false;
      ((result['pots'] as List).first as Map)['winners'] = [order.first];
      final reveal = revealHoldemRound(GameRound.fromDoc(doc))!;
      expect(reveal.verdict, FairnessVerdict.verified);
      expect(reveal.seats.map((s) => s.seat), order);
      final holes = (v['holes']! as Map).cast<String, Object?>();
      for (final s in reveal.seats) {
        expect(s.cards, _strs(holes['${s.seat}']));
        expect(s.folded, s.seat != order.first);
        expect(s.hand, isNotNull);
      }
      // Without the dealt prefix, the seed alone gives the same cards.
      (doc['fairness']! as Map)['dealt'] = null;
      expect(revealHoldemRound(GameRound.fromDoc(doc))!.seats.first.cards, _strs(holes['${order.first}']));
    });

    test('a round without a draw proof: commitment only; no result: nothing to reveal', () {
      final r = GameRound.fromDoc({
        'tableId': 'ho-x',
        'round': 3,
        'result': <String, Object?>{},
        'fairness': {'commit': sha256Hex('s'), 'seed': 's', 'remainingBefore': null, 'dealt': null, 'decks': null},
      });
      expect(verifyHoldemRound(r), FairnessVerdict.verified);
      expect(revealHoldemRound(r), isNull);
    });
  });

  group('raise slider maths', () {
    const m = HoldemRaiseModel(minTo: 1200, maxTo: 19800, kind: 'raise', currentBet: 600, myBet: 0, callCents: 600, middleCents: 1600);

    test('whole dollars between the minimum raise and the stack', () {
      expect(m.clamp(0), 1200);
      expect(m.clamp(1249), 1200);
      expect(m.clamp(1250), 1300);
      expect(m.clamp(50000), 19800);
      expect(m.amountAt(0), 1200);
      expect(m.amountAt(1), 19800);
      expect(m.amountAt(0.5) % 100, 0);
      for (final to in [1200, 3400, 10000, 19800]) {
        expect(m.amountAt(m.positionOf(to)), to);
      }
    });

    test('pot presets: call first, then the pot after the call', () {
      // pot after the call = 1600 + 600 = 2200 → pot raise to 600 + 2200 = 2800, half pot 600 + 1100 = 1700.
      expect(m.presetTo(HoldemPreset.pot), 2800);
      expect(m.presetTo(HoldemPreset.halfPot), 1700);
      expect(m.presets.map((p) => p.$1), [HoldemPreset.min, HoldemPreset.halfPot, HoldemPreset.pot, HoldemPreset.allIn]);
      const bet = HoldemRaiseModel(minTo: 200, maxTo: 5000, kind: 'bet', middleCents: 1000);
      expect(bet.presetTo(HoldemPreset.halfPot), 500);
      expect(bet.presetTo(HoldemPreset.pot), 1000);
      expect(bet.actionFor(700), {'type': 'bet', 'toCents': 700});
    });

    test('only an all-in when the minimum is out of reach; presets deduplicated', () {
      const short = HoldemRaiseModel(minTo: 1200, maxTo: 900, kind: 'raise', currentBet: 600);
      expect(short.allInOnly, isTrue);
      expect(short.clamp(100), 900);
      expect(short.presets, [(HoldemPreset.allIn, 900)]);
      expect(short.actionFor(900), {'type': 'allIn'});
      const tight = HoldemRaiseModel(minTo: 1200, maxTo: 1400, kind: 'raise', currentBet: 600, callCents: 600, middleCents: 3000);
      expect(tight.presets.map((p) => p.$2).toSet().length, tight.presets.length);
      expect(tight.presets.last, (HoldemPreset.allIn, 1400));
    });

    test('actions: raise to an amount, all-in at the stack', () {
      expect(m.actionFor(3000), {'type': 'raise', 'toCents': 3000});
      expect(m.actionFor(19800), {'type': 'allIn'});
      expect(m.addedFor(3000), 3000);
      expect(HoldemRaiseModel.of(const HoldemToAct(seat: 0, callCents: 600)), isNull);
      expect(HoldemRaiseModel.of(const HoldemToAct(seat: 0, kind: 'raise', minToCents: 1200, maxToCents: 1800))!.maxTo, 1800);
    });
  });

  group('state parsing is tolerant', () {
    test('empty or mistyped g never throws', () {
      final t = HoldemTable.fromG(const {'button': 'x', 'board': 3, 'pots': [1, null], 'toAct': {'seat': 'a'}, 'result': 'no'});
      expect(t.button, -1);
      expect(t.board, isEmpty);
      expect(t.pots.length, 2);
      expect(t.toAct, isNull);
      expect(t.result, isNull);
      final s = HoldemSeatState.fromG(const {'lastAction': 'dance', 'shown': 'AS'});
      expect(s.lastAction, isNull);
      expect(s.shown, isNull);
      expect(s.live, isFalse);
    });

    test('fixtures: my turn on the flop, chips in the middle, the live hand blocks a rebuy', () {
      final t = GameTableState.fromDoc(kHoldemTableId, holdemFlopDoc());
      final h = HoldemTable.of(t);
      expect(h.toAct!.callCents, 600);
      expect(holdemStepOf(t), HoldemStep.flop);
      expect(holdemChipsInMiddle(t), 1600);
      expect(holdemInLiveHand(t, t.seats[0]!), isTrue);
      final w = GameTableState.fromDoc(kHoldemTableId, holdemWaitingDoc());
      expect(holdemInLiveHand(w, w.seats[0]!), isFalse);
      final r = HoldemTable.of(GameTableState.fromDoc(kHoldemTableId, holdemShowdownDoc())).result!;
      expect(r.winningHand!.category, HoldemCategory.twoPair);
    });
  });

  group('words', () {
    test('hand names in French and English', () {
      final fr = l10nOf(const Locale('fr'));
      final en = l10nOf(const Locale('en'));
      String both(String cards) {
        final v = evaluateHoldemHand(cards.split(' '));
        return '${holdemHandName(fr, v)} | ${holdemHandName(en, v)}';
      }

      expect(both('AS AH 3D 6C 8S QD KH'), "Paire d'as | Pair of aces");
      expect(both('KS KH KD 7C 7D 2S 3H'), 'Full aux rois par les 7 | Full house, kings full of sevens');
      expect(both('AS 2D 3C 4H 5S 9D KC'), 'Quinte au 5 | Five-high straight');
      expect(both('2S 7S 9S JS KS AH 3H'), "Couleur à l'as | Ace-high flush");
      expect(both('QS QH QD 7C 3D 2S 9H'), 'Brelan de dames | Three queens');
      expect(both('8D 8C 4S 4H 2D 3C AS'), 'Deux paires, 8 et 4 | Two pair, eights and fours');
      expect(both('AS KS QS JS TS 2H 3D'), 'Quinte flush royale | Royal flush');
      expect(both('9H 8H 7H 6H 5H 2C 2D'), 'Quinte flush au 9 | Nine-high straight flush');
      expect(both('2C 4D 6H 8S TC QD AH'), 'Hauteur as | Ace high');
      expect(both('9C 9D 9H 9S KD KC 2S'), 'Carré de 9 | Four nines');
    });

    test('history summary and profile lines', () {
      final fr = l10nOf(const Locale('fr'));
      final v = (vectors['deals']! as List).cast<Map<String, Object?>>()[0];
      final round = GameRound.fromDoc(holdemRoundFromVector(v));
      expect(holdemRoundSummary(fr, round), startsWith('Pot 20 \$ · '));
      final folded = GameRound.fromDoc({
        'result': {'order': [0, 1], 'potCents': 300, 'pots': [], 'hands': {}, 'winners': [1], 'showdown': false},
      });
      expect(holdemRoundSummary(fr, folded), 'Pot 3 \$ · sans abattage');
      expect(holdemRoundSummary(fr, GameRound.fromDoc(const {'result': {}})), isNull);
      final lines = holdemStatLines(fr, const GameStats(rounds: 9, counters: {'pots': 4, 'showdowns': 3, 'showdownsWon': 2, 'allIns': 1, 'bestHand': 7}));
      expect(lines, [
        (fr.holdemStatPots, '4'),
        (fr.holdemStatShowdowns, '2 / 3'),
        (fr.holdemStatAllIns, '1'),
        (fr.holdemStatBestHand, fr.holdemCatFullHouse),
      ]);
    });

    test('game entry: playable, own verifier, sounds of the group', () {
      expect(holdemGame.playable, isTrue);
      expect(holdemGame.verifyRound, verifyHoldemRound);
      expect(holdemGame.sounds.every((s) => s.file.startsWith('holdem_')), isTrue);
      expect(holdemGame.sounds.length, 11);
    });
  });

  group('stage scene (events → commands → props)', () {
    StageController newStage(RecordingStageFeedback rec) => StageController(geometry: kHoldemGeometry, feedback: rec);

    test('first snapshot: built from the state without animation', () {
      final rec = RecordingStageFeedback();
      final stage = newStage(rec);
      addTearDown(stage.dispose);
      final scene = HoldemScene(stage);
      scene.onTable(_view(holdemFlopDoc()), const [], true);
      expect(stage.isBusy, isFalse);
      final ids = stage.props.map((p) => p.id).toSet();
      expect(ids, containsAll(['board-0', 'board-1', 'board-2', 'burn-0', 'pot', 'bet-5']));
      for (final s in [5, 0, 1, 2, 3]) {
        expect(ids, containsAll(['hole-$s-0', 'hole-$s-1']));
      }
      expect(ids.contains('hole-4-0'), isFalse);
      expect((stage.prop('pot')!.data! as HoldemChips).cents, 1000);
      final mine = stage.prop('hole-0-0')!.data! as HoldemCard;
      expect((mine.mine, mine.flip), (true, 1.0));
      expect(rec.cues, isEmpty);
    });

    test('a batch of events animates to exactly the next snapshot (deal, bets, collect, burn, flop)', () {
      final rec = RecordingStageFeedback();
      final stage = newStage(rec);
      addTearDown(stage.dispose);
      final scene = HoldemScene(stage);
      final pre = holdemPreflopDoc();
      // Start from an empty table, then the whole preflop arrives at once.
      scene.onTable(_view({...pre, 'events': <Object?>[], 'g': {...(pre['g']! as Map), 'order': <int>[]}, 'seats': [for (final s in pre['seats']! as List) s == null ? null : {...(s as Map), 'g': {...(s['g'] as Map), 'inHand': false, 'betCents': 0}}]}), const [], true);
      expect(stage.props, isEmpty);
      final preView = _view(pre);
      scene.onTable(preView, preView.table.events, false);
      expect(stage.isBusy, isTrue);
      stage.advance(const Duration(seconds: 10));
      expect(stage.isBusy, isFalse);
      expect(rec.names.where((n) => n == 'holdem_card_pitch').length, 10); // 5 players × 2 cards
      expect(stage.props.where((p) => p.id.startsWith('hole-')).length, 10);
      expect(stage.props.where((p) => p.id.startsWith('fly-')), isEmpty);
      expect((stage.prop('bet-0')!.data! as HoldemChips).cents, 200);
      // The flop arrives.
      final flop = _view(holdemFlopDoc());
      final fresh = flop.table.events.where((e) => e.seq > preView.table.events.length).toList();
      expect(fresh.map((e) => e.type), ['check', 'collect', 'burn', 'flop', 'bet']);
      scene.onTable(flop, fresh, false);
      for (var i = 0; i < 400 && stage.isBusy; i++) {
        stage.advance(const Duration(milliseconds: 16));
      }
      expect(stage.isBusy, isFalse);
      expect(rec.names, containsAll(['holdem_check_knock', 'holdem_chips_collect', 'holdem_card_burn', 'holdem_board_flip', 'holdem_chips_bet']));
      expect([for (var i = 0; i < 3; i++) (stage.prop('board-$i')!.data! as HoldemCard).code], ['AH', '7C', '2D']);
      expect((stage.prop('pot')!.data! as HoldemChips).cents, 1000);
      expect((stage.prop('bet-5')!.data! as HoldemChips).cents, 600);
      expect(stage.prop('bet-0'), isNull);
      expect(stage.prop('board-0')!.pos, kHoldemGeometry.boardSlot(0));
    });

    test('showdown and win: shown cards face up, the pot leaves, winners highlighted', () {
      final rec = RecordingStageFeedback();
      final stage = newStage(rec);
      addTearDown(stage.dispose);
      final scene = HoldemScene(stage);
      scene.onTable(_view(holdemFlopDoc()), const [], true);
      final sd = _view(holdemShowdownDoc());
      scene.onTable(sd, sd.table.events.where((e) => e.type == 'showdown' || e.type == 'win').toList(), false);
      stage.advance(const Duration(seconds: 8));
      expect(rec.names, containsAll(['holdem_showdown', 'holdem_pot_win']));
      final luna = stage.prop('hole-2-0')!.data! as HoldemCard;
      expect((luna.code, luna.flip, luna.dim), ('QH', 1.0, true));
      expect(stage.prop('hole-1-0'), isNull); // folded
      expect(stage.prop('pot'), isNull);
      final ace = stage.propsOf('card').firstWhere((p) => (p.data! as HoldemCard).code == 'AH');
      expect((ace.data! as HoldemCard).highlight, isTrue);
    });

    test('a new hand sweeps the previous one; far behind → fast-forward', () {
      final stage = newStage(RecordingStageFeedback());
      addTearDown(stage.dispose);
      final scene = HoldemScene(stage);
      scene.onTable(_view(holdemShowdownDoc()), const [], true);
      expect(stage.props, isNotEmpty);
      final next = _view(holdemPreflopDoc(round: 8));
      scene.onTable(next, next.table.events, false);
      scene.onTable(next, next.table.events, false); // queued work > 3 s: the first batch is skipped
      stage.advance(const Duration(seconds: 12));
      expect(stage.props.where((p) => p.id.startsWith('hole-')).length, 10);
      expect(stage.prop('board-0'), isNull);
    });
  });
}
