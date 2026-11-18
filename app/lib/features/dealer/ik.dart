import 'dart:math' as math;
import 'dart:ui';

/// Result of a two-bone inverse-kinematics solve.
class IkSolution {
  const IkSolution({required this.elbow, required this.hand, required this.reached});
  final Offset elbow;

  /// Where the hand actually is (equals the target when [reached]).
  final Offset hand;
  final bool reached;
}

/// Analytic two-bone IK (law of cosines).
///
/// [bendPositive] chooses which of the two mirror solutions is used: with
/// screen coordinates (y down) `true` bends the elbow clockwise from the
/// shoulder→target direction. Targets out of reach are clamped onto the
/// reach sphere (arm fully extended towards the target); targets too close
/// are pushed out to the minimum distance.
IkSolution solveTwoBone(
  Offset shoulder,
  Offset target,
  double upper,
  double fore, {
  bool bendPositive = true,
}) {
  assert(upper > 0 && fore > 0);
  final toTarget = target - shoulder;
  final rawDist = toTarget.distance;
  final maxReach = upper + fore;
  final minReach = (upper - fore).abs() + 1e-3;
  final dist = rawDist.clamp(minReach, maxReach - 1e-6).toDouble();
  final reached = rawDist <= maxReach && rawDist >= minReach;

  final dir = rawDist < 1e-9 ? const Offset(0, 1) : toTarget / rawDist;
  final hand = shoulder + dir * dist;

  // Angle between shoulder→hand and shoulder→elbow.
  final cosA = ((upper * upper + dist * dist - fore * fore) / (2 * upper * dist)).clamp(-1.0, 1.0);
  final a = math.acos(cosA) * (bendPositive ? 1 : -1);
  final base = math.atan2(dir.dy, dir.dx);
  final elbow = shoulder + Offset(math.cos(base + a), math.sin(base + a)) * upper;
  return IkSolution(elbow: elbow, hand: hand, reached: reached);
}

/// Pulls [target] back inside a reach radius around [origin] (used for the
/// "pitch" release point when a card goes farther than the arm can reach).
Offset clampToReach(Offset origin, Offset target, double reach) {
  final d = target - origin;
  final dist = d.distance;
  if (dist <= reach || dist == 0) return target;
  return origin + d / dist * reach;
}

/// Point on a quadratic Bézier.
Offset quadBezier(Offset p0, Offset p1, Offset p2, double t) {
  final u = 1 - t;
  return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
}
