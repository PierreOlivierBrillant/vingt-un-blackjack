/// Procedural avatars `avatar01`..`avatar24`: no image asset, no upload.
/// Each id maps to a hue (15° steps, [avatarHueOf]), a glyph (6 shapes) and
/// a background pattern (4 patterns) so all 24 are visually distinct.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/backend_constants.dart';
import '../domain/models.dart' show avatarHueOf;

/// 0-based index of [avatarId] (`avatar01` → 0), or a stable fallback.
int avatarIndexOf(String avatarId) {
  final n = int.tryParse(avatarId.replaceFirst('avatar', ''));
  if (n != null && n >= 1 && n <= 24) return n - 1;
  return avatarId.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xFFFF) % 24;
}

class AvatarPainter extends CustomPainter {
  AvatarPainter(this.avatarId) : index = avatarIndexOf(avatarId), hue = avatarHueOf(avatarId).toDouble();

  final String avatarId;
  final int index;
  final double hue;

  int get glyph => index % 6;
  int get pattern => index ~/ 6;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));

    final base = HSLColor.fromAHSL(1, hue, 0.62, 0.46).toColor();
    final deep = HSLColor.fromAHSL(1, (hue + 24) % 360, 0.66, 0.28).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [base, deep]).createShader(rect),
    );

    final overlay = Paint()..color = Colors.white.withValues(alpha: 0.13);
    switch (pattern) {
      case 0:
        break;
      case 1: // concentric rings
        overlay
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.09;
        for (var k = 1; k <= 3; k++) {
          canvas.drawCircle(c, r * (0.38 + k * 0.22), overlay);
        }
      case 2: // diagonal stripes
        overlay.strokeWidth = r * 0.16;
        for (var k = -4; k <= 4; k++) {
          final o = Offset(k * r * 0.42, 0);
          canvas.drawLine(c + o + Offset(-r, -r), c + o + Offset(r, r), overlay);
        }
      default: // dots
        for (var y = -2; y <= 2; y++) {
          for (var x = -2; x <= 2; x++) {
            canvas.drawCircle(c + Offset(x * r * 0.42 + (y.isOdd ? r * 0.21 : 0), y * r * 0.42), r * 0.07, overlay);
          }
        }
    }

    final fg = Paint()..color = Colors.white;
    final g = r * 0.5;
    final path = switch (glyph) {
      0 => Path()..addOval(Rect.fromCircle(center: c, radius: g * 0.85)),
      1 => _polygon(c, g, 4, math.pi / 4), // square
      2 => _polygon(c, g * 1.05, 4, 0), // diamond
      3 => _polygon(c, g * 1.05, 3, -math.pi / 2), // triangle
      4 => _star(c, g * 1.1, g * 0.48, 5),
      _ => _polygon(c, g, 6, 0), // hexagon
    };
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, fg);
    // A small "eye" so the glyph reads as a character.
    canvas.drawCircle(c + Offset(-g * 0.22, -g * 0.08), g * 0.11, Paint()..color = deep);
    canvas.drawCircle(c + Offset(g * 0.22, -g * 0.08), g * 0.11, Paint()..color = deep);
    canvas.restore();
  }

  static Path _polygon(Offset c, double r, int n, double rot) {
    final p = Path();
    for (var i = 0; i < n; i++) {
      final a = rot + i * 2 * math.pi / n;
      final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  static Path _star(Offset c, double outer, double inner, int n) {
    final p = Path();
    for (var i = 0; i < n * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / n;
      final r = i.isEven ? outer : inner;
      final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(AvatarPainter old) => old.avatarId != avatarId;
}

/// Grid of the 24 procedural avatars. Each tile has `Key('avatar-<id>')`.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({super.key, required this.selected, required this.onSelected, this.size = 46});
  final String selected;
  final ValueChanged<String> onSelected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final id in Backend.avatarIds)
          Semantics(
            button: true,
            selected: id == selected,
            label: id,
            child: InkResponse(
              key: Key('avatar-$id'),
              onTap: () => onSelected(id),
              radius: size / 2 + 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: id == selected ? primary : Colors.transparent, width: 3),
                ),
                child: SizedBox.square(dimension: size, child: CustomPaint(painter: AvatarPainter(id))),
              ),
            ),
          ),
      ],
    );
  }
}
