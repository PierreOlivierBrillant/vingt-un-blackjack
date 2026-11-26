/// Motion of the wheel and the ball during one spin, computed BACKWARDS from the drawn pocket.
///
/// The number is public from "Rien ne va plus" (`g.number`), so the client knows where the ball
/// must end. The ball is described relative to the wheel (rotating frame):
///   rel(t) = pocketAngle(number) + S(T − t) + wobble(T − t)
/// where T is the landing time, S(u) the distance still to travel u ms before landing (S(0) = 0,
/// S'(0) = 0: the ball comes to rest in its pocket with no speed relative to the wheel) and wobble
/// the bounces on the frets, also exactly 0 at u = 0. Whatever the wheel does, `ball = wheel + rel`
/// therefore lands in the drawn pocket at T and stays in it. Pure maths, unit-tested
/// (`test/unit/roulette/roulette_spin_test.dart`).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'roulette_engine.dart';

const double kPocketStep = 2 * math.pi / 37;

/// Angle of [n]'s pocket centre on the wheel (wheel frame; 0 = the zero, clockwise).
double pocketAngle(int n) {
  final i = kWheelOrder.indexOf(n);
  if (i < 0) throw RangeError('not a roulette number: $n');
  return i * kPocketStep;
}

/// Number of the pocket at [angle] (wheel frame).
int pocketAt(double angle) {
  final i = (angle / kPocketStep).round() % 37;
  return kWheelOrder[i < 0 ? i + 37 : i];
}

double _wrap(double a) {
  final t = a % (2 * math.pi);
  return t < 0 ? t + 2 * math.pi : t;
}

/// Ball track radius (fraction of the wheel radius) and the ring where pockets catch the ball.
const double kBallTrackRadius = 0.86;
const double kPocketRadius = 0.6;

@immutable
class SpinFrame {
  const SpinFrame({required this.wheelExtra, required this.ballRel, required this.ballRadius, required this.landed, required this.bouncing});

  /// Extra rotation of the wheel given by the croupier's push (radians, added to the idle spin).
  final double wheelExtra;

  /// Ball angle relative to the wheel (radians).
  final double ballRel;

  /// Ball distance from the centre (fraction of the wheel radius).
  final double ballRadius;
  final bool landed;

  /// The ball is hopping between frets.
  final bool bouncing;

  /// Pocket the ball is over now.
  int get pocket => pocketAt(ballRel);
}

/// One spin of the wheel towards [number], [spinMs] long (server `ROULETTE_TIMING.spinMs`).
/// [round] only varies the look (launch speed, number of bounces) so two spins differ.
@immutable
class RouletteSpin {
  RouletteSpin({required this.number, this.spinMs = 8000, int round = 0})
      : landMs = math.max(2000, spinMs - 700).toDouble(),
        _vMax = 12.5 + (round * 7919 % 23) / 10, // rad/s relative to the wheel at launch
        _bounces = 3 + round % 3,
        _wheelBoost = 1.6 + (round * 104729 % 9) / 10;

  final int number;
  final int spinMs;

  /// Time of the landing (ms after the launch).
  final double landMs;
  final double _vMax;
  final int _bounces;
  final double _wheelBoost;

  /// The ball leaves the rim this long before landing (ms).
  static const double dropMs = 1600;

  /// The ball's relative speed falls like (u/T)^p, p > 0.
  static const double _p = 1.35;

  /// Distance still to travel u ms before landing (radians, ≥ 0).
  double _remaining(double u) {
    if (u <= 0) return 0;
    final x = u / landMs;
    return _vMax * landMs / 1000 / (_p + 1) * math.pow(x, _p + 1);
  }

  /// Fret bounces in the last [dropMs]: 0 at the drop and at the landing.
  double _wobble(double u) {
    if (u <= 0 || u >= dropMs) return 0;
    final x = u / dropMs;
    return 0.32 * math.sin(math.pi * _bounces * x) * x;
  }

  SpinFrame at(double ms) {
    final t = ms.clamp(0.0, double.infinity);
    final u = landMs - t; // time left before landing
    final rel = pocketAngle(number) + _remaining(u) + _wobble(u);
    double radius;
    if (u <= 0) {
      radius = kPocketRadius;
    } else if (u >= dropMs) {
      radius = kBallTrackRadius;
    } else {
      // spirals in over the first half of the drop, then hops in the pockets
      final x = 1 - u / dropMs; // 0 → 1
      final spiral = kBallTrackRadius - (kBallTrackRadius - kPocketRadius) * _smooth(math.min(1, x * 1.8));
      final hop = 0.05 * (1 - x) * math.sin(math.pi * _bounces * u / dropMs).abs();
      radius = spiral + hop;
    }
    // The wheel: the push decays smoothly over the whole spin.
    final total = spinMs.toDouble();
    final w = t >= total ? 1.0 : 1 - math.pow(1 - t / total, 3).toDouble();
    return SpinFrame(
      wheelExtra: _wheelBoost * total / 1000 / 3 * w,
      ballRel: _wrap(rel),
      ballRadius: radius,
      landed: u <= 0,
      bouncing: u > 0 && u < dropMs,
    );
  }

  /// Times (ms) of the fret hits, for the ticking sound.
  List<double> get bounceTimes => [for (var k = 1; k < _bounces * 2; k++) landMs - dropMs + dropMs * k / (_bounces * 2)];
}

/// Smoothstep.
double _smooth(double x) => x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x);
