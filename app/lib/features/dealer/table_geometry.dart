import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where a card goes: the dealer's hand or one hand of a seat.
@immutable
class HandTarget {
  const HandTarget.dealer()
      : seat = -1,
        hand = 0;
  const HandTarget.seat(this.seat, {this.hand = 0}) : assert(seat >= 0);

  /// -1 for the dealer.
  final int seat;

  /// Index of the split hand (0 before any split).
  final int hand;
  bool get isDealer => seat < 0;

  @override
  bool operator ==(Object other) => other is HandTarget && other.seat == seat && other.hand == hand;
  @override
  int get hashCode => Object.hash(seat, hand);
  @override
  String toString() => isDealer ? 'dealer' : 'seat$seat/h$hand';
}

/// Fixed logical layout of the table (1000 × 1300 units, portrait). The stage
/// widget scales it to the available width, so all animation maths happen in
/// one resolution-independent space.
class TableGeometry {
  const TableGeometry();

  static const size = Size(1000, 1300);
  static const seatCount = 5;

  static const cardWidth = 112.0;
  static const cardHeight = cardWidth * 88 / 63;

  // Dealer body.
  static const headCenter = Offset(500, 128);
  static const headRadius = 60.0;
  static const leftShoulder = Offset(408, 248);
  static const rightShoulder = Offset(592, 248);
  static const upperArm = 172.0;
  static const foreArm = 168.0;
  static const reach = (upperArm + foreArm) * 0.94;
  static const leftHandRest = Offset(452, 470);
  static const rightHandRest = Offset(548, 470);

  // Felt furniture.
  static const feltTop = 312.0;
  static const feltBottom = 1262.0;
  static const rackCenter = Offset(500, 362);
  static const rackSize = Size(330, 58);
  static const shoeCenter = Offset(858, 372);
  static const shoeExit = Offset(790, 402);
  static const discardCenter = Offset(140, 382);
  static const shuffleCenter = Offset(500, 548);

  /// Betting-circle centres. Seat 0 is "first base" (the dealer's left,
  /// i.e. screen right); dealing goes 0 → 4.
  static const seatSpots = <Offset>[
    Offset(872, 1004),
    Offset(688, 1112),
    Offset(500, 1150),
    Offset(312, 1112),
    Offset(128, 1004),
  ];

  static const dealerCardsOrigin = Offset(432, 596);
  static const dealerCardSpacing = cardWidth * 0.66;

  Offset seatSpot(int seat) => seatSpots[seat];

  /// Where a seat's chips sit for hand [hand] out of [handCount].
  Offset betSpot(int seat, {int hand = 0, int handCount = 1}) {
    final base = seatSpots[seat];
    if (handCount <= 1) return base;
    return base + Offset(_handOffset(hand, handCount), -6);
  }

  double _handOffset(int hand, int handCount) => (hand - (handCount - 1) / 2) * cardWidth * 1.12;

  /// Cards lean towards the dealer.
  double seatRotation(int seat) => (seatSpots[seat].dx - 500) / 500 * -0.22;

  /// Resting centre of card [index] of [target].
  Offset cardRest(HandTarget target, int index, {int handCount = 1}) {
    if (target.isDealer) {
      return dealerCardsOrigin + Offset(index * dealerCardSpacing, 0);
    }
    final base = seatSpots[target.seat] + const Offset(0, -168);
    final hx = handCount <= 1 ? 0.0 : _handOffset(target.hand, handCount);
    // Fan towards the table centre so edge seats stay on the felt.
    final dir = seatSpots[target.seat].dx > 520 ? -1.0 : 1.0;
    final step = handCount > 1 ? 0.2 : 0.26;
    return base + Offset(hx + dir * index * cardWidth * step, -index * cardHeight * 0.17);
  }

  double cardRestRotation(HandTarget target) => target.isDealer ? 0 : seatRotation(target.seat);

  /// Point below a seat where a player's own chips come from / go to.
  Offset playerPocket(int seat) => seatSpots[seat] + const Offset(0, 230);

  /// Centre of the "insurance" arc printed on the felt (see FeltPainter).
  static const insuranceArcCenter = Offset(500, 300);
  static const insuranceArcRadius = 470.0;

  /// Where a seat's insurance bet sits: on the insurance arc, in front of it.
  Offset insuranceSpot(int seat) {
    final d = seatSpots[seat] - insuranceArcCenter;
    return insuranceArcCenter + d / d.distance * (insuranceArcRadius + 38);
  }
}
