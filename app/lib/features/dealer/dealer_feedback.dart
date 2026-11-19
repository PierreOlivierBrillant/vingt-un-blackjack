import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Moments where sound / haptics fire. The controller emits them at exact
/// points of each animation timeline (e.g. [cardLand] slightly before the
/// card touches the felt, so the sample's thump lands with it); the
/// director adds zero-duration cues at their place in the queue (actions,
/// timeouts, powers...). The app decides how to render them.
enum DealerCue {
  /// A card leaves the shoe.
  cardDraw,

  /// A card touches the felt (seat or dealer). Info: seat (null = dealer).
  cardLand,

  /// A face-up card turns over in flight.
  cardFlip,

  /// The dealer starts turning the hole card (lead-in of the reveal).
  holeReveal,

  /// The hole card turns face up.
  holeFlip,

  /// Chips land on a betting spot. Info: seat, cents.
  chipPlace,

  /// A losing bet is raked away. Info: seat.
  chipCollect,

  /// Winnings slide from the rack towards a seat. Info: seat, cents.
  payoutStart,

  /// Winnings land beside the bet. Info: seat, cents.
  payout,

  /// End of hand: the cards are swept to the discard tray.
  sweep,

  /// End of hand: chips left on the felt go back to their owners.
  chipsReturn,

  shuffle,

  /// Second half of the shuffle (bridge).
  shuffleBridge,

  /// A dealer reaction / seat badge appears. Info: reaction, seat, hand,
  /// cents (profit for wins).
  react,

  /// Legacy coarse cues (haptics): a blackjack / a bust reaction.
  blackjack,
  bust,

  /// One more whole second elapsed on the turn timer. Info: seat, seconds.
  timerTick,

  /// 75 % of the turn time used. Info: seat.
  timerWarning,

  /// Director cue: a player action was applied. Info: seat, action.
  action,

  /// Director cue: a seat ran out of time. Info: seat.
  timeout,

  /// Director cue: a player sat down. Info: seat.
  seatJoin,

  /// Director cue: a power was used. Info: seat, power (enum name).
  power,

  /// Director cue: the dealer checks for blackjack under an ace / ten.
  peek,

  /// Director cue: the dealer will draw; suspense loop on / off.
  suspenseStart,
  suspenseStop,
}

/// Player actions as seen by the feedback layer.
enum CueAction { hit, stand, double, split, surrender, insurance }

/// Details attached to a cue.
@immutable
class CueInfo {
  const CueInfo({this.seat, this.hand = 0, this.cents, this.reaction, this.seconds, this.action, this.power});
  final int? seat;
  final int hand;
  final int? cents;

  /// Name of the `DealerReaction` for [DealerCue.react].
  final String? reaction;
  final int? seconds;
  final CueAction? action;

  /// Name of the `PowerType` for [DealerCue.power].
  final String? power;

  static const none = CueInfo();

  @override
  String toString() => [
        if (seat != null) 'seat$seat',
        if (hand != 0) 'h$hand',
        if (cents != null) '$cents¢',
        ?reaction,
        if (seconds != null) '${seconds}s',
        ?action?.name,
        ?power,
      ].join(' ');
}

/// Sound/haptic hook; the controller only knows this interface.
abstract interface class DealerFeedback {
  void cue(DealerCue cue, [CueInfo info = CueInfo.none]);
}

class SilentDealerFeedback implements DealerFeedback {
  const SilentDealerFeedback();
  @override
  void cue(DealerCue cue, [CueInfo info = CueInfo.none]) {}
}

/// Platform-only fallback (no audio assets): system clicks and haptics.
class SystemDealerFeedback implements DealerFeedback {
  SystemDealerFeedback({this.sound = true, this.haptics = true});

  bool sound;
  bool haptics;

  @override
  void cue(DealerCue cue, [CueInfo info = CueInfo.none]) {
    if (sound && _clicks.contains(cue)) {
      SystemSound.play(SystemSoundType.click);
    }
    if (!haptics) return;
    switch (cue) {
      case DealerCue.cardLand || DealerCue.chipPlace:
        HapticFeedback.selectionClick();
      case DealerCue.cardFlip || DealerCue.chipCollect || DealerCue.holeFlip:
        HapticFeedback.lightImpact();
      case DealerCue.payout || DealerCue.shuffle || DealerCue.timerWarning:
        HapticFeedback.mediumImpact();
      case DealerCue.blackjack || DealerCue.bust:
        HapticFeedback.heavyImpact();
      default:
        break;
    }
  }

  static const _clicks = {DealerCue.cardLand, DealerCue.cardFlip, DealerCue.chipPlace, DealerCue.payout};
}

/// Records cues (tests, debugging overlays).
class RecordingDealerFeedback implements DealerFeedback {
  final cues = <DealerCue>[];
  final infos = <CueInfo>[];
  @override
  void cue(DealerCue cue, [CueInfo info = CueInfo.none]) {
    cues.add(cue);
    infos.add(info);
  }
}

/// Sends every cue to several feedbacks.
class MultiDealerFeedback implements DealerFeedback {
  const MultiDealerFeedback(this.targets);
  final List<DealerFeedback> targets;
  @override
  void cue(DealerCue cue, [CueInfo info = CueInfo.none]) {
    for (final t in targets) {
      t.cue(cue, info);
    }
  }
}
