/// Procedural characters (Sprint 2): what a character looks like, as data.
/// [CharacterPainter] (`character_painter.dart`) draws any [CharacterSpec]
/// with any [CharacterExpression]; the same painter serves the visual-novel
/// busts, the medallions and the croupiers' heads on the game stages.
/// The cast of the Rendez-vous meta is described in `cast.dart`.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 8 hairstyles.
enum HairStyle {
  /// Short, swept, side part (Lucas).
  sidePart,

  /// Very short all over.
  buzz,

  /// Chin-length bob with a fringe.
  bob,

  /// Long and straight, past the shoulders.
  long,

  /// Tied high at the back.
  ponytail,

  /// Gathered in a bun on top.
  bun,

  /// Short to mid-length curls.
  curly,

  /// Shaved sides, longer swept top.
  undercut,
}

/// What the character wears (drawn on the shoulders / chest).
enum Outfit {
  /// Croupier: white shirt, waistcoat, bow tie slot.
  dealerVest,

  /// Croupier: fitted dress with a waistcoat-like bodice.
  dealerDress,

  /// Bar: dark shirt, rolled sleeves, apron straps.
  bartender,

  /// Pianist: tuxedo jacket with satin lapels.
  tuxedo,

  /// Magician: high collar and cape.
  magician,

  /// VIP concierge: suit jacket and tie.
  concierge,

  /// Casual top (players, off-duty).
  casual,
}

/// Small extras, any combination.
enum Accessory { glasses, earrings, bowTie, necktie, nameTag, necklace, flower, topHat, headband }

/// 8 facial expressions.
enum CharacterExpression { neutral, smile, laugh, wink, surprised, blush, sad, thinking }

/// Facial hair.
enum FacialHair { none, stubble, moustache }

/// How the character is framed by [CharacterPainter].
enum CharacterFraming {
  /// Head and shoulders (visual novel, stages).
  bust,

  /// Head only (lists, seat plates).
  head,

  /// Head in a round badge with a background (medallions, selector).
  medallion,
}

/// Role of a character in the casino (Rendez-vous meta).
enum CharacterRole { dealer, regular, player }

/// Pronouns, for texts (Alex uses « iel » / they).
enum CharacterPronoun { she, he, they }

/// A character's look. Colors are plain ARGB; everything is deterministic.
@immutable
class CharacterSpec {
  const CharacterSpec({
    required this.id,
    required this.name,
    required this.age,
    required this.pronoun,
    required this.role,
    required this.skin,
    required this.hair,
    required this.hairStyle,
    required this.eyes,
    required this.outfit,
    required this.outfitPrimary,
    required this.outfitSecondary,
    this.outfitAccent = const Color(0xFFE0C068),
    this.accessories = const {},
    this.lips = const Color(0xFFB4655A),
    this.facialHair = FacialHair.none,
    this.faceWidth = 1.0,
    this.freckles = false,
    this.medallionColor = const Color(0xFF14202B),
  }) : assert(faceWidth >= 0.85 && faceWidth <= 1.15);

  /// `CHARACTER_IDS` value (or any stable id for players / previews).
  final String id;

  /// Display name (proper noun, identical in every language).
  final String name;

  /// Every character is an adult (24–38).
  final int age;
  final CharacterPronoun pronoun;
  final CharacterRole role;

  final Color skin;
  final Color hair;
  final HairStyle hairStyle;
  final Color eyes;
  final Outfit outfit;

  /// Main garment color (waistcoat, dress, jacket, cape).
  final Color outfitPrimary;

  /// Shirt / lining color.
  final Color outfitSecondary;

  /// Trim, tie, badges.
  final Color outfitAccent;
  final Set<Accessory> accessories;
  final Color lips;
  final FacialHair facialHair;

  /// Face width factor (0.85..1.15).
  final double faceWidth;
  final bool freckles;

  /// Background of the medallion framing.
  final Color medallionColor;

  bool has(Accessory a) => accessories.contains(a);

  CharacterSpec copyWith({HairStyle? hairStyle, Outfit? outfit, Set<Accessory>? accessories, Color? hair}) => CharacterSpec(
        id: id,
        name: name,
        age: age,
        pronoun: pronoun,
        role: role,
        skin: skin,
        hair: hair ?? this.hair,
        hairStyle: hairStyle ?? this.hairStyle,
        eyes: eyes,
        outfit: outfit ?? this.outfit,
        outfitPrimary: outfitPrimary,
        outfitSecondary: outfitSecondary,
        outfitAccent: outfitAccent,
        accessories: accessories ?? this.accessories,
        lips: lips,
        facialHair: facialHair,
        faceWidth: faceWidth,
        freckles: freckles,
        medallionColor: medallionColor,
      );
}

/// Pose of a character for one frame (all values deterministic inputs).
@immutable
class CharacterPose {
  const CharacterPose({
    this.expression = CharacterExpression.neutral,
    this.level = 1,
    this.blink = 0,
    this.breath = 0.5,
    this.talk = 0,
    this.headTilt = 0,
    this.gaze = Offset.zero,
  });

  final CharacterExpression expression;

  /// Strength of [expression] (0 = neutral face, 1 = full).
  final double level;

  /// 0 = eyes open, 1 = closed.
  final double blink;

  /// 0..1 breathing phase (shoulders rise at 1).
  final double breath;

  /// 0..1 mouth opening while speaking (visual novel).
  final double talk;

  /// Head roll in radians.
  final double headTilt;

  /// Pupils offset, each axis in -1..1.
  final Offset gaze;

  @override
  bool operator ==(Object other) =>
      other is CharacterPose &&
      other.expression == expression &&
      other.level == level &&
      other.blink == blink &&
      other.breath == breath &&
      other.talk == talk &&
      other.headTilt == headTilt &&
      other.gaze == gaze;
  @override
  int get hashCode => Object.hash(expression, level, blink, breath, talk, headTilt, gaze);
}

/// Deterministic blink (0..1) at [clockMs] for a character offset by [phaseMs]
/// (so two characters never blink together): a 150 ms blink every ~3.7 s,
/// a double blink every third cycle.
double blinkAt(int clockMs, {int phaseMs = 0, int periodMs = 3700}) {
  final ms = clockMs + phaseMs;
  final cycle = ms ~/ periodMs;
  final t = ms % periodMs;
  double one(int start) {
    final d = t - start;
    if (d < 0 || d > 150) return 0;
    return 1 - ((d - 75).abs() / 75);
  }

  final b = one(0);
  return cycle % 3 == 2 ? (b > one(230) ? b : one(230)) : b;
}

/// Deterministic breathing phase (0..1) at [clockMs] (period 4.2 s).
double breathAt(int clockMs, {int phaseMs = 0, int periodMs = 4200}) =>
    (math.sin((clockMs + phaseMs) / periodMs * 2 * math.pi) + 1) / 2;
