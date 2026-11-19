import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/cards.dart';
import 'package:vingtun/domain/table_state.dart';
import 'package:vingtun/features/dealer/dealer_controller.dart';
import 'package:vingtun/features/table/table_director.dart';

import '../table_fixtures.dart';

TableState snap(Map<String, Object?> d) => TableState.fromDoc('tbl', d);

List<String> codes(DealerController c, HandTarget t) => [for (final x in c.cardsFor(t)) x.card?.code ?? '??'];

void main() {
  late DealerController dealer;
  late TableDirector director;
  var now = DateTime.fromMillisecondsSinceEpoch(kT0);

  setUp(() {
    now = DateTime.fromMillisecondsSinceEpoch(kT0);
    dealer = DealerController();
    director = TableDirector(dealer, now: () => now);
  });
  tearDown(() => dealer.dispose());

  /// Animation commands queued by [f] only (feedback cues are checked by
  /// the sound tests).
  List<String> queuedBy(void Function() f) {
    final before = dealer.pendingCommands.length;
    f();
    return [for (final c in dealer.pendingCommands.skip(before)) if (c is! CueCommand) c.toString()];
  }

  group('first snapshot → instant rebuild from the state', () {
    test('betting: chips placed, nothing left to animate', () {
      director.apply(snap(tableDoc(seats: [seatDoc(0, 'me', bet: 1000)], events: [ev(1, 'bet', seat: 0, amount: 1000)])));
      expect(dealer.pendingCommands, isEmpty);
      expect(dealer.chipStacks.single.cents, 1000);
      expect(director.lastSeq, 1);
    });

    test('mid-hand with split hands and a hidden hole card', () {
      director.apply(snap(tableDoc(
        phase: 'playerTurns',
        seats: [
          seatDoc(0, 'me', bet: 1000, hands: [
            handDoc(['8S', '3D'], fromSplit: true),
            handDoc(['8H', 'TD'], fromSplit: true),
          ]),
          seatDoc(1, 'b', bet: 500, bot: true, hands: [handDoc(['AS', 'KC'], bet: 500)]),
        ],
        dealerCards: ['7D'],
        holeHidden: true,
        turn: {'seatIndex': 0, 'handIndex': 1},
        deadlineMs: kT0 + 15000,
        eventSeq: 40,
      )));
      // Only the turn ring is queued; the scene itself is already in place.
      expect(dealer.pendingCommands.map((c) => c.toString()), ['turn(seat0)']);
      expect(dealer.handCount(0), 2);
      expect(codes(dealer, const HandTarget.seat(0)), ['8S', '3D']);
      expect(codes(dealer, const HandTarget.seat(0, hand: 1)), ['8H', '10D']);
      expect(codes(dealer, const HandTarget.seat(1)), ['AS', 'KC']);
      expect(codes(dealer, const HandTarget.dealer()), ['7D', '??']);
      expect(dealer.cardsFor(const HandTarget.dealer()).last.faceUp, isFalse);
      expect(dealer.chipStacks.where((s) => s.seat == 0).map((s) => s.cents), [1000, 1000]);
    });

    test('settled hand shows its result badges', () {
      director.apply(snap(tableDoc(
        phase: 'settled',
        seats: [
          seatDoc(0, 'me', bet: 1000, net: 1500, hands: [handDoc(['AS', 'KC'], done: true, result: 'blackjack', ret: 2500)]),
        ],
        dealerCards: ['9D', '8C'],
        eventSeq: 12,
      )));
      expect(dealer.badges[(0, 0)], SeatBadge.blackjack);
      expect(codes(dealer, const HandTarget.dealer()), ['9D', '8C']);
    });
  });

  test('a full hand is animated event by event, in order', () {
    final seats0 = [seatDoc(0, 'me', bet: 1000), seatDoc(1, 'b', bot: true)];
    director.apply(snap(tableDoc(seats: seats0, events: [ev(1, 'bet', seat: 0, amount: 1000)], deadlineMs: kT0 + 15000)));
    expect(dealer.pendingCommands, isEmpty);

    // Deal.
    final dealEvents = [
      ev(1, 'bet', seat: 0, amount: 1000),
      ev(2, 'bet', seat: 1, amount: 500),
      ev(3, 'deal', seat: 0, hand: 0, card: 'TH'),
      ev(4, 'deal', seat: 1, hand: 0, card: '9C'),
      ev(5, 'dealerUp', card: '7D'),
      ev(6, 'deal', seat: 0, hand: 0, card: '6S'),
      ev(7, 'deal', seat: 1, hand: 0, card: '9H'),
      ev(8, 'dealerHole'),
    ];
    final dealt = queuedBy(() => director.apply(snap(tableDoc(
          phase: 'playerTurns',
          seats: [
            seatDoc(0, 'me', bet: 1000, hands: [handDoc(['TH', '6S'])]),
            seatDoc(1, 'b', bot: true, bet: 500, hands: [handDoc(['9C', '9H'], bet: 500)]),
          ],
          dealerCards: ['7D'],
          holeHidden: true,
          turn: {'seatIndex': 0, 'handIndex': 0},
          deadlineMs: kT0 + 20000,
          events: dealEvents,
        ))));
    expect(dealt, [
      'bet(seat1/h0, 500)',
      'deal(10H -> seat0/h0)',
      'deal(9C -> seat1/h0)',
      'deal(7D -> dealer)',
      'deal(6S -> seat0/h0)',
      'deal(9H -> seat1/h0)',
      'deal(?? -> dealer)',
      'turn(seat0)',
    ]);

    // I hit and bust, the bot stands, the dealer reveals, draws, busts; settle.
    final settled = queuedBy(() => director.apply(snap(tableDoc(
          phase: 'settled',
          seats: [
            seatDoc(0, 'me', bet: 1000, net: -1000, hands: [handDoc(['TH', '6S', '9D'], done: true, result: 'bust', ret: 0)]),
            seatDoc(1, 'b', bot: true, bet: 500, net: 500, hands: [handDoc(['9C', '9H'], bet: 500, done: true, result: 'win', ret: 1000)]),
          ],
          dealerCards: ['7D', '5C', 'KC'],
          deadlineMs: kT0 + 26000,
          events: [
            ...dealEvents,
            ev(9, 'hit', seat: 0, hand: 0, card: '9D'),
            ev(10, 'stand', seat: 1, hand: 0),
            ev(11, 'reveal', card: '5C'),
            ev(12, 'dealerHit', card: 'KC'),
            ev(13, 'settle', seat: 0, hand: 0, result: 'bust', amount: 0),
            ev(14, 'settle', seat: 1, hand: 0, result: 'win', amount: 1000),
          ],
        ))));
    expect(settled, [
      'deal(9D -> seat0/h0)',
      'react(DealerReaction.bust seat0)',
      'reveal(5C)',
      'deal(KC -> dealer)',
      'react(DealerReaction.dealerBust)',
      'collectBet(seat0/h0)',
      'react(DealerReaction.win seat1)',
      'payout(seat1/h0, 500)',
      'turn(off)',
    ]);

    // Next hand: the table is swept first, then the new shoe and bets.
    final next = queuedBy(() => director.apply(snap(tableDoc(
          hand: 2,
          seats: [seatDoc(0, 'me'), seatDoc(1, 'b', bot: true, bet: 500)],
          deadlineMs: kT0 + 41000,
          events: [ev(15, 'shuffle'), ev(16, 'bet', seat: 1, amount: 500)],
        ))));
    expect(next, ['collectAll', 'shuffle', 'bet(seat1/h0, 500)']);
    expect(director.handNumber, 2);

    // Everything plays to the end without error.
    dealer.fastForward();
    expect(dealer.pendingCommands, isEmpty);
    expect(dealer.chipStacks.single.cents, 500);
  });

  test('split: the second card moves to a new hand, then both hands are dealt', () {
    final hands = [handDoc(['8S', '8H'])];
    director.apply(snap(tableDoc(
      phase: 'playerTurns',
      seats: [seatDoc(0, 'me', bet: 1000, hands: hands)],
      dealerCards: ['9D'],
      holeHidden: true,
      turn: {'seatIndex': 0, 'handIndex': 0},
      eventSeq: 10,
    )));
    final q = queuedBy(() => director.apply(snap(tableDoc(
          phase: 'playerTurns',
          seats: [
            seatDoc(0, 'me', bet: 1000, hands: [handDoc(['8S', '3D'], fromSplit: true), handDoc(['8H', 'KD'], fromSplit: true)]),
          ],
          dealerCards: ['9D'],
          holeHidden: true,
          turn: {'seatIndex': 0, 'handIndex': 0},
          events: [
            ev(11, 'split', seat: 0, hand: 0, amount: 1000),
            ev(12, 'deal', seat: 0, hand: 0, card: '3D'),
            ev(13, 'deal', seat: 0, hand: 1, card: 'KD'),
          ],
        ))));
    expect(q, ['split(seat0/h0)', 'deal(3D -> seat0/h0)', 'deal(KD -> seat0/h1)']);
    dealer.fastForward();
    expect(dealer.handCount(0), 2);
    expect(codes(dealer, const HandTarget.seat(0)), ['8S', '3D']);
    expect(codes(dealer, const HandTarget.seat(0, hand: 1)), ['8H', 'KD']);
    expect(dealer.chipStacks.where((s) => s.seat == 0).length, 2);
  });

  test('double: only the extra stake is pushed, then one card', () {
    director.apply(snap(tableDoc(
      phase: 'playerTurns',
      seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(['5S', '6H'])])],
      dealerCards: ['9D'],
      holeHidden: true,
      turn: {'seatIndex': 0, 'handIndex': 0},
      eventSeq: 8,
    )));
    final q = queuedBy(() => director.apply(snap(tableDoc(
          phase: 'playerTurns',
          seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(['5S', '6H', 'TC'], bet: 2000, doubled: true, done: true)])],
          dealerCards: ['9D'],
          holeHidden: true,
          events: [ev(9, 'power', seat: 0, hand: 0, power: 'freeDouble'), ev(10, 'double', seat: 0, hand: 0, card: 'TC', amount: 2000)],
        ))));
    expect(q, ['bet(seat0/h0, 1000)', 'deal(10C -> seat0/h0)', 'turn(off)']);
  });

  test('dealer blackjack on the peek: surprised dealer', () {
    director.apply(snap(tableDoc(
      phase: 'playerTurns',
      seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(['9S', '7H'])])],
      dealerCards: ['AD'],
      holeHidden: true,
      eventSeq: 8,
    )));
    final q = queuedBy(() => director.apply(snap(tableDoc(
          phase: 'settled',
          seats: [seatDoc(0, 'me', bet: 1000, net: -1000, hands: [handDoc(['9S', '7H'], done: true, result: 'lose', ret: 0)])],
          dealerCards: ['AD', 'KH'],
          events: [
            ev(9, 'peek', dealerBlackjack: true),
            ev(10, 'reveal', card: 'KH'),
            ev(11, 'settle', seat: 0, hand: 0, result: 'lose', amount: 0),
          ],
        ))));
    expect(q, [
      'peek',
      'react(DealerReaction.dealerBlackjack)',
      'reveal(KH)',
      'react(DealerReaction.lose seat0)',
      'collectBet(seat0/h0)',
    ]);
  });

  test('missing events inside a hand → rebuild from the state', () {
    director.apply(snap(tableDoc(
      phase: 'playerTurns',
      seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(['9S', '7H'])])],
      dealerCards: ['6D'],
      holeHidden: true,
      events: [ev(5, 'deal', seat: 0, hand: 0, card: '9S')],
    )));
    director.apply(snap(tableDoc(
      phase: 'playerTurns',
      seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(['9S', '7H', '2C'])])],
      dealerCards: ['6D'],
      holeHidden: true,
      events: [ev(9, 'hit', seat: 0, hand: 0, card: '2C')],
    )));
    expect(dealer.pendingCommands.whereType<DealCardCommand>(), isEmpty);
    expect(codes(dealer, const HandTarget.seat(0)), ['9S', '7H', '2C']);
    expect(director.lastSeq, 9);
  });

  test('notices: second chance, power, shuffle, hand settled', () {
    director.apply(snap(tableDoc(
      phase: 'playerTurns',
      seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(['TS', '6H'])])],
      dealerCards: ['6D'],
      holeHidden: true,
      eventSeq: 3,
    )));
    final notices = director.apply(snap(tableDoc(
      phase: 'settled',
      seats: [seatDoc(0, 'me', bet: 1000, net: 1000, hands: [handDoc(['TS', '6H', '4C'], done: true, result: 'win', ret: 2000)])],
      dealerCards: ['6D', 'TD', 'KS'],
      events: [
        ev(4, 'power', seat: 0, hand: 0, power: 'secondChance'),
        ev(5, 'secondChance', seat: 0, hand: 0, card: 'QH'),
        ev(6, 'hit', seat: 0, hand: 0, card: '4C'),
        ev(7, 'stand', seat: 0, hand: 0),
        ev(8, 'reveal', card: 'TD'),
        ev(9, 'dealerHit', card: 'KS'),
        ev(10, 'settle', seat: 0, hand: 0, result: 'win', amount: 2000),
      ],
    )));
    expect(notices.whereType<PowerUsedNotice>().single.seatIndex, 0);
    expect(notices.whereType<SecondChanceNotice>().single.discarded, const PlayingCard(Rank.queen, Suit.hearts));
    expect(notices.whereType<HandSettledNotice>().single.handNumber, 1);
    // The replacement card did not bust: no bust reaction, a payout instead.
    expect(dealer.pendingCommands.map((c) => c.toString()), contains('payout(seat0/h0, 1000)'));
    expect(dealer.pendingCommands.map((c) => c.toString()), isNot(contains('react(DealerReaction.bust seat0)')));
  });

  test('turn ring follows the server deadline (time already elapsed is shown)', () {
    director.apply(snap(tableDoc(
      phase: 'playerTurns',
      seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(['9S', '7H'])])],
      dealerCards: ['6D'],
      holeHidden: true,
      turn: {'seatIndex': 0, 'handIndex': 0},
      deadlineMs: kT0 + 20000,
      eventSeq: 3,
    )));
    now = now.add(const Duration(seconds: 5));
    dealer.advance(const Duration(milliseconds: 1)); // starts the queued turn command
    expect(dealer.turnSeat, 0);
    expect(dealer.turnRemaining.inMilliseconds, closeTo(15000, 5));

    // Same turn, same deadline: nothing new queued.
    final q = queuedBy(() => director.apply(snap(tableDoc(
          phase: 'playerTurns',
          seats: [seatDoc(0, 'me', bet: 1000, hands: [handDoc(['9S', '7H'])])],
          dealerCards: ['6D'],
          holeHidden: true,
          turn: {'seatIndex': 0, 'handIndex': 0},
          deadlineMs: kT0 + 20000,
          eventSeq: 3,
        ))));
    expect(q, isEmpty);
  });
}
