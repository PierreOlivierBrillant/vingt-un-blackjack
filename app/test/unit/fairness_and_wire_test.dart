import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/cards.dart';
import 'package:vingtun/domain/fairness.dart';
import 'package:vingtun/domain/table_state.dart';
import 'package:vingtun/domain/wire.dart';

void main() {
  group('card codes: backend "TH" ↔ client "10H"', () {
    test('the ten is spelled T on the wire and 10 on screen', () {
      final c = cardFromWire('TH');
      expect(c, const PlayingCard(Rank.ten, Suit.hearts));
      expect(c.code, '10H');
      expect(cardToWire(c), 'TH');
    });

    test('every card of a deck round-trips through the backend format', () {
      for (final code in buildWireShoe(1)) {
        expect(cardToWire(cardFromWire(code)), code);
      }
      expect(buildWireShoe(1).toSet(), hasLength(52));
    });

    test('lenient on "10H" and case, strict on garbage', () {
      expect(cardFromWire('10h'), const PlayingCard(Rank.ten, Suit.hearts));
      expect(cardFromWire(' qs '), const PlayingCard(Rank.queen, Suit.spades));
      for (final bad in ['', 'T', '1H', '11S', 'TX', 'ZZ', 'AH1']) {
        expect(() => cardFromWire(bad), throwsFormatException, reason: bad);
        expect(cardFromWireOrNull(bad), isNull);
      }
      expect(cardFromWireOrNull(42), isNull);
    });

    test('table documents with T tens parse into ten cards; bad codes are skipped', () {
      final t = TableState.fromDoc('x', {
        'seats': [
          {'seatIndex': 0, 'uid': 'u', 'hands': [
            {'cards': ['TH', 'TS', '??'], 'total': 20},
          ]},
        ],
        'dealer': {'cards': ['TD'], 'holeHidden': true},
        'events': [
          {'seq': 1, 'type': 'deal', 'card': 'TC', 'atMs': 1},
          {'seq': 2, 'type': 'dealerHole', 'card': null, 'atMs': 2},
        ],
      });
      expect(t.seats[0]!.hands.single.cards.map((c) => c.code), ['10H', '10S']);
      expect(t.dealer.cards.single.rank, Rank.ten);
      expect(t.events.first.card!.code, '10C');
      expect(t.events.last.card, isNull);
    });

    test('peek doc: "TC" hole card', () {
      expect(PeekResult.fromDoc({'handNumber': 3, 'holeCard': 'TC'})!.holeCard, const PlayingCard(Rank.ten, Suit.clubs));
      expect(PeekResult.fromDoc({'handNumber': 3, 'holeCard': 'XX'}), isNull);
    });
  });

  group('provably fair verifier (vector computed by the backend, fair.ts)', () {
    const seed = 'a3f1c2d4e5b60718293a4b5c6d7e8f90112233445566778899aabbccddeeff00';
    const commit = '1309f953015195d9eadc0455c1e42a5cfc463d4cad90c0cc940ff77b5f1633bd';
    // remaining = buildShoe(6).filter((_, i) => i % 3 !== 0).slice(0, 120).reverse()
    final shoe = buildWireShoe(6);
    final remaining = [for (var i = 0; i < shoe.length; i++) if (i % 3 != 0) shoe[i]].take(120).toList().reversed.toList();
    const dealt = ['8S', '2S', '6H', '5S', '8S', '2D', 'JD', '8S', '9H', 'KC', '8C', 'QD'];

    test('SHA-256 commitment', () => expect(sha256Hex(seed), commit));

    test('same deal order as the server, refill included', () {
      final order = fairDealOrder(remaining, seed);
      expect(order.take(12), dealt);
      expect(order.skip(remaining.length).take(5), ['4S', 'QS', 'QH', '8S', 'TH']);
      expect(order.length, remaining.length + 312);
    });

    test('verdicts', () {
      expect(verifyFairness(commit: commit, seed: seed, remainingBefore: remaining, dealt: dealt), FairnessVerdict.verified);
      expect(verifyFairness(commit: commit.toUpperCase(), seed: seed, remainingBefore: remaining, dealt: dealt),
          FairnessVerdict.verified);
      expect(verifyFairness(commit: commit, seed: '${seed}0', remainingBefore: remaining, dealt: dealt), FairnessVerdict.badCommit);
      expect(verifyFairness(commit: commit, seed: seed, remainingBefore: remaining, dealt: [...dealt.take(11), 'AS']),
          FairnessVerdict.badOrder);
      // The order of `remainingBefore` does not matter (canonicalised).
      expect(verifyFairness(commit: commit, seed: seed, remainingBefore: remaining.reversed.toList(), dealt: dealt),
          FairnessVerdict.verified);
    });

    test('DRBG rejects bad bounds and is deterministic', () {
      expect(() => SeededRng('x').nextInt(0), throwsRangeError);
      final a = [for (var i = 0; i < 20; i++) SeededRng('s').nextInt(52)];
      expect(a.toSet(), hasLength(1));
      final r = SeededRng('s');
      expect([for (var i = 0; i < 20; i++) r.nextInt(1)], everyElement(0));
    });
  });
}
