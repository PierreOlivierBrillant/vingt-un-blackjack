/// Generic, deterministic animation queue of the Sprint 2 game stages,
/// alongside the blackjack `DealerController` (which does not move).
///
/// HOW A GAME USES IT (`lib/features/games/<jeu>/`):
///  * subclass [StageCommand] for each animation (spin the wheel, pitch a
///    card, roll the dice…): `begin` captures the start state, `step(t)` sets
///    the state at raw progress `t ∈ (0, 1]` (apply your own easing),
///    `finish` settles the end state. A command may keep scratch fields: a
///    NEW instance is enqueued each time;
///  * enqueue with [StageController.enqueue] (returns a Future completed when
///    the command has fully played); commands run strictly FIFO;
///  * time ONLY moves through [StageController.advance] — driven by
///    [StageDriver] in the app, called by hand in tests — so playback is
///    fully deterministic (golden frames, unit tests);
///  * rebuilding a scene from a snapshot: enqueue the commands then
///    [StageController.fastForward] (cues muted);
///  * shared state lives on the controller: [StageProp]s (positioned objects:
///    chips, cards, ball, dice…), the croupier's two IK arms ([StageArm],
///    `solveTwoBone`), [StageActor]s (expression, head, speech, plus
///    deterministic blink/breath) and a turn timer with tick / warning cues;
///  * sounds / haptics go through [StageCue]s sent to a [StageFeedback]
///    (see [SoundStageFeedback]); [StageController.emitOnce] fires a cue once
///    per command run, [StageController.ahead] anticipates a sample's attack.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/audio/sfx.dart';
import '../../core/audio/sound_providers.dart' show Haptic, Haptics;
import '../../core/audio/sound_service.dart';
import '../../core/characters/character_spec.dart';
import '../dealer/ik.dart';
import 'stage_geometry.dart';

// ----------------------------------------------------------------- cues --

/// A point of the timeline where something should be heard or felt.
@immutable
class StageCue {
  const StageCue(this.name, {this.sound, this.volume = 1, this.haptic, this.seat, this.data});

  /// Stable name (tests, logs): 'ballDrop', 'timerTick'…
  final String name;
  final SoundCue? sound;
  final double volume;
  final Haptic? haptic;
  final int? seat;
  final Object? data;

  static const timerTick = StageCue('timerTick', sound: Sfx.timerTick);
  static const timerWarning = StageCue('timerWarning', sound: Sfx.timerUrgent, haptic: Haptic.light);

  StageCue withSeat(int? seat) => StageCue(name, sound: sound, volume: volume, haptic: haptic, seat: seat, data: data);

  @override
  String toString() => 'cue($name${seat == null ? '' : ' seat$seat'})';
}

abstract interface class StageFeedback {
  void cue(StageCue cue);
}

class SilentStageFeedback implements StageFeedback {
  const SilentStageFeedback();
  @override
  void cue(StageCue cue) {}
}

/// Records every cue (tests).
class RecordingStageFeedback implements StageFeedback {
  final cues = <StageCue>[];
  List<String> get names => [for (final c in cues) c.name];
  @override
  void cue(StageCue cue) => cues.add(cue);
}

/// Plays the cue's sound (through the governor) and haptic.
class SoundStageFeedback implements StageFeedback {
  SoundStageFeedback(this.sound, {this.haptics});
  final SoundService sound;
  final Haptics? haptics;
  @override
  void cue(StageCue cue) {
    final s = cue.sound;
    if (s != null && !s.loop) sound.play(s, volume: cue.volume);
    final h = cue.haptic;
    if (h != null) haptics?.call(h);
  }
}

// --------------------------------------------------------------- objects --

/// A positioned object of the scene (chip stack, card, ball, die, puck…),
/// in [StageGeometry] units. [kind] and [data] are free for the game.
class StageProp {
  StageProp({
    required this.id,
    required this.kind,
    this.pos = Offset.zero,
    this.rotation = 0,
    this.scale = 1,
    this.opacity = 1,
    this.lift = 0,
    this.z = 0,
    this.data,
  });
  final String id;
  final String kind;
  Offset pos;
  double rotation;
  double scale;
  double opacity;

  /// Height above the felt (drop shadow offset, arcs).
  double lift;

  /// Paint order (low first).
  int z;
  Object? data;

  @override
  String toString() => 'prop($id/$kind @ ${pos.dx.toStringAsFixed(0)},${pos.dy.toStringAsFixed(0)})';
}

/// One arm of the croupier (two-bone IK from the shoulder).
class StageArm {
  StageArm({required this.shoulder, required this.upper, required this.fore, required this.rest, this.bendPositive = true}) : hand = rest;
  final Offset shoulder;
  final double upper;
  final double fore;
  final Offset rest;

  /// Which side the arm is on: false = the croupier's right (screen left),
  /// true = screen right. Used to keep the elbow natural (low and outwards).
  final bool bendPositive;
  Offset hand;

  /// 0 = open hand, 1 = pinching something.
  double grip = 0;

  double get reach => (upper + fore) * 0.94;

  /// Of the two IK solutions, the natural one: elbow low and out to the side
  /// (a fixed bend direction would flip the elbow above the shoulder for some
  /// targets) — same rule as the blackjack arms.
  IkSolution solve() {
    final side = bendPositive ? 1.0 : -1.0;
    double score(IkSolution s) => s.elbow.dy + 0.6 * side * (s.elbow.dx - shoulder.dx);
    final a = solveTwoBone(shoulder, hand, upper, fore, bendPositive: true);
    final b = solveTwoBone(shoulder, hand, upper, fore, bendPositive: false);
    return score(a) >= score(b) ? a : b;
  }
}

/// A character on the stage (the croupier, a stickman…): expression and
/// head; blink/breath come from the clock ([StageController.blinkOf]).
class StageActor {
  StageActor(this.id, {this.phaseMs = 0});
  final String id;

  /// Offsets blink/breath so two actors never blink together.
  final int phaseMs;
  CharacterExpression expression = CharacterExpression.neutral;
  double expressionLevel = 0;
  Duration _expressionHeld = Duration.zero;
  Duration expressionHold = const Duration(milliseconds: 1400);
  double headTilt = 0;
  double talk = 0;
  Offset gaze = Offset.zero;
}

// -------------------------------------------------------------- commands --

/// One animation step. See the library doc.
abstract class StageCommand {
  StageCommand();

  /// Length at speed 1 (zero = instantaneous: begin + step(1) + finish at once).
  Duration get duration;

  void begin(StageController stage) {}

  /// [t] = raw progress in (0, 1]; called every frame and once with 1.
  void step(StageController stage, double t) {}

  void finish(StageController stage) {}

  String get label => runtimeType.toString();
  @override
  String toString() => label;
}

/// Waits.
class PauseCommand extends StageCommand {
  PauseCommand(this.duration);
  @override
  final Duration duration;
  @override
  String get label => 'pause(${duration.inMilliseconds}ms)';
}

/// Emits [cue] at this point of the timeline.
class CueCommand extends StageCommand {
  CueCommand(this.cue);
  final StageCue cue;
  @override
  Duration get duration => Duration.zero;
  @override
  void begin(StageController stage) => stage.emit(cue);
  @override
  String get label => 'cue(${cue.name})';
}

/// Runs [action] instantly, in order (e.g. spawn a prop, set a flag).
class CallbackCommand extends StageCommand {
  CallbackCommand(this.action, {this.name = 'callback'});
  final void Function(StageController stage) action;
  final String name;
  @override
  Duration get duration => Duration.zero;
  @override
  void begin(StageController stage) => action(stage);
  @override
  String get label => name;
}

/// Ad-hoc animation from closures ([curve] applied to t before [onStep]).
class TweenCommand extends StageCommand {
  TweenCommand(this.duration, {required this.onStep, this.onBegin, this.onFinish, this.curve = Curves.easeInOut, this.name = 'tween'});
  @override
  final Duration duration;
  final void Function(StageController stage, double t) onStep;
  final void Function(StageController stage)? onBegin;
  final void Function(StageController stage)? onFinish;
  final Curve curve;
  final String name;
  @override
  void begin(StageController stage) => onBegin?.call(stage);
  @override
  void step(StageController stage, double t) => onStep(stage, curve.transform(t));
  @override
  void finish(StageController stage) => onFinish?.call(stage);
  @override
  String get label => name;
}

/// Moves prop [id] to [to] (optional rotation / scale / opacity), with an
/// optional arc of height [arc] (lift peaks mid-way). Missing prop: no-op.
class MovePropCommand extends StageCommand {
  MovePropCommand(this.id, {required this.to, required this.duration, this.rotation, this.scale, this.opacity, this.arc = 0, this.curve = Curves.easeInOutCubic});
  final String id;
  final Offset to;
  @override
  final Duration duration;
  final double? rotation;
  final double? scale;
  final double? opacity;
  final double arc;
  final Curve curve;
  late Offset _from;
  late double _rot0, _scale0, _op0;

  @override
  void begin(StageController stage) {
    final p = stage.prop(id);
    if (p == null) return;
    _from = p.pos;
    _rot0 = p.rotation;
    _scale0 = p.scale;
    _op0 = p.opacity;
  }

  @override
  void step(StageController stage, double t) {
    final p = stage.prop(id);
    if (p == null) return;
    final u = curve.transform(t);
    p.pos = Offset.lerp(_from, to, u)!;
    if (rotation != null) p.rotation = _rot0 + (rotation! - _rot0) * u;
    if (scale != null) p.scale = _scale0 + (scale! - _scale0) * u;
    if (opacity != null) p.opacity = _op0 + (opacity! - _op0) * u;
    p.lift = arc * math.sin(math.pi * t);
  }

  @override
  void finish(StageController stage) => stage.prop(id)?.lift = 0;

  @override
  String get label => 'move($id)';
}

/// Moves one croupier hand to [target] (clamped to reach) and sets its grip.
/// [left] null = the arm whose shoulder is closer to the target. The hands
/// ease back to rest once the queue is empty, unless [hold] (then until a
/// [RestArmsCommand]).
class ReachCommand extends StageCommand {
  ReachCommand(this.target, {required this.duration, this.left, this.grip = 1, this.hold = false, this.curve = Curves.easeInOutCubic});
  final Offset target;
  @override
  final Duration duration;
  final bool? left;
  final double grip;
  final bool hold;
  final Curve curve;
  late StageArm _arm;
  late Offset _from;
  late double _grip0;
  late Offset _to;

  @override
  void begin(StageController stage) {
    _arm = left == null ? stage.armFor(target) : (left! ? stage.leftArm : stage.rightArm);
    _from = _arm.hand;
    _grip0 = _arm.grip;
    _to = clampToReach(_arm.shoulder, target, _arm.reach);
    if (hold) stage.holdArms = true;
  }

  @override
  void step(StageController stage, double t) {
    final u = curve.transform(t);
    _arm.hand = Offset.lerp(_from, _to, u)!;
    _arm.grip = _grip0 + (grip - _grip0) * u;
  }

  @override
  String get label => 'reach(${target.dx.toStringAsFixed(0)},${target.dy.toStringAsFixed(0)})';
}

/// Lets the arms ease back to rest (also happens when the queue is idle).
class RestArmsCommand extends StageCommand {
  RestArmsCommand({this.duration = const Duration(milliseconds: 350)});
  @override
  final Duration duration;
  late Offset _l, _r;
  @override
  void begin(StageController stage) {
    _l = stage.leftArm.hand;
    _r = stage.rightArm.hand;
  }

  @override
  void step(StageController stage, double t) {
    final u = Curves.easeOut.transform(t);
    stage.leftArm.hand = Offset.lerp(_l, stage.leftArm.rest, u)!;
    stage.rightArm.hand = Offset.lerp(_r, stage.rightArm.rest, u)!;
    stage.leftArm.grip *= 1 - u;
    stage.rightArm.grip *= 1 - u;
  }

  @override
  void finish(StageController stage) => stage.holdArms = false;
}

/// Sets an actor's expression (it fades back to neutral after [hold]).
class ExpressionCommand extends StageCommand {
  ExpressionCommand(this.expression, {this.actor = StageController.dealerId, this.hold = const Duration(milliseconds: 1400), this.duration = const Duration(milliseconds: 220)});
  final CharacterExpression expression;
  final String actor;
  final Duration hold;
  @override
  final Duration duration;
  @override
  void begin(StageController stage) => stage.setExpression(expression, actor: actor, hold: hold, level: 0);
  @override
  void step(StageController stage, double t) => stage.actor(actor).expressionLevel = Curves.easeOut.transform(t);
  @override
  String get label => 'expression(${expression.name})';
}

/// Queued start / stop of the turn timer (null seat = stop).
class TurnTimerCommand extends StageCommand {
  TurnTimerCommand(this.seat, {this.total = const Duration(seconds: 20), this.remaining});
  final int? seat;
  final Duration total;
  final Duration? remaining;
  @override
  Duration get duration => Duration.zero;
  @override
  void begin(StageController stage) {
    final s = seat;
    if (s == null) {
      stage.stopTurnTimer();
    } else {
      stage.startTurnTimer(s, total, remaining: remaining);
    }
  }

  @override
  String get label => seat == null ? 'turn(off)' : 'turn(seat$seat)';
}

/// Plays [children] together; lasts as long as the longest one.
class ParallelCommand extends StageCommand {
  ParallelCommand(this.children);
  final List<StageCommand> children;
  final _done = <StageCommand>{};

  @override
  Duration get duration => children.fold(Duration.zero, (m, c) => c.duration > m ? c.duration : m);

  @override
  void begin(StageController stage) {
    for (final c in children) {
      c.begin(stage);
    }
  }

  @override
  void step(StageController stage, double t) {
    final total = duration.inMicroseconds;
    for (final c in children) {
      if (_done.contains(c)) continue;
      final d = c.duration.inMicroseconds;
      final u = d == 0 ? 1.0 : (t * total / d).clamp(0.0, 1.0);
      if (u > 0) c.step(stage, u);
      if (u >= 1) {
        c.finish(stage);
        _done.add(c);
      }
    }
  }

  @override
  void finish(StageController stage) {
    for (final c in children) {
      if (_done.add(c)) {
        c.step(stage, 1);
        c.finish(stage);
      }
    }
  }

  @override
  String get label => 'parallel(${children.map((c) => c.label).join(', ')})';
}

// ------------------------------------------------------------ controller --

class _Run {
  _Run(this.command, this.duration);
  final StageCommand command;
  final Duration duration;
  final completer = Completer<void>();
  Duration elapsed = Duration.zero;
  final emitted = <String>{};
}

/// See the library documentation.
class StageController extends ChangeNotifier {
  StageController({required this.geometry, StageFeedback? feedback, double speed = 1, Iterable<String> actors = const [dealerId]})
      : feedback = feedback ?? const SilentStageFeedback(),
        _rate = speed,
        leftArm = StageArm(shoulder: geometry.leftShoulder, upper: geometry.upperArm, fore: geometry.foreArm, rest: geometry.leftHandRest, bendPositive: false),
        rightArm = StageArm(shoulder: geometry.rightShoulder, upper: geometry.upperArm, fore: geometry.foreArm, rest: geometry.rightHandRest) {
    var i = 0;
    for (final a in actors) {
      _actors[a] = StageActor(a, phaseMs: 1300 * i++);
    }
  }

  /// Id of the croupier actor (always present).
  static const dealerId = 'dealer';

  final StageGeometry geometry;
  StageFeedback feedback;
  double _rate;

  double get speed => _rate;

  /// Playback rate of commands enqueued from now on (2 = twice as fast).
  set speed(double v) {
    assert(v > 0);
    _rate = v;
  }

  final _queue = Queue<_Run>();
  _Run? _active;
  Duration _clock = Duration.zero;

  final StageArm leftArm;
  final StageArm rightArm;

  /// True while a command keeps the hands away from rest.
  bool holdArms = false;

  final _props = <String, StageProp>{};
  final _actors = <String, StageActor>{};

  int? _turnSeat;
  Duration _turnTotal = Duration.zero;
  Duration _turnElapsed = Duration.zero;
  bool _turnWarned = false;

  // ------------------------------------------------------------- getters --

  Duration get clock => _clock;
  bool get isBusy => _active != null || _queue.isNotEmpty;
  StageCommand? get current => _active?.command;
  List<StageCommand> get pending => [for (final r in _queue) r.command];

  /// Progress (0..1) of the running command.
  double get currentProgress {
    final a = _active;
    if (a == null || a.duration == Duration.zero) return 0;
    return a.elapsed.inMicroseconds / a.duration.inMicroseconds;
  }

  /// Time still needed to drain the queue.
  Duration get remainingDuration {
    var total = Duration.zero;
    final a = _active;
    if (a != null) total += a.duration - a.elapsed;
    for (final r in _queue) {
      total += r.duration;
    }
    return total;
  }

  // -------------------------------------------------------------- props --

  /// Props sorted by [StageProp.z] (stable for equal z).
  List<StageProp> get props {
    final list = _props.values.toList();
    final order = {for (var i = 0; i < list.length; i++) list[i]: i};
    list.sort((a, b) => a.z != b.z ? a.z.compareTo(b.z) : order[a]!.compareTo(order[b]!));
    return list;
  }

  StageProp? prop(String id) => _props[id];
  Iterable<StageProp> propsOf(String kind) => _props.values.where((p) => p.kind == kind);

  StageProp addProp(StageProp p) {
    _props[p.id] = p;
    notifyListeners();
    return p;
  }

  void removeProp(String id) {
    if (_props.remove(id) != null) notifyListeners();
  }

  void removePropsOf(String kind) {
    _props.removeWhere((_, p) => p.kind == kind);
    notifyListeners();
  }

  // -------------------------------------------------------------- actors --

  StageActor actor(String id) => _actors.putIfAbsent(id, () => StageActor(id, phaseMs: 1300 * _actors.length));
  StageActor get dealer => actor(dealerId);
  Iterable<StageActor> get actors => _actors.values;

  double blinkOf(StageActor a) => blinkAt(_clock.inMilliseconds, phaseMs: a.phaseMs);
  double breathOf(StageActor a) => breathAt(_clock.inMilliseconds, phaseMs: a.phaseMs);

  /// The pose to paint [a] with this frame.
  CharacterPose poseOf(StageActor a) => CharacterPose(
        expression: a.expression,
        level: a.expressionLevel,
        blink: blinkOf(a),
        breath: breathOf(a),
        talk: a.talk,
        headTilt: a.headTilt,
        gaze: a.gaze,
      );

  /// Immediate expression change (see [ExpressionCommand] for the queued one).
  void setExpression(CharacterExpression e, {String actor = dealerId, Duration hold = const Duration(milliseconds: 1400), double level = 1}) {
    final a = this.actor(actor);
    a.expression = e;
    a.expressionLevel = level;
    a.expressionHold = hold;
    a._expressionHeld = Duration.zero;
    notifyListeners();
  }

  // ---------------------------------------------------------------- arms --

  /// The arm whose shoulder is closer to [target].
  StageArm armFor(Offset target) =>
      (target - leftArm.shoulder).distance <= (target - rightArm.shoulder).distance ? leftArm : rightArm;

  // ---------------------------------------------------------- turn timer --

  int? get turnSeat => _turnSeat;
  double get turnFraction =>
      _turnTotal == Duration.zero ? 0 : (_turnElapsed.inMicroseconds / _turnTotal.inMicroseconds).clamp(0.0, 1.0);
  Duration get turnRemaining {
    final r = _turnTotal - _turnElapsed;
    return r.isNegative ? Duration.zero : r;
  }

  /// Seconds shown in a turn ring (ceil).
  int get turnSecondsLeft => (turnRemaining.inMilliseconds / 1000).ceil();

  /// Starts the ring of [seat] for [total]; [remaining] resumes a timer
  /// already running on the server (snapshot rebuild).
  void startTurnTimer(int seat, Duration total, {Duration? remaining}) {
    _turnSeat = seat;
    _turnTotal = total;
    final r = remaining ?? total;
    _turnElapsed = total - (r > total ? total : r);
    _turnWarned = turnFraction >= 0.75;
    notifyListeners();
  }

  void stopTurnTimer() {
    _turnSeat = null;
    _turnTotal = Duration.zero;
    _turnElapsed = Duration.zero;
    notifyListeners();
  }

  // ------------------------------------------------------------ queueing --

  /// Queues [c]; completes when it has fully played (or on [reset]).
  Future<void> enqueue(StageCommand c) {
    final scaled = Duration(microseconds: (c.duration.inMicroseconds / _rate).round());
    final run = _Run(c, scaled);
    _queue.add(run);
    notifyListeners();
    return run.completer.future;
  }

  /// Queues several commands in order; completes after the last one.
  Future<void> enqueueAll(Iterable<StageCommand> commands) {
    Future<void> last = Future.value();
    for (final c in commands) {
      last = enqueue(c);
    }
    return last;
  }

  Future<void> pause(Duration d) => enqueue(PauseCommand(d));
  Future<void> cue(StageCue c) => enqueue(CueCommand(c));

  /// Sends [c] to the feedback now.
  void emit(StageCue c) => feedback.cue(c);

  /// Sends [c] once per run of the current command (keyed by [key]).
  void emitOnce(String key, StageCue c) {
    final a = _active;
    if (a == null) {
      emit(c);
    } else if (a.emitted.add(key)) {
      emit(c);
    }
  }

  /// True once progress [t] of the current command is within [leadMs] of
  /// [at] (so a sample whose impact is [leadMs] into the file lands on [at]).
  bool ahead(double t, double at, int leadMs) {
    final a = _active;
    final ms = a == null ? 0 : a.duration.inMicroseconds / 1000;
    return t >= at || (at - t) * ms <= leadMs;
  }

  /// Plays every queued command to its end now (no animation, cues muted).
  void fastForward() {
    final saved = feedback;
    feedback = const SilentStageFeedback();
    try {
      advance(remainingDuration + const Duration(microseconds: 1));
    } finally {
      feedback = saved;
    }
  }

  /// Clears the queue and the scene; pending futures complete.
  void reset() {
    for (final r in [?_active, ..._queue]) {
      if (!r.completer.isCompleted) r.completer.complete();
    }
    _active = null;
    _queue.clear();
    _props.clear();
    holdArms = false;
    for (final arm in [leftArm, rightArm]) {
      arm
        ..hand = arm.rest
        ..grip = 0;
    }
    for (final a in _actors.values) {
      a
        ..expression = CharacterExpression.neutral
        ..expressionLevel = 0
        ..headTilt = 0
        ..talk = 0;
    }
    stopTurnTimer();
  }

  // ---------------------------------------------------------------- time --

  /// Moves time forward by [dt], running as many commands as fit.
  void advance(Duration dt) {
    if (dt.isNegative) return;
    _clock += dt;
    var remaining = dt;
    while (_active != null || _queue.isNotEmpty) {
      if (_active == null) {
        _active = _queue.removeFirst();
        _active!.command.begin(this);
      }
      final a = _active!;
      final need = a.duration - a.elapsed;
      if (remaining >= need) {
        a.elapsed = a.duration;
        a.command.step(this, 1);
        a.command.finish(this);
        _active = null;
        remaining -= need;
        a.completer.complete();
        if (remaining == Duration.zero && _queue.isEmpty) break;
      } else {
        a.elapsed += remaining;
        a.command.step(this, a.elapsed.inMicroseconds / a.duration.inMicroseconds);
        remaining = Duration.zero;
        break;
      }
    }
    // Hands only drift back with the time left AFTER the queue drained, so the
    // result does not depend on how frames split a command's end.
    _idle(dt, idle: _active == null ? remaining : Duration.zero);
    _tickTurn(dt);
    notifyListeners();
  }

  void _idle(Duration dt, {required Duration idle}) {
    final secs = dt.inMicroseconds / 1e6;
    if (_active == null && !holdArms && idle > Duration.zero) {
      final k = 1 - math.exp(-idle.inMicroseconds / 1e6 * 7);
      final sway = Offset(0, (breathOf(dealer) - 0.5) * 6);
      for (final arm in [leftArm, rightArm]) {
        arm.hand = Offset.lerp(arm.hand, arm.rest + sway, k)!;
        arm.grip *= 1 - k;
      }
    }
    for (final a in _actors.values) {
      if (a.expression == CharacterExpression.neutral) continue;
      a._expressionHeld += dt;
      if (a._expressionHeld > a.expressionHold) {
        a.expressionLevel = math.max(0, a.expressionLevel - secs * 1.6);
        if (a.expressionLevel == 0) a.expression = CharacterExpression.neutral;
      }
    }
  }

  void _tickTurn(Duration dt) {
    final seat = _turnSeat;
    if (seat == null || dt == Duration.zero) return;
    final before = turnSecondsLeft;
    _turnElapsed += dt;
    final after = turnSecondsLeft;
    if (after < before && _turnElapsed < _turnTotal) emit(StageCue.timerTick.withSeat(seat));
    if (!_turnWarned && turnFraction >= 0.75) {
      _turnWarned = true;
      emit(StageCue.timerWarning.withSeat(seat));
    }
  }
}
