/// Widget around [CharacterPainter]: a character at a given size and framing,
/// optionally alive (blink + breathing driven by a ticker; [animate] false
/// draws one still frame, e.g. in goldens and lists).
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'character_painter.dart';
import 'character_spec.dart';

class CharacterPortrait extends StatefulWidget {
  const CharacterPortrait({
    super.key,
    required this.spec,
    this.size = 96,
    this.framing = CharacterFraming.medallion,
    this.expression = CharacterExpression.neutral,
    this.animate = false,
    this.pose,
  });

  final CharacterSpec spec;

  /// Width; the height follows the framing (bust 400:480, others square).
  final double size;
  final CharacterFraming framing;
  final CharacterExpression expression;

  /// Blink and breathe (deterministic from the elapsed time).
  final bool animate;

  /// Exact pose (overrides [expression] and [animate]).
  final CharacterPose? pose;

  @override
  State<CharacterPortrait> createState() => _CharacterPortraitState();
}

class _CharacterPortraitState extends State<CharacterPortrait> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  int _ms = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CharacterPortrait old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _sync();
  }

  void _sync() {
    if (widget.animate && widget.pose == null) {
      _ticker ??= createTicker((elapsed) => setState(() => _ms = elapsed.inMilliseconds))..start();
    } else {
      _ticker?.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.spec.id.codeUnits.fold<int>(0, (a, c) => a * 31 + c) % 3700;
    final pose = widget.pose ??
        CharacterPose(
          expression: widget.expression,
          blink: widget.animate ? blinkAt(_ms, phaseMs: phase) : 0,
          breath: widget.animate ? breathAt(_ms, phaseMs: phase) : 0.5,
        );
    final h = widget.framing == CharacterFraming.bust ? widget.size * CharacterPainter.box.height / CharacterPainter.box.width : widget.size;
    return Semantics(
      label: widget.spec.name,
      image: true,
      child: SizedBox(
        width: widget.size,
        height: h,
        child: CustomPaint(painter: CharacterPainter(spec: widget.spec, pose: pose, framing: widget.framing)),
      ),
    );
  }
}
