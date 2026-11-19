/// Turns successive `tables/{id}` snapshots into [DealerController] commands.
///
/// The server publishes, per hand, an ordered event log (`events`, `seq`
/// monotonic across hands, reset when betting opens) plus the resulting
/// state. The director:
///  * on the first snapshot (or when events were missed inside a hand)
///    rebuilds the scene from the STATE instantly ([TableDirector.resync]);
///  * otherwise animates every event with `seq` greater than the last one it
///    rendered, in order: bets, deal (face-down hole card), hits, doubles,
///    splits, hole-card reveal, dealer draws, payouts / collections and the
///    dealer's reactions; a new hand first sweeps the previous one;
///  * keeps the turn ring in sync with `turn` + `deadlineMs`.
///
/// Pure Dart on top of [DealerController] (no widget), fully unit-tested.
library;

import '../../domain/cards.dart';
import '../../domain/models.dart' show PowerType;
import '../../domain/table_state.dart';
import '../dealer/dealer_controller.dart';
import '../dealer/dealer_feedback.dart';

/// Something the table screen may want to tell the player (toast).
sealed class TableNotice {
  const TableNotice();
}

class SecondChanceNotice extends TableNotice {
  const SecondChanceNotice(this.seatIndex, this.discarded);
  final int seatIndex;
  final PlayingCard discarded;
}

class PowerUsedNotice extends TableNotice {
  const PowerUsedNotice(this.seatIndex, this.power);
  final int seatIndex;
  final PowerType power;
}

class ShuffleNotice extends TableNotice {
  const ShuffleNotice();
}

/// Hand-finished notice (once per hand, when its `settle` events arrive).
class HandSettledNotice extends TableNotice {
  const HandSettledNotice(this.handNumber);
  final int handNumber;
}

class TableDirector {
  TableDirector(this.dealer, {DateTime Function()? now, this.backlogSpeedUp = const Duration(seconds: 5)})
      : _now = now ?? DateTime.now;

  final DealerController dealer;
  final DateTime Function() _now;

  /// When more than this much animation is queued, new commands play faster.
  final Duration backlogSpeedUp;

  int? _lastSeq;
  int? _handNumber;
  TableTurn? _turn;
  DateTime? _turnDeadline;

  /// Client mirror of the cards dealt per hand (to detect busts) and of the
  /// chips in front of each hand (to compute payouts).
  final Map<HandTarget, List<PlayingCard>> _cards = {};
  final Map<(int, int), int> _bets = {};
  final Set<int> _insured = {};
  bool _settledThisHand = false;

  /// Last event rendered (null before the first snapshot).
  int? get lastSeq => _lastSeq;
  int? get handNumber => _handNumber;

  /// Feeds a new snapshot; returns the notices raised by its new events.
  List<TableNotice> apply(TableState t) {
    final notices = <TableNotice>[];
    final last = _lastSeq;
    if (last == null) {
      resync(t);
    } else if (t.eventSeq != last || t.handNumber != _handNumber) {
      final fresh = [for (final e in t.events) if (e.seq > last) e];
      if (t.handNumber != _handNumber) {
        // New hand: the log restarted when betting opened, so `fresh` holds
        // the whole new hand. Sweep whatever is left of the previous one.
        if (dealer.cards.isNotEmpty || dealer.chipStacks.isNotEmpty) dealer.collectAll();
        _clearMirror();
        _play(fresh, notices);
      } else if (fresh.isNotEmpty && fresh.first.seq != last + 1 && t.events.isNotEmpty && t.events.first.seq > last + 1) {
        // Events of this hand were dropped from the log: rebuild.
        resync(t);
      } else {
        _play(fresh, notices);
      }
      if (fresh.any((e) => e.type == TableEventType.settle) && !_settledThisHand) {
        _settledThisHand = true;
        notices.add(HandSettledNotice(t.handNumber));
      }
    }
    _lastSeq = t.eventSeq;
    _handNumber = t.handNumber;
    _syncTurn(t);
    return notices;
  }

  /// Rebuilds the whole scene from the state, without animation.
  void resync(TableState t) {
    dealer.reset();
    _clearMirror();
    _turn = null;
    _turnDeadline = null;
    for (final s in t.seats) {
      if (s == null) continue;
      if (s.hands.isEmpty) {
        if (s.betCents > 0) _bet(s.seatIndex, 0, s.betCents);
        continue;
      }
      dealer.setHandCount(s.seatIndex, s.hands.length);
      for (final (h, hand) in s.hands.indexed) {
        if (hand.betCents > 0) _bet(s.seatIndex, h, hand.betCents);
      }
    }
    // Deal in table order: first card of everyone, dealer up card, rest.
    final maxCards = [
      for (final s in t.seats.nonNulls)
        for (final h in s.hands) h.cards.length,
    ].fold<int>(0, (a, b) => a > b ? a : b);
    for (var i = 0; i < maxCards; i++) {
      for (final s in t.seats.nonNulls) {
        for (final (h, hand) in s.hands.indexed) {
          if (i < hand.cards.length) _deal(HandTarget.seat(s.seatIndex, hand: h), hand.cards[i]);
        }
      }
      if (i == 0) _dealDealerFromState(t);
    }
    if (maxCards == 0) _dealDealerFromState(t);
    if (t.phase == ServerTablePhase.settled) {
      for (final s in t.seats.nonNulls) {
        for (final (h, hand) in s.hands.indexed) {
          final r = _reactionFor(hand.result);
          if (r != null) dealer.react(r, seat: s.seatIndex, hand: h);
        }
      }
      _settledThisHand = true;
    }
    dealer.fastForward();
    _lastSeq = t.eventSeq;
    _handNumber = t.handNumber;
  }

  void _dealDealerFromState(TableState t) {
    if (_cards.containsKey(const HandTarget.dealer())) return;
    final d = t.dealer;
    if (d.cards.isEmpty) return;
    _deal(const HandTarget.dealer(), d.cards.first);
    if (d.holeHidden) {
      dealer.dealCard(const HandTarget.dealer(), faceUp: false);
    }
    for (final c in d.cards.skip(1)) {
      _deal(const HandTarget.dealer(), c);
    }
  }

  void _clearMirror() {
    _cards.clear();
    _bets.clear();
    _insured.clear();
    _settledThisHand = false;
  }

  void _bet(int seat, int hand, int cents) {
    if (cents <= 0) return;
    _bets[(seat, hand)] = (_bets[(seat, hand)] ?? 0) + cents;
    dealer.placeBet(seat, cents, hand: hand);
  }

  void _deal(HandTarget target, PlayingCard card) {
    (_cards[target] ??= []).add(card);
    dealer.dealCard(target, card: card);
  }

  static DealerReaction? _reactionFor(HandResult? r) => switch (r) {
        HandResult.blackjack => DealerReaction.blackjack,
        HandResult.win => DealerReaction.win,
        HandResult.push => DealerReaction.push,
        HandResult.lose || HandResult.surrender => DealerReaction.lose,
        HandResult.bust => DealerReaction.bust,
        null => null,
      };

  void _action(int? seat, int hand, CueAction a) {
    if (seat != null) dealer.cue(DealerCue.action, CueInfo(seat: seat, hand: hand, action: a));
  }

  void _play(List<TableEvent> events, List<TableNotice> notices) {
    if (events.isEmpty) return;
    dealer.speed = dealer.remainingDuration > backlogSpeedUp || events.length > 30 ? 2.2 : 1.0;
    var dealerReacted = false;
    var suspense = false;
    final lastDealerHit = events.lastIndexWhere((e) => e.type == TableEventType.dealerHit);
    for (final (i, e) in events.indexed) {
      final seat = e.seatIndex;
      final hand = e.handIndex ?? 0;
      final target = seat == null ? null : HandTarget.seat(seat, hand: hand);
      switch (e.type) {
        case TableEventType.shuffle:
          dealer.shuffle();
          notices.add(const ShuffleNotice());
        case TableEventType.bet:
          if (seat != null && e.amountCents != null) _bet(seat, 0, e.amountCents!);
        case TableEventType.deal || TableEventType.hit:
          if (target != null && e.card != null) {
            if (e.type == TableEventType.hit) _action(seat, hand, CueAction.hit);
            _deal(target, e.card!);
            if (e.type == TableEventType.hit && handTotal(_cards[target]!).isBust) {
              dealer.react(DealerReaction.bust, seat: seat, hand: hand);
            }
          }
        case TableEventType.double:
          if (target != null && seat != null) {
            _action(seat, hand, CueAction.double);
            final total = e.amountCents ?? 0;
            final extra = total - (_bets[(seat, hand)] ?? 0);
            if (extra > 0) _bet(seat, hand, extra);
            if (e.card != null) {
              _deal(target, e.card!);
              if (handTotal(_cards[target]!).isBust) dealer.react(DealerReaction.bust, seat: seat, hand: hand);
            }
          }
        case TableEventType.split:
          if (seat != null) {
            _action(seat, hand, CueAction.split);
            _split(seat, hand, e.amountCents);
          }
        case TableEventType.stand:
          _action(seat, hand, CueAction.stand);
        case TableEventType.surrender:
          if (seat != null) {
            _action(seat, hand, CueAction.surrender);
            _cards.remove(HandTarget.seat(seat, hand: hand));
            dealer.surrenderHand(seat, hand: hand);
          }
        case TableEventType.insurance:
          if (seat != null && (e.amountCents ?? 0) > 0) {
            _action(seat, 0, CueAction.insurance);
            _insured.add(seat);
            dealer.placeInsurance(seat, e.amountCents!);
          }
        case TableEventType.dealerUp:
          if (e.card != null) _deal(const HandTarget.dealer(), e.card!);
        case TableEventType.dealerHit:
          if (e.card != null) _deal(const HandTarget.dealer(), e.card!);
          if (suspense && i == lastDealerHit) {
            suspense = false;
            dealer.cue(DealerCue.suspenseStop);
          }
        case TableEventType.dealerHole:
          dealer.dealCard(const HandTarget.dealer(), faceUp: false);
        case TableEventType.reveal:
          if (e.card != null) {
            (_cards[const HandTarget.dealer()] ??= []).add(e.card!);
            dealer.revealHoleCard(e.card!);
            if (lastDealerHit > i) {
              suspense = true;
              dealer.cue(DealerCue.suspenseStart);
            }
          }
        case TableEventType.peek:
          dealer.peekHoleCard();
          if (_insured.isNotEmpty) {
            dealer.resolveInsurance(won: e.dealerBlackjack == true);
            _insured.clear();
          }
          if (e.dealerBlackjack == true) {
            dealer.react(DealerReaction.dealerBlackjack);
            dealerReacted = true;
          }
        case TableEventType.settle:
          if (seat == null) break;
          if (suspense) {
            suspense = false;
            dealer.cue(DealerCue.suspenseStop);
          }
          if (!dealerReacted) {
            dealerReacted = true;
            final d = _cards[const HandTarget.dealer()];
            if (d != null && handTotal(d).isBust) dealer.react(DealerReaction.dealerBust);
          }
          _settle(seat, hand, e.result, e.amountCents ?? 0);
        case TableEventType.secondChance:
          if (seat != null && e.card != null) {
            notices.add(SecondChanceNotice(seat, e.card!));
            // Show the card that would have busted, then rewind it away.
            final t = HandTarget.seat(seat, hand: hand);
            dealer.dealCard(t, card: e.card);
            dealer.cue(DealerCue.power, CueInfo(seat: seat, hand: hand, power: PowerType.secondChance.name));
            dealer.discardLastCard(t);
          }
        case TableEventType.power:
          if (seat != null && e.power != null) {
            notices.add(PowerUsedNotice(seat, e.power!));
            // Second chance sounds when it actually rewinds a card.
            if (e.power != PowerType.secondChance) {
              dealer.cue(DealerCue.power, CueInfo(seat: seat, hand: hand, power: e.power!.name));
            }
          }
        case TableEventType.timeout:
          if (seat != null) dealer.cue(DealerCue.timeout, CueInfo(seat: seat, hand: hand));
        case TableEventType.join:
          if (seat != null) dealer.cue(DealerCue.seatJoin, CueInfo(seat: seat));
        case TableEventType.leave:
          break;
      }
    }
    if (suspense) dealer.cue(DealerCue.suspenseStop);
  }

  /// Mirrors the engine: the second card of hand [hand] becomes hand
  /// `hand + 1`, later hands shift right; the new hand gets the same bet.
  void _split(int seat, int hand, int? newBet) {
    final from = HandTarget.seat(seat, hand: hand);
    final cards = _cards[from] ?? const <PlayingCard>[];
    final next = <HandTarget, List<PlayingCard>>{};
    final bets = <(int, int), int>{};
    _cards.forEach((t, l) {
      if (!t.isDealer && t.seat == seat && t.hand > hand) {
        next[HandTarget.seat(seat, hand: t.hand + 1)] = l;
      } else {
        next[t] = l;
      }
    });
    _bets.forEach((k, v) => bets[k.$1 == seat && k.$2 > hand ? (seat, k.$2 + 1) : k] = v);
    next[from] = cards.isEmpty ? [] : [cards.first];
    next[HandTarget.seat(seat, hand: hand + 1)] = cards.length > 1 ? cards.sublist(1) : [];
    bets[(seat, hand + 1)] = newBet ?? bets[(seat, hand)] ?? 0;
    _cards
      ..clear()
      ..addAll(next);
    _bets
      ..clear()
      ..addAll(bets);
    dealer.splitHand(seat, hand: hand);
  }

  void _settle(int seat, int hand, HandResult? result, int returnedCents) {
    final bet = _bets[(seat, hand)] ?? 0;
    final r = _reactionFor(result);
    switch (result) {
      case HandResult.blackjack || HandResult.win:
        final profit = returnedCents - bet;
        dealer.react(r!, seat: seat, hand: hand, cents: profit);
        if (profit > 0) dealer.payout(seat, profit, hand: hand);
      case HandResult.push:
        dealer.react(r!, seat: seat, hand: hand);
      case HandResult.lose:
        dealer.react(r!, seat: seat, hand: hand);
        dealer.collectBet(seat, hand: hand);
      case HandResult.surrender:
        // Half already raked when the hand was folded; the rest goes back
        // to the player with the sweep.
        dealer.react(r!, seat: seat, hand: hand);
      case HandResult.bust:
        dealer.collectBet(seat, hand: hand);
      case null:
        break;
    }
  }

  void _syncTurn(TableState t) {
    final turn = t.phase == ServerTablePhase.playerTurns ? t.turn : null;
    final deadline = turn == null ? null : t.deadline;
    if (turn == _turn && deadline == _turnDeadline) return;
    _turn = turn;
    _turnDeadline = deadline;
    if (turn == null || deadline == null) {
      dealer.queueTurnTimer(null);
      return;
    }
    final left = deadline.difference(_now());
    final seat = t.seats[turn.seatIndex];
    final total = seat != null && seat.isBot
        ? (left.isNegative ? const Duration(milliseconds: 500) : left)
        : const Duration(milliseconds: 20000);
    dealer.queueTurnTimer(turn.seatIndex, total: total, remaining: () {
      final r = deadline.difference(_now());
      return r.isNegative ? Duration.zero : r;
    });
  }
}
