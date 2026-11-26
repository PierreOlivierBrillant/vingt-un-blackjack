/// Provably-fair check of a finished hold'em hand ([GameUi.verifyRound]) and
/// the reveal of EVERY hole card from the revealed seed (assumed choice shown
/// in the rules: the seed makes folded cards verifiable, hence visible).
///
/// The deal is `fairDealOrder(buildShoe(1), seed, 1)` with the fixed
/// positions of `holdemDeckLayout` (`shared/games/holdem.ts`): player k of
/// `result.order` gets cards k and n+k, then burn, flop×3, burn, turn, burn,
/// river.
library;

import 'package:flutter/foundation.dart';

import '../../../domain/fairness.dart';
import '../../../domain/game_table.dart';
import 'holdem_evaluator.dart';
import 'holdem_state.dart';

/// `holdemDeckLayout(n)`.
@immutable
class HoldemDeckLayout {
  const HoldemDeckLayout(this.n);
  final int n;
  int hole(int k, int pass) => pass * n + k;
  List<int> get burns => [2 * n, 2 * n + 4, 2 * n + 6];
  List<int> get flop => [2 * n + 1, 2 * n + 2, 2 * n + 3];
  int get turn => 2 * n + 5;
  int get river => 2 * n + 7;
  int get total => 2 * n + 8;
}

/// Every card of one hand, rebuilt from the deal order.
@immutable
class HoldemDeal {
  const HoldemDeal({required this.order, required this.holes, required this.burns, required this.board});

  /// Rebuilds the hand from the first `2n+8` cards of the deal order.
  static HoldemDeal? fromDealt(List<String> dealt, List<int> order) {
    final layout = HoldemDeckLayout(order.length);
    if (order.isEmpty || dealt.length < layout.total) return null;
    return HoldemDeal(
      order: order,
      holes: {for (var k = 0; k < order.length; k++) order[k]: [dealt[layout.hole(k, 0)], dealt[layout.hole(k, 1)]]},
      burns: [for (final i in layout.burns) dealt[i]],
      board: [for (final i in layout.flop) dealt[i], dealt[layout.turn], dealt[layout.river]],
    );
  }

  /// Re-deals from the seed alone.
  static HoldemDeal? fromSeed(String seed, List<int> order) =>
      fromDealt(fairDealOrder(buildWireShoe(1), seed, decks: 1).take(HoldemDeckLayout(order.length).total).toList(), order);

  final List<int> order;

  /// seat → two hole cards.
  final Map<int, List<String>> holes;
  final List<String> burns;
  final List<String> board;

  /// Best hand of [seat] with the full board.
  HandValue? handOf(int seat) {
    final h = holes[seat];
    return h == null ? null : evaluateHoldemHand([...h, ...board]);
  }
}

/// [GameUi.verifyRound] of the hold'em: commitment, deal order (prefix of
/// `fairDealOrder(remainingBefore, seed, 1)`), then the hand itself — board,
/// showdown hole cards, hand scores and the winners of every pot.
FairnessVerdict verifyHoldemRound(GameRound round) {
  final f = round.fairness;
  if (f.seed.isEmpty || sha256Hex(f.seed) != f.commit.toLowerCase()) return FairnessVerdict.badCommit;
  final remaining = f.remainingBefore, dealt = f.dealt;
  if (remaining == null || dealt == null || dealt.isEmpty) return FairnessVerdict.verified; // nothing more to check
  final order = verifyFairness(commit: f.commit, seed: f.seed, remainingBefore: remaining, dealt: dealt, decks: f.decks ?? 1);
  if (order != FairnessVerdict.verified) return order;
  final result = HoldemResult.fromDoc(round.result);
  if (result == null || result.order.isEmpty) return FairnessVerdict.verified;
  final deal = HoldemDeal.fromDealt(dealt, result.order);
  if (deal == null) return FairnessVerdict.badOrder;
  if (result.board.isNotEmpty && !listEquals(result.board, deal.board)) return FairnessVerdict.badOrder;
  for (final e in result.hands.entries) {
    final hole = deal.holes[e.key];
    if (hole == null || !listEquals(hole, e.value.cards)) return FairnessVerdict.badOrder;
    final v = deal.handOf(e.key)!;
    if (v.score != e.value.score || (e.value.category != null && v.category != e.value.category)) return FairnessVerdict.badOrder;
  }
  if (result.showdown) {
    for (final pot in result.pots) {
      final contenders = [for (final s in pot.eligible) if (result.hands.containsKey(s)) s];
      if (contenders.isEmpty) continue;
      var top = -1;
      for (final s in contenders) {
        final sc = deal.handOf(s)!.score;
        if (sc > top) top = sc;
      }
      final expected = [for (final s in contenders) if (deal.handOf(s)!.score == top) s]..sort();
      final got = [...pot.winners]..sort();
      if (!listEquals(expected, got)) return FairnessVerdict.badOrder;
    }
  }
  return FairnessVerdict.verified;
}

/// One player of a revealed hand.
@immutable
class HoldemRevealedSeat {
  const HoldemRevealedSeat({required this.seat, required this.username, required this.cards, this.hand, this.folded = false, this.netCents = 0});
  final int seat;
  final String username;
  final List<String> cards;

  /// Best hand with the full board (as if every card had been dealt).
  final HandValue? hand;

  /// Did not reach the showdown (folded or won uncontested).
  final bool folded;
  final int netCents;
}

/// A finished hand with every hole card rebuilt from the seed.
@immutable
class HoldemReveal {
  const HoldemReveal({required this.verdict, required this.round, required this.board, required this.seats, this.result});
  final FairnessVerdict verdict;
  final int round;
  final List<String> board;
  final List<HoldemRevealedSeat> seats;
  final HoldemResult? result;
}

/// Every hole card of [round] (null when the round carries no hold'em deal).
HoldemReveal? revealHoldemRound(GameRound round) {
  final result = HoldemResult.fromDoc(round.result);
  if (result == null || result.order.isEmpty || round.fairness.seed.isEmpty) return null;
  final dealt = round.fairness.dealt;
  final deal = dealt != null && dealt.isNotEmpty ? HoldemDeal.fromDealt(dealt, result.order) : HoldemDeal.fromSeed(round.fairness.seed, result.order);
  if (deal == null) return null;
  return HoldemReveal(
    verdict: verifyHoldemRound(round),
    round: round.round,
    board: deal.board,
    result: result,
    seats: [
      for (final seat in result.order)
        HoldemRevealedSeat(
          seat: seat,
          username: round.seats.where((s) => s.seatIndex == seat).firstOrNull?.username ?? '#${seat + 1}',
          cards: deal.holes[seat]!,
          hand: deal.handOf(seat),
          folded: !result.hands.containsKey(seat),
          netCents: round.seats.where((s) => s.seatIndex == seat).firstOrNull?.netCents ?? 0,
        ),
    ],
  );
}
