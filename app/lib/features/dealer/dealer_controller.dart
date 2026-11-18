import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import '../../domain/cards.dart';
import 'dealer_feedback.dart';
import 'ik.dart';
import 'table_geometry.dart';

export 'table_geometry.dart' show HandTarget;

enum DealerReaction { blackjack, bust, dealerBlackjack, dealerBust, win, push }

enum DealerMood { neutral, smile, wince, surprised }

enum SeatBadge { blackjack, bust, win, lose, push }

/// Base duration of every command at speed 1.0.
@immutable
class DealerTimings {
  const DealerTimings({
    this.deal = const Duration(milliseconds: 640),
    this.reveal = const Duration(milliseconds: 560),
    this.split = const Duration(milliseconds: 460),
    this.bet = const Duration(milliseconds: 320),
    this.payout = const Duration(milliseconds: 620),
    this.collectBet = const Duration(milliseconds: 520),
    this.collectAll = const Duration(milliseconds: 1000),
    this.shuffle = const Duration(milliseconds: 2400),
    this.react = const Duration(milliseconds: 900),
  });

  final Duration deal;
  final Duration reveal;
  final Duration split;
  final Duration bet;
  final Duration payout;
  final Duration collectBet;
  final Duration collectAll;
  final Duration shuffle;
  final Duration react;
}

// ------------------------------------------------------------- commands --

sealed class DealerCommand {
  const DealerCommand();
  Duration baseDuration(DealerTimings t);
}

class DealCardCommand extends DealerCommand {
  const DealCardCommand(this.target, this.card, this.faceUp);
  final HandTarget target;
  final PlayingCard? card;
  final bool faceUp;
  @override
  Duration baseDuration(DealerTimings t) => t.deal;
  @override
  String toString() => 'deal(${faceUp ? card : '??'} -> $target)';
}

class RevealHoleCardCommand extends DealerCommand {
  const RevealHoleCardCommand(this.card);
  final PlayingCard card;
  @override
  Duration baseDuration(DealerTimings t) => t.reveal;
  @override
  String toString() => 'reveal($card)';
}

class SplitHandCommand extends DealerCommand {
  const SplitHandCommand(this.seat, this.hand);
  final int seat;
  final int hand;
  @override
  Duration baseDuration(DealerTimings t) => t.split;
  @override
  String toString() => 'split(seat$seat/h$hand)';
}

class PlaceBetCommand extends DealerCommand {
  const PlaceBetCommand(this.seat, this.hand, this.cents);
  final int seat;
  final int hand;
  final int cents;
  @override
  Duration baseDuration(DealerTimings t) => t.bet;
  @override
  String toString() => 'bet(seat$seat/h$hand, $cents)';
}

class PayoutCommand extends DealerCommand {
  const PayoutCommand(this.seat, this.hand, this.cents);
  final int seat;
  final int hand;
  final int cents;
  @override
  Duration baseDuration(DealerTimings t) => t.payout;
  @override
  String toString() => 'payout(seat$seat/h$hand, $cents)';
}

class CollectBetCommand extends DealerCommand {
  const CollectBetCommand(this.seat, this.hand);
  final int seat;
  final int hand;
  @override
  Duration baseDuration(DealerTimings t) => t.collectBet;
  @override
  String toString() => 'collectBet(seat$seat/h$hand)';
}

class CollectAllCommand extends DealerCommand {
  const CollectAllCommand();
  @override
  Duration baseDuration(DealerTimings t) => t.collectAll;
  @override
  String toString() => 'collectAll';
}

class ShuffleCommand extends DealerCommand {
  const ShuffleCommand();
  @override
  Duration baseDuration(DealerTimings t) => t.shuffle;
  @override
  String toString() => 'shuffle';
}

class ReactCommand extends DealerCommand {
  const ReactCommand(this.reaction, this.seat, this.hand);
  final DealerReaction reaction;
  final int? seat;
  final int hand;
  @override
  Duration baseDuration(DealerTimings t) => t.react;
  @override
  String toString() => 'react($reaction${seat == null ? '' : ' seat$seat'})';
}

/// Zero-duration command that starts (or, with `seat == null`, stops) the
/// turn timer at its exact place in the queue.
class TurnTimerCommand extends DealerCommand {
  const TurnTimerCommand(this.seat, this.total);
  final int? seat;
  final Duration total;
  @override
  Duration baseDuration(DealerTimings t) => Duration.zero;
  @override
  String toString() => seat == null ? 'turn(off)' : 'turn(seat$seat)';
}

class PauseCommand extends DealerCommand {
  const PauseCommand(this.duration);
  final Duration duration;
  @override
  Duration baseDuration(DealerTimings t) => duration;
  @override
  String toString() => 'pause(${duration.inMilliseconds}ms)';
}

// ---------------------------------------------------------- scene state --

/// A card on (or flying over) the felt. Mutated only by the controller.
class TableCard {
  TableCard({required this.id, required this.target, required this.index, this.card, required this.faceUp});

  final int id;
  HandTarget target;
  int index;

  /// `null` while the hole card's value is unknown to the client.
  PlayingCard? card;
  bool faceUp;

  Offset pos = TableGeometry.shoeExit;
  double rotation = -0.35;

  /// 0 = back visible, 1 = face visible (3D flip progress).
  double flip = 0;

  /// 0 = resting on the felt, 1 = highest point of a toss (shadow/scale).
  double lift = 0;
  double opacity = 1;
  bool visible = false;
}

enum ChipStackKind { bet, payout }

class ChipStackState {
  ChipStackState({required this.id, required this.seat, required this.hand, required this.cents, required this.kind, required this.pos});
  final int id;
  int seat;
  int hand;
  int cents;
  final ChipStackKind kind;
  Offset pos;
  double lift = 0;
  double opacity = 1;
}

class ArmState {
  ArmState(this.hand);
  Offset hand;

  /// 0 = open hand, 1 = pinching a card / chips.
  double grip = 0;
}

class _Running {
  _Running(this.command, this.completer, this.duration);
  final DealerCommand command;
  final Completer<void> completer;
  final Duration duration;
  Duration elapsed = Duration.zero;
  late Offset startLeft;
  late Offset startRight;
  final emitted = <String>{};
  // Per-command scratch data.
  TableCard? card;
  ChipStackState? stack;
  Map<int, Offset> fromPositions = {};
  Map<int, Offset> chipFrom = {};
  Offset? control;
}

/// Backend-independent animation controller for the dealer.
///
/// Every public action enqueues a command and returns a future that
/// completes when that command's animation has fully played. Commands run
/// strictly in FIFO order; time only moves through [advance] (driven by a
/// ticker in [DealerStage], or manually in tests), so playback is fully
/// deterministic.
class DealerController extends ChangeNotifier {
  DealerController({
    this.timings = const DealerTimings(),
    DealerFeedback? feedback,
    double speed = 1.0,
  })  : feedback = feedback ?? const SilentDealerFeedback(),
        _rate = speed;

  static const geometry = TableGeometry();

  final DealerTimings timings;
  DealerFeedback feedback;
  double _rate;

  double get speed => _rate;
  set speed(double v) {
    assert(v > 0);
    _rate = v;
  }

  final _queue = Queue<_Running>();
  _Running? _active;
  var _nextId = 1;
  Duration _clock = Duration.zero;
  Duration _moodElapsed = Duration.zero;

  final List<TableCard> _cards = [];
  final List<ChipStackState> _chips = [];
  final Map<int, int> _handCounts = {};
  final Map<(int, int), SeatBadge> _badges = {};

  final ArmState leftArm = ArmState(TableGeometry.leftHandRest);
  final ArmState rightArm = ArmState(TableGeometry.rightHandRest);

  DealerMood mood = DealerMood.neutral;

  /// 0..1 strength of the current facial expression.
  double moodLevel = 0;

  /// Head roll in radians (shake on bust, nod on blackjack).
  double headTilt = 0;
  double headNod = 0;

  /// 0..1 while a shuffle is playing, otherwise null.
  double? shuffleProgress;

  /// Fraction of the shoe left (1 = fresh 6-deck shoe).
  double shoeLevel = 1;
  int cardsDealtFromShoe = 0;
  static const shoeSize = 312;

  int? turnSeat;
  Duration _turnTotal = Duration.zero;
  Duration _turnElapsed = Duration.zero;
  bool _turnWarned = false;

  // ------------------------------------------------------------- getters --

  Duration get clock => _clock;
  List<TableCard> get cards => List.unmodifiable(_cards);
  List<ChipStackState> get chipStacks => List.unmodifiable(_chips);
  Map<(int, int), SeatBadge> get badges => Map.unmodifiable(_badges);
  DealerCommand? get currentCommand => _active?.command;
  List<DealerCommand> get pendingCommands => [for (final r in _queue) r.command];
  bool get isBusy => _active != null || _queue.isNotEmpty;

  /// Progress (0..1) of the running command.
  double get currentProgress {
    final a = _active;
    if (a == null || a.duration == Duration.zero) return 0;
    return a.elapsed.inMicroseconds / a.duration.inMicroseconds;
  }

  /// Total time still needed to drain the queue at the current speed.
  Duration get remainingDuration {
    var total = Duration.zero;
    final a = _active;
    if (a != null) total += a.duration - a.elapsed;
    for (final r in _queue) {
      total += r.duration;
    }
    return total;
  }

  int handCount(int seat) => _handCounts[seat] ?? 1;

  List<TableCard> cardsFor(HandTarget target) =>
      (_cards.where((c) => c.target == target).toList()..sort((a, b) => a.index.compareTo(b.index)));

  /// Total of the cards whose value is known and face up (display only).
  HandTotal? visibleTotal(HandTarget target) {
    final known = cardsFor(target).where((c) => c.faceUp && c.card != null && c.flip >= 0.5 && c.visible);
    if (known.isEmpty) return null;
    return handTotal(known.map((c) => c.card!));
  }

  double get turnFraction => _turnTotal == Duration.zero
      ? 0
      : (_turnElapsed.inMicroseconds / _turnTotal.inMicroseconds).clamp(0.0, 1.0);

  Duration get turnRemaining {
    final r = _turnTotal - _turnElapsed;
    return r.isNegative ? Duration.zero : r;
  }

  /// Blink amount 0..1 (1 = eyes closed), deterministic from the clock.
  double get blink {
    const period = 3700;
    final ms = _clock.inMilliseconds;
    final cycle = ms ~/ period;
    final t = ms % period;
    double one(int start) {
      final d = t - start;
      if (d < 0 || d > 150) return 0;
      return 1 - ((d - 75).abs() / 75);
    }

    final b = one(0);
    // Every third cycle a quick double blink.
    return cycle % 3 == 2 ? math.max(b, one(230)) : b;
  }

  /// Breathing phase 0..1 → chest/shoulder offset.
  double get breath => (math.sin(_clock.inMilliseconds / 4200 * 2 * math.pi) + 1) / 2;

  // ------------------------------------------------------------- commands --

  Future<void> dealCard(HandTarget target, {PlayingCard? card, bool faceUp = true}) {
    if (faceUp && card == null) {
      throw ArgumentError('A face-up card needs a value');
    }
    return _enqueue(DealCardCommand(target, card, faceUp));
  }

  Future<void> revealHoleCard(PlayingCard card) => _enqueue(RevealHoleCardCommand(card));
  Future<void> splitHand(int seat, {int hand = 0}) => _enqueue(SplitHandCommand(seat, hand));
  Future<void> placeBet(int seat, int cents, {int hand = 0}) => _enqueue(PlaceBetCommand(seat, hand, cents));
  Future<void> payout(int seat, int cents, {int hand = 0}) => _enqueue(PayoutCommand(seat, hand, cents));
  Future<void> collectBet(int seat, {int hand = 0}) => _enqueue(CollectBetCommand(seat, hand));
  Future<void> collectAll() => _enqueue(const CollectAllCommand());
  Future<void> shuffle() => _enqueue(const ShuffleCommand());
  Future<void> react(DealerReaction reaction, {int? seat, int hand = 0}) =>
      _enqueue(ReactCommand(reaction, seat, hand));
  Future<void> pause(Duration d) => _enqueue(PauseCommand(d));

  /// Queued variant of [startTurnTimer] / [stopTurnTimer].
  Future<void> queueTurnTimer(int? seat, {Duration total = const Duration(seconds: 20)}) =>
      _enqueue(TurnTimerCommand(seat, total));

  void startTurnTimer(int seat, Duration total) {
    turnSeat = seat;
    _turnTotal = total;
    _turnElapsed = Duration.zero;
    _turnWarned = false;
    notifyListeners();
  }

  void stopTurnTimer() {
    turnSeat = null;
    _turnTotal = Duration.zero;
    _turnElapsed = Duration.zero;
    notifyListeners();
  }

  /// Clears the table instantly. Pending futures complete (they never hang).
  void reset() {
    for (final r in [?_active, ..._queue]) {
      if (!r.completer.isCompleted) r.completer.complete();
    }
    _active = null;
    _queue.clear();
    _cards.clear();
    _chips.clear();
    _handCounts.clear();
    _badges.clear();
    shuffleProgress = null;
    mood = DealerMood.neutral;
    moodLevel = 0;
    headTilt = 0;
    headNod = 0;
    leftArm
      ..hand = TableGeometry.leftHandRest
      ..grip = 0;
    rightArm
      ..hand = TableGeometry.rightHandRest
      ..grip = 0;
    stopTurnTimer();
  }

  Future<void> _enqueue(DealerCommand c) {
    final base = c.baseDuration(timings);
    final scaled = Duration(microseconds: (base.inMicroseconds / _rate).round());
    final run = _Running(c, Completer<void>(), scaled);
    _queue.add(run);
    notifyListeners();
    return run.completer.future;
  }

  // ----------------------------------------------------------------- time --

  /// Moves time forward by [dt], running as many commands as fit.
  void advance(Duration dt) {
    if (dt.isNegative) return;
    _clock += dt;
    var remaining = dt;

    while (_active != null || _queue.isNotEmpty) {
      if (_active == null) {
        _active = _queue.removeFirst();
        _begin(_active!);
      }
      final a = _active!;
      final need = a.duration - a.elapsed;
      if (remaining >= need) {
        a.elapsed = a.duration;
        _step(a, 1);
        _finish(a);
        _active = null;
        remaining -= need;
        a.completer.complete();
        if (remaining == Duration.zero && _queue.isEmpty) break;
      } else {
        a.elapsed += remaining;
        _step(a, a.elapsed.inMicroseconds / a.duration.inMicroseconds);
        remaining = Duration.zero;
        break;
      }
    }

    _idle(dt);
    _tickTurn(dt);
    notifyListeners();
  }

  void _tickTurn(Duration dt) {
    if (turnSeat == null) return;
    _turnElapsed += dt;
    if (!_turnWarned && turnFraction >= 0.75) {
      _turnWarned = true;
      feedback.cue(DealerCue.timerWarning);
    }
  }

  void _idle(Duration dt) {
    final secs = dt.inMicroseconds / 1e6;
    if (_active == null) {
      final k = 1 - math.exp(-secs * 7);
      final sway = Offset(0, (breath - 0.5) * 6);
      leftArm.hand = Offset.lerp(leftArm.hand, TableGeometry.leftHandRest + sway, k)!;
      rightArm.hand = Offset.lerp(rightArm.hand, TableGeometry.rightHandRest + sway, k)!;
      leftArm.grip *= 1 - k;
      rightArm.grip *= 1 - k;
      headTilt *= 1 - k;
      headNod *= 1 - k;
    }
    if (mood != DealerMood.neutral && (_active?.command is! ReactCommand)) {
      _moodElapsed += dt;
      if (_moodElapsed > const Duration(milliseconds: 1400)) {
        moodLevel = math.max(0, moodLevel - secs * 1.6);
        if (moodLevel == 0) mood = DealerMood.neutral;
      }
    }
  }

  void _emit(_Running r, String key, DealerCue cue) {
    if (r.emitted.add(key)) feedback.cue(cue);
  }

  // -------------------------------------------------------- command logic --

  void _begin(_Running r) {
    r.startLeft = leftArm.hand;
    r.startRight = rightArm.hand;
    switch (r.command) {
      case DealCardCommand(:final target, :final card, :final faceUp):
        final index = _cards.where((c) => c.target == target).length;
        final tc = TableCard(id: _nextId++, target: target, index: index, card: card, faceUp: faceUp);
        _cards.add(tc);
        r.card = tc;
        final rest = _cardRest(tc);
        final pull = TableGeometry.shoeExit + const Offset(-46, 26);
        r.control = Offset.lerp(pull, rest, 0.5)! + Offset((rest.dx - pull.dx) * 0.12, -150);
      case RevealHoleCardCommand(:final card):
        final hole = _cards.where((c) => c.target.isDealer && !c.faceUp).firstOrNull;
        if (hole != null) {
          hole.card = card;
          hole.faceUp = true;
          r.card = hole;
          r.fromPositions[hole.id] = hole.pos;
        }
      case SplitHandCommand(:final seat, :final hand):
        _beginSplit(r, seat, hand);
      case PlaceBetCommand(:final seat, :final hand, :final cents):
        final s = ChipStackState(
          id: _nextId++,
          seat: seat,
          hand: hand,
          cents: cents,
          kind: ChipStackKind.bet,
          pos: geometry.playerPocket(seat),
        )..opacity = 0;
        _chips.add(s);
        r.stack = s;
      case PayoutCommand(:final seat, :final hand, :final cents):
        final s = ChipStackState(
          id: _nextId++,
          seat: seat,
          hand: hand,
          cents: cents,
          kind: ChipStackKind.payout,
          pos: TableGeometry.rackCenter,
        )..opacity = 0;
        _chips.add(s);
        r.stack = s;
      case CollectBetCommand(:final seat, :final hand):
        r.stack = _chips
            .where((c) => c.seat == seat && c.hand == hand && c.kind == ChipStackKind.bet)
            .firstOrNull;
        if (r.stack != null) r.chipFrom[r.stack!.id] = r.stack!.pos;
      case CollectAllCommand():
        for (final c in _cards) {
          r.fromPositions[c.id] = c.pos;
        }
        for (final s in _chips) {
          r.chipFrom[s.id] = s.pos;
        }
        _emit(r, 'sweep', DealerCue.cardLand);
      case ShuffleCommand():
        _cards.clear();
        _chips.clear();
        _handCounts.clear();
        _badges.clear();
        shuffleProgress = 0;
        _emit(r, 'shuffle', DealerCue.shuffle);
      case ReactCommand(:final reaction, :final seat, :final hand):
        mood = switch (reaction) {
          DealerReaction.blackjack || DealerReaction.win || DealerReaction.dealerBust => DealerMood.smile,
          DealerReaction.bust => DealerMood.wince,
          DealerReaction.dealerBlackjack => DealerMood.surprised,
          DealerReaction.push => DealerMood.neutral,
        };
        moodLevel = 1;
        _moodElapsed = Duration.zero;
        if (seat != null) {
          final badge = switch (reaction) {
            DealerReaction.blackjack => SeatBadge.blackjack,
            DealerReaction.bust => SeatBadge.bust,
            DealerReaction.win || DealerReaction.dealerBust => SeatBadge.win,
            DealerReaction.push => SeatBadge.push,
            DealerReaction.dealerBlackjack => SeatBadge.lose,
          };
          _badges[(seat, hand)] = badge;
        }
        if (reaction == DealerReaction.blackjack) _emit(r, 'bj', DealerCue.blackjack);
        if (reaction == DealerReaction.bust) _emit(r, 'bust', DealerCue.bust);
      case TurnTimerCommand(:final seat, :final total):
        if (seat == null) {
          turnSeat = null;
          _turnTotal = Duration.zero;
          _turnElapsed = Duration.zero;
        } else {
          turnSeat = seat;
          _turnTotal = total;
          _turnElapsed = Duration.zero;
          _turnWarned = false;
        }
      case PauseCommand():
        break;
    }
  }

  void _beginSplit(_Running r, int seat, int hand) {
    final old = handCount(seat);
    for (final c in _cards.where((c) => c.target.seat == seat)) {
      r.fromPositions[c.id] = c.pos;
    }
    for (final s in _chips.where((s) => s.seat == seat)) {
      r.chipFrom[s.id] = s.pos;
    }
    // Shift later hands right.
    for (final c in _cards.where((c) => c.target.seat == seat && c.target.hand > hand)) {
      c.target = HandTarget.seat(seat, hand: c.target.hand + 1);
    }
    for (final s in _chips.where((s) => s.seat == seat && s.hand > hand)) {
      s.hand += 1;
    }
    final handCards = cardsFor(HandTarget.seat(seat, hand: hand));
    if (handCards.length >= 2) {
      final moved = handCards[1];
      moved
        ..target = HandTarget.seat(seat, hand: hand + 1)
        ..index = 0;
      for (var i = 2; i < handCards.length; i++) {
        handCards[i].index = i - 1;
      }
    }
    _handCounts[seat] = old + 1;
    final bet = _chips
        .where((s) => s.seat == seat && s.hand == hand && s.kind == ChipStackKind.bet)
        .firstOrNull;
    if (bet != null) {
      final dup = ChipStackState(
        id: _nextId++,
        seat: seat,
        hand: hand + 1,
        cents: bet.cents,
        kind: ChipStackKind.bet,
        pos: geometry.playerPocket(seat),
      );
      _chips.add(dup);
      r.chipFrom[dup.id] = dup.pos;
    }
    _emit(r, 'split', DealerCue.chipPlace);
  }

  Offset _cardRest(TableCard c) =>
      geometry.cardRest(c.target, c.index, handCount: c.target.isDealer ? 1 : handCount(c.target.seat));

  Offset _chipRest(ChipStackState s) {
    final spot = geometry.betSpot(s.seat, hand: s.hand, handCount: handCount(s.seat));
    if (s.kind == ChipStackKind.bet) return spot;
    // Payouts sit beside the bet, towards the table centre.
    final dir = spot.dx > 500 ? -1.0 : 1.0;
    return spot + Offset(dir * 52, -18);
  }

  static double _seg(double u, double a, double b) => ((u - a) / (b - a)).clamp(0.0, 1.0);

  void _step(_Running r, double u) {
    switch (r.command) {
      case DealCardCommand(:final target):
        _stepDeal(r, u, target);
      case RevealHoleCardCommand():
        _stepReveal(r, u);
      case SplitHandCommand():
        final e = Curves.easeInOutCubic.transform(u);
        for (final c in _cards.where((c) => r.fromPositions.containsKey(c.id))) {
          final to = _cardRest(c);
          c.pos = Offset.lerp(r.fromPositions[c.id], to, e)!;
          c.lift = math.sin(math.pi * u) * 0.25;
        }
        for (final s in _chips.where((s) => r.chipFrom.containsKey(s.id))) {
          s.pos = Offset.lerp(r.chipFrom[s.id], _chipRest(s), e)!;
        }
      case PlaceBetCommand():
        final s = r.stack!;
        final e = Curves.easeOutCubic.transform(u);
        s.pos = Offset.lerp(geometry.playerPocket(s.seat), _chipRest(s), e)!;
        s.opacity = _seg(u, 0, 0.3);
        s.lift = math.sin(math.pi * u) * 0.6;
        if (u >= 1) _emit(r, 'place', DealerCue.chipPlace);
      case PayoutCommand():
        _stepPayout(r, u);
      case CollectBetCommand():
        _stepCollectBet(r, u);
      case CollectAllCommand():
        _stepCollectAll(r, u);
      case ShuffleCommand():
        _stepShuffle(r, u);
      case ReactCommand(:final reaction):
        moodLevel = 1;
        if (reaction == DealerReaction.bust || reaction == DealerReaction.dealerBlackjack) {
          headTilt = math.sin(u * 6 * math.pi) * 0.07 * (1 - u);
        } else if (reaction != DealerReaction.push) {
          headNod = math.sin(u * 4 * math.pi) * 0.5 * (1 - u);
        }
      case PauseCommand() || TurnTimerCommand():
        break;
    }
  }

  void _stepDeal(_Running r, double u, HandTarget target) {
    final c = r.card!;
    final rest = _cardRest(c);
    final restRot = geometry.cardRestRotation(target);
    final pull = TableGeometry.shoeExit + const Offset(-46, 26);
    const shoulder = TableGeometry.rightShoulder;

    if (u < 0.22) {
      final k = Curves.easeInOut.transform(_seg(u, 0, 0.22));
      rightArm.hand = Offset.lerp(r.startRight, TableGeometry.shoeExit, k)!;
      rightArm.grip = k;
      return;
    }
    if (!c.visible) {
      c.visible = true;
      cardsDealtFromShoe++;
      shoeLevel = math.max(0, 1 - cardsDealtFromShoe / shoeSize);
      _emit(r, 'draw', DealerCue.cardDraw);
    }
    if (u < 0.34) {
      final k = Curves.easeOut.transform(_seg(u, 0.22, 0.34));
      c.pos = Offset.lerp(TableGeometry.shoeExit, pull, k)!;
      c.rotation = -0.35;
      c.lift = 0.05 * k;
      rightArm.hand = c.pos;
      rightArm.grip = 1;
      return;
    }
    if (u < 0.86) {
      final k = _seg(u, 0.34, 0.86);
      final e = Curves.easeOutCubic.transform(k);
      c.pos = quadBezier(pull, r.control!, rest, e);
      final spin = (rest.dx < 500 ? -1 : 1) * 0.3;
      c.rotation = (-0.35 + (restRot + 0.35) * e) + math.sin(math.pi * e) * spin;
      c.lift = math.sin(math.pi * e);
      if (c.faceUp) {
        c.flip = Curves.easeInOut.transform(_seg(k, 0.3, 0.75));
        if (c.flip >= 0.5) _emit(r, 'flip', DealerCue.cardFlip);
      }
      final release = clampToReach(shoulder, c.pos, TableGeometry.reach);
      final back = Curves.easeInOut.transform(_seg(k, 0.35, 1));
      rightArm.hand = Offset.lerp(release, TableGeometry.rightHandRest, back)!;
      rightArm.grip = 1 - _seg(k, 0.2, 0.45);
      return;
    }
    c
      ..pos = rest
      ..rotation = restRot
      ..lift = 0
      ..flip = c.faceUp ? 1 : 0;
    rightArm.hand = TableGeometry.rightHandRest;
    rightArm.grip = 0;
    _emit(r, 'land', DealerCue.cardLand);
  }

  void _stepReveal(_Running r, double u) {
    final c = r.card;
    if (c == null) return;
    final from = r.fromPositions[c.id]!;
    if (u < 0.35) {
      final k = Curves.easeInOut.transform(_seg(u, 0, 0.35));
      leftArm.hand = Offset.lerp(r.startLeft, from + const Offset(-8, 16), k)!;
      leftArm.grip = k;
    } else if (u < 0.8) {
      final f = _seg(u, 0.35, 0.8);
      c.flip = Curves.easeInOut.transform(f);
      c.lift = math.sin(math.pi * f) * 0.7;
      c.pos = from + Offset(0, -26 * math.sin(math.pi * f));
      leftArm.hand = c.pos + const Offset(-8, 16);
      leftArm.grip = 1;
      if (c.flip >= 0.5) _emit(r, 'flip', DealerCue.cardFlip);
    } else {
      final k = Curves.easeInOut.transform(_seg(u, 0.8, 1));
      c
        ..flip = 1
        ..lift = 0
        ..pos = from;
      leftArm.hand = Offset.lerp(from + const Offset(-8, 16), TableGeometry.leftHandRest, k)!;
      leftArm.grip = 1 - k;
    }
  }

  ArmState _armFor(int seat) => geometry.seatSpot(seat).dx < 500 ? leftArm : rightArm;
  Offset _shoulderFor(int seat) =>
      geometry.seatSpot(seat).dx < 500 ? TableGeometry.leftShoulder : TableGeometry.rightShoulder;
  Offset _restFor(int seat) =>
      geometry.seatSpot(seat).dx < 500 ? TableGeometry.leftHandRest : TableGeometry.rightHandRest;
  Offset _startFor(_Running r, int seat) => geometry.seatSpot(seat).dx < 500 ? r.startLeft : r.startRight;

  void _stepPayout(_Running r, double u) {
    final s = r.stack!;
    final arm = _armFor(s.seat);
    final shoulder = _shoulderFor(s.seat);
    final rack = TableGeometry.rackCenter + Offset(geometry.seatSpot(s.seat).dx < 500 ? -80 : 80, 0);
    if (u < 0.3) {
      final k = Curves.easeInOut.transform(_seg(u, 0, 0.3));
      arm.hand = Offset.lerp(_startFor(r, s.seat), rack, k)!;
      arm.grip = k;
      s.pos = rack;
      s.opacity = 0;
      return;
    }
    if (u < 0.85) {
      final k = _seg(u, 0.3, 0.85);
      final e = Curves.easeOutCubic.transform(k);
      s.opacity = 1;
      s.pos = Offset.lerp(rack, _chipRest(s), e)!;
      s.lift = math.sin(math.pi * e) * 0.5;
      final release = clampToReach(shoulder, s.pos, TableGeometry.reach);
      arm.hand = Offset.lerp(release, _restFor(s.seat), Curves.easeInOut.transform(_seg(k, 0.5, 1)))!;
      arm.grip = 1 - _seg(k, 0.4, 0.6);
      return;
    }
    s
      ..pos = _chipRest(s)
      ..lift = 0
      ..opacity = 1;
    arm.hand = _restFor(s.seat);
    arm.grip = 0;
    _emit(r, 'pay', DealerCue.payout);
  }

  void _stepCollectBet(_Running r, double u) {
    final s = r.stack;
    if (s == null) return;
    final arm = _armFor(s.seat);
    final shoulder = _shoulderFor(s.seat);
    final from = r.chipFrom[s.id]!;
    final reachPoint = clampToReach(shoulder, from, TableGeometry.reach);
    if (u < 0.4) {
      final k = Curves.easeInOut.transform(_seg(u, 0, 0.4));
      arm.hand = Offset.lerp(_startFor(r, s.seat), reachPoint, k)!;
      arm.grip = 0;
      return;
    }
    _emit(r, 'collect', DealerCue.chipCollect);
    final k = Curves.easeInCubic.transform(_seg(u, 0.4, 0.92));
    s.pos = Offset.lerp(from, TableGeometry.rackCenter, k)!;
    s.opacity = 1 - _seg(u, 0.8, 1);
    arm.hand = Offset.lerp(reachPoint, _restFor(s.seat), Curves.easeInOut.transform(_seg(u, 0.4, 1)))!;
    arm.grip = 0.4;
  }

  void _stepCollectAll(_Running r, double u) {
    final n = math.max(1, _cards.length);
    for (var i = 0; i < _cards.length; i++) {
      final c = _cards[i];
      final from = r.fromPositions[c.id] ?? c.pos;
      final start = i / n * 0.4;
      final k = Curves.easeInOutCubic.transform(_seg(u, start, start + 0.5));
      final to = TableGeometry.discardCenter + Offset(0, -i * 1.5);
      c.pos = Offset.lerp(from, to, k)!;
      c.rotation = c.rotation * (1 - k) + 0.5 * k;
      c.lift = math.sin(math.pi * k) * 0.3;
      c.opacity = 1 - _seg(u, 0.85, 1) * (k >= 1 ? 1 : 0);
    }
    for (final s in _chips) {
      final from = r.chipFrom[s.id] ?? s.pos;
      final k = Curves.easeIn.transform(_seg(u, 0.45, 1));
      s.pos = Offset.lerp(from, geometry.playerPocket(s.seat), k)!;
      s.opacity = 1 - k;
    }
    if (u >= 0.45) _emit(r, 'chips', DealerCue.chipCollect);
    // Both hands sweep in towards the discard tray.
    final l1 = Curves.easeInOut.transform(_seg(u, 0, 0.35));
    final l2 = Curves.easeInOut.transform(_seg(u, 0.35, 0.75));
    final l3 = Curves.easeInOut.transform(_seg(u, 0.75, 1));
    final leftSweep = clampToReach(TableGeometry.leftShoulder, const Offset(330, 760), TableGeometry.reach);
    final rightSweep = clampToReach(TableGeometry.rightShoulder, const Offset(690, 760), TableGeometry.reach);
    leftArm.hand = l3 > 0
        ? Offset.lerp(TableGeometry.discardCenter + const Offset(60, 20), TableGeometry.leftHandRest, l3)!
        : l2 > 0
            ? Offset.lerp(leftSweep, TableGeometry.discardCenter + const Offset(60, 20), l2)!
            : Offset.lerp(r.startLeft, leftSweep, l1)!;
    rightArm.hand = l3 > 0
        ? Offset.lerp(const Offset(470, 520), TableGeometry.rightHandRest, l3)!
        : l2 > 0
            ? Offset.lerp(rightSweep, const Offset(470, 520), l2)!
            : Offset.lerp(r.startRight, rightSweep, l1)!;
    leftArm.grip = 0.3;
    rightArm.grip = 0.3;
  }

  void _stepShuffle(_Running r, double u) {
    shuffleProgress = u;
    const c = TableGeometry.shuffleCenter;
    if (u < 0.12) {
      final k = Curves.easeInOut.transform(_seg(u, 0, 0.12));
      leftArm.hand = Offset.lerp(r.startLeft, c + const Offset(-120, 0), k)!;
      rightArm.hand = Offset.lerp(r.startRight, c + const Offset(120, 0), k)!;
      leftArm.grip = rightArm.grip = k;
    } else if (u < 0.86) {
      final k = _seg(u, 0.12, 0.86);
      final squeeze = math.sin(k * 3 * math.pi).abs();
      leftArm.hand = c + Offset(-120 + 55 * squeeze, -8 * squeeze);
      rightArm.hand = c + Offset(120 - 55 * squeeze, -8 * squeeze);
      leftArm.grip = rightArm.grip = 1;
      if (k > 0.33) _emit(r, 'riffle2', DealerCue.cardLand);
      if (k > 0.66) _emit(r, 'riffle3', DealerCue.cardLand);
    } else {
      final k = Curves.easeInOut.transform(_seg(u, 0.86, 1));
      // Right hand carries the deck to the shoe, left returns to rest.
      rightArm.hand = Offset.lerp(c, TableGeometry.shoeExit, k)!;
      leftArm.hand = Offset.lerp(c + const Offset(-65, -8), TableGeometry.leftHandRest, k)!;
      leftArm.grip = 1 - k;
      if (u >= 0.95) {
        shoeLevel = 1;
        cardsDealtFromShoe = 0;
      }
    }
  }

  void _finish(_Running r) {
    switch (r.command) {
      case PlaceBetCommand():
        final s = r.stack!;
        final existing = _chips
            .where((x) => x != s && x.seat == s.seat && x.hand == s.hand && x.kind == ChipStackKind.bet)
            .firstOrNull;
        if (existing != null) {
          existing.cents += s.cents;
          _chips.remove(s);
        }
        s
          ..lift = 0
          ..opacity = 1;
      case CollectBetCommand():
        if (r.stack != null) _chips.remove(r.stack);
      case CollectAllCommand():
        _cards.clear();
        _chips.clear();
        _handCounts.clear();
        _badges.clear();
      case ShuffleCommand():
        shuffleProgress = null;
        shoeLevel = 1;
        cardsDealtFromShoe = 0;
        rightArm.grip = 0;
      case SplitHandCommand():
        for (final c in _cards.where((c) => r.fromPositions.containsKey(c.id))) {
          c.lift = 0;
        }
      case ReactCommand():
        headTilt = 0;
        _moodElapsed = Duration.zero;
      default:
        break;
    }
  }

  @override
  void dispose() {
    for (final r in [?_active, ..._queue]) {
      if (!r.completer.isCompleted) r.completer.complete();
    }
    _queue.clear();
    _active = null;
    super.dispose();
  }
}
