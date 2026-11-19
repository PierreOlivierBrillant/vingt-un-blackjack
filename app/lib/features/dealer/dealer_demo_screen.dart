import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/card_style.dart';
import '../table/table_sounds.dart';
import 'dealer_controller.dart';
import 'dealer_stage.dart';
import 'demo_round.dart';

/// Plays a scripted 5-seat round locally (no backend) so the dealer can be
/// seen and tested now.
class DealerDemoScreen extends ConsumerStatefulWidget {
  const DealerDemoScreen({super.key, this.autoStart = true});
  final bool autoStart;

  @override
  ConsumerState<DealerDemoScreen> createState() => _DealerDemoScreenState();
}

class _DealerDemoScreenState extends ConsumerState<DealerDemoScreen> {
  late final DealerController _c;
  late final TableSoundscape _sounds;
  bool _loop = true;
  bool _firstRound = true;
  int _rounds = 0;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    // Same sound design as a real table; the viewer is seat 2 in the script.
    _sounds = TableSoundscape(
      sound: ref.read(soundProvider),
      haptics: ref.read(hapticsProvider),
      mySeat: () => 2,
      minBetCents: () => 500,
      maxBetCents: () => 50000,
    );
    _c = DealerController(feedback: _sounds);
    if (widget.autoStart) _play();
  }

  @override
  void dispose() {
    _loop = false;
    _c.dispose();
    _sounds.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_c.isBusy) return;
    _c.speed = _speed;
    final done = enqueueDemoRound(_c, shuffleFirst: _firstRound);
    _firstRound = false;
    setState(() {});
    await done;
    if (!mounted) return;
    setState(() => _rounds++);
    if (_loop && mounted) {
      await _c.pause(const Duration(milliseconds: 900));
      if (mounted && _loop) await _play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final style = ref.watch(equippedStyleProvider).value ?? const CardStyle();
    return Scaffold(
      backgroundColor: const Color(0xFF0A1620),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1620),
        foregroundColor: Colors.white,
        // The casino room is always dark, whatever the app theme.
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
        title: Text(l.dealerDemoTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(child: DealerStage(controller: _c, style: style, seats: kDemoSeats)),
          ),
          Container(
            color: p.surface,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListenableBuilder(
                    listenable: _c,
                    builder: (context, _) => Row(
                      children: [
                        Icon(_c.isBusy ? Icons.play_circle : Icons.pause_circle, size: 18, color: _c.isBusy ? p.win : p.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _c.currentCommand?.toString() ?? l.dealerIdle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                        Text(
                          l.dealerQueue(_c.pendingCommands.length, (_c.remainingDuration.inMilliseconds / 1000).toStringAsFixed(1)),
                          style: TextStyle(color: p.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(l.dealerSpeed, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          min: 0.25,
                          max: 2,
                          divisions: 7,
                          label: '×$_speed',
                          onChanged: (v) => setState(() => _speed = v),
                        ),
                      ),
                      Text(l.dealerLoop),
                      Switch(value: _loop, onChanged: (v) => setState(() => _loop = v)),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('demo-play'),
                          onPressed: _play,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l.dealerPlayRound),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: const Key('demo-shuffle'),
                        onPressed: () {
                          _c.speed = _speed;
                          _c.shuffle();
                        },
                        child: Text(l.dealerShuffle),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        key: const Key('demo-reset'),
                        tooltip: l.dealerReset,
                        onPressed: () => setState(() {
                          _loop = false;
                          _c.reset();
                        }),
                        icon: const Icon(Icons.restart_alt),
                      ),
                    ],
                  ),
                  Text(l.dealerRounds(_rounds), style: TextStyle(color: p.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
