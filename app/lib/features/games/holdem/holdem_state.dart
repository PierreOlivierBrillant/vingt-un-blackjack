/// Typed, tolerant views of the hold'em parts of a kernel table
/// (`shared/games/holdem.ts`): public `g` ([HoldemTable]), seat `g`
/// ([HoldemSeatState]), the pending decision ([HoldemToAct]) and the end of a
/// hand ([HoldemResult], also `rounds/{n}.result`). A missing or mistyped
/// field falls back to a safe value, never throws (like `GameTableState`).
library;

import 'package:flutter/foundation.dart';

import '../../../domain/game_table.dart';
import '../../../domain/wire.dart';
import 'holdem_evaluator.dart';

/// `HOLDEM_TIMING` (ms).
abstract final class HoldemTiming {
  static const decisionMs = 20000;
  static const waitingMs = 15000;
  static const settledMs = 5000;
  static const showdownExtraMs = 2500;
  static const runoutStreetMs = 1200;
  static const boardDelayMs = 1200;
}

/// `HOLDEM_STREETS` + the end / waiting steps (`table.step`).
enum HoldemStep { preflop, flop, turn, river, waiting, showdown, folded }

/// `HoldemLastAction`.
enum HoldemLastAction { sb, bb, fold, check, call, bet, raise, allIn }

@immutable
class HoldemPot {
  const HoldemPot({required this.cents, this.eligible = const [], this.winners = const []});
  factory HoldemPot.fromDoc(Object? v) {
    final d = asMap(v);
    return HoldemPot(
      cents: asInt(d['cents']),
      eligible: [for (final x in asList(d['eligible'])) if (x is num) x.toInt()],
      winners: [for (final x in asList(d['winners'])) if (x is num) x.toInt()],
    );
  }
  final int cents;
  final List<int> eligible;

  /// Only in a result.
  final List<int> winners;
}

/// `HoldemToAct`: what the seat on turn may do.
@immutable
class HoldemToAct {
  const HoldemToAct({required this.seat, this.callCents = 0, this.kind, this.minToCents, this.maxToCents});
  static HoldemToAct? fromDoc(Object? v) {
    if (v is! Map) return null;
    final d = asMap(v);
    final seat = asIntOrNull(d['seat']);
    if (seat == null) return null;
    final kind = asString(d['kind']);
    return HoldemToAct(
      seat: seat,
      callCents: asInt(d['callCents']),
      kind: kind == 'bet' || kind == 'raise' ? kind : null,
      minToCents: asIntOrNull(d['minToCents']),
      maxToCents: asIntOrNull(d['maxToCents']),
    );
  }

  final int seat;

  /// Chips needed to call, capped at the stack (0 = check possible).
  final int callCents;

  /// 'bet' | 'raise' | null (no bet / raise possible).
  final String? kind;
  final int? minToCents;
  final int? maxToCents;

  bool get canCheck => callCents == 0;
  bool get canRaise => kind != null && minToCents != null && maxToCents != null;
}

/// One showdown hand of a result.
@immutable
class HoldemShownHand {
  const HoldemShownHand({required this.cards, this.category, this.score = 0, this.best = const []});
  factory HoldemShownHand.fromDoc(Object? v) {
    final d = asMap(v);
    return HoldemShownHand(
      cards: asStringList(d['cards']),
      category: holdemCategoryFromWire(d['category']),
      score: asInt(d['score']),
      best: asStringList(d['best']),
    );
  }
  final List<String> cards;
  final HoldemCategory? category;
  final int score;
  final List<String> best;
}

/// `HoldemResult` (end of the hand: `g.result`, `rounds/{n}.result`).
@immutable
class HoldemResult {
  const HoldemResult({
    this.button = -1,
    this.sb,
    this.bb = -1,
    this.smallBlindCents = 0,
    this.bigBlindCents = 0,
    this.order = const [],
    this.board = const [],
    this.boardShown = 0,
    this.potCents = 0,
    this.pots = const [],
    this.hands = const {},
    this.winners = const [],
    this.showdown = false,
  });

  static HoldemResult? fromDoc(Object? v) {
    if (v is! Map) return null;
    final d = asMap(v);
    if (d.isEmpty) return null;
    return HoldemResult(
      button: asInt(d['button'], -1),
      sb: asIntOrNull(d['sb']),
      bb: asInt(d['bb'], -1),
      smallBlindCents: asInt(d['smallBlindCents']),
      bigBlindCents: asInt(d['bigBlindCents']),
      order: [for (final x in asList(d['order'])) if (x is num) x.toInt()],
      board: asStringList(d['board']),
      boardShown: asInt(d['boardShown']),
      potCents: asInt(d['potCents']),
      pots: [for (final p in asList(d['pots'])) HoldemPot.fromDoc(p)],
      hands: {
        for (final e in asMap(d['hands']).entries) ?int.tryParse(e.key): HoldemShownHand.fromDoc(e.value),
      },
      winners: [for (final x in asList(d['winners'])) if (x is num) x.toInt()],
      showdown: asBool(d['showdown']),
    );
  }

  final int button;
  final int? sb;
  final int bb;
  final int smallBlindCents;
  final int bigBlindCents;

  /// Seats dealt in, dealing order.
  final List<int> order;

  /// The 5 cards fixed at the deal.
  final List<String> board;
  final int boardShown;
  final int potCents;
  final List<HoldemPot> pots;

  /// Showdown hands by seat.
  final Map<int, HoldemShownHand> hands;
  final List<int> winners;
  final bool showdown;

  /// The best hand that won (showdown), or null.
  HoldemShownHand? get winningHand {
    HoldemShownHand? best;
    for (final w in winners) {
      final h = hands[w];
      if (h != null && (best == null || h.score > best.score)) best = h;
    }
    return best;
  }
}

/// Public `g` of a hold'em table (`HoldemPublic`).
@immutable
class HoldemTable {
  const HoldemTable({
    this.button = -1,
    this.sb,
    this.bb,
    this.order = const [],
    this.board = const [],
    this.potCents = 0,
    this.pots = const [],
    this.currentBetCents = 0,
    this.minRaiseCents = 0,
    this.toAct,
    this.result,
  });

  factory HoldemTable.fromG(Map<String, Object?> g) => HoldemTable(
        button: asInt(g['button'], -1),
        sb: asIntOrNull(g['sb']),
        bb: asIntOrNull(g['bb']),
        order: [for (final x in asList(g['order'])) if (x is num) x.toInt()],
        board: asStringList(g['board']),
        potCents: asInt(g['potCents']),
        pots: [for (final p in asList(g['pots'])) HoldemPot.fromDoc(p)],
        currentBetCents: asInt(g['currentBetCents']),
        minRaiseCents: asInt(g['minRaiseCents']),
        toAct: HoldemToAct.fromDoc(g['toAct']),
        result: HoldemResult.fromDoc(g['result']),
      );

  factory HoldemTable.of(GameTableState t) => HoldemTable.fromG(t.g);

  final int button;
  final int? sb;
  final int? bb;
  final List<int> order;
  final List<String> board;
  final int potCents;
  final List<HoldemPot> pots;
  final int currentBetCents;
  final int minRaiseCents;
  final HoldemToAct? toAct;
  final HoldemResult? result;
}

/// Seat `g` of a hold'em seat (`HoldemSeat`).
@immutable
class HoldemSeatState {
  const HoldemSeatState({
    this.inHand = false,
    this.folded = false,
    this.allIn = false,
    this.betCents = 0,
    this.committedCents = 0,
    this.lastAction,
    this.waitBB = false,
    this.timeouts = 0,
    this.handsOut = 0,
    this.shown,
  });

  factory HoldemSeatState.fromG(Map<String, Object?> g) => HoldemSeatState(
        inHand: asBool(g['inHand']),
        folded: asBool(g['folded']),
        allIn: asBool(g['allIn']),
        betCents: asInt(g['betCents']),
        committedCents: asInt(g['committedCents']),
        lastAction: enumByName(HoldemLastAction.values, g['lastAction']),
        waitBB: asBool(g['waitBB']),
        timeouts: asInt(g['timeouts']),
        handsOut: asInt(g['handsOut']),
        shown: g['shown'] is List ? asStringList(g['shown']) : null,
      );

  factory HoldemSeatState.of(GameSeat s) => HoldemSeatState.fromG(s.g);

  final bool inHand;
  final bool folded;
  final bool allIn;
  final int betCents;
  final int committedCents;
  final HoldemLastAction? lastAction;
  final bool waitBB;
  final int timeouts;
  final int handsOut;
  final List<String>? shown;

  /// Still holding cards in the current hand.
  bool get live => inHand && !folded;
}

/// `table.step` of a hold'em table (null outside a hand).
HoldemStep? holdemStepOf(GameTableState t) => enumByName(HoldemStep.values, t.step);

/// Whether [seat] is dealt in a hand that is being played (rebuy refused).
bool holdemInLiveHand(GameTableState t, GameSeat seat) {
  final step = holdemStepOf(t);
  return t.phase == GamePhase.live && step != HoldemStep.waiting && HoldemSeatState.of(seat).inHand;
}

/// Total chips in the middle: the pot plus every bet in front of a seat.
int holdemChipsInMiddle(GameTableState t) {
  var total = HoldemTable.of(t).potCents;
  for (final s in t.seats) {
    if (s != null) total += HoldemSeatState.of(s).betCents;
  }
  return total;
}
