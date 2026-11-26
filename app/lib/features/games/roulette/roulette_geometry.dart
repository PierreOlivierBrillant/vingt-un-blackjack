/// Logical layout of the roulette stage (1000 × 1300 units) and the two tactile surfaces shared
/// by the stage and the betting panel: the betting layout ([RouletteLayout], hit-testing every one
/// of the 157 spots: pleins, chevaux on the edges, carrés on the corners, transversales and
/// sixains on the bottom line, trios / premier quatre on the zero's edge) and the racetrack
/// ([RouletteRacetrack]: wheel order, sectors of the call bets).
library;

import 'dart:math' as math;
import 'dart:ui';

import '../../stage/stage_geometry.dart';
import 'roulette_engine.dart';

class RouletteGeometry extends StageGeometry {
  const RouletteGeometry();

  /// A little shorter than the default stage: the betting panel needs room on small phones.
  @override
  Size get size => const Size(1000, 1150);

  @override
  int get seatCount => 7;

  /// Players sit along the bottom of the table, below the betting layout.
  @override
  List<Offset> get seatSpots => StageGeometry.arcSeats(7, center: const Offset(500, 935), radiusX: 440, radiusY: 165, fromDeg: 14, toDeg: 166);

  /// Centre of the wheel (to the croupier's right, like a real table).
  Offset get wheelCenter => const Offset(200, 472);
  double get wheelRadius => 168;

  /// The betting layout painted on the felt (every player's chips).
  Rect get layoutRect => const Rect.fromLTRB(24, 664, 976, 960);
  RouletteLayout get layout => RouletteLayout(layoutRect);

  /// Where the croupier keeps the house chips (losing chips go there, payouts come from it).
  Offset get bank => const Offset(560, 588);

  /// Where the dolly waits between two spins.
  Offset get dollyRest => const Offset(650, 584);

  /// Score board (history, hot / cold numbers).
  Rect get marquee => const Rect.fromLTRB(672, 326, 984, 630);

  /// Chips of a player go back to here (in front of the seat).
  Offset seatPocket(int seat) => seatSpots[seat] + const Offset(0, 40);
}

/// The French/European betting layout inside [rect]: the zero on the left, 12 columns of 3
/// numbers (top row 3, 6 … 36), the three "2:1" column bets on the right, the dozens and the six
/// even chances below.
class RouletteLayout {
  RouletteLayout(this.rect)
      : _col = rect.width / 13.9,
        _row = rect.height / (3 + 2 * 0.72);

  final Rect rect;
  final double _col;
  final double _row;

  double get colWidth => _col;
  double get rowHeight => _row;
  double get _zeroW => _col * 0.9;
  double get _rowSmall => _row * 0.72;

  /// The 3 × 12 number grid.
  Rect get gridRect => Rect.fromLTWH(rect.left + _zeroW, rect.top, _col * 12, _row * 3);
  Rect get zeroRect => Rect.fromLTWH(rect.left, rect.top, _zeroW, _row * 3);

  /// Column (0..11) and row (0 = top) of a number 1..36.
  (int, int) cellOf(int n) => ((n - 1) ~/ 3, 2 - (n - 1) % 3);
  int numberAt(int col, int row) => col * 3 + (3 - row);

  Rect cellRect(int n) {
    if (n == 0) return zeroRect;
    final (c, r) = cellOf(n);
    return Rect.fromLTWH(gridRect.left + c * _col, rect.top + r * _row, _col, _row);
  }

  /// "2:1" cell of column bet c (1 = bottom row 1, 4 … 34; 3 = top row).
  Rect columnRect(int c) => Rect.fromLTWH(gridRect.right, rect.top + (3 - c) * _row, rect.right - gridRect.right, _row);
  Rect dozenRect(int d) => Rect.fromLTWH(gridRect.left + (d - 1) * 4 * _col, gridRect.bottom, 4 * _col, _rowSmall);

  /// Even chances left to right: manque, pair, rouge, noir, impair, passe.
  static const evenOrder = ['low', 'even', 'red', 'black', 'odd', 'high'];
  Rect evenRect(String id) {
    final i = evenOrder.indexOf(id);
    return Rect.fromLTWH(gridRect.left + i * 2 * _col, gridRect.bottom + _rowSmall, 2 * _col, _rowSmall);
  }

  /// Where the chips of [id] sit.
  Offset spotCenter(String id) {
    final s = rouletteSpot(id);
    if (s == null) return rect.center;
    final g = gridRect;
    switch (s.type) {
      case RouletteSpotType.straight:
        return cellRect(s.numbers.first).center;
      case RouletteSpotType.split:
      case RouletteSpotType.corner:
        if (s.numbers.first == 0) return Offset(g.left, cellRect(s.numbers.last).center.dy);
        return _mean([for (final n in s.numbers) cellRect(n).center]);
      case RouletteSpotType.street:
        return Offset(cellRect(s.numbers.first).center.dx, g.bottom);
      case RouletteSpotType.line:
        return Offset(cellRect(s.numbers.first).right, g.bottom);
      case RouletteSpotType.trio:
        return Offset(g.left, id == 'tr0-1-2' ? rect.top + 2 * _row : rect.top + _row);
      case RouletteSpotType.firstFour:
        return Offset(g.left, g.bottom);
      case RouletteSpotType.dozen:
        return dozenRect(int.parse(id.substring(5))).center;
      case RouletteSpotType.column:
        return columnRect(int.parse(id.substring(3))).center;
      case RouletteSpotType.even:
        return evenRect(id).center;
    }
  }

  static Offset _mean(List<Offset> l) => l.fold(Offset.zero, (a, b) => a + b) / l.length.toDouble();

  /// Edge band (fraction of a cell) that selects a cheval / carré / transversale instead of a plein.
  static const edge = 0.24;

  /// The spot under [p] (null outside the layout).
  String? spotAt(Offset p) {
    if (!rect.inflate(_row * 0.05).contains(p)) return null;
    final g = gridRect;
    if (p.dx < g.left - _col * edge * 0.6) return p.dy <= g.bottom ? 'n0' : null;
    if (p.dx >= g.right + _col * edge * 0.6) {
      return p.dy < g.bottom ? 'col${3 - ((p.dy - rect.top) / _row).floor().clamp(0, 2)}' : null;
    }
    if (p.dy > g.bottom + _row * edge * 0.6) {
      final x = ((p.dx - g.left) / _col).clamp(0.0, 11.999);
      if (p.dy < g.bottom + _rowSmall) return 'dozen${x ~/ 4 + 1}';
      return evenOrder[(x ~/ 2).clamp(0, 5)];
    }
    // Inside (or on the border of) the number grid.
    final fx = (p.dx - g.left) / _col;
    final fy = (p.dy - g.top) / _row;
    var col = fx.floor().clamp(0, 11);
    var row = fy.floor().clamp(0, 2);
    final ux = fx - col, uy = fy - row;
    // Neighbour across the nearest edge: h = -1 left / +1 right, v = -1 above / +1 below.
    var h = 0, v = 0;
    if (ux < edge) {
      h = -1;
    } else if (ux > 1 - edge && col < 11) {
      h = 1;
    }
    final bottomLine = fy > 3 - edge;
    if (!bottomLine) {
      if (uy < edge && row > 0) {
        v = -1;
      } else if (uy > 1 - edge && row < 2) {
        v = 1;
      }
    }
    if (h == -1 && col == 0) {
      // The zero's edge: chevaux with 0, trios, premier quatre.
      if (bottomLine) return 'first4';
      final n = numberAt(0, row);
      if (v == 0) return 'sp0-$n';
      final pair = [n, numberAt(0, row + v)]..sort();
      return pair[0] == 1 ? 'tr0-1-2' : 'tr0-2-3';
    }
    if (h == -1) {
      col -= 1; // the boundary is between col and col + 1
      h = 1;
    }
    if (bottomLine) return h == 1 ? 'ln${col * 3 + 1}' : 'st${col * 3 + 1}';
    if (v == -1) {
      row -= 1; // the boundary is between row and row + 1
      v = 1;
    }
    final a = numberAt(col, row);
    if (h == 0 && v == 0) return 'n$a';
    if (v == 0) return 'sp$a-${a + 3}';
    if (h == 0) return 'sp${a - 1}-$a';
    return 'co${a - 1}';
  }
}

/// The racetrack (wheel order around a stadium) inside [rect]: the zero on the right end, the
/// tiers on the left; inner zones TIERS · ORPHELINS · VOISINS · ZÉRO.
class RouletteRacetrack {
  RouletteRacetrack(this.rect);
  final Rect rect;

  double get band => rect.height * 0.3;
  double get _r => rect.height / 2;

  /// Point at [f] ∈ [0, 1) of the centre line of the band (0 = middle of the right end, then
  /// clockwise on screen).
  Offset pointAt(double f) {
    final r = _r - band / 2;
    final straight = rect.width - 2 * _r;
    final arc = math.pi * r;
    final total = 2 * straight + 2 * arc;
    var d = (f % 1) * total;
    final cr = Offset(rect.right - _r, rect.center.dy), cl = Offset(rect.left + _r, rect.center.dy);
    if (d < arc / 2) return cr + Offset(math.cos(d / r), math.sin(d / r)) * r;
    d -= arc / 2;
    if (d < straight) return Offset(cr.dx - d, rect.center.dy + r);
    d -= straight;
    if (d < arc) {
      final a = math.pi / 2 + d / r;
      return cl + Offset(math.cos(a), math.sin(a)) * r;
    }
    d -= arc;
    if (d < straight) return Offset(cl.dx + d, rect.center.dy - r);
    d -= straight;
    final a = -math.pi / 2 + d / r;
    return cr + Offset(math.cos(a), math.sin(a)) * r;
  }

  Offset numberCenter(int n) => pointAt(kWheelOrder.indexOf(n) / 37);

  /// Length of one number cell along the track.
  double get cellSize => (2 * (rect.width - 2 * _r) + 2 * math.pi * (_r - band / 2)) / 37;

  /// Inner area (inside the band).
  RRect get inner => RRect.fromRectAndRadius(rect.deflate(band), Radius.circular(_r - band));

  static const sectors = [RouletteAnnounce.tiers, RouletteAnnounce.orphelins, RouletteAnnounce.voisins, RouletteAnnounce.jeuZero];

  /// Rect of an inner zone.
  Rect sectorRect(RouletteAnnounce a) {
    final r = rect.deflate(band);
    final w = r.width / 4;
    return Rect.fromLTWH(r.left + sectors.indexOf(a) * w, r.top, w, r.height);
  }

  /// Number of the track under [p] (null inside or outside the band).
  int? numberAt(Offset p) {
    if (!rect.contains(p) || inner.contains(p)) return null;
    var best = 0;
    var bestD = double.infinity;
    for (final n in kWheelOrder) {
      final d = (numberCenter(n) - p).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  RouletteAnnounce? sectorAt(Offset p) {
    if (!inner.contains(p)) return null;
    for (final a in sectors) {
      if (sectorRect(a).contains(p)) return a;
    }
    return null;
  }
}
