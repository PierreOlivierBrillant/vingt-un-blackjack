// Baccarat trend boards (Bead Plate, Big Road with ties and dragon tails,
// Big Eye Boy) and the client-side rules/payouts of the model.
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/features/games/baccarat/baccarat_model.dart';
import 'package:vingtun/features/games/baccarat/baccarat_roads.dart';

List<BaccaratBead> seq(String s) => [
      for (final ch in s.split(''))
        BaccaratBead(
          winner: switch (ch) {
            'B' => BaccaratWinner.banker,
            'P' => BaccaratWinner.player,
            _ => BaccaratWinner.tie,
          },
        ),
    ];

List<(int, int)> at(BigRoad r) => [for (final c in r.cells) (c.col, c.row)];

void main() {
  group('Bead Plate', () {
    test('one cell per coup, column by column, 6 rows', () {
      final cells = beadPlate(seq('BPTBBPPB'));
      expect([for (final c in cells) (c.col, c.row)], [(0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (1, 0), (1, 1)]);
      expect(cells[2].bead.winner, BaccaratWinner.tie);
    });

    test('winning total of a bead', () {
      expect(const BaccaratBead(winner: BaccaratWinner.player, player: 8, banker: 3).winningTotal, 8);
      expect(const BaccaratBead(winner: BaccaratWinner.banker, player: 2, banker: 6).winningTotal, 6);
    });
  });

  group('Big Road', () {
    test('a new column at each change of winner; ties counted on the previous cell', () {
      final r = bigRoad(seq('BBBPPTB'));
      expect(at(r), [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (2, 0)]);
      expect([for (final c in r.cells) c.ties], [0, 0, 0, 0, 1, 0]);
      expect(r.columns, [3, 2, 1]);
      expect(r.width, 3);
    });

    test('ties opening the shoe are shown on the first cell', () {
      final r = bigRoad(seq('TTBT'));
      expect(r.leadingTies, 2);
      expect(r.cells.single.ties, 3);
      expect(bigRoad(seq('TT')).cells, isEmpty);
      expect(bigRoad(seq('TT')).leadingTies, 2);
    });

    test('a streak longer than 6 turns right (dragon tail); the next streak starts after its first column', () {
      final r = bigRoad(seq('BBBPPBBBBBBBP'));
      expect(at(r), [
        (0, 0), (0, 1), (0, 2), //
        (1, 0), (1, 1), //
        (2, 0), (2, 1), (2, 2), (2, 3), (2, 4), (2, 5), (3, 5), //
        (3, 0),
      ]);
      expect(r.columns, [3, 2, 7, 1]);
    });

    test('a streak meeting an earlier tail turns right above it', () {
      final r = bigRoad(seq('BBBBBBBPPPPPPPB'));
      expect(at(r).sublist(7), [(1, 0), (1, 1), (1, 2), (1, 3), (1, 4), (2, 4), (3, 4), (2, 0)]);
    });

    test('pairs and naturals are kept on the cells', () {
      final r = bigRoad([
        const BaccaratBead(winner: BaccaratWinner.banker, bankerPair: true),
        const BaccaratBead(winner: BaccaratWinner.player, playerPair: true, natural: true),
      ]);
      expect([r.cells[0].bankerPair, r.cells[1].playerPair, r.cells[1].natural], [true, true, true]);
    });
  });

  group('Big Eye Boy', () {
    test('starts at the second cell of the second column; red when the pattern repeats', () {
      final r = bigRoad(seq('BBPPBB'));
      expect(derivedColors(r), [DerivedColor.red, DerivedColor.red, DerivedColor.red]);
    });

    test('blue when the cell to the left is empty but the one above it is not; red when both are empty', () {
      final r = bigRoad(seq('BPPPB'));
      expect(derivedColors(r), [DerivedColor.blue, DerivedColor.red, DerivedColor.blue]);
      final cells = bigEyeBoy(r);
      expect([for (final c in cells) (c.col, c.row)], [(0, 0), (1, 0), (2, 0)]);
    });

    test('without a second cell in column 2 it starts at column 3; nothing before', () {
      expect(derivedColors(bigRoad(seq('BP'))), isEmpty);
      expect(derivedColors(bigRoad(seq('BPB'))), [DerivedColor.red]); // columns 1 and 1: same length
      expect(derivedColors(bigRoad(seq('BBPB'))), [DerivedColor.blue]); // columns 2 and 1
    });

    test('a choppy shoe gives a red road (alternation is itself a pattern)', () {
      final colors = derivedColors(bigRoad(seq('BPBPBPBP')));
      expect(colors, everyElement(DerivedColor.red));
      expect(colors, hasLength(6));
    });
  });

  group('model rules (mirror of the server engine)', () {
    test('values, totals, burn counts, pairs', () {
      expect(['AS', '2H', '9C', 'TS', 'JH', 'QD', 'KC'].map(baccaratValue), [1, 2, 9, 0, 0, 0, 0]);
      expect(baccaratTotal(['9S', '8H']), 7);
      expect(['AS', '7D', 'TS', 'KC'].map(baccaratBurnCount), [1, 7, 10, 10]);
      expect(baccaratPair(['7H', '7S']), isTrue);
      expect(baccaratPair(['KH', 'QS']), isFalse);
    });

    test('the Banker drawing chart', () {
      const chart = {
        0: 'DDDDDDDDDD|D', 1: 'DDDDDDDDDD|D', 2: 'DDDDDDDDDD|D', 3: 'DDDDDDDDSD|D',
        4: 'SSDDDDDDSS|D', 5: 'SSSSDDDDSS|D', 6: 'SSSSSSDDSS|S', 7: 'SSSSSSSSSS|S',
      };
      for (final e in chart.entries) {
        for (var p = 0; p <= 9; p++) {
          expect(baccaratBankerDraws(e.key, p), e.value[p] == 'D', reason: 'banker ${e.key} vs $p');
        }
        expect(baccaratBankerDraws(e.key, null), e.value[11] == 'D');
      }
    });

    test('payouts: Banker 0.95:1 exact, ties push the main bets, tie 8:1, pairs 11:1, free commission', () {
      const banker = BaccaratCoup(player: ['2S', '3H'], banker: ['9S', 'KH'], playerTotal: 5, bankerTotal: 9, winner: BaccaratWinner.banker);
      expect(baccaratReturn({'banker': 700}, banker), 1365);
      expect(baccaratReturn({'banker': 700}, banker, freeCommission: true), 1400);
      expect(baccaratReturn({'player': 700, 'tie': 100}, banker), 0);
      const tie = BaccaratCoup(player: ['7S', '7H'], banker: ['KS', '7D'], playerTotal: 4, bankerTotal: 7, winner: BaccaratWinner.tie, playerPair: true);
      expect(baccaratReturn({'banker': 1000, 'player': 500, 'tie': 100, 'playerPair': 200, 'bankerPair': 100}, tie), 1000 + 500 + 900 + 2400);
    });

    test('parsing is tolerant', () {
      final t = BaccaratTable.fromDoc(const {'shoe': 'oops', 'beads': [{'w': 'B', 'p': 3, 'b': 7}, {'w': 'X'}, 5], 'coup': {'player': ['AS']}});
      expect(t.shoe.remaining, 416);
      expect(t.beads, hasLength(1));
      expect(t.coup, isNull);
      expect(BaccaratTable.fromDoc(const {}).beads, isEmpty);
    });
  });
}
