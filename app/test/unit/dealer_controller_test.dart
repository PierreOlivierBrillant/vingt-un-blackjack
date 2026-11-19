import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/cards.dart';
import 'package:vingtun/features/dealer/dealer_controller.dart';
import 'package:vingtun/features/dealer/dealer_feedback.dart';
import 'package:vingtun/features/dealer/demo_round.dart';
import 'package:vingtun/features/dealer/table_geometry.dart';

PlayingCard c(String code) => PlayingCard.parse(code);

/// Advances in 16 ms frames (like a 60 Hz ticker) and lets futures resolve.
Future<void> run(DealerController d, Duration total, {Duration frame = const Duration(milliseconds: 16)}) async {
  var t = Duration.zero;
  while (t < total) {
    final step = total - t < frame ? total - t : frame;
    d.advance(step);
    t += step;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late DealerController d;
  late RecordingDealerFeedback fb;
  const timings = DealerTimings();

  setUp(() {
    fb = RecordingDealerFeedback();
    d = DealerController(feedback: fb);
  });
  tearDown(() => d.dispose());

  test('commands run strictly in FIFO order, futures complete in order', () async {
    final done = <String>[];
    d.placeBet(0, 500).then((_) => done.add('bet'));
    d.dealCard(const HandTarget.seat(0), card: c('AS')).then((_) => done.add('deal1'));
    d.dealCard(const HandTarget.dealer(), faceUp: false).then((_) => done.add('hole'));
    d.revealHoleCard(c('KD')).then((_) => done.add('reveal'));
    d.collectAll().then((_) => done.add('collect'));

    expect(d.pendingCommands.map((x) => x.runtimeType.toString()), [
      'PlaceBetCommand',
      'DealCardCommand',
      'DealCardCommand',
      'RevealHoleCardCommand',
      'CollectAllCommand',
    ]);
    expect(d.isBusy, isTrue);
    await run(d, d.remainingDuration + const Duration(milliseconds: 1));
    expect(done, ['bet', 'deal1', 'hole', 'reveal', 'collect']);
    expect(d.isBusy, isFalse);
  });

  test('a command takes exactly its configured duration (scaled by speed)', () async {
    var finished = false;
    d.dealCard(const HandTarget.seat(2), card: c('7H')).then((_) => finished = true);
    expect(d.remainingDuration, timings.deal);

    d.advance(timings.deal - const Duration(milliseconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse, reason: 'still 1 ms to go');
    d.advance(const Duration(milliseconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(finished, isTrue);

    final fast = DealerController(speed: 2);
    fast.shuffle();
    expect(fast.remainingDuration, Duration(microseconds: timings.shuffle.inMicroseconds ~/ 2));
    fast.dispose();
  });

  test('one big advance runs several commands and carries the remainder', () async {
    d.dealCard(const HandTarget.seat(0), card: c('2C'));
    d.dealCard(const HandTarget.seat(1), card: c('3C'));
    d.dealCard(const HandTarget.seat(2), card: c('4C'));
    d.advance(timings.deal * 2 + const Duration(milliseconds: 100));
    expect(d.cards.length, 3);
    expect(d.pendingCommands, isEmpty);
    expect(d.currentCommand, isA<DealCardCommand>());
    expect(d.currentProgress, closeTo(100 / timings.deal.inMilliseconds, 1e-6));
  });

  test('dealt card lands at its rest position, face up, with cues in order', () async {
    d.dealCard(const HandTarget.seat(3), card: c('QH'));
    await run(d, timings.deal);
    final card = d.cards.single;
    expect(card.visible, isTrue);
    expect(card.flip, 1);
    expect(card.lift, 0);
    expect(card.pos, DealerController.geometry.cardRest(const HandTarget.seat(3), 0));
    expect(fb.cues, [DealerCue.cardDraw, DealerCue.cardFlip, DealerCue.cardLand]);
    expect(d.cardsDealtFromShoe, 1);
    expect(d.shoeLevel, closeTo(1 - 1 / 312, 1e-9));
  });

  test('card is in flight mid-animation: lifted, between shoe and rest', () async {
    d.dealCard(const HandTarget.seat(0), card: c('9S'));
    await run(d, Duration(milliseconds: (timings.deal.inMilliseconds * 0.6).round()));
    final card = d.cards.single;
    final rest = DealerController.geometry.cardRest(const HandTarget.seat(0), 0);
    expect(card.lift, greaterThan(0.3));
    expect(card.pos, isNot(rest));
    expect(card.pos.dy, lessThan(rest.dy));
  });

  test('face-down hole card has no value until revealHoleCard', () async {
    expect(() => d.dealCard(const HandTarget.dealer()), throwsArgumentError, reason: 'face up needs a value');
    d.dealCard(const HandTarget.dealer(), card: c('10H'));
    d.dealCard(const HandTarget.dealer(), faceUp: false);
    await run(d, timings.deal * 2);
    final hole = d.cardsFor(const HandTarget.dealer())[1];
    expect(hole.card, isNull);
    expect(hole.flip, 0);
    expect(d.visibleTotal(const HandTarget.dealer())!.total, 10);

    d.revealHoleCard(c('6S'));
    await run(d, timings.reveal);
    expect(hole.card, c('6S'));
    expect(hole.flip, 1);
    expect(d.visibleTotal(const HandTarget.dealer())!.total, 16);
    expect(fb.cues.last, DealerCue.holeFlip);
  });

  test('split moves the second card to a new hand and duplicates the bet', () async {
    d.placeBet(2, 5000);
    d.dealCard(const HandTarget.seat(2), card: c('8H'));
    d.dealCard(const HandTarget.seat(2), card: c('8S'));
    d.splitHand(2);
    await run(d, d.remainingDuration);
    expect(d.handCount(2), 2);
    expect(d.cardsFor(const HandTarget.seat(2, hand: 0)).single.card, c('8H'));
    expect(d.cardsFor(const HandTarget.seat(2, hand: 1)).single.card, c('8S'));
    final bets = d.chipStacks.where((s) => s.seat == 2).toList();
    expect(bets.map((s) => (s.hand, s.cents)), unorderedEquals([(0, 5000), (1, 5000)]));
    final g = DealerController.geometry;
    expect(d.cardsFor(const HandTarget.seat(2, hand: 1)).single.pos, g.cardRest(const HandTarget.seat(2, hand: 1), 0, handCount: 2));
  });

  test('bets merge, payouts add a stack, collectBet removes it, collectAll clears', () async {
    d.placeBet(1, 1000);
    d.placeBet(1, 500);
    await run(d, d.remainingDuration);
    expect(d.chipStacks.single.cents, 1500);

    d.payout(1, 1500);
    await run(d, d.remainingDuration);
    expect(d.chipStacks.length, 2);
    expect(fb.cues.last, DealerCue.payout);

    d.placeBet(4, 2500);
    d.collectBet(4);
    await run(d, d.remainingDuration);
    expect(d.chipStacks.where((s) => s.seat == 4), isEmpty);

    d.dealCard(const HandTarget.seat(1), card: c('5D'));
    d.react(DealerReaction.bust, seat: 1);
    await run(d, d.remainingDuration);
    expect(d.badges[(1, 0)], SeatBadge.bust);
    expect(d.mood, DealerMood.wince);

    d.collectAll();
    await run(d, d.remainingDuration);
    expect(d.cards, isEmpty);
    expect(d.chipStacks, isEmpty);
    expect(d.badges, isEmpty);
  });

  test('shuffle refills the shoe and exposes progress while running', () async {
    d.dealCard(const HandTarget.seat(0), card: c('2D'));
    await run(d, timings.deal);
    expect(d.shoeLevel, lessThan(1));
    d.shuffle();
    await run(d, timings.shuffle ~/ 2);
    expect(d.shuffleProgress, closeTo(0.5, 0.02));
    expect(d.cards, isEmpty);
    await run(d, timings.shuffle);
    expect(d.shuffleProgress, isNull);
    expect(d.shoeLevel, 1);
    expect(fb.cues, contains(DealerCue.shuffle));
  });

  test('turn timer: queued start/stop, fraction, warning cue at 75 %', () async {
    d.queueTurnTimer(3, total: const Duration(seconds: 20));
    d.advance(Duration.zero);
    expect(d.turnSeat, 3);
    await run(d, const Duration(seconds: 10), frame: const Duration(milliseconds: 100));
    expect(d.turnFraction, closeTo(0.5, 0.01));
    expect(fb.cues, isNot(contains(DealerCue.timerWarning)));
    await run(d, const Duration(seconds: 6), frame: const Duration(milliseconds: 100));
    expect(fb.cues.where((x) => x == DealerCue.timerWarning).length, 1);
    d.queueTurnTimer(null);
    d.advance(Duration.zero);
    expect(d.turnSeat, isNull);
  });

  test('idle: blinking and breathing evolve with the clock only', () async {
    final blinks = <double>{};
    for (var i = 0; i < 400; i++) {
      d.advance(const Duration(milliseconds: 20));
      blinks.add(d.blink);
    }
    expect(blinks.any((b) => b > 0.5), isTrue, reason: 'eyes close at some point');
    expect(blinks.contains(0.0), isTrue, reason: 'and are open most of the time');
    expect(d.breath, inInclusiveRange(0, 1));
    // Hands return to rest when nothing runs.
    expect((d.rightArm.hand - TableGeometry.rightHandRest).distance, lessThan(8));
  });

  test('reset clears everything and completes pending futures', () async {
    var completed = 0;
    for (var i = 0; i < 5; i++) {
      d.dealCard(HandTarget.seat(i), card: c('AS')).then((_) => completed++);
    }
    d.advance(const Duration(milliseconds: 100));
    d.reset();
    await Future<void>.delayed(Duration.zero);
    expect(completed, 5);
    expect(d.cards, isEmpty);
    expect(d.isBusy, isFalse);
  });

  test('scripted demo round plays to completion with the expected story', () async {
    final done = enqueueDemoRound(d);
    final total = d.remainingDuration;
    expect(total, greaterThan(const Duration(seconds: 20)));
    expect(total, lessThan(const Duration(seconds: 40)));

    var finished = false;
    done.then((_) => finished = true);

    // Snapshot after the deal + blackjack payout: 11 player cards + 2 dealer.
    var sawSplit = false;
    var sawReveal = false;
    var elapsed = Duration.zero;
    while (!finished && elapsed < total + const Duration(seconds: 1)) {
      d.advance(const Duration(milliseconds: 16));
      elapsed += const Duration(milliseconds: 16);
      await Future<void>.delayed(Duration.zero);
      if (d.handCount(2) == 2) sawSplit = true;
      final dealer = d.cardsFor(const HandTarget.dealer());
      if (dealer.length >= 2 && dealer[1].card != null) sawReveal = true;
      final cmd = d.currentCommand;
      if (cmd is ReactCommand && cmd.reaction == DealerReaction.blackjack) {
        expect(d.mood, DealerMood.smile);
        expect(d.badges[(0, 0)], SeatBadge.blackjack);
      }
      if (cmd is ReactCommand && cmd.reaction == DealerReaction.bust) {
        expect(d.mood, DealerMood.wince);
      }
    }
    expect(finished, isTrue);
    expect(sawSplit, isTrue);
    expect(sawReveal, isTrue);
    expect(d.cards, isEmpty, reason: 'collectAll at the end');
    expect(fb.cues, containsAllInOrder([DealerCue.shuffle, DealerCue.blackjack, DealerCue.bust, DealerCue.payout]));
    // 5 seats × 2 + dealer × 2 + hit (seat 1) + 3 after the split + double (seat 4) + dealer draw.
    expect(fb.cues.where((x) => x == DealerCue.cardDraw).length, 18);
  });
}
