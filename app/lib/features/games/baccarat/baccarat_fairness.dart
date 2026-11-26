/// Client-side fairness verifier of a finished baccarat coup — a port of
/// `firebase/functions/src/games/baccarat/engine.ts` (`dealCoup`) on top of
/// the shared `fairDealOrder` / `SeededRng` port (`domain/fairness.dart`).
/// Checked against the server's vectors `assets/fairness/baccarat_vectors.json`
/// (`test/unit/baccarat_fairness_test.dart`).
///
/// A round is verified when:
///  1. SHA-256(seed) equals the commitment published before the bets;
///  2. `dealt` is exactly the prefix of `fairDealOrder(remainingBefore, seed, 8)`;
///  3. re-dealing that order with the official rules (burn on the first coup
///     of a shoe, drawing chart) gives the very cards, totals and winner of
///     the round's result.
library;

import 'package:flutter/foundation.dart';

import '../../../domain/fairness.dart';
import '../../../domain/game_table.dart';
import 'baccarat_model.dart';

@immutable
class BaccaratDeal {
  const BaccaratDeal({
    required this.player,
    required this.banker,
    required this.dealt,
    this.burnCard,
    this.burned = const [],
  });

  final List<String> player;
  final List<String> banker;

  /// Every card taken from the order (burn card, burned cards, the coup).
  final List<String> dealt;
  final String? burnCard;
  final List<String> burned;

  int get playerTotal => baccaratTotal(player);
  int get bankerTotal => baccaratTotal(banker);
  bool get natural => baccaratTotal(player.take(2)) >= 8 || baccaratTotal(banker.take(2)) >= 8;
  bool get playerPair => baccaratPair(player);
  bool get bankerPair => baccaratPair(banker);
  BaccaratWinner get winner => playerTotal > bankerTotal
      ? BaccaratWinner.player
      : bankerTotal > playerTotal
          ? BaccaratWinner.banker
          : BaccaratWinner.tie;
}

/// Deals one coup from [order] (index 0 upward). Throws a [StateError] if
/// the order is too short (never with `fairDealOrder`, which refills).
BaccaratDeal dealBaccaratCoup(List<String> order, {required bool burn}) {
  var i = 0;
  String take() {
    if (i >= order.length) throw StateError('baccarat: deal order exhausted');
    return order[i++];
  }

  String? burnCard;
  final burned = <String>[];
  if (burn) {
    burnCard = take();
    for (var k = 0; k < baccaratBurnCount(burnCard); k++) {
      burned.add(take());
    }
  }
  final player = <String>[take()];
  final banker = <String>[take()];
  player.add(take());
  banker.add(take());
  final p2 = baccaratTotal(player), b2 = baccaratTotal(banker);
  if (p2 < 8 && b2 < 8) {
    int? third;
    if (baccaratPlayerDraws(p2)) {
      final c = take();
      player.add(c);
      third = baccaratValue(c);
    }
    if (baccaratBankerDraws(b2, third)) banker.add(take());
  }
  return BaccaratDeal(player: player, banker: banker, dealt: order.sublist(0, i), burnCard: burnCard, burned: burned);
}

/// The full check of a round document (see the library doc).
FairnessVerdict verifyBaccaratRound(GameRound round) {
  final f = round.fairness;
  if (f.seed.isEmpty || sha256Hex(f.seed) != f.commit.toLowerCase()) return FairnessVerdict.badCommit;
  final remaining = f.remainingBefore, dealt = f.dealt;
  if (remaining == null || dealt == null || remaining.isEmpty) return FairnessVerdict.verified; // commitment only
  final order = fairDealOrder(remaining, f.seed, decks: f.decks ?? BaccaratRules.decks);
  final coup = BaccaratCoup.fromDoc(round.result);
  final BaccaratDeal deal;
  try {
    deal = dealBaccaratCoup(order, burn: coup?.hasBurn ?? false);
  } on StateError {
    return FairnessVerdict.badOrder;
  }
  if (!listEquals(deal.dealt, dealt)) return FairnessVerdict.badOrder;
  if (coup != null) {
    final same = listEquals(deal.player, coup.player) &&
        listEquals(deal.banker, coup.banker) &&
        deal.winner == coup.winner &&
        deal.playerTotal == coup.playerTotal &&
        deal.bankerTotal == coup.bankerTotal &&
        deal.burnCard == coup.burnCard;
    if (!same) return FairnessVerdict.badOrder;
  }
  return FairnessVerdict.verified;
}
