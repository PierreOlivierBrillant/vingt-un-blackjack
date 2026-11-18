/// WCAG 2.x contrast helpers (used to keep badges readable in both themes).
library;

import 'package:flutter/painting.dart';

/// [fg] painted with its alpha over the opaque [bg].
Color compositeOver(Color fg, Color bg) => Color.alphaBlend(fg, bg.withValues(alpha: 1));

/// WCAG contrast ratio (1..21) between two colours (alpha composited over
/// [background] first).
double contrastRatio(Color foreground, Color background) {
  final bg = background.withValues(alpha: 1);
  final fg = compositeOver(foreground, bg);
  final a = fg.computeLuminance(), b = bg.computeLuminance();
  final hi = a > b ? a : b, lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}
