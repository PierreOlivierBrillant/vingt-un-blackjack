import 'package:flutter/services.dart';

/// Moments where sound / haptics fire. The controller emits them at exact
/// points of each animation timeline; the app decides how to render them.
enum DealerCue {
  cardDraw,
  cardLand,
  cardFlip,
  chipPlace,
  chipCollect,
  payout,
  shuffle,
  blackjack,
  bust,
  timerWarning,
}

/// Sound/haptic hook. Swap in an audio-backed implementation later; the
/// controller only knows this interface.
abstract interface class DealerFeedback {
  void cue(DealerCue cue);
}

class SilentDealerFeedback implements DealerFeedback {
  const SilentDealerFeedback();
  @override
  void cue(DealerCue cue) {}
}

/// Default implementation using only platform facilities (no audio assets):
/// system click sounds and haptic patterns.
class SystemDealerFeedback implements DealerFeedback {
  SystemDealerFeedback({this.sound = true, this.haptics = true});

  bool sound;
  bool haptics;

  @override
  void cue(DealerCue cue) {
    if (sound && _clicks.contains(cue)) {
      SystemSound.play(SystemSoundType.click);
    }
    if (!haptics) return;
    switch (cue) {
      case DealerCue.cardLand || DealerCue.chipPlace:
        HapticFeedback.selectionClick();
      case DealerCue.cardFlip || DealerCue.chipCollect:
        HapticFeedback.lightImpact();
      case DealerCue.payout || DealerCue.shuffle || DealerCue.timerWarning:
        HapticFeedback.mediumImpact();
      case DealerCue.blackjack || DealerCue.bust:
        HapticFeedback.heavyImpact();
      case DealerCue.cardDraw:
        break;
    }
  }

  static const _clicks = {DealerCue.cardLand, DealerCue.cardFlip, DealerCue.chipPlace, DealerCue.payout};
}

/// Records cues (tests, debugging overlays).
class RecordingDealerFeedback implements DealerFeedback {
  final cues = <DealerCue>[];
  @override
  void cue(DealerCue cue) => cues.add(cue);
}
