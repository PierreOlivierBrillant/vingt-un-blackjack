import 'dart:ui';

import '../../domain/cards.dart';

/// Vector suit symbols fitted into [r]. Drawn from cubic curves, no glyphs,
/// so they render identically on every device and in golden tests.
Path suitPath(Suit suit, Rect r) => switch (suit) {
      Suit.hearts => _heart(r),
      Suit.diamonds => _diamond(r),
      Suit.spades => _spade(r),
      Suit.clubs => _club(r),
    };

Path _heart(Rect r) {
  final w = r.width, h = r.height, x = r.left, y = r.top;
  return Path()
    ..moveTo(x + w * 0.5, y + h * 0.98)
    ..cubicTo(x + w * 0.18, y + h * 0.72, x - w * 0.02, y + h * 0.48, x + w * 0.03, y + h * 0.27)
    ..cubicTo(x + w * 0.08, y + h * 0.04, x + w * 0.40, y - h * 0.02, x + w * 0.5, y + h * 0.22)
    ..cubicTo(x + w * 0.60, y - h * 0.02, x + w * 0.92, y + h * 0.04, x + w * 0.97, y + h * 0.27)
    ..cubicTo(x + w * 1.02, y + h * 0.48, x + w * 0.82, y + h * 0.72, x + w * 0.5, y + h * 0.98)
    ..close();
}

Path _diamond(Rect r) {
  final w = r.width, h = r.height, x = r.left, y = r.top;
  return Path()
    ..moveTo(x + w * 0.5, y)
    ..quadraticBezierTo(x + w * 0.70, y + h * 0.28, x + w * 0.92, y + h * 0.5)
    ..quadraticBezierTo(x + w * 0.70, y + h * 0.72, x + w * 0.5, y + h)
    ..quadraticBezierTo(x + w * 0.30, y + h * 0.72, x + w * 0.08, y + h * 0.5)
    ..quadraticBezierTo(x + w * 0.30, y + h * 0.28, x + w * 0.5, y)
    ..close();
}

Path _spade(Rect r) {
  final w = r.width, h = r.height, x = r.left, y = r.top;
  final body = Path()
    ..moveTo(x + w * 0.5, y)
    ..cubicTo(x + w * 0.62, y + h * 0.18, x + w * 1.02, y + h * 0.36, x + w * 0.98, y + h * 0.58)
    ..cubicTo(x + w * 0.95, y + h * 0.78, x + w * 0.66, y + h * 0.80, x + w * 0.54, y + h * 0.66)
    ..quadraticBezierTo(x + w * 0.58, y + h * 0.88, x + w * 0.74, y + h)
    ..lineTo(x + w * 0.26, y + h)
    ..quadraticBezierTo(x + w * 0.42, y + h * 0.88, x + w * 0.46, y + h * 0.66)
    ..cubicTo(x + w * 0.34, y + h * 0.80, x + w * 0.05, y + h * 0.78, x + w * 0.02, y + h * 0.58)
    ..cubicTo(x - w * 0.02, y + h * 0.36, x + w * 0.38, y + h * 0.18, x + w * 0.5, y)
    ..close();
  return body;
}

Path _club(Rect r) {
  final w = r.width, h = r.height, x = r.left, y = r.top;
  final rad = w * 0.235;
  final p = Path()
    ..addOval(Rect.fromCircle(center: Offset(x + w * 0.5, y + h * 0.25), radius: rad))
    ..addOval(Rect.fromCircle(center: Offset(x + w * 0.25, y + h * 0.55), radius: rad))
    ..addOval(Rect.fromCircle(center: Offset(x + w * 0.75, y + h * 0.55), radius: rad))
    ..addRect(Rect.fromLTRB(x + w * 0.38, y + h * 0.3, x + w * 0.62, y + h * 0.6));
  final stem = Path()
    ..moveTo(x + w * 0.46, y + h * 0.55)
    ..quadraticBezierTo(x + w * 0.44, y + h * 0.86, x + w * 0.26, y + h)
    ..lineTo(x + w * 0.74, y + h)
    ..quadraticBezierTo(x + w * 0.56, y + h * 0.86, x + w * 0.54, y + h * 0.55)
    ..close();
  return Path.combine(PathOperation.union, p, stem);
}
