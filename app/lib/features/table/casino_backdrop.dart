import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Decor filling the room above the table on tall screens (instead of an
/// empty band): a neon sign ([sign], "VINGT·UN" by default, in [neon]
/// colour), warm pendant lamps and soft bokeh on the back wall. Its bottom
/// edge is the screen background colour, which is also the stage's top edge
/// (seamless). Each game passes its own sign / colour (`GameUi`).
class CasinoBackdrop extends StatelessWidget {
  const CasinoBackdrop({super.key, this.sign = 'VINGT·UN', this.neon = const Color(0xFF00E701)});

  final String sign;
  final Color neon;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _BackdropPainter(sign, neon), size: Size.infinite),
      );
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.sign, this.neonColor);
  final String sign;
  final Color neonColor;
  static const _bg = Color(0xFF0A1620);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = _bg);
    if (size.height < 30) return;
    // Wall glow, strongest behind the sign.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 0.9,
          colors: [const Color(0xFF1A3346).withValues(alpha: 0.9), _bg],
        ).createShader(rect),
    );
    // Bokeh (deterministic).
    final r = math.Random(21);
    for (var i = 0; i < 26; i++) {
      final c = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height * 0.9);
      final rad = 4 + r.nextDouble() * 14;
      final hue = [const Color(0xFFFFC83D), const Color(0xFFFF5A7A), const Color(0xFF3D8BFF)][i % 3];
      canvas.drawCircle(c, rad, Paint()
        ..color = hue.withValues(alpha: 0.05 + r.nextDouble() * 0.07)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.6));
    }
    // Pendant lamps.
    const lamps = 5;
    for (var i = 0; i < lamps; i++) {
      final x = size.width * (i + 0.5) / lamps;
      final y = math.min(size.height * 0.22, 46.0);
      canvas.drawLine(Offset(x, 0), Offset(x, y - 8), Paint()
        ..color = const Color(0xFF2B3B48)
        ..strokeWidth = 1.5);
      canvas.drawCircle(Offset(x, y), 26, Paint()
        ..color = const Color(0x33FFC46B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
      final shade = Path()
        ..moveTo(x - 14, y)
        ..lineTo(x - 7, y - 9)
        ..lineTo(x + 7, y - 9)
        ..lineTo(x + 14, y)
        ..close();
      canvas.drawPath(shade, Paint()..color = const Color(0xFF8C6A2E));
      canvas.drawCircle(Offset(x, y + 1), 4, Paint()..color = const Color(0xFFFFE3A6));
    }
    // Neon sign, only when there is room for it.
    if (size.height >= 110) {
      // Longer signs shrink to fit ("VINGT·UN" keeps its Sprint 1 size).
      final fontSize = math.min(size.height * 0.24, size.width * 0.11 * math.min(1.0, 8 / math.max(1, sign.length)));
      final center = Offset(size.width / 2, size.height * 0.58);
      void neon(Color glow, double blur, double width) {
        final tp = TextPainter(
          text: TextSpan(
            text: sign,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              letterSpacing: fontSize * 0.08,
              foreground: Paint()
                ..style = width > 0 ? PaintingStyle.stroke : PaintingStyle.fill
                ..strokeWidth = width
                ..color = glow
                ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      }

      neon(neonColor.withValues(alpha: 0x88 / 0xFF), 14, 6);
      neon(neonColor.withValues(alpha: 0xCC / 0xFF), 4, 3);
      neon(neonColor == const Color(0xFF00E701) ? const Color(0xFFD9FFD9) : Color.lerp(neonColor, Colors.white, 0.85)!, 0, 1.2);
    }
    // Fade into the background at the bottom (meets the stage seamlessly).
    final fade = Rect.fromLTWH(0, size.height * 0.75, size.width, size.height * 0.25);
    canvas.drawRect(
      fade,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x000A1620), _bg],
        ).createShader(fade),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => oldDelegate.sign != sign || oldDelegate.neonColor != neonColor;
}
