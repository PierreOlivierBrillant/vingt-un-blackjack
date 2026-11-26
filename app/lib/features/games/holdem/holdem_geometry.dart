/// Logical layout of the hold'em stage (1000 × 1300 units). OWNER: hold'em
/// implementer — placeholder values: board cards, pot(s), burn pile and the
/// dealer button positions still have to be placed.
library;

import 'dart:ui';

import '../../stage/stage_geometry.dart';

class HoldemGeometry extends StageGeometry {
  const HoldemGeometry();

  @override
  int get seatCount => 6;

  /// Around an oval table, the croupier at the top.
  @override
  List<Offset> get seatSpots => StageGeometry.arcSeats(6, center: const Offset(500, 790), radiusX: 400, radiusY: 360, fromDeg: 0, toDeg: 180);

  /// Centre of the five board cards and of the pot.
  Offset get boardCenter => const Offset(500, 660);
  Offset get potCenter => const Offset(500, 800);
}
