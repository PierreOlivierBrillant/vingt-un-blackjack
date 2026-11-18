import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/cards.dart';
import 'package:vingtun/features/cards/chips.dart';
import 'package:vingtun/features/dealer/ik.dart';

List<PlayingCard> h(String codes) => codes.split(' ').map(PlayingCard.parse).toList();

void main() {
  group('PlayingCard', () {
    test('parses wire codes', () {
      expect(PlayingCard.parse('AS'), const PlayingCard(Rank.ace, Suit.spades));
      expect(PlayingCard.parse('10h'), const PlayingCard(Rank.ten, Suit.hearts));
      expect(PlayingCard.parse('TD'), const PlayingCard(Rank.ten, Suit.diamonds));
      expect(PlayingCard.parse('QC').code, 'QC');
    });
    test('rejects bad codes', () {
      expect(() => PlayingCard.parse('1S'), throwsFormatException);
      expect(() => PlayingCard.parse('AX'), throwsFormatException);
      expect(() => PlayingCard.parse('A'), throwsFormatException);
    });
  });

  group('handTotal', () {
    test('soft and hard totals', () {
      expect(handTotal(h('AS 6D')).total, 17);
      expect(handTotal(h('AS 6D')).soft, isTrue);
      expect(handTotal(h('AS 6D 10C')).total, 17);
      expect(handTotal(h('AS 6D 10C')).soft, isFalse);
      expect(handTotal(h('AS AD')).total, 12);
      expect(handTotal(h('AS AD AC AH 7S')).total, 21);
      expect(handTotal(h('KS QD 5C')).isBust, isTrue);
    });
    test('natural blackjack only with two cards', () {
      expect(isNaturalBlackjack(h('AS KD')), isTrue);
      expect(isNaturalBlackjack(h('7S 7D 7C')), isFalse);
    });
  });

  group('chipsFor', () {
    test('greedy decomposition sums to the amount', () {
      final chips = chipsFor(3750);
      expect(chips.fold<int>(0, (a, c) => a + c.cents), 3700); // .50 not representable
      expect(chipsFor(12600).map((c) => c.cents), [10000, 2500, 100]);
    });
  });

  group('two-bone IK', () {
    const s = Offset(0, 0);
    test('reachable target: hand on target, bone lengths preserved', () {
      const t = Offset(120, 160);
      final r = solveTwoBone(s, t, 150, 150);
      expect(r.reached, isTrue);
      expect((r.hand - t).distance, lessThan(1e-6));
      expect((r.elbow - s).distance, closeTo(150, 1e-6));
      expect((r.hand - r.elbow).distance, closeTo(150, 1e-6));
    });
    test('bend direction flips the elbow side', () {
      const t = Offset(0, 200);
      final a = solveTwoBone(s, t, 150, 150, bendPositive: true);
      final b = solveTwoBone(s, t, 150, 150, bendPositive: false);
      expect(a.elbow.dx.sign, -b.elbow.dx.sign);
      expect(a.elbow.dy, closeTo(b.elbow.dy, 1e-9));
    });
    test('unreachable target: arm fully extended toward it', () {
      const t = Offset(0, 1000);
      final r = solveTwoBone(s, t, 150, 150);
      expect(r.reached, isFalse);
      expect(r.hand.dx, closeTo(0, 1e-6));
      expect(r.hand.dy, closeTo(300, 1e-3));
    });
    test('clampToReach and bezier helpers', () {
      expect(clampToReach(s, const Offset(0, 50), 100), const Offset(0, 50));
      expect(clampToReach(s, const Offset(0, 500), 100), const Offset(0, 100));
      expect(quadBezier(const Offset(0, 0), const Offset(50, 100), const Offset(100, 0), 0), Offset.zero);
      expect(quadBezier(const Offset(0, 0), const Offset(50, 100), const Offset(100, 0), 0.5), const Offset(50, 50));
    });
  });
}
