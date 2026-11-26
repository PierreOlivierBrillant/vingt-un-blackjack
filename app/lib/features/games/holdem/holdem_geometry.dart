/// Logical layout of the hold'em stage (1000 × 1300 units): Alex the croupier
/// at the top, the deck in front of their right hand, the burn pile in front
/// of the left one, the five board cards across the middle, the pot below
/// them, six seats around the lower half of the oval. Each seat has its hole
/// cards, its bet (chips pushed in front of it) and its dealer button spot on
/// the line from the seat to the centre of the table.
library;

import 'dart:ui';

import '../../stage/stage_geometry.dart';

class HoldemGeometry extends StageGeometry {
  const HoldemGeometry();

  @override
  int get seatCount => 6;

  /// Around an oval table, the croupier at the top (seat 0 = screen right).
  @override
  List<Offset> get seatSpots => StageGeometry.arcSeats(6, center: const Offset(500, 790), radiusX: 400, radiusY: 360, fromDeg: 0, toDeg: 180);

  /// Centre of the table (where bets travel to).
  Offset get tableCenter => const Offset(500, 800);

  /// Board cards.
  Offset get boardCenter => const Offset(500, 632);
  double get boardCardWidth => 92;
  double get boardGap => 12;
  Offset boardSlot(int i) => boardCenter + Offset((i - 2) * (boardCardWidth + boardGap), 0);

  /// The pot (chips) and its label below.
  Offset get potCenter => const Offset(500, 790);

  /// Where the deck sits and where burnt cards / mucked cards go.
  Offset get deckSpot => const Offset(640, 452);
  Offset get burnSpot => const Offset(362, 452);
  Offset get muckSpot => const Offset(430, 470);

  /// Hole cards.
  double get holeCardWidth => 64;
  double get myHoleCardWidth => 78;

  Offset _toward(int seat, double distance, {double side = 0}) {
    final s = seatSpot(seat);
    final d = tableCenter - s;
    final len = d.distance;
    final u = len == 0 ? const Offset(0, -1) : d / len;
    return s + u * distance + Offset(-u.dy, u.dx) * side;
  }

  /// Centre of a seat's two hole cards.
  Offset holeSpot(int seat) => _toward(seat, 96);

  /// Hole card [index] (0 or 1) of [seat], slightly fanned.
  Offset holeCardSpot(int seat, int index, {bool mine = false}) {
    final w = mine ? myHoleCardWidth : holeCardWidth;
    return holeSpot(seat) + Offset((index - 0.5) * w * 0.62, 0);
  }

  /// Chips the seat has in front of it on this street.
  Offset betSpot(int seat) => _toward(seat, 196);

  /// Dealer button / blind marker of a seat.
  Offset buttonSpot(int seat) => _toward(seat, 150, side: 74);

  /// Where a seat's chips come from / go to (on its seat ring).
  Offset pocket(int seat) => seatSpot(seat);
}
