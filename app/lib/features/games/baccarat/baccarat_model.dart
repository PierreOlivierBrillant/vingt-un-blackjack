/// Client mirror of the baccarat public state (`gameTables/{bc-…}.g`,
/// `rounds/{n}.result`), exactly as documented in
/// `firebase/functions/src/shared/games/baccarat.ts`. Parsing is tolerant
/// (missing / mistyped fields fall back to safe values, never throw), like
/// `GameTableState.fromDoc`.
library;

import 'package:flutter/foundation.dart';

import '../../../domain/game_table.dart';
import '../../../domain/wire.dart';

/// Bet spots (`BACCARAT_SPOTS`), board order.
enum BaccaratSpot {
  player('player', 1),
  tie('tie', 8),
  banker('banker', 0.95),
  playerPair('playerPair', 11),
  bankerPair('bankerPair', 11);

  const BaccaratSpot(this.wire, this.payout);
  final String wire;

  /// Winnings per unit staked ("to 1").
  final double payout;

  bool get isMain => this == player || this == banker;
  static BaccaratSpot? fromWire(Object? v) => values.where((s) => s.wire == v).firstOrNull;
}

enum BaccaratWinner { player, banker, tie }

/// `BACCARAT_TIMING` (ms) — the client animation fits the server's 'dealing' step.
abstract final class BaccaratTiming {
  static const bettingMs = 20000;
  static const burnMs = 2600;
  static const cardMs = 650;
  static const thirdCardMs = 1500;
  static const revealMs = 2600;
  static const settledMs = 5000;

  /// Same formula as the server's `dealingMs`.
  static int dealingMs({required bool burn, required int thirds}) => (burn ? burnMs : 0) + 4 * cardMs + thirds * thirdCardMs + revealMs;
}

abstract final class BaccaratRules {
  static const decks = 8;
  static const shoeSize = 416;
  static const cutCards = 16;
  static const shoeThresholdPct = 46;
}

/// Baccarat value of a wire card code: ace 1, 2–9 face value, ten / faces 0.
int baccaratValue(String code) {
  final r = code.isEmpty ? '' : code[0];
  return switch (r) {
    'A' => 1,
    'T' || 'J' || 'Q' || 'K' || '1' => 0, // '1' = "10…" (long form)
    _ => int.tryParse(r) ?? 0,
  };
}

int baccaratTotal(Iterable<String> cards) => cards.fold(0, (t, c) => t + baccaratValue(c)) % 10;

/// Number of cards burned after the burn card (ace 1, 2–9, ten / faces 10).
int baccaratBurnCount(String code) {
  final v = baccaratValue(code);
  return v == 0 ? 10 : v;
}

bool baccaratPair(List<String> cards) => cards.length >= 2 && cards[0].isNotEmpty && cards[1].isNotEmpty && cards[0][0] == cards[1][0];

/// Player draws on 0–5.
bool baccaratPlayerDraws(int total) => total <= 5;

/// Banker's drawing rule (no natural); [playerThird] null = Player stood.
bool baccaratBankerDraws(int bankerTotal, int? playerThird) {
  final p = playerThird;
  if (p == null) return bankerTotal <= 5;
  return switch (bankerTotal) {
    0 || 1 || 2 => true,
    3 => p != 8,
    4 => p >= 2 && p <= 7,
    5 => p >= 4 && p <= 7,
    6 => p == 6 || p == 7,
    _ => false,
  };
}

/// One coup (`BaccaratCoupPublic`, or a round's `result`).
@immutable
class BaccaratCoup {
  const BaccaratCoup({
    required this.player,
    required this.banker,
    required this.playerTotal,
    required this.bankerTotal,
    required this.winner,
    this.natural = false,
    this.playerPair = false,
    this.bankerPair = false,
    this.burnCard,
    this.burnCount = 0,
    this.burned = const [],
  });

  static BaccaratCoup? fromDoc(Object? raw) {
    final d = asMap(raw);
    final p = asStringList(d['player']);
    final b = asStringList(d['banker']);
    if (p.length < 2 || b.length < 2) return null;
    final burn = asMap(d['burn']);
    final pt = d['playerTotal'] is num ? asInt(d['playerTotal']) : baccaratTotal(p);
    final bt = d['bankerTotal'] is num ? asInt(d['bankerTotal']) : baccaratTotal(b);
    return BaccaratCoup(
      player: p,
      banker: b,
      playerTotal: pt,
      bankerTotal: bt,
      winner: enumByName(BaccaratWinner.values, d['winner']) ?? (pt > bt ? BaccaratWinner.player : bt > pt ? BaccaratWinner.banker : BaccaratWinner.tie),
      natural: asBool(d['natural']),
      playerPair: asBool(d['playerPair']),
      bankerPair: asBool(d['bankerPair']),
      burnCard: asString(burn['card']),
      burnCount: asInt(burn['count']),
      burned: asStringList(burn['cards']),
    );
  }

  /// Cards in deal order (index 2 = third card, laid sideways).
  final List<String> player;
  final List<String> banker;
  final int playerTotal;
  final int bankerTotal;
  final BaccaratWinner winner;
  final bool natural;
  final bool playerPair;
  final bool bankerPair;

  /// First coup of a shoe: the burn card shown face up and how many cards were burned.
  final String? burnCard;
  final int burnCount;

  /// The burned cards (round documents only, revealed with the proof).
  final List<String> burned;

  bool get hasBurn => burnCard != null;
  bool get anyPair => playerPair || bankerPair;
  int get thirdCards => (player.length > 2 ? 1 : 0) + (banker.length > 2 ? 1 : 0);

  /// The coup's cards in deal order: P1 B1 P2 B2 (P3) (B3).
  List<(bool player, int index, String card)> get dealOrder => [
        (true, 0, player[0]),
        (false, 0, banker[0]),
        (true, 1, player[1]),
        (false, 1, banker[1]),
        if (player.length > 2) (true, 2, player[2]),
        if (banker.length > 2) (false, 2, banker[2]),
      ];

  /// Total of a hand after its first [n] cards.
  int totalAfter({required bool isPlayer, required int n}) => baccaratTotal((isPlayer ? player : banker).take(n));
}

/// One coup of the shoe (`BaccaratBead`).
@immutable
class BaccaratBead {
  const BaccaratBead({required this.winner, this.round = 0, this.player = 0, this.banker = 0, this.playerPair = false, this.bankerPair = false, this.natural = false});

  static BaccaratBead? fromDoc(Object? raw) {
    final d = asMap(raw);
    final w = switch (d['w']) {
      'P' => BaccaratWinner.player,
      'B' => BaccaratWinner.banker,
      'T' => BaccaratWinner.tie,
      _ => null,
    };
    if (w == null) return null;
    return BaccaratBead(
      winner: w,
      round: asInt(d['round']),
      player: asInt(d['p']),
      banker: asInt(d['b']),
      playerPair: asBool(d['pp']),
      bankerPair: asBool(d['bp']),
      natural: asBool(d['nat']),
    );
  }

  final BaccaratWinner winner;
  final int round;
  final int player;
  final int banker;
  final bool playerPair;
  final bool bankerPair;
  final bool natural;

  /// Total of the winning hand (either on a tie).
  int get winningTotal => winner == BaccaratWinner.player ? player : banker;
}

/// Shoe counters (`BaccaratShoePublic`).
@immutable
class BaccaratShoe {
  const BaccaratShoe({
    this.number = 1,
    this.total = BaccaratRules.shoeSize,
    this.remaining = BaccaratRules.shoeSize,
    this.cutAt = BaccaratRules.cutCards,
    this.coups = 0,
    this.banker = 0,
    this.player = 0,
    this.tie = 0,
    this.cutOut = false,
  });

  factory BaccaratShoe.fromDoc(Object? raw) {
    final d = asMap(raw);
    return BaccaratShoe(
      number: asInt(d['n'], 1),
      total: asInt(d['total'], BaccaratRules.shoeSize),
      remaining: asInt(d['remaining'], BaccaratRules.shoeSize),
      cutAt: asInt(d['cutAt'], BaccaratRules.cutCards),
      coups: asInt(d['coups']),
      banker: asInt(d['banker']),
      player: asInt(d['player']),
      tie: asInt(d['tie']),
      cutOut: asBool(d['cutOut']),
    );
  }

  final int number;
  final int total;
  final int remaining;
  final int cutAt;
  final int coups;
  final int banker;
  final int player;
  final int tie;
  final bool cutOut;

  double get fill => total <= 0 ? 0 : (remaining / total).clamp(0.0, 1.0);
}

/// `gameTables/{bc-…}.g`.
@immutable
class BaccaratTable {
  const BaccaratTable({this.shoe = const BaccaratShoe(), this.coup, this.beads = const [], this.seriesShoe});

  factory BaccaratTable.fromState(GameTableState t) => BaccaratTable.fromDoc(t.g);

  factory BaccaratTable.fromDoc(Map<String, Object?> g) => BaccaratTable(
        shoe: BaccaratShoe.fromDoc(g['shoe']),
        coup: BaccaratCoup.fromDoc(g['coup']),
        beads: [for (final b in asList(g['beads'])) ?BaccaratBead.fromDoc(b)],
        seriesShoe: asIntOrNull(asMap(g['series'])['shoe']),
      );

  final BaccaratShoe shoe;

  /// The coup being dealt / just settled (null while betting).
  final BaccaratCoup? coup;

  /// Coups of the current shoe, oldest first.
  final List<BaccaratBead> beads;

  /// Shoe of the running long market (sim tables), else null.
  final int? seriesShoe;
}

/// What a whole board returns against [coup] (stake included) — same rules
/// as the server's `settleBoard` (exact cents for whole-dollar bets).
int baccaratReturn(Map<String, int> board, BaccaratCoup coup, {bool freeCommission = false}) {
  var ret = 0;
  for (final e in board.entries) {
    final v = e.value;
    if (v <= 0) continue;
    ret += switch (BaccaratSpot.fromWire(e.key)) {
      BaccaratSpot.player => coup.winner == BaccaratWinner.player ? 2 * v : coup.winner == BaccaratWinner.tie ? v : 0,
      BaccaratSpot.banker => coup.winner == BaccaratWinner.banker
          ? 2 * v - (freeCommission ? 0 : v * 5 ~/ 100)
          : coup.winner == BaccaratWinner.tie
              ? v
              : 0,
      BaccaratSpot.tie => coup.winner == BaccaratWinner.tie ? 9 * v : 0,
      BaccaratSpot.playerPair => coup.playerPair ? 12 * v : 0,
      BaccaratSpot.bankerPair => coup.bankerPair ? 12 * v : 0,
      null => 0,
    };
  }
  return ret;
}
