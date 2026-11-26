import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import 'table_sounds.dart';

/// Visual counterpart of the win fanfares: confetti for a good win, a gold
/// flash + coin rain + banner for the big ones. Purely decorative (ignores
/// pointers), driven by [TableSoundscape.celebrations].
class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({super.key, required this.celebrations});
  final ValueListenable<Celebration?> celebrations;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Celebration? _current;
  List<_Particle> _particles = const [];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
    widget.celebrations.addListener(_onCelebration);
  }

  @override
  void didUpdateWidget(CelebrationOverlay old) {
    super.didUpdateWidget(old);
    if (old.celebrations != widget.celebrations) {
      old.celebrations.removeListener(_onCelebration);
      widget.celebrations.addListener(_onCelebration);
    }
  }

  void _onCelebration() {
    final c = widget.celebrations.value;
    if (c == null || !mounted) return;
    final r = math.Random(c.serial);
    final coins = c.big;
    final n = coins ? 70 : 46;
    setState(() {
      _current = c;
      _particles = [
        for (var i = 0; i < n; i++)
          _Particle(
            x: r.nextDouble(),
            delay: r.nextDouble() * 0.35,
            speed: 0.55 + r.nextDouble() * 0.6,
            spin: (r.nextDouble() - 0.5) * 14,
            size: coins ? 10 + r.nextDouble() * 9 : 5 + r.nextDouble() * 5,
            sway: r.nextDouble() * math.pi * 2,
            color: coins ? null : _confetti[r.nextInt(_confetti.length)],
          ),
      ];
    });
    _c.forward(from: 0);
  }

  static const _confetti = [Color(0xFFFFC83D), Color(0xFF2FD17C), Color(0xFF3D8BFF), Color(0xFFFF5A7A), Color(0xFFB47CFF)];

  @override
  void dispose() {
    widget.celebrations.removeListener(_onCelebration);
    _c.dispose();
    super.dispose();
  }

  String _banner(BuildContext context, Celebration c) {
    final l = context.l10n;
    final label = c.label;
    if (label != null) return label;
    return switch (c.kind) {
      CelebrationKind.blackjack => l.badgeBlackjack,
      CelebrationKind.bigWin || CelebrationKind.jackpot => l.celebrationBigWin,
      CelebrationKind.streak => l.celebrationStreak(c.streak ?? 0),
      CelebrationKind.dealerBust => l.celebrationDealerBust,
      CelebrationKind.win => l.celebrationWin,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = _current;
    if (c == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          if (t == 0 || t == 1) return const SizedBox.shrink();
          final flash = c.big ? (1 - (t / 0.12)).clamp(0.0, 1.0) * 0.55 : 0.0;
          final pop = Curves.elasticOut.transform((t / 0.35).clamp(0.0, 1.0));
          final fade = 1 - ((t - 0.8) / 0.2).clamp(0.0, 1.0);
          return Stack(
            key: const Key('celebration'),
            children: [
              if (flash > 0) Positioned.fill(child: ColoredBox(color: const Color(0xFFFFE9A8).withValues(alpha: flash))),
              Positioned.fill(child: CustomPaint(painter: _ParticlePainter(_particles, t))),
              Center(
                child: Opacity(
                  opacity: fade,
                  child: Transform.scale(
                    scale: 0.3 + 0.7 * pop,
                    child: Text(
                      _banner(context, c),
                      key: const Key('celebration-banner'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: c.big ? 40 : 30,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        color: c.big ? const Color(0xFFFFD54A) : Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 12, offset: Offset(0, 3)),
                          Shadow(color: Color(0xAAFF9900), blurRadius: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.x,
    required this.delay,
    required this.speed,
    required this.spin,
    required this.size,
    required this.sway,
    this.color,
  });
  final double x;
  final double delay;
  final double speed;
  final double spin;
  final double size;
  final double sway;

  /// null = gold coin.
  final Color? color;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.particles, this.t);
  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final u = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (u <= 0) continue;
      final y = -30 + u * p.speed * (size.height + 80) * 1.3;
      if (y > size.height + 30) continue;
      final x = p.x * size.width + math.sin(p.sway + u * 7) * 18;
      final a = p.spin * u;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(a);
      if (p.color == null) {
        // Coin seen at an angle: squash horizontally with the spin.
        final squash = 0.25 + 0.75 * math.cos(a * 1.7).abs();
        canvas.scale(squash, 1);
        final r = p.size / 2;
        canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0xFFB8860B));
        canvas.drawCircle(Offset.zero, r * 0.82, Paint()..color = const Color(0xFFFFC83D));
        canvas.drawCircle(Offset(-r * 0.25, -r * 0.3), r * 0.28, Paint()..color = const Color(0xCCFFF6C8));
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), Paint()..color = p.color!);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t || old.particles != particles;
}
