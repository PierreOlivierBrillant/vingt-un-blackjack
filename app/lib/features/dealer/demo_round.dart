import '../../domain/cards.dart';
import 'dealer_controller.dart';
import 'dealer_stage.dart';

PlayingCard _c(String code) => PlayingCard.parse(code);

/// Seats used by the demo (seat 0 = first base, screen right).
const kDemoSeats = <DealerSeat?>[
  DealerSeat(name: 'LunaRiver', stackCents: 84200),
  DealerSeat(name: 'Bot Ada', stackCents: 30000, isBot: true),
  DealerSeat(name: 'Joueur21', stackCents: 124350, isMe: true),
  DealerSeat(name: 'Karim_21', stackCents: 9100),
  DealerSeat(name: 'Bot Max', stackCents: 52000, isBot: true),
];

/// Enqueues a complete scripted round on [c] and returns the future of its
/// last command. Covers: shuffle, bets on 5 seats, two dealing passes with a
/// face-down hole card, a natural blackjack (3:2), a bust, a split with two
/// hands, a double, the turn timer, the hole-card reveal, a dealer bust,
/// payouts, losing-bet collection and the final sweep.
///
/// Totals: seat0 A♠K♥ BJ · seat1 9♣7♦+10♠ bust · seat2 8♥8♠ split →
/// (8♥3♦10♣ = 21) / (8♠9♥ = 17) · seat3 10♦6♣ stand · seat4 5♠6♥ double +9♠ =
/// 20 · dealer 10♥ (6♠) +7♣ = 23 bust.
Future<void> enqueueDemoRound(DealerController c, {bool shuffleFirst = true}) {
  const think = Duration(milliseconds: 700);
  const turn = Duration(seconds: 20);
  if (shuffleFirst) c.shuffle();

  for (final (seat, cents) in const [(0, 2500), (1, 1000), (2, 5000), (3, 500), (4, 2500)]) {
    c.placeBet(seat, cents);
  }
  c.pause(const Duration(milliseconds: 300));

  // First pass.
  c.dealCard(const HandTarget.seat(0), card: _c('AS'));
  c.dealCard(const HandTarget.seat(1), card: _c('9C'));
  c.dealCard(const HandTarget.seat(2), card: _c('8H'));
  c.dealCard(const HandTarget.seat(3), card: _c('10D'));
  c.dealCard(const HandTarget.seat(4), card: _c('5S'));
  c.dealCard(const HandTarget.dealer(), card: _c('10H'));
  // Second pass; the dealer's hole card stays unknown to the client.
  c.dealCard(const HandTarget.seat(0), card: _c('KH'));
  c.dealCard(const HandTarget.seat(1), card: _c('7D'));
  c.dealCard(const HandTarget.seat(2), card: _c('8S'));
  c.dealCard(const HandTarget.seat(3), card: _c('6C'));
  c.dealCard(const HandTarget.seat(4), card: _c('6H'));
  c.dealCard(const HandTarget.dealer(), faceUp: false);

  // Natural blackjack is paid immediately (3:2).
  c.react(DealerReaction.blackjack, seat: 0);
  c.payout(0, 3750);

  // Seat 1 hits and busts.
  c.queueTurnTimer(1, total: turn);
  c.pause(think);
  c.dealCard(const HandTarget.seat(1), card: _c('10S'));
  c.queueTurnTimer(null);
  c.react(DealerReaction.bust, seat: 1);
  c.collectBet(1);

  // You split eights, then play both hands.
  c.queueTurnTimer(2, total: turn);
  c.pause(think);
  c.splitHand(2);
  c.dealCard(const HandTarget.seat(2, hand: 0), card: _c('3D'));
  c.pause(const Duration(milliseconds: 400));
  c.dealCard(const HandTarget.seat(2, hand: 0), card: _c('10C'));
  c.dealCard(const HandTarget.seat(2, hand: 1), card: _c('9H'));
  c.queueTurnTimer(null);

  // Seat 3 stands on 16.
  c.queueTurnTimer(3, total: turn);
  c.pause(think);
  c.queueTurnTimer(null);

  // Seat 4 doubles on 11.
  c.queueTurnTimer(4, total: turn);
  c.pause(think);
  c.placeBet(4, 2500);
  c.dealCard(const HandTarget.seat(4), card: _c('9S'));
  c.queueTurnTimer(null);

  // Dealer plays: reveal 16, draw, bust.
  c.revealHoleCard(_c('6S'));
  c.pause(const Duration(milliseconds: 350));
  c.dealCard(const HandTarget.dealer(), card: _c('7C'));
  c.react(DealerReaction.dealerBust);

  c.payout(2, 5000, hand: 0);
  c.payout(2, 5000, hand: 1);
  c.payout(3, 500);
  c.payout(4, 5000);
  c.pause(const Duration(milliseconds: 1400));
  return c.collectAll();
}
