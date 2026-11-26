/// Trend boards of the baccarat ("roads"), derived from the coups of the
/// current shoe (`g.beads`, oldest first). Pure functions, unit-tested
/// (`test/unit/baccarat_roads_test.dart`):
///  * [beadPlate]: one cell per coup, 6 rows, filled column by column;
///  * [bigRoad]: ties never take a cell (counted on the previous cell, or
///    on the first one when the shoe opens with ties), a new column each
///    time the winner changes, a streak that hits the bottom row or an
///    occupied cell turns right ("dragon tail");
///  * [bigEyeBoy]: the first derived road (red = the Big Road repeats its
///    pattern, blue = it breaks it), compared one column back.
library;

import 'package:flutter/foundation.dart';

import 'baccarat_model.dart';

const kRoadRows = 6;

@immutable
class BeadCell {
  const BeadCell({required this.col, required this.row, required this.bead});
  final int col;
  final int row;
  final BaccaratBead bead;
}

/// Bead Plate: coup i → column i ~/ 6, row i % 6.
List<BeadCell> beadPlate(List<BaccaratBead> beads) => [
      for (var i = 0; i < beads.length; i++) BeadCell(col: i ~/ kRoadRows, row: i % kRoadRows, bead: beads[i]),
    ];

/// One Big Road cell: a Player or Banker win (ties are counted on it).
@immutable
class RoadCell {
  const RoadCell({
    required this.col,
    required this.row,
    required this.winner,
    this.ties = 0,
    this.playerPair = false,
    this.bankerPair = false,
    this.natural = false,
    required this.logicalCol,
    required this.depth,
  });
  final int col;
  final int row;

  /// player or banker (never tie).
  final BaccaratWinner winner;

  /// Ties that followed this coup (shown as a green slash with the count).
  final int ties;
  final bool playerPair;
  final bool bankerPair;
  final bool natural;

  /// Index of the streak (column before any dragon tail) and position in it.
  final int logicalCol;
  final int depth;

  RoadCell withTie() => RoadCell(
        col: col, row: row, winner: winner, ties: ties + 1, playerPair: playerPair, bankerPair: bankerPair, natural: natural,
        logicalCol: logicalCol, depth: depth,
      );

  @override
  String toString() => '${winner == BaccaratWinner.banker ? 'B' : 'P'}($col,$row${ties > 0 ? ' +$ties' : ''})';
}

@immutable
class BigRoad {
  const BigRoad({required this.cells, required this.leadingTies, required this.columns});

  final List<RoadCell> cells;

  /// Ties before the first Player / Banker win of the shoe.
  final int leadingTies;

  /// Length of each streak (logical column), used by the derived roads.
  final List<int> columns;

  int get width => cells.isEmpty ? 0 : cells.map((c) => c.col).reduce((a, b) => a > b ? a : b) + 1;
}

/// Places a sequence of streak labels on a 6-row grid with dragon tails.
/// [labels] is the sequence of values; a new streak starts when the value
/// changes. Returns (col, row, logicalCol, depth) for each entry.
List<(int col, int row, int logical, int depth)> placeStreaks<T>(List<T> labels, {int rows = kRoadRows}) {
  final out = <(int, int, int, int)>[];
  final taken = <(int, int)>{};
  var logical = -1;
  var startCol = -1;
  var col = 0, row = 0, depth = 0;
  var turned = false;
  T? last;
  for (var i = 0; i < labels.length; i++) {
    final v = labels[i];
    if (i == 0 || v != last) {
      logical++;
      startCol++;
      while (taken.contains((startCol, 0))) {
        startCol++;
      }
      col = startCol;
      row = 0;
      depth = 0;
      turned = false;
    } else {
      depth++;
      if (!turned && row + 1 < rows && !taken.contains((col, row + 1))) {
        row++;
      } else {
        turned = true;
        col++;
      }
    }
    taken.add((col, row));
    out.add((col, row, logical, depth));
    last = v;
  }
  return out;
}

BigRoad bigRoad(List<BaccaratBead> beads) {
  final wins = <BaccaratBead>[];
  final ties = <int>[];
  var leading = 0;
  for (final b in beads) {
    if (b.winner == BaccaratWinner.tie) {
      if (wins.isEmpty) {
        leading++;
      } else {
        ties[ties.length - 1]++;
      }
    } else {
      wins.add(b);
      ties.add(0);
    }
  }
  final pos = placeStreaks([for (final w in wins) w.winner]);
  final cells = <RoadCell>[
    for (var i = 0; i < wins.length; i++)
      RoadCell(
        col: pos[i].$1,
        row: pos[i].$2,
        winner: wins[i].winner,
        ties: ties[i] + (i == 0 ? leading : 0),
        playerPair: wins[i].playerPair,
        bankerPair: wins[i].bankerPair,
        natural: wins[i].natural,
        logicalCol: pos[i].$3,
        depth: pos[i].$4,
      ),
  ];
  final columns = <int>[];
  for (final c in cells) {
    if (c.logicalCol >= columns.length) columns.add(0);
    columns[c.logicalCol]++;
  }
  return BigRoad(cells: cells, leadingTies: leading, columns: columns);
}

enum DerivedColor { red, blue }

@immutable
class DerivedCell {
  const DerivedCell({required this.col, required this.row, required this.color});
  final int col;
  final int row;
  final DerivedColor color;
  @override
  String toString() => '${color == DerivedColor.red ? 'R' : 'B'}($col,$row)';
}

/// The colours of a derived road comparing [k] columns back (1 = Big Eye
/// Boy, 2 = Small Road, 3 = Cockroach Pig), from the Big Road's streaks.
List<DerivedColor> derivedColors(BigRoad road, {int k = 1}) {
  final cols = road.columns;
  final out = <DerivedColor>[];
  for (final c in road.cells) {
    final lc = c.logicalCol;
    final r = c.depth;
    // The road starts at (column k, row 1), or (column k + 1, row 0) if that cell never exists.
    if (lc < k || (lc == k && r == 0)) continue;
    if (r == 0) {
      out.add(cols[lc - 1] == cols[lc - 1 - k] ? DerivedColor.red : DerivedColor.blue);
    } else {
      final left = cols[lc - k];
      out.add(left >= r + 1 ? DerivedColor.red : left == r ? DerivedColor.blue : DerivedColor.red);
    }
  }
  return out;
}

/// Big Eye Boy cells (same grid rules as the Big Road).
List<DerivedCell> bigEyeBoy(BigRoad road) {
  final colors = derivedColors(road);
  final pos = placeStreaks(colors);
  return [for (var i = 0; i < colors.length; i++) DerivedCell(col: pos[i].$1, row: pos[i].$2, color: colors[i])];
}
