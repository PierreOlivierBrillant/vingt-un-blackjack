/// Painters of the roulette: the wheel (cached pocket ring + turret, rotating with
/// [RouletteScene.wheelAngle]) and its ball, the betting layout with every player's chips in
/// their colour (shared by the stage and the tactile panel), the racetrack, and the animated
/// props (chips, dolly, rake).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart' show kAppFont;
import '../../cards/chips.dart';
import '../../stage/stage_controller.dart';
import '../../stage/stage_view.dart';
import 'roulette_engine.dart';
import 'roulette_geometry.dart';
import 'roulette_scene.dart';
import 'roulette_spin.dart';

const kRouletteRed = Color(0xFFC8102E);
const kRouletteBlack = Color(0xFF15171C);
const kRouletteGreen = Color(0xFF0B7A3E);
const _gold = Color(0xFFE8C66A);

Color rouletteNumberColor(int n) => switch (rouletteColorOf(n)) {
      RouletteColor.red => kRouletteRed,
      RouletteColor.black => kRouletteBlack,
      RouletteColor.green => kRouletteGreen,
    };

/// Compact chip label ("5", "25", "1K", "2.5K").
String chipLabel(int cents) {
  final d = cents ~/ 100;
  if (d < 1000) return '$d';
  final k = d / 1000;
  return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
}

void paintPlayerChip(Canvas canvas, Offset c, double r, int color, int cents, {double opacity = 1}) {
  final base = rouletteChipColor(color);
  final stripe = color == 6 ? const Color(0xFF1475E1) : Colors.white;
  final d = ChipDenomination(cents, base.withValues(alpha: opacity), stripe.withValues(alpha: opacity), chipLabel(cents));
  paintChip(canvas, c, r, d);
}

TextPainter _text(String s, double size, Color color, {FontWeight weight = FontWeight.w800, double spacing = 0}) => TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: kAppFont, color: color, fontSize: size, fontWeight: weight, height: 1, letterSpacing: spacing)),
      textDirection: TextDirection.ltr,
    )..layout();

void _centerText(Canvas canvas, String s, Offset c, double size, Color color, {double rotation = 0, FontWeight weight = FontWeight.w800}) {
  final tp = _text(s, size, color, weight: weight);
  canvas.save();
  canvas.translate(c.dx, c.dy);
  if (rotation != 0) canvas.rotate(rotation);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

// ------------------------------------------------------------------- wheel --

/// The rotating part of the wheel (pockets + numbers + turret), drawn once per radius.
final _wheelCache = <double, ui.Picture>{};

ui.Picture _wheelPicture(double r) => _wheelCache.putIfAbsent(r, () {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final ring = r * 0.74, inner = r * 0.5;
      // pockets
      for (var i = 0; i < 37; i++) {
        final n = kWheelOrder[i];
        final a0 = -math.pi / 2 + (i - 0.5) * kPocketStep;
        final path = Path()
          ..arcTo(Rect.fromCircle(center: Offset.zero, radius: ring), a0, kPocketStep, true)
          ..arcTo(Rect.fromCircle(center: Offset.zero, radius: inner), a0 + kPocketStep, -kPocketStep, false)
          ..close();
        c.drawPath(path, Paint()..color = rouletteNumberColor(n));
        // number, read from outside
        final a = i * kPocketStep;
        final p = Offset(math.sin(a), -math.cos(a)) * (ring - r * 0.07);
        _centerText(c, '$n', p, r * 0.075, Colors.white, rotation: a);
        // fret
        final fa = a0;
        c.drawLine(Offset(math.cos(fa), math.sin(fa)) * inner, Offset(math.cos(fa), math.sin(fa)) * ring,
            Paint()..color = _gold.withValues(alpha: 0.85)..strokeWidth = r * 0.008);
      }
      c.drawCircle(Offset.zero, ring, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.012..color = _gold);
      // pocket bottom ring (where the ball rests) — slightly darker band
      c.drawCircle(Offset.zero, r * 0.62, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.012..color = Colors.black.withValues(alpha: 0.25));
      c.drawCircle(Offset.zero, inner, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.014..color = _gold);
      // cone and turret
      c.drawCircle(
        Offset.zero,
        inner,
        Paint()..shader = const RadialGradient(colors: [Color(0xFFB07A44), Color(0xFF5A3418)]).createShader(Rect.fromCircle(center: Offset.zero, radius: inner)),
      );
      for (var k = 0; k < 8; k++) {
        final a = k * math.pi / 4;
        c.drawLine(Offset.zero, Offset(math.cos(a), math.sin(a)) * inner * 0.92, Paint()..color = const Color(0xFF3A2010).withValues(alpha: 0.35)..strokeWidth = r * 0.01);
      }
      final arm = Paint()..color = _gold..strokeWidth = r * 0.045..strokeCap = StrokeCap.round;
      for (var k = 0; k < 4; k++) {
        final a = k * math.pi / 2;
        final tip = Offset(math.cos(a), math.sin(a)) * inner * 0.62;
        c.drawLine(Offset.zero, tip, arm);
        c.drawCircle(tip, r * 0.04, Paint()..color = const Color(0xFFF6E3A1));
      }
      c.drawCircle(Offset.zero, r * 0.08, Paint()..color = const Color(0xFFF6E3A1));
      c.drawCircle(Offset.zero, r * 0.05, Paint()..color = _gold);
      return rec.endRecording();
    });

/// Paints the wheel and the ball at [center] with radius [r].
void paintWheel(Canvas canvas, Offset center, double r, RouletteScene scene, Duration clock) {
  // bowl: wood + ball track
  canvas.drawCircle(center + Offset(0, r * 0.06), r * 1.04, Paint()..color = Colors.black.withValues(alpha: 0.35));
  canvas.drawCircle(center, r, Paint()..shader = const RadialGradient(colors: [Color(0xFF7A4A26), Color(0xFF3B200E)], stops: [0.75, 1]).createShader(Rect.fromCircle(center: center, radius: r)));
  canvas.drawCircle(center, r * 0.95, Paint()..color = const Color(0xFFD7B98A));
  canvas.drawCircle(center, r * 0.95, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.02..color = const Color(0xFF8A5A30));
  canvas.drawCircle(center, r * 0.78, Paint()..color = const Color(0xFFB8935F));
  // deflectors on the track
  for (var k = 0; k < 8; k++) {
    final a = k * math.pi / 4 + math.pi / 8;
    final p = center + Offset(math.sin(a), -math.cos(a)) * r * 0.8;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(a);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: r * 0.05, height: r * 0.025), Radius.circular(r * 0.01)), Paint()..color = _gold);
    canvas.restore();
  }
  final angle = scene.wheelAngle(clock);
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(angle);
  canvas.drawPicture(_wheelPicture(r));
  // winning pocket glow
  if (scene.showResult && scene.number != null) {
    final i = kWheelOrder.indexOf(scene.number!);
    final a0 = -math.pi / 2 + (i - 0.5) * kPocketStep;
    canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: r * 0.62), a0, kPocketStep, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.24..color = Colors.white.withValues(alpha: 0.28));
  }
  canvas.restore();
  // ball (wheel frame angle → absolute)
  if (scene.ballVisible) {
    final a = angle + scene.ballRel;
    final p = center + Offset(math.sin(a), -math.cos(a)) * r * scene.ballRadius;
    final br = r * 0.042;
    canvas.drawCircle(p + Offset(br * 0.35, br * 0.45), br, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(p, br, Paint()..shader = RadialGradient(center: const Alignment(-0.4, -0.4), colors: const [Colors.white, Color(0xFFC9CED6)]).createShader(Rect.fromCircle(center: p, radius: br)));
  }
}

class RouletteWheelPainter extends StagePainter {
  RouletteWheelPainter(super.stage, this.scene);
  final RouletteScene scene;

  @override
  void paintStage(Canvas canvas) => paintWheel(canvas, scene.geometry.wheelCenter, scene.geometry.wheelRadius, scene, stage.clock);

  @override
  bool shouldRepaint(covariant RouletteWheelPainter oldDelegate) => oldDelegate.stage != stage || oldDelegate.scene != scene;
}

// ------------------------------------------------------------------- layout --

/// Texts painted on the layout (localized by the caller).
@immutable
class LayoutLabels {
  const LayoutLabels({
    this.low = '1-18',
    this.high = '19-36',
    this.even = 'EVEN',
    this.odd = 'ODD',
    this.dozens = const ['1st 12', '2nd 12', '3rd 12'],
    this.column = '2:1',
  });
  final String low, high, even, odd, column;
  final List<String> dozens;

  @override
  bool operator ==(Object other) => other is LayoutLabels && other.low == low && other.high == high && other.even == even && other.odd == odd && listEquals(other.dozens, dozens);
  @override
  int get hashCode => Object.hash(low, high, even, odd, Object.hashAll(dozens));
}

/// Paints the betting layout in [l] (felt lines, numbers, zero, outside bets).
void paintLayout(Canvas canvas, RouletteLayout l, LayoutLabels labels, {int? highlight, Color felt = const Color(0xFF0E5A36), double lineWidth = 2}) {
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = lineWidth
    ..color = const Color(0xFFF2EBD9).withValues(alpha: 0.85);
  final fs = math.min(l.colWidth, l.rowHeight) * 0.42;
  canvas.drawRect(l.rect, Paint()..color = felt);
  // zero
  final z = l.zeroRect;
  final zp = Path()
    ..moveTo(z.right, z.top)
    ..lineTo(z.left + z.width * 0.35, z.top)
    ..lineTo(z.left, z.center.dy)
    ..lineTo(z.left + z.width * 0.35, z.bottom)
    ..lineTo(z.right, z.bottom)
    ..close();
  canvas.drawPath(zp, Paint()..color = kRouletteGreen);
  canvas.drawPath(zp, line);
  _centerText(canvas, '0', z.center, fs * 1.1, Colors.white, rotation: -math.pi / 2);
  for (var n = 1; n <= 36; n++) {
    final r = l.cellRect(n);
    canvas.drawRect(r, line);
    canvas.drawCircle(r.center, math.min(r.width, r.height) * 0.33, Paint()..color = rouletteNumberColor(n));
    _centerText(canvas, '$n', r.center, fs, Colors.white, rotation: -math.pi / 2);
  }
  for (var c = 1; c <= 3; c++) {
    final r = l.columnRect(c);
    canvas.drawRect(r, line);
    _centerText(canvas, labels.column, r.center, fs * 0.8, Colors.white, rotation: -math.pi / 2);
  }
  for (var d = 1; d <= 3; d++) {
    final r = l.dozenRect(d);
    canvas.drawRect(r, line);
    _centerText(canvas, labels.dozens[d - 1], r.center, fs * 0.8, Colors.white);
  }
  for (final id in RouletteLayout.evenOrder) {
    final r = l.evenRect(id);
    canvas.drawRect(r, line);
    switch (id) {
      case 'red' || 'black':
        final d = Path()
          ..moveTo(r.center.dx - r.width * 0.22, r.center.dy)
          ..lineTo(r.center.dx, r.top + r.height * 0.18)
          ..lineTo(r.center.dx + r.width * 0.22, r.center.dy)
          ..lineTo(r.center.dx, r.bottom - r.height * 0.18)
          ..close();
        canvas.drawPath(d, Paint()..color = id == 'red' ? kRouletteRed : kRouletteBlack);
        canvas.drawPath(d, Paint()..style = PaintingStyle.stroke..strokeWidth = lineWidth * 0.7..color = Colors.white70);
      default:
        final text = switch (id) { 'low' => labels.low, 'high' => labels.high, 'even' => labels.even, _ => labels.odd };
        _centerText(canvas, text, r.center, fs * 0.8, Colors.white);
    }
  }
  canvas.drawRect(l.rect, line..strokeWidth = lineWidth * 1.5);
  if (highlight != null) {
    final r = l.cellRect(highlight);
    canvas.drawRect(r.deflate(lineWidth), Paint()..style = PaintingStyle.stroke..strokeWidth = lineWidth * 2.5..color = const Color(0xFFFFE28A));
  }
}

/// Every board's chips on [l] ([boards]: seat → board, [colors]: seat → chip colour).
void paintBoards(Canvas canvas, RouletteLayout l, Map<int, Map<String, int>> boards, Map<int, int> colors, {double? radius, double opacity = 1}) {
  final r = radius ?? math.min(l.colWidth, l.rowHeight) * 0.3;
  final players = boards.values.where((b) => b.isNotEmpty).length;
  for (final e in boards.entries) {
    final color = colors[e.key] ?? e.key;
    for (final s in e.value.entries) {
      if (s.value <= 0 || rouletteSpot(s.key) == null) continue;
      var c = l.spotCenter(s.key);
      if (players > 1) {
        final a = color * 2 * math.pi / 7;
        c += Offset(math.cos(a), math.sin(a)) * r * 0.45;
      }
      paintPlayerChip(canvas, c, r, color, s.value, opacity: opacity);
    }
  }
}

class RouletteLayoutPainter extends StagePainter {
  RouletteLayoutPainter(super.stage, this.scene, {required this.labels, required this.boards, required this.colors});
  final RouletteScene scene;
  final LayoutLabels labels;
  final Map<int, Map<String, int>> boards;
  final Map<int, int> colors;

  @override
  void paintStage(Canvas canvas) {
    final l = scene.geometry.layout;
    paintLayout(canvas, l, labels, highlight: scene.showResult ? scene.number : null, lineWidth: 2.2);
    if (scene.chipsOnLayout) paintBoards(canvas, l, scene.boards.isEmpty ? boards : scene.boards, colors, radius: scene.chipRadius);
  }

  @override
  bool shouldRepaint(covariant RouletteLayoutPainter old) =>
      old.stage != stage || old.scene != scene || old.labels != labels || !mapEquals(old.colors, colors) || !_boardsEqual(old.boards, boards);
}

bool _boardsEqual(Map<int, Map<String, int>> a, Map<int, Map<String, int>> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!mapEquals(e.value, b[e.key])) return false;
  }
  return true;
}

/// The croupier's table furniture: the wooden rail, the felt, the bank of house chips.
class RouletteFeltPainter extends StagePainter {
  RouletteFeltPainter(super.stage, {required this.light, required this.dark, required this.accent});
  final Color light, dark, accent;

  @override
  void paintStage(Canvas canvas) {
    final g = stage.geometry as RouletteGeometry;
    final r = g.felt;
    final shape = RRect.fromRectAndCorners(r, topLeft: const Radius.circular(60), topRight: const Radius.circular(60), bottomLeft: const Radius.circular(160), bottomRight: const Radius.circular(160));
    canvas.drawRRect(shape.inflate(22), Paint()..color = const Color(0xFF3A2115));
    canvas.drawRRect(shape.inflate(14), Paint()..color = const Color(0xFF6B3F22));
    canvas.drawRRect(shape, Paint()..shader = RadialGradient(center: const Alignment(0, -0.35), radius: 1.0, colors: [light, dark]).createShader(r));
    canvas.drawRRect(shape.deflate(18), Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = _gold.withValues(alpha: 0.4));
    // house chips (the croupier's float)
    final bank = g.bank;
    for (var k = 0; k < 5; k++) {
      final cents = const [10000, 2500, 500, 100, 50000][k];
      paintChipStack(canvas, bank + Offset(-80.0 + k * 40, 30), 17, cents * (3 + k % 3));
    }
  }

  @override
  bool shouldRepaint(covariant RouletteFeltPainter old) => old.stage != stage || old.light != light || old.dark != dark || old.accent != accent;
}

ChipProp? chipOf(Object? data) => switch (data) {
      final ChipProp c => c,
      (final ChipProp c, _) => c,
      (final ChipProp c, _, _) => c,
      _ => null,
    };

/// Animated props: chips (raked, paid), the dolly, the rake (a stick from the croupier's hand).
class RoulettePropsPainter extends StagePainter {
  RoulettePropsPainter(super.stage, this.scene);
  final RouletteScene scene;

  @override
  void paintStage(Canvas canvas) {
    for (final p in stage.props) {
      switch (p.kind) {
        case 'chip':
          final c = chipOf(p.data);
          if (c == null) continue;
          if (p.lift > 0) canvas.drawCircle(p.pos + Offset(0, p.lift * 0.6), scene.chipRadius, Paint()..color = Colors.black.withValues(alpha: 0.2));
          paintPlayerChip(canvas, p.pos - Offset(0, p.lift), scene.chipRadius, c.color, c.cents, opacity: p.opacity.clamp(0.0, 1.0));
        case 'dolly':
          final c = p.pos - Offset(0, p.lift);
          canvas.drawCircle(c + const Offset(3, 6), 15, Paint()..color = Colors.black.withValues(alpha: 0.3));
          canvas.drawCircle(c, 15, Paint()..color = Colors.white.withValues(alpha: 0.75));
          canvas.drawCircle(c, 15, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFFB8D8F0));
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c - const Offset(0, 12), width: 10, height: 22), const Radius.circular(4)), Paint()..color = const Color(0xFFDDEEFF));
      }
    }
  }

  @override
  bool shouldRepaint(covariant RoulettePropsPainter old) => old.stage != stage || old.scene != scene;
}

/// The rake, held by the hand nearest to its head (painted above the arms).
class RouletteRakePainter extends StagePainter {
  RouletteRakePainter(super.stage);

  @override
  void paintStage(Canvas canvas) {
    final rake = stage.prop('rake');
    if (rake == null) return;
    final hand = stage.armFor(rake.pos).hand;
    canvas.drawLine(hand, rake.pos, Paint()..color = const Color(0xFF5A3A1E)..strokeWidth = 8..strokeCap = StrokeCap.round);
    final dir = rake.pos - hand;
    final u = dir.distance == 0 ? const Offset(0, 1) : dir / dir.distance;
    final n = Offset(-u.dy, u.dx);
    canvas.drawLine(rake.pos - n * 46, rake.pos + n * 46, Paint()..color = const Color(0xFF3B2412)..strokeWidth = 12..strokeCap = StrokeCap.round);
  }
}

// ------------------------------------------------------------------- racetrack --

void paintRacetrack(Canvas canvas, RouletteRacetrack t, Map<RouletteAnnounce, String> sectorLabels, {Set<int> highlight = const {}}) {
  final outer = RRect.fromRectAndRadius(t.rect, Radius.circular(t.rect.height / 2));
  canvas.drawRRect(outer, Paint()..color = const Color(0xFF0E5A36));
  canvas.drawRRect(outer, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.white70);
  canvas.drawRRect(t.inner, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.white70);
  final cell = t.cellSize;
  for (final n in kWheelOrder) {
    final c = t.numberCenter(n);
    final r = math.min(cell, t.band) * 0.46;
    canvas.drawCircle(c, r, Paint()..color = rouletteNumberColor(n));
    if (highlight.contains(n)) canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFFFFE28A));
    _centerText(canvas, '$n', c, r * 0.95, Colors.white);
  }
  for (final a in RouletteRacetrack.sectors) {
    final r = t.sectorRect(a);
    if (a != RouletteRacetrack.sectors.first) canvas.drawLine(r.topLeft, r.bottomLeft, Paint()..strokeWidth = 1..color = Colors.white38);
    _centerText(canvas, sectorLabels[a] ?? a.name, r.center, math.min(r.height * 0.28, r.width * 0.16), Colors.white);
  }
}

/// Helper: paints [paint] in a box of [size] (for widgets outside the stage).
class FnPainter extends CustomPainter {
  FnPainter(this.fn, {this.key0});
  final void Function(Canvas canvas, Size size) fn;
  final Object? key0;
  @override
  void paint(Canvas canvas, Size size) => fn(canvas, size);
  @override
  bool shouldRepaint(FnPainter old) => old.key0 != key0;
}

/// A little wheel for the history line / tests (no animation).
void paintMiniWheel(Canvas canvas, Size size, StageController stage, RouletteScene scene) =>
    paintWheel(canvas, size.center(Offset.zero), size.shortestSide / 2, scene, stage.clock);
