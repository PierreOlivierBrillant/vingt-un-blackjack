import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/card_style.dart';
import '../cards/chips.dart';
import 'dealer_controller.dart';
import 'ik.dart';
import 'table_geometry.dart';

typedef G = TableGeometry;

const _skin = Color(0xFFE2AE8A);
const _skinShade = Color(0xFFC48A68);
const _hair = Color(0xFF2B1D16);
const _shirt = Color(0xFFF4F4F2);
const _shirtShade = Color(0xFFCFD3D8);
const _vest = Color(0xFF14202B);
const _trim = Color(0xFF00C853);

void _scaleToLogical(Canvas canvas, Size size) {
  final s = size.width / G.size.width;
  canvas.scale(s, s);
}

/// Offset of the shoulders due to breathing (shared by body and arms).
Offset breathOffset(DealerController c) => Offset(0, -2.5 * c.breath);

// ------------------------------------------------------------------ body --

class DealerBodyPainter extends CustomPainter {
  DealerBodyPainter(this.c) : super(repaint: c);
  final DealerController c;

  @override
  void paint(Canvas canvas, Size size) {
    _scaleToLogical(canvas, size);
    // Back wall / room glow behind the dealer.
    final room = Rect.fromLTWH(0, 0, G.size.width, G.feltTop + 10);
    canvas.drawRect(
      room,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.1,
          colors: [Color(0xFF1C3A50), Color(0xFF0A1620)],
        ).createShader(room),
    );
    // Soft spotlight cone.
    canvas.drawCircle(
      const Offset(500, 150),
      260,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );

    final b = breathOffset(c);
    _torso(canvas, b);
    _head(canvas, b);
  }

  void _torso(Canvas canvas, Offset b) {
    final ls = G.leftShoulder + b, rs = G.rightShoulder + b;
    final torso = Path()
      ..moveTo(ls.dx - 18, ls.dy + 8)
      ..quadraticBezierTo(ls.dx - 6, ls.dy - 24, 470, 214 + b.dy)
      ..lineTo(530, 214 + b.dy)
      ..quadraticBezierTo(rs.dx + 6, rs.dy - 24, rs.dx + 18, rs.dy + 8)
      ..lineTo(646, G.feltTop + 20)
      ..lineTo(354, G.feltTop + 20)
      ..close();
    canvas.drawPath(torso, Paint()..color = _shirt);
    // Vest panels.
    final vestL = Path()
      ..moveTo(ls.dx - 16, ls.dy + 10)
      ..quadraticBezierTo(ls.dx + 6, ls.dy - 18, 474, 224 + b.dy)
      ..lineTo(500, 300 + b.dy)
      ..lineTo(500, G.feltTop + 20)
      ..lineTo(354, G.feltTop + 20)
      ..close();
    final vestR = Path()
      ..moveTo(rs.dx + 16, rs.dy + 10)
      ..quadraticBezierTo(rs.dx - 6, rs.dy - 18, 526, 224 + b.dy)
      ..lineTo(500, 300 + b.dy)
      ..lineTo(500, G.feltTop + 20)
      ..lineTo(646, G.feltTop + 20)
      ..close();
    final vestPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1E2E3C), _vest],
      ).createShader(const Rect.fromLTWH(350, 200, 300, 140));
    canvas.drawPath(vestL, vestPaint);
    canvas.drawPath(vestR, vestPaint);
    final trim = Paint()
      ..color = _trim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawLine(Offset(474, 226 + b.dy), Offset(500, 300 + b.dy), trim);
    canvas.drawLine(Offset(526, 226 + b.dy), Offset(500, 300 + b.dy), trim);
    // Bow tie.
    final tie = Path()
      ..moveTo(500, 222 + b.dy)
      ..lineTo(474, 210 + b.dy)
      ..lineTo(474, 236 + b.dy)
      ..close()
      ..moveTo(500, 222 + b.dy)
      ..lineTo(526, 210 + b.dy)
      ..lineTo(526, 236 + b.dy)
      ..close();
    canvas.drawPath(tie, Paint()..color = const Color(0xFFB3123A));
    canvas.drawCircle(Offset(500, 222 + b.dy), 6, Paint()..color = const Color(0xFF8A0E2C));
    // Name tag.
    final tag = RRect.fromRectAndRadius(Rect.fromLTWH(538, 262 + b.dy, 46, 16), const Radius.circular(3));
    canvas.drawRRect(tag, Paint()..color = const Color(0xFFE0C068));
    canvas.drawLine(Offset(546, 270 + b.dy), Offset(576, 270 + b.dy), Paint()
      ..color = const Color(0xFF5A4410)
      ..strokeWidth = 2);
  }

  void _head(Canvas canvas, Offset b) {
    // Neck.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(478, 168 + b.dy, 44, 50), const Radius.circular(12)),
      Paint()..color = _skinShade,
    );
    canvas.save();
    final pivot = Offset(500, 200 + b.dy);
    canvas.translate(pivot.dx, pivot.dy + c.headNod * 6);
    canvas.rotate(c.headTilt);
    canvas.translate(-pivot.dx, -pivot.dy);

    final hc = G.headCenter + Offset(0, b.dy * 0.6);
    // Ears.
    for (final dx in [-52.0, 52.0]) {
      canvas.drawOval(Rect.fromCenter(center: hc + Offset(dx, 6), width: 18, height: 30), Paint()..color = _skinShade);
    }
    final face = Rect.fromCenter(center: hc, width: 104, height: 124);
    canvas.drawOval(
      face,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.3),
          radius: 0.9,
          colors: [Color(0xFFF0C3A2), _skin, _skinShade],
          stops: [0, 0.6, 1],
        ).createShader(face),
    );
    // Hair: swept cap with a side part.
    final hair = Path()
      ..moveTo(hc.dx - 54, hc.dy + 2)
      ..quadraticBezierTo(hc.dx - 62, hc.dy - 64, hc.dx - 4, hc.dy - 70)
      ..quadraticBezierTo(hc.dx + 60, hc.dy - 70, hc.dx + 54, hc.dy - 2)
      ..quadraticBezierTo(hc.dx + 46, hc.dy - 34, hc.dx + 14, hc.dy - 40)
      ..quadraticBezierTo(hc.dx - 20, hc.dy - 44, hc.dx - 30, hc.dy - 30)
      ..quadraticBezierTo(hc.dx - 44, hc.dy - 20, hc.dx - 54, hc.dy + 2)
      ..close();
    canvas.drawPath(hair, Paint()..color = _hair);

    final smile = c.mood == DealerMood.smile ? c.moodLevel : 0.0;
    final wince = c.mood == DealerMood.wince ? c.moodLevel : 0.0;
    final surprise = c.mood == DealerMood.surprised ? c.moodLevel : 0.0;

    // Eyes look at the busiest hand.
    final look = (c.rightArm.hand - hc);
    final gaze = look.distance == 0 ? Offset.zero : look / look.distance * 3.2;
    final eyeOpen = (1 - c.blink) * (1 - wince * 0.6) * (1 + surprise * 0.35);
    for (final dx in [-20.0, 20.0]) {
      final e = hc + Offset(dx, -6);
      final eyeH = 13.0 * eyeOpen.clamp(0.06, 1.4);
      canvas.drawOval(Rect.fromCenter(center: e, width: 22, height: eyeH), Paint()..color = Colors.white);
      if (eyeOpen > 0.2) {
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCenter(center: e, width: 22, height: eyeH)));
        canvas.drawCircle(e + gaze, 5.5, Paint()..color = const Color(0xFF3B2A1E));
        canvas.drawCircle(e + gaze, 2.6, Paint()..color = Colors.black);
        canvas.drawCircle(e + gaze + const Offset(-1.6, -1.6), 1.2, Paint()..color = Colors.white);
        canvas.restore();
      }
      canvas.drawLine(
        e + Offset(-11, -eyeH / 2),
        e + Offset(11, -eyeH / 2),
        Paint()
          ..color = _skinShade
          ..strokeWidth = 2,
      );
      // Eyebrows: up on smile/surprise, knitted on wince.
      final lift = -smile * 4 - surprise * 7;
      final outerX = dx < 0 ? -12.0 : 12.0;
      canvas.drawLine(
        e + Offset(outerX, -16 + lift - wince * 2),
        e + Offset(-outerX, -18 + lift + wince * 6),
        Paint()
          ..color = _hair
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round,
      );
    }
    // Nose.
    final nose = Path()
      ..moveTo(hc.dx, hc.dy - 2)
      ..quadraticBezierTo(hc.dx + 9, hc.dy + 20, hc.dx - 3, hc.dy + 22);
    canvas.drawPath(nose, Paint()
      ..color = _skinShade
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    // Mouth.
    final m = hc + const Offset(0, 38);
    final mouthPaint = Paint()
      ..color = const Color(0xFF8C3B2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (surprise > 0.3) {
      canvas.drawOval(Rect.fromCenter(center: m, width: 14, height: 18 * surprise), Paint()..color = const Color(0xFF5A1F18));
    } else if (smile > 0.05) {
      final mouth = Path()
        ..moveTo(m.dx - 20, m.dy - 4)
        ..quadraticBezierTo(m.dx, m.dy + 18 * smile, m.dx + 20, m.dy - 4)
        ..close();
      canvas.drawPath(mouth, Paint()..color = const Color(0xFF5A1F18));
      canvas.drawRect(Rect.fromLTWH(m.dx - 14, m.dy - 3, 28, 5 * smile), Paint()..color = Colors.white);
    } else {
      final curve = 4 - wince * 10;
      final mouth = Path()
        ..moveTo(m.dx - 16, m.dy)
        ..quadraticBezierTo(m.dx, m.dy + curve, m.dx + 16, m.dy + (wince > 0 ? 2 : 0));
      canvas.drawPath(mouth, mouthPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DealerBodyPainter old) => old.c != c;
}

// ------------------------------------------------------------------ felt --

class FeltPainter extends CustomPainter {
  FeltPainter({required this.felt, required this.payoutLine, required this.ruleLine, required this.insuranceLine});

  final FeltColor felt;
  final String payoutLine;
  final String ruleLine;
  final String insuranceLine;

  static RRect feltShape() => RRect.fromRectAndCorners(
        const Rect.fromLTRB(0, G.feltTop, 1000, G.feltBottom),
        bottomLeft: const Radius.elliptical(480, 420),
        bottomRight: const Radius.elliptical(480, 420),
      );

  @override
  void paint(Canvas canvas, Size size) {
    _scaleToLogical(canvas, size);
    final shape = feltShape();
    // Rail (padded leather) drawn as a thick outline below the felt.
    canvas.drawRRect(shape.inflate(18), Paint()..color = const Color(0xFF3A2115));
    canvas.drawRRect(
      shape.inflate(9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF7A4A2E),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 0.95,
          colors: [felt.light, felt.dark],
        ).createShader(shape.outerRect),
    );
    // Dealer-side straight edge highlight.
    canvas.drawRect(
      const Rect.fromLTWH(0, G.feltTop, 1000, 6),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    final ink = Colors.white.withValues(alpha: 0.55);
    final gold = const Color(0xFFE8C66A).withValues(alpha: 0.85);

    // Printed arcs.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ink;
    final arcRect = Rect.fromCenter(center: const Offset(500, 300), width: 1240, height: 1060);
    canvas.drawArc(arcRect.deflate(160), 0.52, math.pi - 1.04, false, arc);
    canvas.drawArc(arcRect.deflate(120), 0.55, math.pi - 1.1, false, arc..strokeWidth = 1.5);
    _textOnArc(canvas, payoutLine, const Offset(500, 300), 410, gold, 30);
    _textOnArc(canvas, insuranceLine, const Offset(500, 300), 470, ink, 22);

    final rule = TextPainter(
      text: TextSpan(
        text: ruleLine,
        style: TextStyle(fontFamily: kAppFont, color: ink, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 2),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 560);
    rule.paint(canvas, Offset(500 - rule.width / 2, 846));

    // Betting circles.
    for (final s in G.seatSpots) {
      canvas.drawCircle(s, 64, Paint()..color = Colors.black.withValues(alpha: 0.12));
      canvas.drawCircle(
        s,
        64,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = gold,
      );
      canvas.drawCircle(
        s,
        54,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ink,
      );
    }
  }

  void _textOnArc(Canvas canvas, String text, Offset center, double radius, Color color, double fontSize) {
    final style = TextStyle(fontFamily: kAppFont, color: color, fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: 1);
    final glyphs = [
      for (final ch in text.characters)
        TextPainter(text: TextSpan(text: ch, style: style), textDirection: TextDirection.ltr)..layout(),
    ];
    final total = glyphs.fold<double>(0, (a, g) => a + g.width);
    var angle = math.pi / 2 + total / 2 / radius; // centred at the bottom
    for (final g in glyphs) {
      final half = g.width / 2 / radius;
      angle -= half;
      canvas.save();
      canvas.translate(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius);
      canvas.rotate(angle - math.pi / 2);
      g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
      canvas.restore();
      angle -= half;
    }
  }

  @override
  bool shouldRepaint(FeltPainter old) =>
      old.felt != felt || old.payoutLine != payoutLine || old.ruleLine != ruleLine || old.insuranceLine != insuranceLine;
}

// ------------------------------------------------------------- furniture --

class FurniturePainter extends CustomPainter {
  FurniturePainter(this.c, this.style) : super(repaint: c);
  final DealerController c;
  final CardStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    _scaleToLogical(canvas, size);
    _rack(canvas);
    _shoe(canvas);
    _discard(canvas);
  }

  void _rack(Canvas canvas) {
    final r = Rect.fromCenter(center: G.rackCenter, width: G.rackSize.width, height: G.rackSize.height);
    canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(10)), Paint()..color = const Color(0xFF1A1208));
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), Paint()..color = const Color(0xFF2E2212));
    final cols = kChipDenominations.reversed.toList();
    final colW = r.width / (cols.length * 2);
    for (var i = 0; i < cols.length * 2; i++) {
      final d = cols[i ~/ 2];
      final x = r.left + colW * (i + 0.5);
      final col = Rect.fromCenter(center: Offset(x, r.center.dy), width: colW - 5, height: r.height - 10);
      canvas.drawRRect(RRect.fromRectAndRadius(col, const Radius.circular(6)), Paint()..color = d.color);
      for (var k = 0; k < 6; k++) {
        final y = col.top + 4 + k * (col.height - 8) / 5;
        canvas.drawLine(Offset(col.left + 2, y), Offset(col.right - 2, y), Paint()
          ..color = d.stripe.withValues(alpha: 0.6)
          ..strokeWidth = 1.5);
      }
    }
  }

  void _shoe(Canvas canvas) {
    canvas.save();
    canvas.translate(G.shoeCenter.dx, G.shoeCenter.dy);
    canvas.rotate(-0.35);
    const body = Rect.fromLTWH(-80, -48, 170, 96);
    canvas.drawRRect(RRect.fromRectAndRadius(body.shift(const Offset(6, 10)), const Radius.circular(14)),
        Paint()..color = Colors.black.withValues(alpha: 0.35));
    // Card stack inside (length shows how much of the shoe is left).
    final len = 150 * c.shoeLevel;
    final stack = Rect.fromLTWH(84 - len, -38, len, 76);
    canvas.drawRect(stack, Paint()..color = style.backColor);
    for (var x = stack.left; x < stack.right; x += 5) {
      canvas.drawLine(Offset(x, -38), Offset(x, 38), Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1);
    }
    // Smoked acrylic body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(14)),
      Paint()..color = const Color(0xFF0E1A24).withValues(alpha: 0.72),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.25),
    );
    // Mouth of the shoe (front, towards the dealer).
    final mouth = Path()
      ..moveTo(-80, -40)
      ..lineTo(-104, -30)
      ..lineTo(-104, 30)
      ..lineTo(-80, 40)
      ..close();
    canvas.drawPath(mouth, Paint()..color = const Color(0xFF2F4553));
    canvas.restore();
  }

  void _discard(Canvas canvas) {
    final onTable = c.cards.where((x) => x.visible).length;
    final discarded = math.max(0, c.cardsDealtFromShoe - onTable);
    final h = math.min(60.0, discarded * 0.35);
    final base = G.discardCenter;
    final tray = Rect.fromCenter(center: base, width: G.cardWidth + 20, height: G.cardHeight * 0.58);
    canvas.drawRRect(RRect.fromRectAndRadius(tray, const Radius.circular(8)), Paint()..color = Colors.black.withValues(alpha: 0.28));
    if (h > 0) {
      for (var i = 0; i < h ~/ 3; i++) {
        final r = Rect.fromCenter(center: base + Offset(0, -i * 3.0), width: G.cardWidth * 0.95, height: G.cardHeight * 0.5);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = i.isEven ? const Color(0xFFF4F1E8) : const Color(0xFFDAD5C8));
      }
    }
  }

  @override
  bool shouldRepaint(FurniturePainter old) => old.c != c || old.style != style;
}

// ----------------------------------------------------------------- chips --

class ChipsLayerPainter extends CustomPainter {
  ChipsLayerPainter(this.c) : super(repaint: c);
  final DealerController c;

  @override
  void paint(Canvas canvas, Size size) {
    _scaleToLogical(canvas, size);
    for (final s in c.chipStacks) {
      if (s.opacity <= 0.01) continue;
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: s.opacity.clamp(0.0, 1.0)));
      final shadowOffset = const Offset(10, 14) * s.lift;
      canvas.drawCircle(s.pos + shadowOffset + const Offset(0, 6), 30, Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 8 * s.lift));
      paintChipStack(canvas, s.pos - Offset(0, 22 * s.lift), 30 * (1 + 0.1 * s.lift), s.cents);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ChipsLayerPainter old) => old.c != c;
}

// ------------------------------------------------------------------ arms --

class ArmsPainter extends CustomPainter {
  ArmsPainter(this.c, this.style) : super(repaint: c);
  final DealerController c;
  final CardStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    _scaleToLogical(canvas, size);
    final b = breathOffset(c);
    if (c.shuffleProgress != null) _shuffleDeck(canvas, c.shuffleProgress!);
    _arm(canvas, G.leftShoulder + b, c.leftArm, bendPositive: true);
    _arm(canvas, G.rightShoulder + b, c.rightArm, bendPositive: false);
  }

  void _arm(Canvas canvas, Offset shoulder, ArmState arm, {required bool bendPositive}) {
    final ik = solveTwoBone(shoulder, arm.hand, G.upperArm, G.foreArm, bendPositive: bendPositive);
    final upper = Paint()
      ..color = _shirt
      ..strokeWidth = 50
      ..strokeCap = StrokeCap.round;
    final upperShade = Paint()
      ..color = _shirtShade
      ..strokeWidth = 50
      ..strokeCap = StrokeCap.round;
    final fore = Paint()
      ..color = _shirt
      ..strokeWidth = 40
      ..strokeCap = StrokeCap.round;
    // Shadow cast on the felt by the forearm.
    canvas.drawLine(ik.elbow + const Offset(14, 22), ik.hand + const Offset(14, 22), Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 38
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawLine(shoulder + const Offset(3, 4), ik.elbow + const Offset(3, 4), upperShade);
    canvas.drawLine(shoulder, ik.elbow, upper);
    // Sleeve garter.
    final mid = Offset.lerp(shoulder, ik.elbow, 0.45)!;
    final dirU = (ik.elbow - shoulder);
    final nU = Offset(-dirU.dy, dirU.dx) / dirU.distance;
    canvas.drawLine(mid + nU * 24, mid - nU * 24, Paint()
      ..color = _vest
      ..strokeWidth = 9);
    canvas.drawLine(ik.elbow + const Offset(2, 3), ik.hand + const Offset(2, 3), Paint()
      ..color = _shirtShade
      ..strokeWidth = 40
      ..strokeCap = StrokeCap.round);
    canvas.drawLine(ik.elbow, ik.hand, fore);

    // Cuff + hand oriented along the forearm.
    final dir = ik.hand - ik.elbow;
    final ang = math.atan2(dir.dy, dir.dx);
    canvas.save();
    canvas.translate(ik.hand.dx, ik.hand.dy);
    canvas.rotate(ang);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-14, -22, 16, 44), const Radius.circular(5)), Paint()..color = Colors.white);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-14, -22, 16, 44), const Radius.circular(5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _shirtShade);
    final palm = Paint()..color = _skin;
    final shade = Paint()..color = _skinShade;
    // Fingers curl with grip.
    final fingerLen = 30 - 14 * arm.grip;
    for (var i = 0; i < 4; i++) {
      final y = -13.5 + i * 9.0;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(22, y - 4, fingerLen, 8.5), const Radius.circular(4.5));
      canvas.drawRRect(r.shift(const Offset(1, 1.5)), shade);
      canvas.drawRRect(r, palm);
    }
    canvas.drawOval(const Rect.fromLTWH(0, -19, 34, 38), shade);
    canvas.drawOval(const Rect.fromLTWH(-1, -20, 33, 37), palm);
    // Thumb (side depends on which arm, mirrored by orientation).
    final thumbSide = bendPositive ? 1.0 : -1.0;
    canvas.save();
    canvas.translate(16, 16 * thumbSide);
    canvas.rotate(thumbSide * (0.9 - 0.5 * arm.grip));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, -5, 22, 10), const Radius.circular(5)), palm);
    canvas.restore();
    canvas.restore();
  }

  void _shuffleDeck(Canvas canvas, double u) {
    const c0 = G.shuffleCenter;
    final k = ((u - 0.12) / 0.74).clamp(0.0, 1.0);
    final squeeze = math.sin(k * 3 * math.pi).abs();
    final gap = 120 - 55 * squeeze;
    const w = G.cardWidth * 0.95, h = G.cardHeight * 0.9;
    void stack(Offset center, double tilt) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      for (var i = 0; i < 9; i++) {
        final r = Rect.fromCenter(center: Offset(0, -i * 2.2), width: w, height: h);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), Paint()..color = i.isEven ? const Color(0xFFF4F1E8) : const Color(0xFFDDD8CB));
      }
      final top = Rect.fromCenter(center: const Offset(0, -20), width: w, height: h);
      canvas.drawRRect(RRect.fromRectAndRadius(top, const Radius.circular(8)), Paint()..color = style.backColor);
      canvas.drawRRect(RRect.fromRectAndRadius(top.deflate(8), const Radius.circular(5)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.7));
      canvas.restore();
    }

    if (u > 0.86) {
      // Squared-up deck travelling to the shoe.
      final t = ((u - 0.86) / 0.14).clamp(0.0, 1.0);
      stack(Offset.lerp(c0, G.shoeExit, t)!, -0.35 * t);
      return;
    }
    canvas.drawCircle(c0 + const Offset(0, 20), 150, Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    stack(c0 + Offset(-gap / 2 - 20, 0), 0.12 * squeeze);
    stack(c0 + Offset(gap / 2 + 20, 0), -0.12 * squeeze);
    // Riffling cards arcing between the halves.
    if (squeeze > 0.15) {
      final rng = math.Random((k * 60).floor());
      for (var i = 0; i < 6; i++) {
        final t = rng.nextDouble();
        final fromLeft = i.isEven;
        final x = c0.dx + (fromLeft ? -1 : 1) * (gap / 2) * (1 - t);
        final y = c0.dy - 30 - math.sin(t * math.pi) * 40;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate((fromLeft ? 1 : -1) * (0.6 - t));
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w * 0.9, height: 10), const Radius.circular(3)),
          Paint()..color = const Color(0xFFF4F1E8),
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(ArmsPainter old) => old.c != c || old.style != style;
}

/// Countdown ring around the active seat.
class TurnRingPainter extends CustomPainter {
  TurnRingPainter({required this.fraction, required this.color, required this.track});
  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 4;
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * (1 - fraction),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(TurnRingPainter old) => old.fraction != fraction || old.color != color;
}
