/// Pure Dart mirror of the roulette engine (`firebase/functions/src/games/roulette/engine.ts`,
/// contract `shared/games/roulette.ts`): wheel order and colours, the 157 bet spots, payouts,
/// per-type caps, the call bets (annonces) and the board editor of the client (undo, clear,
/// repeat, double — the server only ever receives whole boards). Checked against the backend
/// by `test/unit/roulette/roulette_vectors_test.dart` (app/assets/fairness/roulette_vectors.json).
library;

import 'package:flutter/foundation.dart';

import '../../../domain/fairness.dart';
import '../../../domain/game_table.dart';

/// The 37 pockets clockwise from the zero (real European wheel).
const kWheelOrder = <int>[
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26, //
];

const kRedNumbers = <int>{1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36};

enum RouletteColor { red, black, green }

RouletteColor rouletteColorOf(int n) => n == 0 ? RouletteColor.green : (kRedNumbers.contains(n) ? RouletteColor.red : RouletteColor.black);

/// Bet types (`ROULETTE_SPOT_TYPES`).
enum RouletteSpotType {
  straight(35, 'straightMaxCents'),
  split(17, 'splitMaxCents'),
  street(11, 'streetMaxCents'),
  trio(11, 'streetMaxCents'),
  corner(8, 'cornerMaxCents'),
  firstFour(8, 'cornerMaxCents'),
  line(5, 'lineMaxCents'),
  dozen(2, 'dozenMaxCents'),
  column(2, 'dozenMaxCents'),
  even(1, 'evenMaxCents');

  const RouletteSpotType(this.payout, this.limitKey);

  /// "X to 1".
  final int payout;

  /// Key of the per-spot cap in `limits.extra`.
  final String limitKey;
}

@immutable
class RouletteSpot {
  const RouletteSpot(this.id, this.type, this.numbers);
  final String id;
  final RouletteSpotType type;

  /// Covered numbers, ascending.
  final List<int> numbers;
  bool covers(int n) => numbers.contains(n);

  @override
  String toString() => 'RouletteSpot($id)';
}

const kEvenSpots = ['red', 'black', 'odd', 'even', 'low', 'high'];

Map<String, RouletteSpot> _buildSpots() {
  final m = <String, RouletteSpot>{};
  void add(String id, RouletteSpotType t, List<int> numbers) => m[id] = RouletteSpot(id, t, List.unmodifiable([...numbers]..sort()));
  for (var n = 0; n <= 36; n++) {
    add('n$n', RouletteSpotType.straight, [n]);
  }
  for (final b in [1, 2, 3]) {
    add('sp0-$b', RouletteSpotType.split, [0, b]);
  }
  for (var a = 1; a <= 36; a++) {
    if (a % 3 != 0) add('sp$a-${a + 1}', RouletteSpotType.split, [a, a + 1]);
    if (a + 3 <= 36) add('sp$a-${a + 3}', RouletteSpotType.split, [a, a + 3]);
  }
  for (var a = 1; a <= 34; a += 3) {
    add('st$a', RouletteSpotType.street, [a, a + 1, a + 2]);
  }
  add('tr0-1-2', RouletteSpotType.trio, [0, 1, 2]);
  add('tr0-2-3', RouletteSpotType.trio, [0, 2, 3]);
  for (var a = 1; a <= 32; a++) {
    if (a % 3 != 0) add('co$a', RouletteSpotType.corner, [a, a + 1, a + 3, a + 4]);
  }
  add('first4', RouletteSpotType.firstFour, [0, 1, 2, 3]);
  for (var a = 1; a <= 31; a += 3) {
    add('ln$a', RouletteSpotType.line, [for (var i = 0; i < 6; i++) a + i]);
  }
  final all = [for (var n = 1; n <= 36; n++) n];
  for (final d in [1, 2, 3]) {
    add('dozen$d', RouletteSpotType.dozen, [for (var n = 12 * d - 11; n <= 12 * d; n++) n]);
  }
  for (final c in [1, 2, 3]) {
    add('col$c', RouletteSpotType.column, [for (final n in all) if ((n - c) % 3 == 0) n]);
  }
  add('red', RouletteSpotType.even, [...kRedNumbers]);
  add('black', RouletteSpotType.even, [for (final n in all) if (!kRedNumbers.contains(n)) n]);
  add('odd', RouletteSpotType.even, [for (final n in all) if (n.isOdd) n]);
  add('even', RouletteSpotType.even, [for (final n in all) if (n.isEven) n]);
  add('low', RouletteSpotType.even, [for (var n = 1; n <= 18; n++) n]);
  add('high', RouletteSpotType.even, [for (var n = 19; n <= 36; n++) n]);
  return Map.unmodifiable(m);
}

/// Every valid spot id (157).
final Map<String, RouletteSpot> kRouletteSpots = _buildSpots();

RouletteSpot? rouletteSpot(String id) => kRouletteSpots[id];

/// Return (stake included) of [cents] on [spot] for the drawn number [n].
int rouletteSpotReturn(RouletteSpot spot, int cents, int n, {bool shield = false}) {
  if (spot.covers(n)) return cents * (spot.type.payout + 1);
  if (shield && n == 0 && spot.type == RouletteSpotType.even) return cents ~/ 2;
  return 0;
}

@immutable
class RouletteOutcome {
  const RouletteOutcome(this.returnCents, this.wins);
  final int returnCents;
  final List<String> wins;
}

RouletteOutcome settleRouletteBoard(Map<String, int> board, int n, {bool shield = false}) {
  var ret = 0;
  final wins = <String>[];
  for (final e in board.entries) {
    final s = kRouletteSpots[e.key];
    if (s == null || e.value <= 0) continue;
    ret += rouletteSpotReturn(s, e.value, n, shield: shield);
    if (s.covers(n)) wins.add(e.key);
  }
  return RouletteOutcome(ret, wins);
}

/// Cap of one spot of [type] at a table with [limits].
int rouletteSpotCap(RouletteSpotType type, GameLimits limits) {
  final v = limits.extra[type.limitKey] ?? limits.maxBetCents;
  return v < limits.maxBetCents ? v : limits.maxBetCents;
}

int boardTotal(Map<String, int> b) => b.values.fold(0, (a, v) => a + v);

// ------------------------------------------------------------------- call bets --

/// French call bets (racetrack).
enum RouletteAnnounce { voisins, tiers, orphelins, jeuZero }

/// Units per spot of each call bet (`ANNOUNCES` of the engine).
const kAnnounces = <RouletteAnnounce, Map<String, int>>{
  RouletteAnnounce.voisins: {'tr0-2-3': 2, 'sp4-7': 1, 'sp12-15': 1, 'sp18-21': 1, 'sp19-22': 1, 'sp32-35': 1, 'co25': 2},
  RouletteAnnounce.tiers: {'sp5-8': 1, 'sp10-11': 1, 'sp13-16': 1, 'sp23-24': 1, 'sp27-30': 1, 'sp33-36': 1},
  RouletteAnnounce.orphelins: {'n1': 1, 'sp6-9': 1, 'sp14-17': 1, 'sp17-20': 1, 'sp31-34': 1},
  RouletteAnnounce.jeuZero: {'sp0-3': 1, 'sp12-15': 1, 'n26': 1, 'sp32-35': 1},
};

/// Board of a call bet with [unitCents] per chip.
Map<String, int> announceBoard(RouletteAnnounce a, int unitCents) => {for (final e in kAnnounces[a]!.entries) e.key: e.value * unitCents};

/// [n] and its [k] neighbours on each side of the wheel, in wheel order.
List<int> wheelNeighbours(int n, {int k = 2}) {
  final i = kWheelOrder.indexOf(n);
  if (i < 0) throw RangeError('not a roulette number: $n');
  return [for (var d = -k; d <= k; d++) kWheelOrder[(i + d + 37 * (k + 1)) % 37]];
}

/// "Voisins de n": 5 pleins.
Map<String, int> neighboursBoard(int n, int unitCents) => {for (final x in wheelNeighbours(n)) 'n$x': unitCents};

/// Numbers of a wheel sector (for the racetrack highlight).
List<int> announceNumbers(RouletteAnnounce a) {
  final s = <int>{};
  for (final id in kAnnounces[a]!.keys) {
    s.addAll(kRouletteSpots[id]!.numbers);
  }
  return s.toList()..sort();
}

// ------------------------------------------------------------------- fairness --

/// The number of a round from its revealed seed (`seededRng(seed).nextInt(37)`).
int rouletteNumberOf(String seed) => SeededRng(seed).nextInt(37);

/// Fairness check of a finished round: SHA-256(seed) = commitment, and the number recomputed from
/// the seed equals the published result.
FairnessVerdict verifyRouletteRound(GameRound round) {
  final f = round.fairness;
  if (f.seed.isEmpty || sha256Hex(f.seed) != f.commit.toLowerCase()) return FairnessVerdict.badCommit;
  final n = round.result['number'];
  if (n is! num || rouletteNumberOf(f.seed) != n.toInt()) return FairnessVerdict.badOrder;
  return FairnessVerdict.verified;
}

// ----------------------------------------------------------- hot / cold numbers --

/// The [count] most frequent numbers of [last] (oldest first), ties broken by the most recent.
List<int> hotNumbers(List<int> last, {int count = 4}) {
  if (last.isEmpty) return const [];
  final freq = <int, int>{};
  final recent = <int, int>{};
  for (var i = 0; i < last.length; i++) {
    freq[last[i]] = (freq[last[i]] ?? 0) + 1;
    recent[last[i]] = i;
  }
  final nums = freq.keys.toList()..sort((a, b) => freq[b] != freq[a] ? freq[b]!.compareTo(freq[a]!) : recent[b]!.compareTo(recent[a]!));
  return nums.take(count).toList();
}

/// The [count] least frequent numbers of the wheel in [last] (absent first), ties broken by the
/// longest absence.
List<int> coldNumbers(List<int> last, {int count = 4}) {
  if (last.isEmpty) return const [];
  final freq = <int, int>{for (var n = 0; n <= 36; n++) n: 0};
  final seen = <int, int>{for (var n = 0; n <= 36; n++) n: -1};
  for (var i = 0; i < last.length; i++) {
    if (!freq.containsKey(last[i])) continue;
    freq[last[i]] = freq[last[i]]! + 1;
    seen[last[i]] = i;
  }
  final nums = freq.keys.toList()..sort((a, b) => freq[a] != freq[b] ? freq[a]!.compareTo(freq[b]!) : seen[a] != seen[b] ? seen[a]!.compareTo(seen[b]!) : a.compareTo(b));
  return nums.take(count).toList();
}

// ------------------------------------------------------------------- board editor --

/// Why an edit was not (fully) applied.
enum BoardEditResult { ok, capped, roundLimit, nothing }

/// Client-side bet board with undo history. Every change produces the WHOLE board the client
/// sends with `setBets`; caps are applied like the server (`validateBoard`).
class RouletteBoardEditor {
  RouletteBoardEditor({required this.limits, Map<String, int> board = const {}}) : _board = {...board};

  GameLimits limits;
  Map<String, int> _board;
  final _history = <Map<String, int>>[];

  Map<String, int> get board => Map.unmodifiable(_board);
  int get total => boardTotal(_board);
  bool get canUndo => _history.isNotEmpty;
  bool get isEmpty => _board.isEmpty;

  /// Replaces the board without history (server state, new round).
  void reset(Map<String, int> board, {bool clearHistory = true}) {
    _board = {...board}..removeWhere((_, v) => v <= 0);
    if (clearHistory) _history.clear();
  }

  int capOf(String id) {
    final s = kRouletteSpots[id];
    return s == null ? 0 : rouletteSpotCap(s.type, limits);
  }

  /// Merges [add] (spot → cents) into the board, each spot capped at its type's limit and the
  /// whole board at `maxRoundCents`. One undo step.
  BoardEditResult addAll(Map<String, int> add) {
    final next = {..._board};
    var capped = false;
    for (final e in add.entries) {
      if (e.value <= 0 || !kRouletteSpots.containsKey(e.key)) continue;
      final cap = capOf(e.key);
      final before = next[e.key] ?? 0;
      var v = before + e.value;
      if (v > cap) {
        v = cap - cap % 100;
        capped = true;
      }
      if (v < limits.minBetCents) continue;
      next[e.key] = v;
    }
    if (boardTotal(next) > limits.maxRoundCents) return BoardEditResult.roundLimit;
    if (mapEquals(next, _board)) return capped ? BoardEditResult.capped : BoardEditResult.nothing;
    _history.add(_board);
    _board = next;
    return capped ? BoardEditResult.capped : BoardEditResult.ok;
  }

  BoardEditResult add(String id, int cents) => addAll({id: cents});

  /// Takes the chips off one spot (one undo step).
  bool remove(String id) {
    if (!_board.containsKey(id)) return false;
    _history.add(_board);
    _board = {..._board}..remove(id);
    return true;
  }

  bool undo() {
    if (_history.isEmpty) return false;
    _board = _history.removeLast();
    return true;
  }

  bool clear() {
    if (_board.isEmpty) return false;
    _history.add(_board);
    _board = {};
    return true;
  }

  /// "Rejouer": the previous round's board, added to what is already there.
  BoardEditResult repeat(Map<String, int> previous) => previous.isEmpty ? BoardEditResult.nothing : addAll(previous);

  /// "Doubler": every bet twice (capped per spot; refused above the round limit).
  BoardEditResult double() => _board.isEmpty ? BoardEditResult.nothing : addAll({..._board});
}
