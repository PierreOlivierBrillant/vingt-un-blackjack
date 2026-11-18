import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

@immutable
class ChipDenomination {
  const ChipDenomination(this.cents, this.color, this.stripe, this.label);
  final int cents;
  final Color color;
  final Color stripe;
  final String label;
}

/// Casino-standard colours, largest first.
const kChipDenominations = <ChipDenomination>[
  ChipDenomination(100000, Color(0xFFE0B23A), Color(0xFF6B4E00), '1K'),
  ChipDenomination(50000, Color(0xFF6A2BB8), Color(0xFFF2E6FF), '500'),
  ChipDenomination(10000, Color(0xFF16181C), Color(0xFFE8E8E8), '100'),
  ChipDenomination(2500, Color(0xFF138A36), Color(0xFFFFFFFF), '25'),
  ChipDenomination(500, Color(0xFFC81E2B), Color(0xFFFFFFFF), '5'),
  ChipDenomination(100, Color(0xFFF2F2F2), Color(0xFF1475E1), '1'),
];

/// Greedy decomposition of an amount into chips (largest first). Amounts
/// below 1.00 are not representable as chips and are ignored for display.
List<ChipDenomination> chipsFor(int cents, {int maxChips = 12}) {
  final out = <ChipDenomination>[];
  var rest = cents;
  for (final d in kChipDenominations) {
    while (rest >= d.cents && out.length < maxChips) {
      out.add(d);
      rest -= d.cents;
    }
  }
  return out;
}

/// Paints one chip seen from above at [center].
void paintChip(Canvas canvas, Offset center, double radius, ChipDenomination d, {bool label = true}) {
  final body = Paint()..color = d.color;
  canvas.drawCircle(center + Offset(0, radius * 0.12), radius, Paint()..color = Colors.black.withValues(alpha: 0.35));
  canvas.drawCircle(center, radius, body);
  // Edge inserts.
  final stripe = Paint()
    ..color = d.stripe
    ..style = PaintingStyle.stroke
    ..strokeWidth = radius * 0.22;
  for (var i = 0; i < 6; i++) {
    final a = i * math.pi / 3;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius * 0.86), a, math.pi / 9, false, stripe);
  }
  canvas.drawCircle(
    center,
    radius * 0.62,
    Paint()
      ..color = d.stripe.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.06,
  );
  if (label) {
    final tp = TextPainter(
      text: TextSpan(
        text: d.label,
        style: TextStyle(
          fontFamily: kAppFont,
          color: d.stripe,
          fontSize: radius * (d.label.length > 2 ? 0.55 : 0.7),
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
}

/// Paints a stack of chips; later chips are drawn higher up.
void paintChipStack(Canvas canvas, Offset base, double radius, int cents) {
  final chips = chipsFor(cents).reversed.toList();
  for (var i = 0; i < chips.length; i++) {
    paintChip(canvas, base - Offset(0, i * radius * 0.28), radius, chips[i], label: i == chips.length - 1);
  }
}

class ChipStackPainter extends CustomPainter {
  const ChipStackPainter(this.cents);
  final int cents;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 * 0.92;
    paintChipStack(canvas, Offset(size.width / 2, size.height - r * 1.15), r, cents);
  }

  @override
  bool shouldRepaint(ChipStackPainter old) => old.cents != cents;
}

/// A single tappable chip (bet selector).
class ChipButton extends StatelessWidget {
  const ChipButton({super.key, required this.denomination, this.selected = false, this.onTap, this.size = 48});
  final ChipDenomination denomination;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: selected ? 1.12 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: selected
                ? [BoxShadow(color: Theme.of(context).colorScheme.primary, blurRadius: 10, spreadRadius: 1)]
                : null,
          ),
          child: CustomPaint(painter: _SingleChip(denomination)),
        ),
      ),
    );
  }
}

class _SingleChip extends CustomPainter {
  const _SingleChip(this.d);
  final ChipDenomination d;
  @override
  void paint(Canvas canvas, Size size) =>
      paintChip(canvas, size.center(Offset.zero), size.width / 2 * 0.94, d);
  @override
  bool shouldRepaint(_SingleChip old) => old.d != d;
}
