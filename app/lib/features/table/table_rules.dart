/// Client-side mirror of the engine's legality rules
/// (`firebase/functions/src/engine/round.ts`: canDouble / canSplit /
/// canSurrender / POWER_FOR_ACTION). Only used to enable buttons — the server
/// re-validates everything.
library;

import '../../domain/backend_constants.dart';
import '../../domain/models.dart';
import '../../domain/table_state.dart';

bool isMyTurn(TableState t, SeatState mine) =>
    t.phase == ServerTablePhase.playerTurns && t.turn != null && t.turn!.seatIndex == mine.seatIndex;

/// The hand the server's `turn` points at (or the first hand).
SeatHand? currentHandOf(TableState t, SeatState mine) {
  if (mine.hands.isEmpty) return null;
  final i = isMyTurn(t, mine) ? t.turn!.handIndex : 0;
  return i < mine.hands.length ? mine.hands[i] : null;
}

bool canDouble(SeatHand h) => h.cards.length == 2 && !h.done && !h.doubled && !h.splitAces;

bool canSplit(SeatState seat, SeatHand h) =>
    h.cards.length == 2 &&
    !h.done &&
    !h.splitAces &&
    seat.hands.length < Backend.maxHandsPerSeat &&
    h.cards[0].rank.value == h.cards[1].rank.value;

bool canSurrender(SeatState seat, SeatHand h) =>
    seat.hands.length == 1 && h.cards.length == 2 && !h.fromSplit && !h.doubled && !h.done;

/// Buttons to enable for MY seat now.
Set<PlayerAction> legalActions(TableState t, SeatState mine) {
  if (!isMyTurn(t, mine) || mine.leaving) return const {};
  final h = currentHandOf(t, mine);
  if (h == null || h.done) return const {};
  return {
    PlayerAction.hit,
    PlayerAction.stand,
    if (canDouble(h)) PlayerAction.double,
    if (canSplit(mine, h)) PlayerAction.split,
    if (canSurrender(mine, h)) PlayerAction.surrender,
  };
}

/// `POWER_FOR_ACTION` of the engine.
bool powerAppliesTo(PowerType p, PlayerAction a, {int? amountCents}) => switch (p) {
      PowerType.freeSplit => a == PlayerAction.split,
      PowerType.freeDouble => a == PlayerAction.double,
      PowerType.freeInsurance => a == PlayerAction.insurance && (amountCents ?? 0) > 0,
      PowerType.peek => a == PlayerAction.peek,
      PowerType.secondChance => a == PlayerAction.hit || a == PlayerAction.double,
    };

/// Whether picking [p] in the powers sheet makes sense right now.
bool powerUsableNow(PowerType p, TableState t, SeatState mine, SeatHand? hand) {
  if (mine.powerUsed != null) return false;
  if (p == PowerType.freeInsurance) {
    return t.phase == ServerTablePhase.insurance && mine.insurance != null && !mine.insurance!.decided;
  }
  if (!isMyTurn(t, mine) || hand == null || hand.done) {
    // Arm in advance (except peek, which acts immediately).
    return p != PowerType.peek && t.phase != ServerTablePhase.settled;
  }
  return switch (p) {
    PowerType.freeSplit => canSplit(mine, hand),
    PowerType.freeDouble => canDouble(hand),
    PowerType.peek => true,
    PowerType.secondChance => true,
    PowerType.freeInsurance => false,
  };
}

/// `act{insurance}` maximum: floor(first hand's bet / 2).
int maxInsuranceCents(SeatState mine) => mine.hands.isEmpty ? 0 : mine.hands.first.betCents ~/ 2;

/// placeBet rule: whole dollars within the table limits.
bool isValidBet(int cents, int minBet, int maxBet) => cents % 100 == 0 && cents >= minBet && cents <= maxBet;
