/// Draws any [CharacterSpec] in code (no image asset): 8 hairstyles, outfits,
/// accessories, 8 expressions, blink, breathing and speech. One painter for
/// the visual-novel busts, the medallions (lobby selector, Rendez-vous hub)
/// and the croupiers' heads on the game stages.
///
/// Logical drawing space: [CharacterPainter.box] (400 × 480, head centre at
/// (200, 180)); [CharacterFraming] picks which part is fitted into the canvas.
/// Pure function of (spec, pose, framing): deterministic, golden-tested.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'character_spec.dart';

class CharacterPainter extends CustomPainter {
  const CharacterPainter({required this.spec, this.pose = const CharacterPose(), this.framing = CharacterFraming.bust});

  final CharacterSpec spec;
  final CharacterPose pose;
  final CharacterFraming framing;

  /// Logical size of the bust drawing.
  static const box = Size(400, 480);

  /// Head centre and radii in [box] units.
  static const headCenter = Offset(200, 180);
  static const headRy = 92.0;
  static double headRx(CharacterSpec s) => 74 * s.faceWidth;

  /// Part of [box] shown by each framing.
  static Rect viewportOf(CharacterFraming f) => switch (f) {
        CharacterFraming.bust => Offset.zero & box,
        CharacterFraming.head => const Rect.fromLTWH(70, 40, 260, 270),
        CharacterFraming.medallion => const Rect.fromLTWH(40, 30, 320, 320),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final view = viewportOf(framing);
    final scale = math.min(size.width / view.width, size.height / view.height);
    final dx = (size.width - view.width * scale) / 2;
    final dy = framing == CharacterFraming.bust ? size.height - view.height * scale : (size.height - view.height * scale) / 2;
    canvas.save();
    if (framing == CharacterFraming.medallion) {
      final c = Offset(size.width / 2, size.height / 2);
      final r = math.min(size.width, size.height) / 2;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [_shade(spec.medallionColor, 0.12), _shade(spec.medallionColor, -0.12)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.98)));
    }
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.translate(-view.left, -view.top);
    paintCharacter(canvas, spec, pose);
    canvas.restore();
    if (framing == CharacterFraming.medallion) {
      final c = Offset(size.width / 2, size.height / 2);
      final r = math.min(size.width, size.height) / 2;
      canvas.drawCircle(
        c,
        r - math.max(1.0, r * 0.04) / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, r * 0.04)
          ..color = spec.outfitAccent.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(CharacterPainter old) => old.spec != spec || old.pose != pose || old.framing != framing;
}

/// Paints [spec] in [CharacterPainter.box] coordinates (no framing).
void paintCharacter(Canvas canvas, CharacterSpec spec, CharacterPose pose) {
  _CharacterDrawer(canvas, spec, pose).draw();
}

Color _shade(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

class _Face {
  const _Face({
    this.brow = 0,
    this.browInner = 0,
    this.browAsym = 0,
    this.eyeOpen = 1,
    this.leftClosed = 0,
    this.smile = 0,
    this.open = 0,
    this.round = 0,
    this.mouthShift = 0,
    this.blush = 0,
    this.teeth = false,
  });
  final double brow, browInner, browAsym, eyeOpen, leftClosed, smile, open, round, mouthShift, blush;
  final bool teeth;

  static const neutral = _Face();

  static _Face of(CharacterExpression e) => switch (e) {
        CharacterExpression.neutral => neutral,
        CharacterExpression.smile => const _Face(brow: 0.15, eyeOpen: 0.88, smile: 0.75, blush: 0.15),
        CharacterExpression.laugh => const _Face(brow: 0.35, eyeOpen: 0.4, smile: 1, open: 0.8, blush: 0.4, teeth: true),
        CharacterExpression.wink => const _Face(brow: 0.2, browAsym: -0.4, leftClosed: 1, smile: 0.65, mouthShift: 5),
        CharacterExpression.surprised => const _Face(brow: 1, eyeOpen: 1.28, open: 0.75, round: 1),
        CharacterExpression.blush => const _Face(brow: 0.1, browInner: 0.3, eyeOpen: 0.78, smile: 0.4, blush: 1),
        CharacterExpression.sad => const _Face(browInner: 1, eyeOpen: 0.82, smile: -0.7, blush: 0),
        CharacterExpression.thinking => const _Face(brow: 0.1, browAsym: 0.8, eyeOpen: 0.92, smile: -0.1, mouthShift: 9),
      };

  _Face lerp(double t) {
    double l(double a) => a * t;
    return _Face(
      brow: l(brow),
      browInner: l(browInner),
      browAsym: l(browAsym),
      eyeOpen: 1 + (eyeOpen - 1) * t,
      leftClosed: l(leftClosed),
      smile: l(smile),
      open: l(open),
      round: l(round),
      mouthShift: l(mouthShift),
      blush: l(blush),
      teeth: teeth && t > 0.5,
    );
  }
}

class _CharacterDrawer {
  _CharacterDrawer(this.c, this.s, this.p)
      : rx = CharacterPainter.headRx(s),
        face = _Face.of(p.expression).lerp(p.level.clamp(0.0, 1.0));

  final Canvas c;
  final CharacterSpec s;
  final CharacterPose p;
  final double rx;
  final _Face face;

  static const ry = CharacterPainter.headRy;
  static const pivot = Offset(200, 262); // neck: head tilt pivot

  double get breathDy => -(p.breath - 0.5) * 5;
  Offset get hc => CharacterPainter.headCenter + Offset(0, breathDy * 0.6);
  Color get skinShade => _shade(s.skin, -0.1);
  Color get hairDark => _shade(s.hair, -0.08);
  Paint fill(Color color) => Paint()..color = color;
  Paint stroke(Color color, double w) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  void draw() {
    _hairBack();
    c.save();
    c.translate(0, breathDy);
    _torso();
    c.restore();
    _neck();
    c.save();
    c.translate(0, breathDy);
    _collarAccessories();
    c.restore();
    c.save();
    c.translate(pivot.dx, pivot.dy);
    c.rotate(p.headTilt);
    c.translate(-pivot.dx, -pivot.dy);
    _head();
    c.restore();
  }

  // ---------------------------------------------------------------- body --

  Path _torsoPath(double top) => Path()
    ..moveTo(200 - 64, top)
    ..cubicTo(200 - 140, top + 6, 200 - 178, top + 40, 200 - 186, 480)
    ..lineTo(200 + 186, 480)
    ..cubicTo(200 + 178, top + 40, 200 + 140, top + 6, 200 + 64, top)
    ..close();

  void _torso() {
    const top = 300.0;
    final body = _torsoPath(top);
    final bounds = body.getBounds();
    Paint garment(Color color) => Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_shade(color, 0.06), _shade(color, -0.06)],
      ).createShader(bounds);
    switch (s.outfit) {
      case Outfit.dealerVest:
        c.drawPath(body, garment(s.outfitSecondary)); // shirt
        final vest = Path.combine(ui.PathOperation.difference, body, _vNeck(top, 110, 96));
        c.drawPath(vest, garment(s.outfitPrimary));
        _buttons(top + 128, 3, s.outfitAccent);
        _shirtCollar(top);
      case Outfit.dealerDress:
        final bodice = Path.combine(ui.PathOperation.difference, body, _vNeck(top - 4, 70, 70));
        c.drawPath(body, fill(s.skin));
        c.drawPath(bodice, garment(s.outfitPrimary));
        c.drawPath(_vNeckLine(top - 4, 70, 70), stroke(s.outfitAccent, 3));
      case Outfit.bartender:
        c.drawPath(body, garment(s.outfitPrimary));
        c.drawPath(_shirtV(top, 46), fill(_shade(s.outfitPrimary, 0.08)));
        for (final x in [-58.0, 58.0]) {
          c.drawLine(Offset(200 + x, top + 30), Offset(200 + x * 0.8, 480), stroke(s.outfitSecondary, 14));
        }
        c.drawRect(const Rect.fromLTWH(200 - 70, top + 140, 140, 60), fill(s.outfitSecondary));
      case Outfit.tuxedo:
      case Outfit.concierge:
        c.drawPath(body, garment(s.outfitPrimary));
        c.drawPath(_vNeck(top, 120, 60), fill(s.outfitSecondary));
        final lapel = s.outfit == Outfit.tuxedo ? _shade(s.outfitPrimary, 0.12) : _shade(s.outfitPrimary, 0.05);
        for (final side in [-1.0, 1.0]) {
          final l = Path()
            ..moveTo(200 + side * 22, top + 8)
            ..lineTo(200 + side * 70, top + 2)
            ..lineTo(200 + side * 90, top + 60)
            ..lineTo(200 + side * 34, top + 132)
            ..close();
          c.drawPath(l, fill(lapel));
        }
        _shirtCollar(top);
        if (s.outfit == Outfit.concierge) {
          c.drawCircle(const Offset(200 - 96, top + 96), 9, fill(s.outfitAccent)); // VIP key badge
          c.drawCircle(const Offset(200 - 96, top + 96), 4, fill(_shade(s.outfitAccent, -0.25)));
        }
      case Outfit.magician:
        final cape = Path()
          ..moveTo(200 - 70, top - 6)
          ..cubicTo(200 - 170, top, 200 - 200, top + 60, 200 - 200, 480)
          ..lineTo(200 + 200, 480)
          ..cubicTo(200 + 200, top + 60, 200 + 170, top, 200 + 70, top - 6)
          ..close();
        c.drawPath(cape, garment(s.outfitPrimary));
        c.drawPath(_vNeck(top, 120, 54), fill(s.outfitSecondary));
        // Standing collar, lined.
        for (final side in [-1.0, 1.0]) {
          final collar = Path()
            ..moveTo(200 + side * 40, top - 2)
            ..quadraticBezierTo(200 + side * 120, top - 70, 200 + side * 142, top - 30)
            ..quadraticBezierTo(200 + side * 120, top + 10, 200 + side * 52, top + 14)
            ..close();
          c.drawPath(collar, fill(_shade(s.outfitPrimary, -0.08)));
          c.drawPath(collar, stroke(s.outfitAccent, 3));
        }
      case Outfit.casual:
        c.drawPath(body, garment(s.outfitPrimary));
        c.drawArc(Rect.fromCenter(center: const Offset(200, top + 2), width: 120, height: 60), 0, math.pi, false, stroke(_shade(s.outfitPrimary, -0.15), 6));
    }
  }

  Path _vNeck(double top, double depth, double halfWidth) => Path()
    ..moveTo(200 - halfWidth, top - 2)
    ..lineTo(200, top + depth)
    ..lineTo(200 + halfWidth, top - 2)
    ..close();

  Path _vNeckLine(double top, double depth, double halfWidth) => Path()
    ..moveTo(200 - halfWidth, top - 2)
    ..lineTo(200, top + depth)
    ..lineTo(200 + halfWidth, top - 2);

  Path _shirtV(double top, double depth) => _vNeck(top, depth, 34);

  void _shirtCollar(double top) {
    final collar = fill(_shade(s.outfitSecondary, -0.04));
    for (final side in [-1.0, 1.0]) {
      c.drawPath(
        Path()
          ..moveTo(200 + side * 6, top + 6)
          ..lineTo(200 + side * 40, top - 8)
          ..lineTo(200 + side * 30, top + 30)
          ..close(),
        collar,
      );
    }
  }

  void _buttons(double y, int n, Color color) {
    for (var i = 0; i < n; i++) {
      c.drawCircle(Offset(200, y + i * 34), 4.5, fill(color));
    }
  }

  void _neck() {
    final top = hc.dy + ry * 0.62;
    final r = Rect.fromLTRB(200 - 30, top, 200 + 30, 312 + breathDy);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)), fill(skinShade));
    // Jaw shadow on the neck.
    c.drawOval(Rect.fromCenter(center: Offset(200, top + 6), width: 64, height: 22), fill(_shade(s.skin, -0.16).withValues(alpha: 0.6)));
  }

  void _collarAccessories() {
    const y = 304.0;
    if (s.has(Accessory.necklace)) {
      for (var i = -5; i <= 5; i++) {
        final a = i / 5 * 0.9;
        c.drawCircle(Offset(200 + math.sin(a) * 54, y - 6 + math.cos(a) * 26), 4.2, fill(const Color(0xFFF6F0E2)));
      }
    }
    if (s.has(Accessory.necktie)) {
      final tie = Path()
        ..moveTo(200 - 9, y + 4)
        ..lineTo(200 + 9, y + 4)
        ..lineTo(200 + 15, y + 120)
        ..lineTo(200, y + 140)
        ..lineTo(200 - 15, y + 120)
        ..close();
      c.drawPath(tie, fill(s.outfitAccent));
      c.drawRect(Rect.fromCenter(center: const Offset(200, y + 6), width: 22, height: 14), fill(_shade(s.outfitAccent, -0.12)));
    }
    if (s.has(Accessory.bowTie)) {
      final bow = fill(s.outfitAccent);
      c.drawPath(
        Path()
          ..moveTo(200, y + 6)
          ..lineTo(200 - 30, y - 8)
          ..lineTo(200 - 30, y + 20)
          ..close(),
        bow,
      );
      c.drawPath(
        Path()
          ..moveTo(200, y + 6)
          ..lineTo(200 + 30, y - 8)
          ..lineTo(200 + 30, y + 20)
          ..close(),
        bow,
      );
      c.drawCircle(const Offset(200, y + 6), 7, fill(_shade(s.outfitAccent, -0.18)));
    }
    if (s.has(Accessory.nameTag)) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(274, 366), width: 56, height: 18), const Radius.circular(3));
      c.drawRRect(r, fill(const Color(0xFFE0C068)));
      c.drawRRect(r, stroke(const Color(0xFF5A4410), 1.5));
      c.drawLine(const Offset(256, 366), const Offset(292, 366), stroke(const Color(0xFF5A4410), 2));
    }
  }

  // ---------------------------------------------------------------- hair --

  Rect get _headRect => Rect.fromCenter(center: hc, width: rx * 2, height: ry * 2);

  void _hairBack() {
    final h = fill(s.hair);
    final cx = hc.dx, cy = hc.dy;
    switch (s.hairStyle) {
      case HairStyle.long:
        final back = Path()
          ..moveTo(cx - rx - 10, cy - 20)
          ..cubicTo(cx - rx - 26, cy + 120, cx - rx - 20, cy + 190, cx - rx + 4, cy + 230)
          ..lineTo(cx + rx - 4, cy + 230)
          ..cubicTo(cx + rx + 20, cy + 190, cx + rx + 26, cy + 120, cx + rx + 10, cy - 20)
          ..close();
        c.drawPath(back, h);
      case HairStyle.bob:
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(cx - rx - 16, cy - ry - 8, cx + rx + 16, cy + ry * 0.62), const Radius.circular(70)),
          h,
        );
      case HairStyle.ponytail:
        final tail = Path()
          ..moveTo(cx + rx * 0.5, cy - ry * 0.7)
          ..cubicTo(cx + rx + 60, cy - ry * 0.6, cx + rx + 50, cy + 110, cx + rx + 16, cy + 170)
          ..cubicTo(cx + rx + 10, cy + 110, cx + rx + 6, cy - 10, cx + rx * 0.4, cy - ry * 0.3)
          ..close();
        c.drawPath(tail, h);
      case HairStyle.curly:
        final r = math.Random(7);
        for (var i = 0; i < 22; i++) {
          final a = math.pi * 0.95 + i / 21 * math.pi * 1.1;
          final rr = 1.12 + r.nextDouble() * 0.12;
          c.drawCircle(Offset(cx + math.cos(a) * rx * rr, cy + math.sin(a) * ry * rr * 0.98 + 6), 26 + r.nextDouble() * 8, h);
        }
        for (final side in [-1.0, 1.0]) {
          for (var k = 0; k < 4; k++) {
            c.drawCircle(Offset(cx + side * (rx + 6 - k * 2), cy + k * 22), 22, h);
          }
        }
      case HairStyle.bun:
      case HairStyle.sidePart:
      case HairStyle.buzz:
      case HairStyle.undercut:
        break;
    }
  }

  /// Hair over the whole top of the skull, down to [sideY] at the temples,
  /// with a hairline through ([leftY] at the left temple, [midX],[midY] in
  /// the middle, [rightY] at the right temple). Always covers the crown.
  Path _crown({required double sideY, required double leftY, required double midX, required double midY, required double rightY, double grow = 8}) {
    final cx = hc.dx, cy = hc.dy;
    final outer = Rect.fromCenter(center: hc + Offset(0, -grow / 2), width: rx * 2 + grow * 1.6, height: ry * 2 + grow * 2);
    return Path()
      ..moveTo(cx - rx - grow * 0.8, sideY)
      ..lineTo(cx - rx - grow * 0.8, cy - grow / 2)
      ..arcTo(outer, math.pi, math.pi, false)
      ..lineTo(cx + rx + grow * 0.8, sideY)
      ..lineTo(cx + rx - 4, rightY)
      ..cubicTo(cx + rx * 0.55, midY - 6, midX + rx * 0.25, midY, midX, midY)
      ..cubicTo(midX - rx * 0.25, midY, cx - rx * 0.55, midY - 6, cx - rx + 4, leftY)
      ..close();
  }

  void _hairFront() {
    final h = fill(s.hair);
    final cx = hc.dx, cy = hc.dy;
    switch (s.hairStyle) {
      case HairStyle.sidePart:
        // Swept towards the viewer's right from a part on the left.
        c.drawPath(_crown(sideY: cy + 2, leftY: cy - ry * 0.18, midX: cx - rx * 0.28, midY: cy - ry * 0.62, rightY: cy - ry * 0.12, grow: 10), h);
        final swoop = Path()
          ..moveTo(cx - rx * 0.28, cy - ry * 0.64)
          ..cubicTo(cx + rx * 0.2, cy - ry * 0.75, cx + rx * 0.7, cy - ry * 0.6, cx + rx + 6, cy - ry * 0.25)
          ..lineTo(cx + rx + 6, cy - ry * 0.55)
          ..cubicTo(cx + rx * 0.6, cy - ry * 0.95, cx, cy - ry * 0.95, cx - rx * 0.28, cy - ry * 0.64)
          ..close();
        c.drawPath(swoop, fill(_shade(s.hair, 0.05)));
        c.drawLine(Offset(cx - rx * 0.32, cy - ry - 6), Offset(cx - rx * 0.28, cy - ry * 0.62), stroke(hairDark, 2.5));
      case HairStyle.buzz:
        c.drawPath(
          _crown(sideY: cy - ry * 0.1, leftY: cy - ry * 0.2, midX: cx, midY: cy - ry * 0.6, rightY: cy - ry * 0.2, grow: 3),
          fill(s.hair.withValues(alpha: 0.88)),
        );
      case HairStyle.bob:
        // Straight fringe.
        final fringe = Path()
          ..addPath(_crown(sideY: cy + ry * 0.3, leftY: cy + ry * 0.1, midX: cx, midY: cy - ry * 0.34, rightY: cy + ry * 0.1, grow: 12), Offset.zero);
        c.drawPath(fringe, h);
        c.drawRect(Rect.fromLTRB(cx - rx * 0.72, cy - ry * 0.62, cx + rx * 0.72, cy - ry * 0.34), h);
      case HairStyle.long:
        c.drawPath(_crown(sideY: cy + ry * 0.75, leftY: cy + ry * 0.25, midX: cx, midY: cy - ry * 0.7, rightY: cy + ry * 0.25, grow: 12), h);
        c.drawLine(Offset(cx, cy - ry - 8), Offset(cx, cy - ry * 0.7), stroke(hairDark, 2));
      case HairStyle.ponytail:
      case HairStyle.bun:
        // Pulled back: high hairline and comb lines towards the back.
        c.drawPath(_crown(sideY: cy - 2, leftY: cy - ry * 0.12, midX: cx, midY: cy - ry * 0.55, rightY: cy - ry * 0.12, grow: 6), h);
        for (var i = -2; i <= 2; i++) {
          c.drawLine(Offset(cx + i * rx * 0.24, cy - ry * 0.62), Offset(cx + i * rx * 0.16, cy - ry - 2), stroke(hairDark, 1.6));
        }
        if (s.hairStyle == HairStyle.bun) {
          c.drawCircle(Offset(cx, cy - ry - 20), 32, h);
          c.drawArc(Rect.fromCircle(center: Offset(cx, cy - ry - 20), radius: 20), 0.3, 2.4, false, stroke(hairDark, 2));
        } else {
          c.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx + rx * 0.78, cy - ry * 0.7), width: 16, height: 10), const Radius.circular(4)),
            fill(s.outfitAccent),
          );
        }
      case HairStyle.curly:
        final r = math.Random(11);
        c.drawPath(_crown(sideY: cy + ry * 0.2, leftY: cy, midX: cx, midY: cy - ry * 0.5, rightY: cy, grow: 14), h);
        for (var i = 0; i < 9; i++) {
          final a = math.pi * 1.08 + i / 8 * math.pi * 0.84;
          c.drawCircle(Offset(cx + math.cos(a) * rx * 0.86, cy + math.sin(a) * ry * 0.78), 17 + r.nextDouble() * 5, h);
        }
      case HairStyle.undercut:
        // Shaved sides, longer top swept to the right.
        c.drawPath(
          _crown(sideY: cy - ry * 0.05, leftY: cy - ry * 0.15, midX: cx, midY: cy - ry * 0.58, rightY: cy - ry * 0.15, grow: 3),
          fill(_shade(s.hair, -0.05).withValues(alpha: 0.5)),
        );
        final top = Path()
          ..moveTo(cx - rx * 0.82, cy - ry * 0.5)
          ..cubicTo(cx - rx * 1.0, cy - ry * 1.45, cx + rx * 0.7, cy - ry * 1.5, cx + rx + 16, cy - ry * 0.62)
          ..cubicTo(cx + rx * 0.45, cy - ry * 0.74, cx - rx * 0.3, cy - ry * 0.6, cx - rx * 0.82, cy - ry * 0.5)
          ..close();
        c.drawPath(top, h);
        c.drawPath(top, stroke(_shade(s.hair, 0.12), 2));
    }
  }

  // ---------------------------------------------------------------- head --

  void _head() {
    final cx = hc.dx, cy = hc.dy;
    // Ears.
    for (final side in [-1.0, 1.0]) {
      c.drawOval(Rect.fromCenter(center: Offset(cx + side * rx * 0.98, cy + 8), width: 22, height: 36), fill(skinShade));
    }
    // Face.
    c.drawOval(
      _headRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 0.95,
          colors: [_shade(s.skin, 0.05), s.skin, skinShade],
          stops: const [0, 0.6, 1],
        ).createShader(_headRect),
    );
    if (face.blush > 0) {
      for (final side in [-1.0, 1.0]) {
        c.drawOval(
          Rect.fromCenter(center: Offset(cx + side * rx * 0.58, cy + 28), width: 34, height: 18),
          Paint()
            ..color = const Color(0xFFFF6B8A).withValues(alpha: 0.18 + 0.32 * face.blush)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
    }
    if (s.freckles) {
      final r = math.Random(3);
      for (var i = 0; i < 14; i++) {
        final side = i.isEven ? -1 : 1;
        c.drawCircle(Offset(cx + side * (14 + r.nextDouble() * 34), cy + 14 + r.nextDouble() * 18), 1.6, fill(_shade(s.skin, -0.22)));
      }
    }
    if (s.facialHair == FacialHair.stubble) {
      final jaw = Path()
        ..addArc(Rect.fromCenter(center: hc + const Offset(0, 6), width: rx * 1.86, height: ry * 1.86), 0.15, math.pi - 0.3)
        ..quadraticBezierTo(cx, cy + ry * 0.35, cx + rx * 0.92, cy + ry * 0.18);
      c.drawPath(jaw, fill(s.hair.withValues(alpha: 0.16)));
    }
    _eyes();
    _brows();
    _nose();
    _mouth();
    if (s.facialHair == FacialHair.moustache) {
      final m = Path()
        ..moveTo(cx - 22, cy + 42)
        ..quadraticBezierTo(cx, cy + 30, cx + 22, cy + 42)
        ..quadraticBezierTo(cx, cy + 38, cx - 22, cy + 42)
        ..close();
      c.drawPath(m, fill(hairDark));
    }
    _hairFront();
    if (s.has(Accessory.headband)) {
      c.drawArc(Rect.fromCenter(center: hc + const Offset(0, -6), width: rx * 2 + 10, height: ry * 2), math.pi * 1.12, math.pi * 0.76, false, stroke(s.outfitAccent, 9));
    }
    if (s.has(Accessory.glasses)) _glasses();
    if (s.has(Accessory.earrings)) {
      for (final side in [-1.0, 1.0]) {
        final e = Offset(cx + side * rx * 0.98, cy + 30);
        c.drawCircle(e, 5.5, fill(const Color(0xFFE8C66A)));
        c.drawCircle(e + const Offset(0, 9), 4, fill(const Color(0xFFE8C66A)));
      }
    }
    if (s.has(Accessory.flower)) _flower(Offset(cx + rx * 0.78, cy - ry * 0.62));
    if (s.has(Accessory.topHat)) _topHat();
  }

  Offset _eye(double side) => Offset(hc.dx + side * 30 * s.faceWidth, hc.dy - 2);

  void _eyes() {
    for (final side in [-1.0, 1.0]) {
      final e = _eye(side);
      // Wink closes the eye on the viewer's left.
      final closed = math.max(p.blink, side < 0 ? face.leftClosed : 0.0).clamp(0.0, 1.0);
      final open = (face.eyeOpen * (1 - closed)).clamp(0.0, 1.4);
      if (open < 0.12) {
        // Closed: a gentle lash arc (smiling when the face smiles).
        final curve = face.smile >= 0 ? 5.0 : -3.0;
        final lash = Path()
          ..moveTo(e.dx - 13, e.dy)
          ..quadraticBezierTo(e.dx, e.dy + curve, e.dx + 13, e.dy);
        c.drawPath(lash, stroke(const Color(0xFF241812), 3));
        continue;
      }
      final h = 18 * open;
      final white = Rect.fromCenter(center: e, width: 27, height: h);
      c.drawOval(white, fill(const Color(0xFFFBFAF7)));
      c.save();
      c.clipPath(Path()..addOval(white));
      final g = Offset(p.gaze.dx * 5, p.gaze.dy * 3);
      c.drawCircle(e + g, 8.2, fill(s.eyes));
      c.drawCircle(e + g, 4.2, fill(const Color(0xFF0E0A08)));
      c.drawCircle(e + g + const Offset(-2.6, -2.6), 2.2, fill(Colors.white.withValues(alpha: 0.9)));
      c.restore();
      // Upper lash line.
      c.drawArc(white, math.pi * 1.05, math.pi * 0.9, false, stroke(const Color(0xFF241812), 2.6));
    }
  }

  void _brows() {
    for (final side in [-1.0, 1.0]) {
      final e = _eye(side);
      final raise = face.brow * 9 + (side > 0 ? face.browAsym * 7 : -face.browAsym * 2);
      final inner = face.browInner * 7;
      final y = e.dy - 22 - raise;
      final brow = Path()
        ..moveTo(e.dx - side * 15, y + 2 - inner)
        ..quadraticBezierTo(e.dx, y - 5, e.dx + side * 16, y + 3);
      c.drawPath(brow, stroke(_shade(s.hair, -0.05), 5.2));
    }
  }

  void _nose() {
    final cx = hc.dx, cy = hc.dy;
    final n = Path()
      ..moveTo(cx - 3, cy + 8)
      ..quadraticBezierTo(cx - 9, cy + 26, cx - 1, cy + 28)
      ..quadraticBezierTo(cx + 5, cy + 29, cx + 8, cy + 25);
    c.drawPath(n, stroke(_shade(s.skin, -0.2), 2.6));
  }

  void _mouth() {
    final cx = hc.dx + face.mouthShift, cy = hc.dy + 50;
    final open = math.max(face.open, p.talk * 0.7).clamp(0.0, 1.0);
    final w = 30.0 - face.round * 14 + face.smile.abs() * 4;
    final curve = face.smile * 10;
    if (open > 0.08) {
      final h = 6 + open * 18;
      final Path mouth;
      if (face.round > 0.5) {
        mouth = Path()..addOval(Rect.fromCenter(center: Offset(cx, cy + 2), width: w, height: h));
      } else {
        mouth = Path()
          ..moveTo(cx - w / 2, cy - curve * 0.3)
          ..quadraticBezierTo(cx, cy + curve * 0.4 - 2, cx + w / 2, cy - curve * 0.3)
          ..quadraticBezierTo(cx, cy + h + curve * 0.4, cx - w / 2, cy - curve * 0.3)
          ..close();
      }
      c.drawPath(mouth, fill(const Color(0xFF5A1F18)));
      if (face.teeth) {
        c.save();
        c.clipPath(mouth);
        c.drawRect(Rect.fromLTWH(cx - w / 2, cy - 12, w, 12 + 0.8), fill(const Color(0xFFF8F5EE)));
        c.restore();
      }
      c.drawPath(mouth, stroke(_shade(s.lips, -0.1), 2));
      return;
    }
    final m = Path()
      ..moveTo(cx - w / 2, cy - curve * 0.3)
      ..quadraticBezierTo(cx, cy + curve, cx + w / 2, cy - curve * 0.3 - (face.mouthShift > 0 ? 3 : 0));
    c.drawPath(m, stroke(s.lips, 4));
  }

  void _glasses() {
    final frame = stroke(const Color(0xFF1C1C1E), 3);
    for (final side in [-1.0, 1.0]) {
      final e = _eye(side);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: e, width: 40, height: 30), const Radius.circular(9)), frame);
    }
    final l = _eye(-1), r = _eye(1);
    c.drawLine(l + const Offset(20, -2), r + const Offset(-20, -2), frame);
    c.drawLine(l + const Offset(-20, -4), Offset(hc.dx - rx * 0.98, hc.dy - 6), frame);
    c.drawLine(r + const Offset(20, -4), Offset(hc.dx + rx * 0.98, hc.dy - 6), frame);
  }

  void _flower(Offset at) {
    for (var i = 0; i < 5; i++) {
      final a = i / 5 * 2 * math.pi;
      c.drawCircle(at + Offset(math.cos(a), math.sin(a)) * 9, 7.5, fill(const Color(0xFFFF8FB1)));
    }
    c.drawCircle(at, 5, fill(const Color(0xFFFFD54A)));
  }

  void _topHat() {
    final cx = hc.dx, top = hc.dy - ry;
    c.save();
    c.translate(cx, top);
    c.rotate(-0.12);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-92, -6, 184, 18), const Radius.circular(9)), fill(const Color(0xFF111015)));
    c.drawRect(const Rect.fromLTWH(-58, -104, 116, 104), fill(const Color(0xFF16141C)));
    c.drawRect(const Rect.fromLTWH(-58, -30, 116, 16), fill(s.outfitAccent));
    c.drawRect(const Rect.fromLTWH(-58, -104, 116, 6), fill(const Color(0xFF26222E)));
    c.restore();
  }
}
