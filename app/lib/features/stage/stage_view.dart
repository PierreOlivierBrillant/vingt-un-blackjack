/// Rendering side of [StageController]: [StageView] scales the logical
/// [StageGeometry] space to the available width and stacks [StagePainter]
/// layers (each repaints when the controller notifies) plus pixel-space
/// overlays; [StageDriver] advances the controller with a ticker.
/// Generic layers for every game: [StageDealerPainter] (croupier bust drawn
/// by `CharacterPainter`) and [StageArmsPainter] (IK arms).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/characters/character_painter.dart';
import '../../core/characters/character_spec.dart';
import 'stage_controller.dart';

/// Advances [controller] every frame (capped at 50 ms per frame so a hitch
/// never teleports anything). [drive] false: the owner calls `advance`
/// (tests, goldens).
class StageDriver extends StatefulWidget {
  const StageDriver({super.key, required this.controller, required this.child, this.drive = true});
  final StageController controller;
  final Widget child;
  final bool drive;

  @override
  State<StageDriver> createState() => _StageDriverState();
}

class _StageDriverState extends State<StageDriver> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StageDriver old) {
    super.didUpdateWidget(old);
    if (old.drive != widget.drive) _sync();
  }

  void _sync() {
    if (widget.drive) {
      _ticker ??= createTicker((elapsed) {
        var dt = elapsed - _last;
        _last = elapsed;
        if (dt > const Duration(milliseconds: 50)) dt = const Duration(milliseconds: 50);
        widget.controller.advance(dt);
      })..start();
    } else {
      _ticker?.dispose();
      _ticker = null;
      _last = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A layer painted in logical stage units (the canvas is pre-scaled).
abstract class StagePainter extends CustomPainter {
  StagePainter(this.stage) : super(repaint: stage);
  final StageController stage;

  /// Paint in [StageController.geometry] coordinates.
  void paintStage(Canvas canvas);

  @override
  void paint(Canvas canvas, Size size) {
    final g = stage.geometry.size;
    canvas.save();
    canvas.scale(size.width / g.width, size.height / g.height);
    paintStage(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StagePainter oldDelegate) => oldDelegate.stage != stage;
}

/// The stage at the geometry's aspect ratio: [layers] bottom to top, then
/// [overlays] (positioned widgets in pixels, rebuilt on every notify; use
/// `scale` to convert stage units: `pos * scale`).
class StageView extends StatelessWidget {
  const StageView({super.key, required this.stage, this.layers = const [], this.overlays, this.drive = true});
  final StageController stage;
  final List<StagePainter> layers;
  final List<Widget> Function(BuildContext context, double scale)? overlays;
  final bool drive;

  @override
  Widget build(BuildContext context) {
    final g = stage.geometry.size;
    return StageDriver(
      controller: stage,
      drive: drive,
      child: AspectRatio(
        aspectRatio: g.width / g.height,
        child: LayoutBuilder(builder: (context, box) {
          final scale = box.maxWidth / g.width;
          return ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final l in layers) Positioned.fill(child: CustomPaint(painter: l)),
                if (overlays != null)
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: stage,
                      builder: (context, _) => Stack(clipBehavior: Clip.none, children: overlays!(context, scale)),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// The croupier's bust ([CharacterPainter]) anchored on the geometry's
/// dealer head, posed from [StageController.dealer] (blink, breath,
/// expression, speech). Paint it BEFORE the felt: the felt hides the waist.
class StageDealerPainter extends StagePainter {
  StageDealerPainter(super.stage, this.spec);
  final CharacterSpec spec;

  @override
  void paintStage(Canvas canvas) {
    final g = stage.geometry;
    final k = g.dealerHeadRadius / CharacterPainter.headRy;
    final head = CharacterPainter.headCenter;
    canvas.save();
    canvas.translate(g.dealerHead.dx - head.dx * k, g.dealerHead.dy - head.dy * k);
    canvas.scale(k);
    paintCharacter(canvas, spec, stage.poseOf(stage.dealer));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StageDealerPainter oldDelegate) => oldDelegate.stage != stage || oldDelegate.spec != spec;
}

/// The croupier's two arms: shirt sleeves solved by IK ([StageArm.solve]),
/// skin-coloured hands that close with [StageArm.grip].
class StageArmsPainter extends StagePainter {
  StageArmsPainter(super.stage, this.spec);
  final CharacterSpec spec;

  @override
  void paintStage(Canvas canvas) {
    final k = stage.geometry.dealerHeadRadius / 60;
    for (final arm in [stage.leftArm, stage.rightArm]) {
      final ik = arm.solve();
      final sleeve = switch (spec.outfit) {
        Outfit.dealerVest || Outfit.dealerDress || Outfit.casual => spec.outfitSecondary,
        _ => spec.outfitPrimary,
      };
      Paint line(Color c, double w) => Paint()
        ..color = c
        ..strokeWidth = w * k
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final shadow = Colors.black.withValues(alpha: 0.25);
      canvas.drawLine(arm.shoulder + const Offset(4, 6), ik.elbow + const Offset(4, 6), line(shadow, 50));
      canvas.drawLine(ik.elbow + const Offset(4, 6), ik.hand + const Offset(4, 6), line(shadow, 40));
      canvas.drawLine(arm.shoulder, ik.elbow, line(sleeve, 50));
      canvas.drawLine(ik.elbow, ik.hand, line(sleeve, 40));
      canvas.drawCircle(ik.elbow, 23 * k, Paint()..color = sleeve);
      // Cuff + hand.
      final dir = ik.hand - ik.elbow;
      final u = dir.distance == 0 ? const Offset(0, 1) : dir / dir.distance;
      canvas.drawLine(ik.hand - u * 14 * k, ik.hand - u * 4 * k, line(Color.lerp(sleeve, Colors.black, 0.12)!, 42));
      final r = (20 - 4 * arm.grip) * k;
      canvas.drawCircle(ik.hand + u * 8 * k, r, Paint()..color = spec.skin);
      canvas.drawCircle(ik.hand + u * 8 * k + Offset(-u.dy, u.dx) * r * 0.6, r * 0.45, Paint()..color = Color.lerp(spec.skin, Colors.black, 0.08)!);
    }
  }

  @override
  bool shouldRepaint(covariant StageArmsPainter oldDelegate) => oldDelegate.stage != stage || oldDelegate.spec != spec;
}

/// A ring around a seat spot showing [StageController.turnFraction] (in
/// pixels), for overlays: `StageTurnRing(stage: s, scale: scale)`.
class StageTurnRing extends StatelessWidget {
  const StageTurnRing({super.key, required this.stage, required this.scale, this.radius = 74, this.color = const Color(0xFFFFC83D)});
  final StageController stage;
  final double scale;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final seat = stage.turnSeat;
    if (seat == null || seat >= stage.geometry.seatCount) return const SizedBox.shrink();
    final c = stage.geometry.seatSpot(seat) * scale;
    final r = radius * scale;
    return Positioned(
      left: c.dx - r,
      top: c.dy - r,
      width: r * 2,
      height: r * 2,
      child: IgnorePointer(
        child: CustomPaint(painter: _RingPainter(1 - stage.turnFraction, color, math.max(2, 6 * scale))),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.left, this.color, this.width);
  final double left;
  final Color color;
  final double width;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * left, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = left < 0.25 ? const Color(0xFFFF5A5A) : color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.left != left || old.color != color || old.width != width;
}
