/// Logical layout of the baccarat stage (1000 × 1300 units). OWNER: baccarat
/// implementer — placeholder values: shoe, Player / Banker boxes, squeeze
/// area and trend boards still have to be placed.
library;

import 'dart:ui';

import '../../stage/stage_geometry.dart';

class BaccaratGeometry extends StageGeometry {
  const BaccaratGeometry();

  @override
  int get seatCount => 7;

  @override
  List<Offset> get seatSpots => StageGeometry.arcSeats(7, center: const Offset(500, 720), radiusX: 410, radiusY: 420, fromDeg: 20, toDeg: 160);

  /// Where the Player and Banker hands are laid out.
  Offset get playerBox => const Offset(330, 600);
  Offset get bankerBox => const Offset(670, 600);
  Offset get shoe => const Offset(860, 380);
}
