/// Hold'em hand evaluator: the best 5-card poker hand among 5, 6 or 7 cards.
/// Line-for-line port of `firebase/functions/src/games/holdem/engineHand.ts`
/// (checked against the shared vectors `assets/fairness/holdem_vectors.json`).
///
/// Cards are wire codes (`AS`, `TH`, `9C`…). Score (see
/// `shared/games/holdem.ts`): `category × 16^5 + Σ rank(best[i]) × 16^(4−i)`,
/// ranks 2..14 (ace 14, except the ace of a wheel A-2-3-4-5 which counts 1).
/// Equal scores = exact tie. [HandValue.best] lists the 5 cards in
/// significance order (equal ranks: suits S, H, D, C).
library;

import 'package:flutter/foundation.dart';

/// `HOLDEM_HAND_CATEGORIES`, weakest first.
enum HoldemCategory { highCard, pair, twoPair, trips, straight, flush, fullHouse, quads, straightFlush }

@immutable
class HandValue {
  const HandValue(this.category, this.score, this.best);
  final HoldemCategory category;
  final int score;
  final List<String> best;

  /// A straight flush topped by the ace.
  bool get royal => category == HoldemCategory.straightFlush && best.isNotEmpty && best.first[0] == 'A';

  @override
  String toString() => '${category.name}($score ${best.join(' ')})';
}

const _rankValue = <String, int>{
  'A': 14, 'K': 13, 'Q': 12, 'J': 11, 'T': 10, '9': 9, '8': 8, '7': 7, '6': 6, '5': 5, '4': 4, '3': 3, '2': 2, //
};
const _suitOrder = 'SHDC';

int holdemRankValue(String c) => _rankValue[c[0]] ?? 0;
int _suitIndex(String c) => _suitOrder.indexOf(c[1]);

/// Rank descending, then suit S, H, D, C.
int _byStrength(String a, String b) {
  final d = holdemRankValue(b) - holdemRankValue(a);
  return d != 0 ? d : _suitIndex(a) - _suitIndex(b);
}

int _scoreOf(HoldemCategory category, List<String> best, bool wheel) {
  var s = category.index;
  for (var i = 0; i < 5; i++) {
    final r = wheel && i == 4 ? 1 : holdemRankValue(best[i]);
    s = s * 16 + r;
  }
  return s;
}

/// Highest straight among [sorted] (rank desc): 5 cards top-down (wheel 5-4-3-2-A), or null.
({List<String> cards, bool wheel})? _straightOf(List<String> sorted) {
  final firstOfRank = <int, String>{};
  for (final c in sorted) {
    firstOfRank.putIfAbsent(holdemRankValue(c), () => c);
  }
  for (var top = 14; top >= 6; top--) {
    final run = <String>[];
    for (var r = top; r > top - 5; r--) {
      final c = firstOfRank[r];
      if (c == null) break;
      run.add(c);
    }
    if (run.length == 5) return (cards: run, wheel: false);
  }
  final wheel = [for (final r in const [5, 4, 3, 2, 14]) firstOfRank[r]];
  if (wheel.every((c) => c != null)) return (cards: [for (final c in wheel) c!], wheel: true);
  return null;
}

HandValue _make(HoldemCategory category, List<String> best, [bool wheel = false]) =>
    HandValue(category, _scoreOf(category, best, wheel), List.unmodifiable(best));

/// Best hand of 5 to 7 distinct cards.
HandValue evaluateHoldemHand(List<String> cards) {
  if (cards.length < 5 || cards.length > 7) throw ArgumentError('evaluateHoldemHand: ${cards.length} cards');
  final sorted = [...cards]..sort(_byStrength);

  // Flush / straight flush.
  List<String>? flush;
  for (final s in _suitOrder.split('')) {
    final suited = [for (final c in sorted) if (c[1] == s) c];
    if (suited.length >= 5) {
      flush = suited;
      break;
    }
  }
  if (flush != null) {
    final sf = _straightOf(flush);
    if (sf != null) return _make(HoldemCategory.straightFlush, sf.cards, sf.wheel);
  }

  // Groups of equal rank: count desc, then rank desc (cards inside a group in suit order).
  final groups = <int, List<String>>{};
  for (final c in sorted) {
    (groups[holdemRankValue(c)] ??= []).add(c);
  }
  final ordered = groups.values.toList()
    ..sort((a, b) {
      final d = b.length - a.length;
      return d != 0 ? d : holdemRankValue(b[0]) - holdemRankValue(a[0]);
    });
  List<String> kickers(List<String> used, int n) => sorted.where((c) => !used.contains(c)).take(n).toList();

  final top = ordered[0];
  if (top.length == 4) return _make(HoldemCategory.quads, [...top, ...kickers(top, 1)]);

  if (top.length == 3) {
    final pair = ordered.skip(1).where((g) => g.length >= 2).firstOrNull;
    if (pair != null) return _make(HoldemCategory.fullHouse, [...top, ...pair.take(2)]);
  }
  if (flush != null) return _make(HoldemCategory.flush, flush.take(5).toList());

  final st = _straightOf(sorted);
  if (st != null) return _make(HoldemCategory.straight, st.cards, st.wheel);

  if (top.length == 3) return _make(HoldemCategory.trips, [...top, ...kickers(top, 2)]);
  if (top.length == 2) {
    final second = ordered.length > 1 ? ordered[1] : null;
    if (second != null && second.length == 2) {
      final used = [...top, ...second];
      return _make(HoldemCategory.twoPair, [...used, ...kickers(used, 1)]);
    }
    return _make(HoldemCategory.pair, [...top, ...kickers(top, 3)]);
  }
  return _make(HoldemCategory.highCard, sorted.take(5).toList());
}

/// Wire name of a category (`HOLDEM_HAND_CATEGORIES`), null if unknown.
HoldemCategory? holdemCategoryFromWire(Object? v) => HoldemCategory.values.where((c) => c.name == v).firstOrNull;
