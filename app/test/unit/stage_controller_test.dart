// StageController: deterministic FIFO queue of self-contained commands
// (begin / step / finish), fast-forward, cues, turn timer, actors, IK arms.


import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/characters/character_spec.dart';
import 'package:vingtun/features/games/craps/craps_geometry.dart';
import 'package:vingtun/features/games/holdem/holdem_geometry.dart';
import 'package:vingtun/features/games/roulette/roulette_geometry.dart';
import 'package:vingtun/features/stage/stage_controller.dart';
import 'package:vingtun/features/stage/stage_geometry.dart';

/// Records its life cycle into [log].
class _Probe extends StageCommand {
  _Probe(this.name, this.duration, this.log);
  final String name;
  @override
  final Duration duration;
  final List<String> log;
  @override
  void begin(StageController stage) => log.add('$name:begin');
  @override
  void step(StageController stage, double t) => log.add('$name:${t.toStringAsFixed(2)}');
  @override
  void finish(StageController stage) => log.add('$name:finish');
}

const ms = Duration(milliseconds: 1);

void main() {
  late StageController stage;
  late RecordingStageFeedback fb;

  setUp(() {
    fb = RecordingStageFeedback();
    stage = StageController(geometry: const RouletteGeometry(), feedback: fb);
  });
  tearDown(() => stage.dispose());

  test('commands run FIFO, one at a time, with begin / step(t) / finish', () {
    final log = <String>[];
    stage.enqueue(_Probe('a', const Duration(milliseconds: 100), log));
    stage.enqueue(_Probe('b', const Duration(milliseconds: 100), log));
    expect(stage.isBusy, isTrue);
    expect(stage.remainingDuration, const Duration(milliseconds: 200));
    stage.advance(ms * 50);
    expect(log, ['a:begin', 'a:0.50']);
    expect(stage.current?.label, '_Probe');
    stage.advance(ms * 100); // finishes a, half of b
    expect(log, ['a:begin', 'a:0.50', 'a:1.00', 'a:finish', 'b:begin', 'b:0.50']);
    stage.advance(ms * 50);
    expect(log.last, 'b:finish');
    expect(stage.isBusy, isFalse);
  });

  test('the same script played at any frame rate ends in the same state (deterministic)', () {
    Offset run(Duration frame) {
      final s = StageController(geometry: const RouletteGeometry());
      s.addProp(StageProp(id: 'ball', kind: 'ball', pos: const Offset(100, 100)));
      s.enqueue(MovePropCommand('ball', to: const Offset(700, 400), duration: const Duration(milliseconds: 900), arc: 80));
      s.enqueue(MovePropCommand('ball', to: const Offset(300, 900), duration: const Duration(milliseconds: 600)));
      var mid = Offset.zero;
      for (var t = Duration.zero; t < const Duration(milliseconds: 1500); t += frame) {
        s.advance(frame);
        if (t <= const Duration(milliseconds: 1000) && t + frame > const Duration(milliseconds: 1000)) mid = s.prop('ball')!.pos;
      }
      s.advance(const Duration(milliseconds: 100));
      expect(s.prop('ball')!.pos, const Offset(300, 900));
      expect(s.prop('ball')!.lift, 0);
      s.dispose();
      return mid;
    }

    // Mid-script positions agree to the frame boundary; the end is exact.
    final a = run(const Duration(milliseconds: 10));
    final b = run(const Duration(milliseconds: 20));
    expect((a - b).distance, lessThan(25));
  });

  test('futures complete when the command has played; reset completes the pending ones', () async {
    var done = 0;
    stage.enqueue(PauseCommand(const Duration(milliseconds: 100))).then((_) => done++);
    final last = stage.enqueue(PauseCommand(const Duration(milliseconds: 100)))..then((_) => done++);
    stage.advance(ms * 150);
    await Future<void>.delayed(Duration.zero);
    expect(done, 1);
    stage.reset();
    await last;
    expect(done, 2);
    expect(stage.isBusy, isFalse);
  });

  test('fastForward plays everything instantly with the cues muted', () {
    stage.addProp(StageProp(id: 'c', kind: 'chip'));
    stage.enqueue(CueCommand(const StageCue('ballDrop')));
    stage.enqueue(MovePropCommand('c', to: const Offset(10, 20), duration: const Duration(seconds: 2)));
    stage.enqueue(CueCommand(const StageCue('payout')));
    stage.fastForward();
    expect(stage.isBusy, isFalse);
    expect(stage.prop('c')!.pos, const Offset(10, 20));
    expect(fb.cues, isEmpty);
    // And normal playback emits them in order.
    stage.enqueueAll([CueCommand(const StageCue('a')), PauseCommand(const Duration(milliseconds: 10)), CueCommand(const StageCue('b'))]);
    stage.advance(ms * 20);
    expect(fb.names, ['a', 'b']);
  });

  test('speed scales the commands enqueued afterwards', () {
    stage.speed = 2;
    final log = <String>[];
    stage.enqueue(_Probe('x', const Duration(milliseconds: 200), log));
    expect(stage.remainingDuration, const Duration(milliseconds: 100));
    stage.advance(ms * 100);
    expect(log.last, 'x:finish');
  });

  test('emitOnce fires a cue once per run; ahead anticipates an attack', () {
    final cmd = TweenCommand(const Duration(milliseconds: 1000), onStep: (s, t) {
      if (s.ahead(t, 0.5, 100)) s.emitOnce('hit', const StageCue('hit'));
    }, curve: Curves.linear);
    stage.enqueue(cmd);
    stage.advance(ms * 390);
    expect(fb.names, isEmpty);
    stage.advance(ms * 20); // t = 0.41: within 100 ms of 0.5
    expect(fb.names, ['hit']);
    stage.advance(ms * 600);
    expect(fb.names, ['hit']);
  });

  test('ParallelCommand runs its children together and lasts as long as the longest', () {
    final log = <String>[];
    stage.enqueue(ParallelCommand([_Probe('short', const Duration(milliseconds: 100), log), _Probe('long', const Duration(milliseconds: 400), log)]));
    expect(stage.remainingDuration, const Duration(milliseconds: 400));
    stage.advance(ms * 200);
    expect(log, containsAllInOrder(['short:begin', 'long:begin', 'short:1.00', 'short:finish']));
    expect(log.where((e) => e == 'short:finish').length, 1);
    stage.advance(ms * 200);
    expect(log.last, 'long:finish');
  });

  test('turn timer: a tick cue each second, one warning at 75 %, resumable from the server time', () {
    stage.startTurnTimer(2, const Duration(seconds: 4));
    expect(stage.turnSeat, 2);
    expect(stage.turnSecondsLeft, 4);
    for (var i = 0; i < 40; i++) {
      stage.advance(ms * 100);
    }
    expect(fb.names.where((n) => n == 'timerTick').length, 3); // 3, 2, 1
    expect(fb.names.where((n) => n == 'timerWarning').length, 1);
    expect(fb.cues.first.seat, 2);
    expect(stage.turnFraction, 1);
    stage.startTurnTimer(1, const Duration(seconds: 20), remaining: const Duration(seconds: 5));
    expect(stage.turnFraction, closeTo(0.75, 1e-9));
    expect(stage.turnSecondsLeft, 5);
    stage.enqueue(TurnTimerCommand(null));
    stage.advance(ms);
    expect(stage.turnSeat, isNull);
  });

  test('actors: deterministic blink / breath, expressions fade back to neutral', () {
    final dealer = stage.dealer;
    final other = stage.actor('stickman');
    expect(other.phaseMs, isNot(dealer.phaseMs));
    final blinks = <double>[];
    for (var i = 0; i < 400; i++) {
      stage.advance(ms * 10);
      blinks.add(stage.blinkOf(dealer));
    }
    expect(blinks.any((b) => b > 0.9), isTrue);
    expect(blinks.where((b) => b > 0).length, lessThan(60)); // blinks are short
    expect(stage.breathOf(dealer), inInclusiveRange(0, 1));
    expect(blinkAt(1234, phaseMs: 50), blinkAt(1284));

    stage.enqueue(ExpressionCommand(CharacterExpression.laugh, hold: const Duration(milliseconds: 500)));
    stage.advance(ms * 300);
    expect(dealer.expression, CharacterExpression.laugh);
    expect(stage.poseOf(dealer).level, 1);
    for (var i = 0; i < 30; i++) {
      stage.advance(ms * 100);
    }
    expect(dealer.expression, CharacterExpression.neutral);
    expect(dealer.expressionLevel, 0);
  });

  test('arms: reach clamps to the arm length, then hands ease back to rest when idle', () {
    final far = const Offset(950, 1250);
    stage.enqueue(ReachCommand(far, duration: const Duration(milliseconds: 300)));
    stage.advance(ms * 300); // the queue drains exactly at the end of this frame: no idle time yet
    final arm = stage.armFor(far);
    expect(arm, same(stage.rightArm));
    expect((arm.hand - arm.shoulder).distance, closeTo(arm.reach, 0.5));
    expect(arm.grip, 1);
    final ik = arm.solve();
    expect((ik.elbow - arm.shoulder).distance, closeTo(arm.upper, 1e-6));
    for (var i = 0; i < 100; i++) {
      stage.advance(ms * 20);
    }
    expect((arm.hand - arm.rest).distance, lessThan(8));
    expect(arm.grip, lessThan(0.01));
    // hold keeps the hand out until RestArmsCommand.
    stage.enqueue(ReachCommand(const Offset(600, 500), duration: const Duration(milliseconds: 100), hold: true));
    for (var i = 0; i < 50; i++) {
      stage.advance(ms * 20);
    }
    expect((stage.rightArm.hand - const Offset(600, 500)).distance, lessThan(1));
    stage.enqueue(RestArmsCommand());
    stage.advance(const Duration(seconds: 1));
    expect(stage.holdArms, isFalse);
    expect((stage.rightArm.hand - stage.rightArm.rest).distance, lessThan(8));
  });

  test('props: add / remove / z order / by kind', () {
    stage.addProp(StageProp(id: 'b', kind: 'chip', z: 2));
    stage.addProp(StageProp(id: 'a', kind: 'chip', z: 1));
    stage.addProp(StageProp(id: 'c', kind: 'card', z: 1));
    expect([for (final p in stage.props) p.id], ['a', 'c', 'b']);
    expect(stage.propsOf('chip').length, 2);
    stage.removePropsOf('chip');
    expect([for (final p in stage.props) p.id], ['c']);
    stage.enqueue(MovePropCommand('missing', to: Offset.zero, duration: ms * 10)); // no-op, no throw
    stage.advance(ms * 20);
    stage.removeProp('c');
    expect(stage.props, isEmpty);
  });

  test('geometries: one spot per seat, on the stage, seat 0 on the screen right', () {
    for (final StageGeometry g in const [RouletteGeometry(), HoldemGeometry(), CrapsGeometry()]) {
      expect(g.seatSpots.length, g.seatCount);
      for (final s in g.seatSpots) {
        expect((Offset.zero & g.size).contains(s), isTrue, reason: '$g $s');
      }
      expect(g.seatSpots.first.dx, greaterThan(g.seatSpots.last.dx));
    }
    expect(StageGeometry.arcSeats(1, center: const Offset(10, 10), radiusX: 5, radiusY: 7).single, const Offset(10, 17));
  });
}

