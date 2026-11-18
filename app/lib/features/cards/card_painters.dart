import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/card_style.dart';
import '../../domain/cards.dart';
import 'suit_paths.dart';

/// Standard poker-size ratio (63 × 88 mm).
const kCardAspect = 63 / 88;

/// Ink colours per face style.
class FaceInk {
  const FaceInk({required this.paper, required this.edge, required this.glow});
  final Color paper;
  final Color edge;
  final bool glow;

  static FaceInk of(CardFaceStyle s) => switch (s) {
        CardFaceStyle.neon => const FaceInk(paper: Color(0xFF0B0F1A), edge: Color(0xFF2A3350), glow: true),
        _ => const FaceInk(paper: Color(0xFFFBFAF5), edge: Color(0xFFD8D4C8), glow: false),
      };

  static Color suitColor(Suit suit, CardFaceStyle style) => switch (style) {
        CardFaceStyle.classic => suit.isRed ? const Color(0xFFCC1F2D) : const Color(0xFF15181D),
        CardFaceStyle.fourColor => switch (suit) {
            Suit.spades => const Color(0xFF15181D),
            Suit.hearts => const Color(0xFFCC1F2D),
            Suit.diamonds => const Color(0xFF1565C0),
            Suit.clubs => const Color(0xFF138A36),
          },
        CardFaceStyle.neon => suit.isRed ? const Color(0xFFFF3D9A) : const Color(0xFF39F3FF),
      };
}

/// Pip positions (x: 0..1 across the pip area, y: 0..1 down).
const _pipLayouts = <int, List<Offset>>{
  2: [Offset(.5, 0), Offset(.5, 1)],
  3: [Offset(.5, 0), Offset(.5, .5), Offset(.5, 1)],
  4: [Offset(0, 0), Offset(1, 0), Offset(0, 1), Offset(1, 1)],
  5: [Offset(0, 0), Offset(1, 0), Offset(.5, .5), Offset(0, 1), Offset(1, 1)],
  6: [Offset(0, 0), Offset(1, 0), Offset(0, .5), Offset(1, .5), Offset(0, 1), Offset(1, 1)],
  7: [Offset(0, 0), Offset(1, 0), Offset(.5, .25), Offset(0, .5), Offset(1, .5), Offset(0, 1), Offset(1, 1)],
  8: [Offset(0, 0), Offset(1, 0), Offset(.5, .25), Offset(0, .5), Offset(1, .5), Offset(.5, .75), Offset(0, 1), Offset(1, 1)],
  9: [Offset(0, 0), Offset(1, 0), Offset(0, 1 / 3), Offset(1, 1 / 3), Offset(.5, .5), Offset(0, 2 / 3), Offset(1, 2 / 3), Offset(0, 1), Offset(1, 1)],
  10: [Offset(0, 0), Offset(1, 0), Offset(.5, 1 / 6), Offset(0, 1 / 3), Offset(1, 1 / 3), Offset(0, 2 / 3), Offset(1, 2 / 3), Offset(.5, 5 / 6), Offset(0, 1), Offset(1, 1)],
};

class CardFacePainter extends CustomPainter {
  const CardFacePainter({required this.card, required this.style});

  final PlayingCard card;
  final CardFaceStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = FaceInk.of(style);
    final w = size.width, h = size.height;
    final radius = Radius.circular(w * 0.08);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(rrect, Paint()..color = ink.paper);
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, w * 0.012)
        ..color = ink.edge,
    );

    final color = FaceInk.suitColor(card.suit, style);
    final glow = ink.glow;

    // Corner indices.
    _corner(canvas, size, color, glow);
    canvas.save();
    canvas.translate(w, h);
    canvas.rotate(math.pi);
    _corner(canvas, size, color, glow);
    canvas.restore();

    // Centre.
    final area = Rect.fromLTRB(w * 0.29, h * 0.13, w * 0.71, h * 0.87);
    if (card.rank == Rank.ace) {
      final s = w * (card.suit == Suit.spades ? 0.5 : 0.4);
      _pip(canvas, Rect.fromCenter(center: area.center, width: s, height: s * 1.1), color, glow);
    } else if (card.rank.isFace) {
      _faceCard(canvas, area, color, glow);
    } else {
      final pips = _pipLayouts[card.rank.value]!;
      final pw = w * 0.17;
      for (final p in pips) {
        final c = Offset(area.left + p.dx * area.width, area.top + pw * 0.55 + p.dy * (area.height - pw * 1.1));
        final r = Rect.fromCenter(center: c, width: pw, height: pw * 1.08);
        if (p.dy > 0.5) {
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(math.pi);
          canvas.translate(-c.dx, -c.dy);
          _pip(canvas, r, color, glow);
          canvas.restore();
        } else {
          _pip(canvas, r, color, glow);
        }
      }
    }
  }

  void _corner(Canvas canvas, Size size, Color color, bool glow) {
    final w = size.width;
    final fontSize = w * (card.rank == Rank.ten ? 0.2 : 0.23);
    final tp = TextPainter(
      text: TextSpan(
        text: card.rank.label,
        style: TextStyle(
          fontFamily: kAppFont,
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1,
          letterSpacing: card.rank == Rank.ten ? -fontSize * 0.08 : 0,
          shadows: glow ? [Shadow(color: color, blurRadius: w * 0.05)] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cx = w * 0.13;
    tp.paint(canvas, Offset(cx - tp.width / 2, w * 0.07));
    final s = w * 0.13;
    _pip(canvas, Rect.fromCenter(center: Offset(cx, w * 0.07 + tp.height + s * 0.62), width: s, height: s * 1.08), color, glow);
  }

  void _pip(Canvas canvas, Rect r, Color color, bool glow) {
    final path = suitPath(card.suit, r);
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r.width * 0.18),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, r.width * 0.09)
          ..color = color,
      );
    } else {
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  void _faceCard(Canvas canvas, Rect area, Color color, bool glow) {
    final frame = RRect.fromRectAndRadius(area, Radius.circular(area.width * 0.06));
    final tint = glow ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.08);
    canvas.drawRRect(frame, Paint()..color = tint);
    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, area.width * 0.025)
        ..color = color,
    );
    // Gold band + crown silhouette.
    final gold = glow ? const Color(0xFFFFE066) : const Color(0xFFC9A227);
    final crownW = area.width * 0.62;
    final top = area.top + area.height * 0.14;
    final cx = area.center.dx;
    final crown = Path()
      ..moveTo(cx - crownW / 2, top + crownW * 0.45)
      ..lineTo(cx - crownW / 2, top + crownW * 0.12)
      ..lineTo(cx - crownW / 4, top + crownW * 0.30)
      ..lineTo(cx, top)
      ..lineTo(cx + crownW / 4, top + crownW * 0.30)
      ..lineTo(cx + crownW / 2, top + crownW * 0.12)
      ..lineTo(cx + crownW / 2, top + crownW * 0.45)
      ..close();
    if (card.rank == Rank.jack) {
      // Jack: a feathered cap instead of a crown.
      crown
        ..reset()
        ..moveTo(cx - crownW / 2, top + crownW * 0.45)
        ..quadraticBezierTo(cx - crownW * 0.1, top - crownW * 0.15, cx + crownW / 2, top + crownW * 0.2)
        ..lineTo(cx + crownW / 2, top + crownW * 0.45)
        ..close();
    }
    canvas.drawPath(crown, Paint()..color = gold);
    if (glow) {
      canvas.drawPath(crown, Paint()
        ..color = gold.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, area.width * 0.05));
    }

    final letter = TextPainter(
      text: TextSpan(
        text: card.rank.label,
        style: TextStyle(
          fontFamily: kAppFont,
          color: color,
          fontSize: area.width * 0.62,
          fontWeight: FontWeight.w900,
          height: 1,
          shadows: glow ? [Shadow(color: color, blurRadius: area.width * 0.12)] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    letter.paint(canvas, Offset(cx - letter.width / 2, area.top + area.height * 0.42));
    final s = area.width * 0.26;
    _pip(canvas, Rect.fromCenter(center: Offset(cx, area.bottom - s * 0.9), width: s, height: s * 1.08), color, glow);
  }

  @override
  bool shouldRepaint(CardFacePainter old) => old.card != card || old.style != style;
}

class CardBackPainter extends CustomPainter {
  const CardBackPainter({required this.design, required this.color});

  final CardBackDesign design;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.08));
    canvas.drawRRect(outer, Paint()..color = const Color(0xFFF7F5EE));
    final innerRect = Rect.fromLTRB(w * 0.07, w * 0.07, w * 0.93, h - w * 0.07);
    final inner = RRect.fromRectAndRadius(innerRect, Radius.circular(w * 0.05));
    final hsl = HSLColor.fromColor(color);
    final darker = hsl.withLightness((hsl.lightness * 0.62).clamp(0, 1)).toColor();
    final lighter = hsl.withLightness((hsl.lightness * 1.35 + 0.08).clamp(0, 1)).toColor();
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, darker],
        ).createShader(innerRect),
    );

    canvas.save();
    canvas.clipRRect(inner);
    final line = Paint()
      ..color = lighter.withValues(alpha: 0.55)
      ..strokeWidth = math.max(0.6, w * 0.018)
      ..style = PaintingStyle.stroke;
    switch (design) {
      case CardBackDesign.lattice:
        final step = w * 0.11;
        for (var d = -h; d < w + h; d += step) {
          canvas.drawLine(Offset(d, 0), Offset(d + h, h), line);
          canvas.drawLine(Offset(d + h, 0), Offset(d, h), line);
        }
      case CardBackDesign.stripes:
        final step = w * 0.09;
        final band = Paint()..color = lighter.withValues(alpha: 0.35);
        for (var d = -h; d < w + h; d += step * 2) {
          final p = Path()
            ..moveTo(d, 0)
            ..lineTo(d + step, 0)
            ..lineTo(d + step + h * 0.6, h)
            ..lineTo(d + h * 0.6, h)
            ..close();
          canvas.drawPath(p, band);
        }
      case CardBackDesign.chevron:
        final step = w * 0.12;
        for (var y = innerRect.top - step; y < h + step; y += step) {
          final p = Path()..moveTo(0, y);
          for (var x = 0.0; x <= w; x += step) {
            p.lineTo(x + step / 2, y + step / 2);
            p.lineTo(x + step, y);
          }
          canvas.drawPath(p, line);
        }
      case CardBackDesign.dots:
        final step = w * 0.12;
        final dot = Paint()..color = lighter.withValues(alpha: 0.6);
        var row = 0;
        for (var y = innerRect.top + step / 2; y < h; y += step * 0.86) {
          final off = row.isEven ? 0.0 : step / 2;
          for (var x = innerRect.left + off; x < w; x += step) {
            canvas.drawCircle(Offset(x, y), step * 0.22, dot);
          }
          row++;
        }
      case CardBackDesign.sunburst:
        final c = innerRect.center;
        final ray = Paint()..color = lighter.withValues(alpha: 0.28);
        const n = 24;
        for (var i = 0; i < n; i += 2) {
          final a0 = i * 2 * math.pi / n, a1 = (i + 1) * 2 * math.pi / n;
          final p = Path()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx + math.cos(a0) * h, c.dy + math.sin(a0) * h)
            ..lineTo(c.dx + math.cos(a1) * h, c.dy + math.sin(a1) * h)
            ..close();
          canvas.drawPath(p, ray);
        }
    }
    canvas.restore();

    // Inner frame + central medallion with a "21".
    canvas.drawRRect(
      inner.deflate(w * 0.035),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, w * 0.012)
        ..color = Colors.white.withValues(alpha: 0.7),
    );
    final c = innerRect.center;
    final mr = w * 0.17;
    canvas.drawCircle(c, mr, Paint()..color = darker);
    canvas.drawCircle(
      c,
      mr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, w * 0.02)
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '21',
        style: TextStyle(fontFamily: kAppFont, color: Colors.white, fontSize: mr * 0.95, fontWeight: FontWeight.w900, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(CardBackPainter old) => old.design != design || old.color != color;
}

/// A playing card at a given width. `card == null` or `faceUp == false`
/// shows the back.
class PlayingCardView extends StatelessWidget {
  const PlayingCardView({
    super.key,
    required this.card,
    required this.style,
    this.faceUp = true,
    this.width = 64,
    this.elevation = 2,
  });

  final PlayingCard? card;
  final CardStyle style;
  final bool faceUp;
  final double width;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final showFace = faceUp && card != null;
    return Semantics(
      label: showFace ? card!.code : 'card back',
      child: Container(
        width: width,
        height: width / kCardAspect,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.08),
          boxShadow: elevation <= 0
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: elevation * 2,
                    offset: Offset(0, elevation),
                  ),
                ],
        ),
        child: CustomPaint(
          painter: showFace
              ? CardFacePainter(card: card!, style: style.face)
              : CardBackPainter(design: style.back, color: style.backColor),
        ),
      ),
    );
  }
}
