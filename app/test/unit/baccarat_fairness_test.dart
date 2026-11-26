// The Dart verifier of a baccarat coup against the server's shared vectors
// (`assets/fairness/baccarat_vectors.json`, written by
// firebase/functions/test/unit/baccarat/fairness.test.ts): seed + shoe (+ burn)
// → deal order → the very same coup; tampered proofs are rejected.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/fairness.dart';
import 'package:vingtun/domain/game_table.dart';
import 'package:vingtun/domain/games.dart';
import 'package:vingtun/features/games/baccarat/baccarat_fairness.dart';
import 'package:vingtun/features/games/baccarat/baccarat_game.dart';
import 'package:vingtun/features/games/baccarat/baccarat_model.dart';

List<Map<String, Object?>> loadVectors() {
  final f = File('assets/fairness/baccarat_vectors.json');
  return [for (final v in jsonDecode(f.readAsStringSync()) as List) (v as Map).cast<String, Object?>()];
}

List<String> strings(Object? v) => [for (final x in v! as List) x as String];

GameRound roundOf(Map<String, Object?> v, {List<String>? dealt, Map<String, Object?>? result, String? commit}) {
  final e = (v['expected']! as Map).cast<String, Object?>();
  return GameRound(
    tableId: 'bc-x',
    game: GameId.baccarat,
    round: 1,
    result: result ?? e,
    fairness: GameRoundFairness(
      commit: commit ?? v['commit']! as String,
      seed: v['seed']! as String,
      remainingBefore: strings(v['remainingBefore']),
      dealt: dealt ?? strings(e['dealt']),
      decks: 8,
    ),
  );
}

void main() {
  final vectors = loadVectors();

  test('the vector file covers burns, naturals, ties, third cards and pairs', () {
    expect(vectors.length, greaterThanOrEqualTo(10));
    expect(vectors.where((v) => v['burn'] == true).length, greaterThanOrEqualTo(3));
  });

  for (final v in vectors) {
    test('vector "${v['name']}": same deal order and same coup as the server', () {
      final e = (v['expected']! as Map).cast<String, Object?>();
      expect(sha256Hex(v['seed']! as String), v['commit']);
      final order = fairDealOrder(strings(v['remainingBefore']), v['seed']! as String, decks: 8);
      final deal = dealBaccaratCoup(order, burn: v['burn'] == true);
      expect(deal.dealt, strings(e['dealt']));
      expect(deal.player, strings(e['player']));
      expect(deal.banker, strings(e['banker']));
      expect([deal.playerTotal, deal.bankerTotal], [e['playerTotal'], e['bankerTotal']]);
      expect(deal.winner.name, e['winner']);
      expect([deal.natural, deal.playerPair, deal.bankerPair], [e['natural'], e['playerPair'], e['bankerPair']]);
      final burn = e['burn'] as Map?;
      expect(deal.burnCard, burn?['card']);
      expect(deal.burned, burn == null ? isEmpty : strings(burn['cards']));
      expect(verifyBaccaratRound(roundOf(v)), FairnessVerdict.verified);
      expect(baccaratGame.verifyRound(roundOf(v)), FairnessVerdict.verified);
    });
  }

  test('tampered proofs fail: swapped cards, another commitment, a result that is not the deal', () {
    final v = vectors.first;
    final e = (v['expected']! as Map).cast<String, Object?>();
    final dealt = strings(e['dealt']);
    final swapped = [...dealt];
    final n = swapped.length;
    var j = n - 2;
    while (j > 0 && swapped[j] == swapped[n - 1]) {
      j--;
    }
    (swapped[j], swapped[n - 1]) = (swapped[n - 1], swapped[j]);
    expect(verifyBaccaratRound(roundOf(v, dealt: swapped)), FairnessVerdict.badOrder);
    expect(verifyBaccaratRound(roundOf(v, commit: sha256Hex('other'))), FairnessVerdict.badCommit);
    final lie = {...e, 'winner': e['winner'] == 'banker' ? 'player' : 'banker'};
    expect(verifyBaccaratRound(roundOf(v, result: lie)), FairnessVerdict.badOrder);
    final noBurn = {...e, 'burn': null};
    expect(verifyBaccaratRound(roundOf(v, result: noBurn)), FairnessVerdict.badOrder); // re-dealt without the burn
  });

  test('a round without proof only checks the commitment', () {
    final r = GameRound(
      tableId: 'bc-x',
      game: GameId.baccarat,
      round: 3,
      fairness: GameRoundFairness(commit: sha256Hex('s'), seed: 's'),
    );
    expect(verifyBaccaratRound(r), FairnessVerdict.verified);
  });

  test('the deal engine matches the drawing rules on a hand-built order', () {
    final d = dealBaccaratCoup(['2S', '3H', 'KD', 'KC', '4S', '9H'], burn: false);
    expect(d.player, ['2S', 'KD', '4S']);
    expect(d.banker, ['3H', 'KC', '9H']);
    expect(d.winner, BaccaratWinner.player);
    expect(() => dealBaccaratCoup(['2S'], burn: false), throwsStateError);
  });
}
