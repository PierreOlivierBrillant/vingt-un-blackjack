/// Logical layout of the baccarat stage (1000 × 1300 units, see
/// [StageGeometry]): Inès behind the table, the shoe on her left (screen
/// right), the discard tray on her right, the Player (left, blue) and
/// Banker (right, red) boxes, the trend boards in the middle of the felt
/// and the 7 seats on the arc below.
library;

import 'dart:ui';

import '../../stage/stage_geometry.dart';

class BaccaratGeometry extends StageGeometry {
  const BaccaratGeometry();

  @override
  int get seatCount => 7;

  @override
  List<Offset> get seatSpots => StageGeometry.arcSeats(7, center: const Offset(500, 720), radiusX: 410, radiusY: 420, fromDeg: 20, toDeg: 160);

  /// Size of a dealt card (poker ratio 63 × 88).
  static const cardSize = Size(100, 140);

  /// Centres of the Player and Banker boxes.
  Offset get playerBox => const Offset(300, 520);
  Offset get bankerBox => const Offset(700, 520);
  Size get boxSize => const Size(372, 186);

  Offset box(bool player) => player ? playerBox : bankerBox;

  /// Where card [index] (0, 1, 2 = third card, laid sideways) of a hand lies.
  Offset cardSlot(bool player, int index) {
    final c = box(player);
    return switch (index) {
      0 => c + Offset(player ? 6 : -110, 0),
      1 => c + Offset(player ? 112 : -4, 0),
      _ => c + Offset(player ? -112 : 112, 6), // sideways, on the outer side
    };
  }

  /// Rotation of a dealt card (the third card lies sideways).
  double cardRotation(bool player, int index) => index == 2 ? (player ? -1.5708 : 1.5708) : 0;

  /// Squeeze position of a card (lifted towards the players, bigger).
  Offset squeezeSpot(bool player, int index) {
    final c = box(player);
    return switch (index) {
      0 => c + Offset(player ? -30 : -120, 48),
      1 => c + Offset(player ? 120 : 30, 48),
      _ => c + const Offset(0, 60),
    };
  }

  /// Badge with the hand total, under the box.
  Offset totalBadge(bool player) => box(player) + const Offset(0, 112);

  /// The shoe (cards leave it at [shoeMouth]).
  Offset get shoe => const Offset(868, 368);
  Offset get shoeMouth => const Offset(820, 392);

  /// Discard tray (burned and played cards).
  Offset get discard => const Offset(132, 368);

  /// Where the burn card is shown face up.
  Offset get burnShow => const Offset(500, 420);

  /// The croupier's chip tray (payouts leave from it, lost bets go to it).
  Offset get chipTray => const Offset(500, 352);

  /// Trend boards (Bead Plate | Big Road / Big Eye Boy).
  Rect get roads => const Rect.fromLTRB(176, 660, 824, 880);
}
