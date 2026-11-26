/// Logical layout of a game table stage (Sprint 2). Every game provides its
/// own subclass in `lib/features/games/<jeu>/<jeu>_geometry.dart`; all
/// animation maths happen in this resolution-independent space (default
/// 1000 × 1300 units, portrait, like the blackjack `TableGeometry`), and
/// [StageView] scales it to the available width.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

@immutable
abstract class StageGeometry {
  const StageGeometry();

  /// Logical size of the stage.
  Size get size => const Size(1000, 1300);

  /// Number of seats (`GAME_SEATS[game]`).
  int get seatCount;

  /// Centre of each seat's betting spot / player position, seat 0 first
  /// (seat 0 = the dealer's left, i.e. screen right, like blackjack).
  List<Offset> get seatSpots;

  /// The felt area (below the croupier).
  Rect get felt => Rect.fromLTRB(0, 312, size.width, size.height - 38);

  // ------------------------------------------------------------- croupier --

  /// Centre of the croupier's head (CharacterPainter bust anchored on it).
  Offset get dealerHead => const Offset(500, 128);

  /// Head radius in stage units (scales the bust).
  double get dealerHeadRadius => 60;

  Offset get leftShoulder => const Offset(408, 248);
  Offset get rightShoulder => const Offset(592, 248);
  double get upperArm => 172;
  double get foreArm => 168;
  Offset get leftHandRest => const Offset(452, 470);
  Offset get rightHandRest => const Offset(548, 470);

  /// Comfortable reach of one arm (beyond it, objects are "pitched").
  double get reach => (upperArm + foreArm) * 0.94;

  // -------------------------------------------------------------- helpers --

  Offset seatSpot(int seat) => seatSpots[seat];

  /// Where a seat's own chips come from / go to (below its spot).
  Offset playerPocket(int seat) => seatSpots[seat] + const Offset(0, 230);

  /// Objects in front of a seat lean towards the dealer.
  double seatRotation(int seat) => (seatSpots[seat].dx - size.width / 2) / (size.width / 2) * -0.22;

  /// [count] seats on an elliptical arc around [center] (angles in degrees,
  /// 0° = right, 90° = down), from [fromDeg] (seat 0) to [toDeg].
  static List<Offset> arcSeats(int count, {required Offset center, required double radiusX, required double radiusY, double fromDeg = 20, double toDeg = 160}) {
    if (count == 1) return [center + Offset(0, radiusY)];
    return [
      for (var i = 0; i < count; i++)
        () {
          final a = (fromDeg + (toDeg - fromDeg) * i / (count - 1)) * math.pi / 180;
          return center + Offset(math.cos(a) * radiusX, math.sin(a) * radiusY);
        }(),
    ];
  }
}
