/// Logical layout of the craps stage (1000 × 1300 units). OWNER: craps
/// implementer — placeholder values: the layout (pass line, come, field,
/// place numbers, propositions), the pyramid back wall, the stickman and the
/// ON/OFF puck still have to be placed.
library;

import 'dart:ui';

import '../../stage/stage_geometry.dart';

class CrapsGeometry extends StageGeometry {
  const CrapsGeometry();

  @override
  int get seatCount => 8;

  @override
  List<Offset> get seatSpots => StageGeometry.arcSeats(8, center: const Offset(500, 730), radiusX: 420, radiusY: 430, fromDeg: 12, toDeg: 168);

  /// The back wall the dice bounce on, and where they come to rest.
  Rect get backWall => const Rect.fromLTWH(120, 330, 760, 24);
  Offset get diceRest => const Offset(500, 520);
}
