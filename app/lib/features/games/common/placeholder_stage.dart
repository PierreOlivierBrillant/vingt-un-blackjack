/// Generic stage of a game whose own animations are not written yet (phase
/// A placeholders): the croupier of the table (alive: blink, breathing, IK
/// arms at rest), a felt in the player's equipped colours with the game's
/// seat spots and names, the turn ring and a "being set up" plaque. Built
/// only on the shared pieces (StageController, StageView, CharacterPainter):
/// it is also a working example for the game implementers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sound_providers.dart';
import '../../../core/characters/cast.dart';
import '../../../core/widgets.dart';
import '../../../data/providers.dart';
import '../../../domain/card_style.dart';
import '../../../domain/game_table.dart';
import '../../stage/stage_controller.dart';
import '../../stage/stage_geometry.dart';
import '../../stage/stage_view.dart';
import 'game_table_view.dart';

class GamePlaceholderStage extends ConsumerStatefulWidget {
  const GamePlaceholderStage({super.key, required this.view, required this.geometry, this.drive = true});
  final GameTableView view;
  final StageGeometry geometry;

  /// false in goldens / tests that advance the controller by hand.
  final bool drive;

  @override
  ConsumerState<GamePlaceholderStage> createState() => _GamePlaceholderStageState();
}

class _GamePlaceholderStageState extends ConsumerState<GamePlaceholderStage> {
  late final StageController _stage = StageController(
    geometry: widget.geometry,
    feedback: SoundStageFeedback(ref.read(soundProvider)),
  );
  int? _turnFor;

  @override
  void initState() {
    super.initState();
    _syncTurn();
  }

  @override
  void didUpdateWidget(GamePlaceholderStage old) {
    super.didUpdateWidget(old);
    _syncTurn();
  }

  /// The ring follows the server's turn (remaining time from the deadline).
  void _syncTurn() {
    final t = widget.view.table;
    final seat = t.phase == GamePhase.live ? t.turnSeat : null;
    final key = seat == null ? null : seat * 100000 + t.round;
    if (key == _turnFor) return;
    _turnFor = key;
    if (seat == null) {
      _stage.stopTurnTimer();
    } else {
      _stage.startTurnTimer(seat, const Duration(milliseconds: GameTiming.decisionMs), remaining: t.remainingAt(widget.view.now));
    }
  }

  @override
  void dispose() {
    _stage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ui = widget.view.ui;
    final t = widget.view.table;
    final felt = (ref.watch(equippedStyleProvider).value ?? const CardStyle()).felt;
    final spec = Cast.of(t.dealerCharacterId);
    return StageView(
      stage: _stage,
      drive: widget.drive,
      layers: [
        StageDealerPainter(_stage, spec),
        GameFeltPainter(_stage, light: felt.light, dark: felt.dark, accent: ui.accent),
        StageArmsPainter(_stage, spec),
      ],
      overlays: (context, scale) => [
        StageTurnRing(stage: _stage, scale: scale, color: ui.accent),
        for (var i = 0; i < widget.geometry.seatCount && i < t.seats.length; i++)
          _SeatPlate(
            key: Key('stage-seat-$i'),
            center: widget.geometry.seatSpot(i) * scale,
            scale: scale,
            label: t.seats[i] == null ? null : (t.seats[i]!.uid == widget.view.myUid ? l.gameYou : t.seats[i]!.username),
            me: t.seats[i]?.uid == widget.view.myUid,
          ),
        Positioned(
          left: 0,
          right: 0,
          top: (widget.geometry.felt.top + widget.geometry.felt.height * 0.38) * scale,
          child: Center(
            child: Container(
              key: const Key('game-placeholder'),
              padding: EdgeInsets.symmetric(horizontal: 18 * scale + 6, vertical: 10 * scale + 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ui.accent.withValues(alpha: 0.7)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ui.icon, color: ui.accent, size: 18 + 20 * scale),
                  Text(
                    ui.name(l).toUpperCase(),
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 10 + 18 * scale),
                  ),
                  Text(l.gamePlaceholderTitle, style: TextStyle(color: Colors.white70, fontSize: 8 + 12 * scale)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Felt of a game stage: rounded table edge with a padded rail, felt
/// gradient, one ring per seat spot in the game's accent.
class GameFeltPainter extends StagePainter {
  GameFeltPainter(super.stage, {required this.light, required this.dark, required this.accent});
  final Color light;
  final Color dark;
  final Color accent;

  @override
  void paintStage(Canvas canvas) {
    final g = stage.geometry;
    final r = g.felt;
    final shape = RRect.fromRectAndCorners(r, topLeft: const Radius.circular(60), topRight: const Radius.circular(60), bottomLeft: const Radius.circular(220), bottomRight: const Radius.circular(220));
    canvas.drawRRect(shape.inflate(22), Paint()..color = const Color(0xFF3A2115));
    canvas.drawRRect(shape.inflate(14), Paint()..color = const Color(0xFF6B3F22));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = RadialGradient(center: const Alignment(0, -0.35), radius: 1.0, colors: [light, dark]).createShader(r),
    );
    canvas.drawRRect(
      shape.deflate(26),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFE8C66A).withValues(alpha: 0.45),
    );
    for (var i = 0; i < g.seatCount; i++) {
      final c = g.seatSpot(i);
      canvas.drawCircle(c, 58, Paint()..color = Colors.black.withValues(alpha: 0.12));
      canvas.drawCircle(
        c,
        58,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = accent.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(covariant GameFeltPainter oldDelegate) =>
      oldDelegate.stage != stage || oldDelegate.light != light || oldDelegate.dark != dark || oldDelegate.accent != accent;
}

class _SeatPlate extends StatelessWidget {
  const _SeatPlate({super.key, required this.center, required this.scale, required this.label, required this.me});
  final Offset center;
  final double scale;
  final String? label;
  final bool me;

  @override
  Widget build(BuildContext context) {
    // Inside the seat ring (rings are close to each other on 7–8 seat tables).
    final w = 116 * scale + 8;
    final fs = 6 + 11 * scale;
    return Positioned(
      left: center.dx - w / 2,
      top: center.dy - fs * 0.9,
      width: w,
      child: label == null
          ? const SizedBox.shrink()
          : Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: me ? const Color(0xFF00A800) : Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fs),
                ),
              ),
            ),
    );
  }
}
