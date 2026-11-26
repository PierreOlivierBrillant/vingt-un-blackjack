/// Pure maths of the hold'em bet / raise slider: the amounts are "raise TO"
/// totals for the street (`toCents`), whole dollars, between the server's
/// `g.toAct.minToCents` (the minimum bet / raise) and `maxToCents` (all-in).
/// When the minimum is out of reach only the all-in remains ([allInOnly]).
library;

import 'package:flutter/foundation.dart';

import 'holdem_state.dart';

/// A preset button of the slider.
enum HoldemPreset { min, halfPot, pot, allIn }

@immutable
class HoldemRaiseModel {
  const HoldemRaiseModel({
    required this.minTo,
    required this.maxTo,
    required this.kind,
    this.currentBet = 0,
    this.myBet = 0,
    this.callCents = 0,
    this.middleCents = 0,
  });

  /// From the pending decision (null when no bet / raise is possible).
  static HoldemRaiseModel? of(HoldemToAct? toAct, {int currentBet = 0, int myBet = 0, int middleCents = 0}) {
    if (toAct == null || !toAct.canRaise) return null;
    return HoldemRaiseModel(
      minTo: toAct.minToCents!,
      maxTo: toAct.maxToCents!,
      kind: toAct.kind!,
      currentBet: currentBet,
      myBet: myBet,
      callCents: toAct.callCents,
      middleCents: middleCents,
    );
  }

  /// Smallest legal "to" amount (cents).
  final int minTo;

  /// All-in "to" amount (my bet on this street + my stack).
  final int maxTo;

  /// 'bet' (nobody bet on this street) or 'raise'.
  final String kind;

  /// Highest bet of the street (`g.currentBetCents`).
  final int currentBet;

  /// My chips already in front of me on this street.
  final int myBet;
  final int callCents;

  /// Every chip in the middle: pot + all the bets in front of the seats (mine included).
  final int middleCents;

  static const step = 100;

  bool get isBet => kind == 'bet';

  /// Only an all-in is possible (the minimum is the whole stack).
  bool get allInOnly => minTo >= maxTo;

  /// Lowest value of the slider.
  int get low => allInOnly ? maxTo : minTo;

  /// Whole dollars, within [low]..[maxTo].
  int clamp(int to) {
    if (allInOnly) return maxTo;
    final snapped = ((to + step ~/ 2) ~/ step) * step;
    if (snapped >= maxTo) return maxTo;
    if (snapped <= minTo) return minTo;
    return snapped;
  }

  /// Slider position (0..1) of an amount.
  double positionOf(int to) => allInOnly || maxTo == low ? 1 : ((clamp(to) - low) / (maxTo - low)).clamp(0.0, 1.0);

  /// Amount at a slider position (0..1), snapped to whole dollars.
  int amountAt(double position) => allInOnly ? maxTo : clamp((low + (maxTo - low) * position.clamp(0.0, 1.0)).round());

  /// "Raise to" of a pot-sized bet / raise times [fraction]: the call first,
  /// then [fraction] × the pot as it would be after the call.
  int potTo(double fraction) {
    final afterCall = middleCents + callCents;
    final to = (isBet ? myBet : currentBet) + (afterCall * fraction).round();
    return clamp(to);
  }

  /// Amount of a preset.
  int presetTo(HoldemPreset p) => switch (p) {
        HoldemPreset.min => low,
        HoldemPreset.halfPot => potTo(0.5),
        HoldemPreset.pot => potTo(1),
        HoldemPreset.allIn => maxTo,
      };

  /// Presets worth a button: distinct amounts, min first, all-in last.
  List<(HoldemPreset, int)> get presets {
    if (allInOnly) return [(HoldemPreset.allIn, maxTo)];
    final out = <(HoldemPreset, int)>[];
    final seen = <int>{};
    for (final p in HoldemPreset.values) {
      final v = presetTo(p);
      if (seen.add(v)) out.add((p, v));
    }
    return out;
  }

  /// Whether [to] puts the whole stack in.
  bool isAllIn(int to) => clamp(to) >= maxTo;

  /// Chips that leave the stack for a "to" amount.
  int addedFor(int to) => clamp(to) - myBet;

  /// The action sent to the server for [to].
  Map<String, Object?> actionFor(int to) => isAllIn(to) ? const {'type': 'allIn'} : {'type': kind, 'toCents': clamp(to)};
}
