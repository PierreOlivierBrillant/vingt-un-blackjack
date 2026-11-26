/// State of the roulette stage that the painters read every frame ([RouletteScene]) and the
/// [StageCommand]s that animate it: the spin (wheel push + ball computed backwards,
/// `roulette_spin.dart`), the dolly placed by Camille, the rake taking the losing chips, the
/// payouts pushed to the winners, the reset of a new round. Everything is driven by the
/// deterministic [StageController] clock (tests advance it by hand).
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart' show Curves;

import '../../stage/stage_controller.dart';
import 'roulette_engine.dart';
import 'roulette_geometry.dart';
import 'roulette_sounds.dart';
import 'roulette_spin.dart';

/// Chip colour of each seat colour index (`RouletteSeat.color`).
const kRouletteChipColors = <Color>[
  Color(0xFF2E86DE), // blue
  Color(0xFFF5B041), // amber
  Color(0xFF8E44AD), // purple
  Color(0xFFE67E22), // orange
  Color(0xFFEC407A), // pink
  Color(0xFF26C6DA), // cyan
  Color(0xFFF2F2F2), // white
];

Color rouletteChipColor(int color) => kRouletteChipColors[color.abs() % kRouletteChipColors.length];

/// Cues of the roulette stage (sounds through [SoundStageFeedback]).
abstract final class RouletteCues {
  static const placeBets = StageCue('placeBets', sound: RouletteSfx.placeBets);
  static const noMoreBets = StageCue('noMoreBets', sound: RouletteSfx.noMoreBets);
  static const launch = StageCue('ballLaunch', sound: RouletteSfx.ballLaunch);
  static const tick = StageCue('ballTick', sound: RouletteSfx.ballTick, volume: 0.7);
  static const drop = StageCue('ballDrop', sound: RouletteSfx.ballDrop);
  static const dolly = StageCue('dolly', sound: RouletteSfx.dolly);
  static const rake = StageCue('rake', sound: RouletteSfx.rake);
  static const payout = StageCue('payout', sound: RouletteSfx.payout);
  static const straightWin = StageCue('straightWin', sound: RouletteSfx.straightWin);
  static const zero = StageCue('zero', sound: RouletteSfx.zero);
}

/// Data of a chip prop (kind 'chip').
class ChipProp {
  const ChipProp(this.color, this.cents);
  final int color;
  final int cents;
}

/// What the painters draw (mutated by the commands and by the screen).
class RouletteScene {
  RouletteScene(this.geometry);
  final RouletteGeometry geometry;

  /// Idle rotation of the wheel (rad/s).
  static const idleSpeed = 0.32;

  /// Rotation accumulated by the past spins, and the extra one of the running spin.
  double wheelOffset = 0;
  double spinExtra = 0;
  double wheelAngle(Duration clock) => idleSpeed * clock.inMicroseconds / 1e6 + wheelOffset + spinExtra;

  bool ballVisible = false;
  double ballRel = 0;
  double ballRadius = kBallTrackRadius;
  bool ballLanded = false;

  /// Number of the current round once drawn (null while betting).
  int? number;

  /// The ball has landed: winning cell highlighted, result badge.
  bool showResult = false;

  /// Static chips on the layout: seat → board (painted while [chipsOnLayout]).
  Map<int, Map<String, int>> boards = const {};

  /// Chip colour of each seat.
  Map<int, int> colors = const {};
  bool chipsOnLayout = true;

  /// Last numbers of the table (oldest first), for the score board.
  List<int> last = const [];

  /// The dolly sits on this number (null = at its resting place).
  int? dollyOn;

  /// Croupier speech bubble (text and clock time until which it shows).
  String? speech;
  Duration speechUntil = Duration.zero;

  /// The ball rolling (the screen starts / stops the loop).
  void Function(bool rolling)? onRolling;

  void say(StageController stage, String text, {Duration hold = const Duration(milliseconds: 1800)}) {
    speech = text;
    speechUntil = stage.clock + hold;
  }

  /// Position of [spot]'s chips for [color] (several players on one spot fan out a little).
  Offset chipPos(String spot, int color, {int players = 1}) {
    final c = geometry.layout.spotCenter(spot);
    if (players <= 1) return c;
    final a = color * 2 * math.pi / 7;
    return c + Offset(math.cos(a), math.sin(a)) * 9;
  }

  double get chipRadius => math.min(geometry.layout.colWidth, geometry.layout.rowHeight) * 0.3;
}

/// The ball is launched and the wheel pushed; the ball's path is computed backwards to land in
/// [spin.number] (see [RouletteSpin]). [fromMs] resumes a spin already running on the server.
class SpinCommand extends StageCommand {
  SpinCommand(this.scene, this.spin, {this.fromMs = 0, this.launchArm = true});
  final RouletteScene scene;
  final RouletteSpin spin;
  final double fromMs;
  final bool launchArm;
  StageArm? _arm;
  Offset _handFrom = Offset.zero;
  var _ticks = 0;
  var _rolling = false;

  @override
  Duration get duration => Duration(microseconds: (math.max(0.0, spin.spinMs - fromMs) * 1000).round());

  @override
  void begin(StageController stage) {
    scene.ballVisible = true;
    scene.ballLanded = false;
    scene.showResult = false;
    scene.number = spin.number;
    if (launchArm && fromMs < 300) {
      _arm = stage.armFor(scene.geometry.wheelCenter);
      _handFrom = _arm!.hand;
      stage.emit(RouletteCues.launch);
    }
    _ticks = spin.bounceTimes.where((t) => t < fromMs).length;
    _setRolling(fromMs < spin.landMs);
  }

  void _setRolling(bool v) {
    if (v == _rolling) return;
    _rolling = v;
    scene.onRolling?.call(v);
  }

  @override
  void step(StageController stage, double t) {
    final ms = fromMs + t * (spin.spinMs - fromMs);
    final f = spin.at(ms);
    scene.spinExtra = f.wheelExtra;
    scene.ballRel = f.ballRel;
    scene.ballRadius = f.ballRadius;
    final arm = _arm;
    if (arm != null) {
      // the hand flicks the ball along the rim, then goes back to rest
      if (ms < 260) {
        final rim = scene.geometry.wheelCenter + const Offset(150, -60);
        arm.hand = Offset.lerp(_handFrom, rim, Curves.easeOut.transform(ms / 260))!;
        arm.grip = 1;
      } else if (ms < 900) {
        final u = Curves.easeInOut.transform((ms - 260) / 640);
        arm.hand = Offset.lerp(scene.geometry.wheelCenter + const Offset(150, -60), arm.rest, u)!;
        arm.grip = 1 - u;
      }
    }
    final bounces = spin.bounceTimes;
    while (_ticks < bounces.length && ms >= bounces[_ticks]) {
      stage.emitOnce('tick$_ticks', RouletteCues.tick);
      _ticks++;
    }
    if (f.landed && !scene.ballLanded) {
      scene.ballLanded = true;
      scene.showResult = true;
      _setRolling(false);
      stage.emitOnce('drop', RouletteCues.drop);
    }
  }

  @override
  void finish(StageController stage) {
    scene.wheelOffset += scene.spinExtra;
    scene.spinExtra = 0;
    scene.ballRel = pocketAngle(spin.number);
    scene.ballRadius = kPocketRadius;
    scene.ballLanded = true;
    scene.showResult = true;
    _setRolling(false);
    final arm = _arm;
    if (arm != null) {
      arm.hand = arm.rest;
      arm.grip = 0;
    }
  }

  @override
  String get label => 'spin(${spin.number})';
}

/// Camille picks the dolly and puts it on the winning number.
List<StageCommand> placeDollyCommands(RouletteScene scene, int number) {
  final target = scene.geometry.layout.cellRect(number).center;
  return [
    ReachCommand(scene.geometry.dollyRest, duration: const Duration(milliseconds: 300), grip: 1),
    CallbackCommand((s) => s.prop('dolly')?.pos = s.armFor(scene.geometry.dollyRest).hand, name: 'pickDolly'),
    ParallelCommand([
      ReachCommand(Offset(target.dx, math.min(target.dy, 560)), duration: const Duration(milliseconds: 420), grip: 1),
      MovePropCommand('dolly', to: target, duration: const Duration(milliseconds: 520), arc: 40),
    ]),
    CueCommand(RouletteCues.dolly),
    CallbackCommand((_) => scene.dollyOn = number, name: 'dollyOn'),
    RestArmsCommand(),
  ];
}

/// The rake sweeps the losing chips ([losing]: seat → spots) to the bank.
List<StageCommand> rakeCommands(RouletteScene scene, Map<int, List<String>> losing) {
  final ids = <String>[];
  return [
    CallbackCommand((s) {
      final keep = <int, Map<String, int>>{};
      for (final e in scene.boards.entries) {
        final lost = losing[e.key] ?? const [];
        final players = scene.boards.length;
        for (final spot in e.value.keys) {
          if (!lost.contains(spot)) continue;
          final id = 'lost:${e.key}:$spot';
          ids.add(id);
          final color = scene.colors[e.key] ?? e.key;
          s.addProp(StageProp(id: id, kind: 'chip', pos: scene.chipPos(spot, color, players: players), z: 2, data: ChipProp(color, e.value[spot]!)));
        }
        keep[e.key] = {for (final x in e.value.entries) if (!lost.contains(x.key)) x.key: x.value};
      }
      scene.boards = keep;
    }, name: 'collectLosers'),
    if (losing.values.any((l) => l.isNotEmpty)) ...[
      CallbackCommand((s) => s.addProp(StageProp(id: 'rake', kind: 'rake', pos: scene.geometry.layout.rect.center, z: 5)), name: 'rakeOut'),
      ReachCommand(const Offset(500, 560), duration: const Duration(milliseconds: 260), grip: 1, hold: true),
      CueCommand(RouletteCues.rake),
      TweenCommand(
        const Duration(milliseconds: 760),
        name: 'rake',
        curve: Curves.easeInOutCubic,
        onBegin: (s) {
          for (final id in ids) {
            final p = s.prop(id);
            if (p != null) p.data = (p.data! as ChipProp, p.pos);
          }
        },
        onStep: (s, u) {
          final bank = scene.geometry.bank;
          final rake = s.prop('rake');
          if (rake != null) rake.pos = Offset.lerp(scene.geometry.layout.rect.center + const Offset(0, 120), bank, u)!;
          for (final id in ids) {
            final p = s.prop(id);
            if (p == null || p.data is! (ChipProp, Offset)) continue;
            final (_, from) = p.data! as (ChipProp, Offset);
            p.pos = Offset.lerp(from, bank, u)!;
            p.opacity = u < 0.8 ? 1 : (1 - (u - 0.8) / 0.2);
          }
        },
        onFinish: (s) {
          for (final id in ids) {
            s.removeProp(id);
          }
          s.removeProp('rake');
        },
      ),
      RestArmsCommand(),
    ],
  ];
}

/// Pays the winners: payout chips leave the bank, join the winning stakes, everything goes back
/// to the player's place. [returns]: seat → total returned (winning stakes included).
List<StageCommand> payoutCommands(RouletteScene scene, Map<int, int> returns) {
  final winners = {for (final e in returns.entries) if (e.value > 0) e.key: e.value};
  if (winners.isEmpty) return [CallbackCommand((_) => scene.chipsOnLayout = false, name: 'noWinner')];
  final ids = <String>[];
  return [
    CallbackCommand((s) {
      for (final e in winners.entries) {
        final color = scene.colors[e.key] ?? e.key;
        final board = scene.boards[e.key] ?? const {};
        final staked = boardTotal(board);
        final won = math.max(0, e.value - staked);
        final spot = board.isEmpty ? null : board.keys.first;
        final target = spot == null ? scene.geometry.layout.rect.center : scene.chipPos(spot, color) + const Offset(16, -10);
        if (won > 0) {
          final id = 'pay:${e.key}';
          ids.add(id);
          s.addProp(StageProp(id: id, kind: 'chip', pos: scene.geometry.bank, z: 3, data: (ChipProp(color, won), target)));
        }
      }
    }, name: 'payoutOut'),
    CueCommand(RouletteCues.payout),
    TweenCommand(
      const Duration(milliseconds: 520),
      name: 'payoutPush',
      onStep: (s, u) {
        for (final id in ids) {
          final p = s.prop(id);
          if (p == null || p.data is! (ChipProp, Offset)) continue;
          final (_, to) = p.data! as (ChipProp, Offset);
          p.pos = Offset.lerp(scene.geometry.bank, to, u)!;
          p.lift = 20 * math.sin(math.pi * u);
        }
      },
    ),
    PauseCommand(const Duration(milliseconds: 350)),
    // stakes + winnings slide to the player
    CallbackCommand((s) {
      for (final e in winners.entries) {
        final color = scene.colors[e.key] ?? e.key;
        final board = scene.boards[e.key] ?? const {};
        for (final spot in board.keys) {
          final id = 'win:${e.key}:$spot';
          ids.add(id);
          s.addProp(StageProp(id: id, kind: 'chip', pos: scene.chipPos(spot, color, players: scene.boards.length), z: 3, data: ChipProp(color, board[spot]!)));
        }
        for (final id in ids.where((i) => i.startsWith('pay:${e.key}'))) {
          final p = s.prop(id);
          if (p != null && p.data is (ChipProp, Offset)) p.data = (p.data! as (ChipProp, Offset)).$1;
        }
      }
      scene.chipsOnLayout = false;
      for (final id in ids) {
        final p = s.prop(id);
        if (p != null) p.data = (p.data! as ChipProp, p.pos, _seatOf(id));
      }
    }, name: 'toPlayers'),
    TweenCommand(
      const Duration(milliseconds: 600),
      name: 'toPlayers',
      curve: Curves.easeInCubic,
      onStep: (s, u) {
        for (final id in ids) {
          final p = s.prop(id);
          if (p == null || p.data is! (ChipProp, Offset, int)) continue;
          final (_, from, seat) = p.data! as (ChipProp, Offset, int);
          p.pos = Offset.lerp(from, scene.geometry.seatPocket(seat.clamp(0, 6)), u)!;
          p.opacity = 1 - u * 0.7;
        }
      },
      onFinish: (s) {
        for (final id in ids) {
          s.removeProp(id);
        }
      },
    ),
  ];
}

int _seatOf(String propId) => int.tryParse(propId.split(':')[1]) ?? 0;

/// A new round opens: the dolly goes back, the ball is taken out, the layout is cleared.
List<StageCommand> newRoundCommands(RouletteScene scene, {String? say}) => [
      CallbackCommand((s) {
        scene.ballVisible = false;
        scene.ballLanded = false;
        scene.showResult = false;
        scene.number = null;
        scene.chipsOnLayout = true;
        scene.boards = const {};
        scene.dollyOn = null;
        if (say != null) scene.say(s, say);
      }, name: 'newRound'),
      MovePropCommand('dolly', to: scene.geometry.dollyRest, duration: const Duration(milliseconds: 380), arc: 30),
      CueCommand(RouletteCues.placeBets),
    ];

/// Number of the spot a chip sits on (helper for the losing / winning split).
Map<int, List<String>> losingSpots(Map<int, Map<String, int>> boards, Map<int, List<String>> wins) => {
      for (final e in boards.entries) e.key: [for (final spot in e.value.keys) if (!(wins[e.key] ?? const []).contains(spot)) spot],
    };
