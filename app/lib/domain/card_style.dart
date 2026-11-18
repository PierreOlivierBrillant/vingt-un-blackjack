import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

/// Card faces. The enum names ARE the server's `CARD_FACES` wire values.
enum CardFaceStyle { classic, fourColor, neon }

enum CardBackDesign { lattice, stripes, chevron, dots, sunburst }

/// Back colours offered in the customisation screen.
const kCardBackColors = <Color>[
  Color(0xFFB3123A), // 0 casino red
  Color(0xFF1457C9), // 1 royal blue
  Color(0xFF0E7A3E), // 2 emerald
  Color(0xFF5B2BB5), // 3 violet
  Color(0xFF14181F), // 4 midnight
  Color(0xFFC77D0A), // 5 amber
];

/// Felts. [wire] is the server's `FELTS` value (`users/{uid}.felt`).
enum FeltColor {
  green('green', Color(0xFF0B6B3A), Color(0xFF064A27)),
  navy('blue', Color(0xFF17406B), Color(0xFF0C2440)),
  crimson('red', Color(0xFF7A1424), Color(0xFF4C0A15)),
  purple('purple', Color(0xFF4A2380), Color(0xFF2B124D)),
  charcoal('black', Color(0xFF2A3138), Color(0xFF15191D));

  const FeltColor(this.wire, this.light, this.dark);
  final String wire;
  final Color light;
  final Color dark;

  static FeltColor? fromWire(Object? v) {
    for (final f in values) {
      if (f.wire == v) return f;
    }
    return null;
  }
}

/// The server's 6 card backs (`CARD_BACKS`), each = one design + one colour.
/// THE single mapping between the client renderer and the backend enum. The
/// enum names ARE the wire values.
enum CardBackId {
  classicBlue(CardBackDesign.lattice, 1),
  classicRed(CardBackDesign.lattice, 0),
  midnight(CardBackDesign.stripes, 4),
  emerald(CardBackDesign.chevron, 2),
  neonGrid(CardBackDesign.dots, 3),
  goldFiligree(CardBackDesign.sunburst, 5);

  const CardBackId(this.design, this.colorIndex);
  final CardBackDesign design;
  final int colorIndex;
  Color get color => kCardBackColors[colorIndex];

  static CardBackId? fromWire(Object? v) {
    for (final b in values) {
      if (b.name == v) return b;
    }
    return null;
  }

  /// Exact server back for [style], or null if the combination is not one of
  /// the 6 server backs.
  static CardBackId? of(CardStyle style) {
    for (final b in values) {
      if (b.design == style.back && b.colorIndex == style.backColorIndex % kCardBackColors.length) return b;
    }
    return null;
  }

  /// Exact match, else the back with the same colour, else the same design,
  /// else [classicBlue] (the server default).
  static CardBackId nearest(CardStyle style) {
    final exact = of(style);
    if (exact != null) return exact;
    final ci = style.backColorIndex % kCardBackColors.length;
    for (final b in values) {
      if (b.colorIndex == ci) return b;
    }
    for (final b in values) {
      if (b.design == style.back) return b;
    }
    return classicBlue;
  }
}

@immutable
class CardStyle {
  const CardStyle({
    this.face = CardFaceStyle.classic,
    this.back = CardBackDesign.lattice,
    this.backColorIndex = 0,
    this.felt = FeltColor.green,
  });

  /// Style equipped on the server (`users/{uid}` cardBack/cardFace/felt).
  factory CardStyle.fromServer({required CardBackId back, required CardFaceStyle face, required FeltColor felt}) =>
      CardStyle(face: face, back: back.design, backColorIndex: back.colorIndex, felt: felt);

  /// Parses the wire values, falling back to the server defaults
  /// (classicBlue / classic / green).
  factory CardStyle.fromWire({Object? cardBack, Object? cardFace, Object? felt}) => CardStyle.fromServer(
        back: CardBackId.fromWire(cardBack) ?? CardBackId.classicBlue,
        face: _faceFromWire(cardFace) ?? CardFaceStyle.classic,
        felt: FeltColor.fromWire(felt) ?? FeltColor.green,
      );

  /// Server default of a new profile.
  static const serverDefault = CardStyle(backColorIndex: 1);

  final CardFaceStyle face;
  final CardBackDesign back;
  final int backColorIndex;
  final FeltColor felt;

  Color get backColor => kCardBackColors[backColorIndex % kCardBackColors.length];

  /// The server back this style maps to ([CardBackId.nearest]).
  CardBackId get serverBack => CardBackId.nearest(this);

  /// True when the style is exactly representable on the server.
  bool get isServerStyle => CardBackId.of(this) != null;

  /// Style after a round trip through the server enums.
  CardStyle get normalized => CardStyle.fromServer(back: serverBack, face: face, felt: felt);

  /// `equipCardStyle` payload (without requestId).
  Map<String, Object?> toWire() => {'cardBack': serverBack.name, 'cardFace': face.name, 'felt': felt.wire};

  CardStyle copyWith({
    CardFaceStyle? face,
    CardBackDesign? back,
    int? backColorIndex,
    FeltColor? felt,
  }) =>
      CardStyle(
        face: face ?? this.face,
        back: back ?? this.back,
        backColorIndex: backColorIndex ?? this.backColorIndex,
        felt: felt ?? this.felt,
      );

  /// Same style with one of the 6 server backs.
  CardStyle withServerBack(CardBackId b) => copyWith(back: b.design, backColorIndex: b.colorIndex);

  @override
  bool operator ==(Object other) =>
      other is CardStyle &&
      other.face == face &&
      other.back == back &&
      other.backColorIndex == backColorIndex &&
      other.felt == felt;

  @override
  int get hashCode => Object.hash(face, back, backColorIndex, felt);
}

CardFaceStyle? _faceFromWire(Object? v) {
  for (final f in CardFaceStyle.values) {
    if (f.name == v) return f;
  }
  return null;
}
