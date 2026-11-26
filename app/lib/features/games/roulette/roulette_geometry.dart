/// Logical layout of the roulette stage (1000 × 1300 units). OWNER: roulette
/// implementer — placeholder values: the wheel, the betting layout and the
/// racetrack still have to be placed (PLAN_SPRINT2.md « Animations par jeu »).
library;

import 'dart:ui';

import '../../stage/stage_geometry.dart';

class RouletteGeometry extends StageGeometry {
  const RouletteGeometry();

  @override
  int get seatCount => 7;

  @override
  List<Offset> get seatSpots => StageGeometry.arcSeats(7, center: const Offset(500, 760), radiusX: 400, radiusY: 380, fromDeg: 22, toDeg: 158);

  /// Centre of the wheel (to the croupier's right, like a real table).
  Offset get wheelCenter => const Offset(790, 500);
  double get wheelRadius => 150;
}
