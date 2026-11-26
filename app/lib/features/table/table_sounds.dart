/// The table's sound design: turns the [DealerController]'s cues (emitted at
/// exact animation instants) into sounds, haptics and celebrations.
///
/// The viewer's own seat gets the full treatment (graded win fanfares,
/// streaks, countdown ticks, haptics); other seats are mixed lower and never
/// trigger fanfares (so they can't mask the viewer's own).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/audio/sfx.dart';
import '../../core/audio/sound_providers.dart';
import '../../core/audio/sound_service.dart';
import '../dealer/dealer_feedback.dart';

/// [jackpot]: a game-specific big hit of the Sprint 2 games (straight up at
/// roulette, royal flush, hard way…), shown with its own [Celebration.label].
enum CelebrationKind { win, bigWin, blackjack, streak, dealerBust, jackpot }

@immutable
class Celebration {
  const Celebration(this.kind, this.serial, {this.cents, this.streak, this.label});
  final CelebrationKind kind;

  /// Increases with every celebration (lets the overlay restart).
  final int serial;
  final int? cents;
  final int? streak;

  /// Banner text overriding the default of [kind] (games' own hits).
  final String? label;

  /// Big ones get the coin rain, the flash and the heavy haptics.
  bool get big =>
      kind == CelebrationKind.bigWin || kind == CelebrationKind.blackjack || kind == CelebrationKind.jackpot || (streak ?? 0) >= 5;

  @override
  String toString() => 'Celebration($kind${cents == null ? '' : ' $cents'}${streak == null ? '' : ' x$streak'})';
}

/// How a winning hand of the viewer is graded.
enum WinGrade { small, medium, big }

/// profit / table minimum: < 2 small, < 8 medium, otherwise big.
WinGrade gradeWin(int profitCents, int minBetCents) {
  final ratio = minBetCents <= 0 ? 1.0 : profitCents / minBetCents;
  if (ratio >= 8) return WinGrade.big;
  if (ratio >= 2) return WinGrade.medium;
  return WinGrade.small;
}

class TableSoundscape implements DealerFeedback {
  TableSoundscape({
    required this.sound,
    required this.mySeat,
    required this.minBetCents,
    required this.maxBetCents,
    Haptics? haptics,
    math.Random? random,
  })  : haptics = haptics ?? Haptics(() => false),
        _random = random ?? math.Random();

  final SoundService sound;
  final Haptics haptics;

  /// The viewer's seat (null: spectator / queued).
  final int? Function() mySeat;
  final int Function() minBetCents;
  final int Function() maxBetCents;
  final math.Random _random;

  /// Last celebration (the overlay listens).
  final celebrations = ValueNotifier<Celebration?>(null);

  /// Consecutive winning hands of the viewer at this table.
  int streak = 0;
  var _serial = 0;
  bool _suspense = false;

  static const othersVolume = 0.55;

  bool _mine(CueInfo i) => i.seat != null && i.seat == mySeat();
  double _vol(CueInfo i, {double other = othersVolume}) => _mine(i) ? 1 : other;

  void _celebrate(CelebrationKind k, {int? cents, int? streak}) {
    final c = Celebration(k, ++_serial, cents: cents, streak: streak);
    celebrations.value = c;
    haptics(c.big ? Haptic.celebration : Haptic.medium);
  }

  @override
  void cue(DealerCue cue, [CueInfo info = CueInfo.none]) {
    switch (cue) {
      case DealerCue.cardDraw || DealerCue.blackjack || DealerCue.bust:
        break; // sound comes with the landing / the reaction
      case DealerCue.cardLand:
        sound.play(SfxVariants.pick(SfxVariants.cardDeal, _random), volume: info.seat == null ? 0.9 : _vol(info, other: 0.75));
        if (_mine(info)) haptics(Haptic.selection);
      case DealerCue.cardFlip:
        sound.play(SfxVariants.pick(SfxVariants.cardFlip, _random), volume: 0.6);
      case DealerCue.holeReveal:
        sound.play(Sfx.cardRevealHole);
      case DealerCue.holeFlip:
        haptics(Haptic.light);
      case DealerCue.peek:
        sound.play(SfxVariants.pick(SfxVariants.cardFlip, _random), volume: 0.45);
        // "Does the dealer have blackjack?": a short roll for the seated viewer.
        if (mySeat() != null) sound.play(Sfx.drumrollShort, volume: 0.8);
      case DealerCue.chipPlace:
        if (_mine(info) && (info.cents ?? 0) >= maxBetCents() && maxBetCents() > 0) {
          sound.play(Sfx.chipAllin);
          haptics(Haptic.heavy);
        } else {
          sound.play(Sfx.chipBetPlace, volume: _vol(info));
          if (_mine(info)) {
            sound.play(SfxVariants.pick(SfxVariants.chipClink, _random), volume: 0.7);
            haptics(Haptic.selection);
          }
        }
      case DealerCue.chipCollect:
        sound.play(Sfx.chipsRakeLose, volume: _vol(info, other: 0.45));
      case DealerCue.payoutStart:
        sound.play(Sfx.chipsPushWin, volume: _vol(info, other: 0.45));
      case DealerCue.payout:
        if (_mine(info)) {
          sound.play(SfxVariants.pick(SfxVariants.chipClink, _random));
          sound.play(Sfx.coinSingle, volume: 0.8);
          haptics(Haptic.medium);
        }
      case DealerCue.sweep:
        sound.play(Sfx.cardsCollect, volume: 0.8);
      case DealerCue.chipsReturn:
        sound.play(Sfx.chipStack, volume: 0.7);
      case DealerCue.shuffle:
        sound.play(Sfx.shuffleRiffle);
      case DealerCue.shuffleBridge:
        sound.play(Sfx.shuffleBridge);
      case DealerCue.react:
        _react(info);
      case DealerCue.timerTick:
        if (!_mine(info)) break;
        final s = info.seconds ?? 99;
        if (s <= 0) break;
        if (s <= 5) {
          sound.play(Sfx.timerUrgent);
          haptics(Haptic.selection);
        } else {
          sound.play(Sfx.timerTick, volume: 0.8);
        }
      case DealerCue.timerWarning:
        if (_mine(info)) haptics(Haptic.medium);
      case DealerCue.action:
        final s = switch (info.action) {
          CueAction.hit => Sfx.actionHit,
          CueAction.stand => Sfx.actionStand,
          CueAction.double => Sfx.actionDouble,
          CueAction.split => Sfx.actionSplit,
          CueAction.surrender => Sfx.actionSurrender,
          CueAction.insurance => Sfx.actionInsurance,
          null => null,
        };
        if (s != null) sound.play(s, volume: _vol(info));
      case DealerCue.timeout:
        sound.play(Sfx.timeout, volume: _vol(info, other: 0.35));
        if (_mine(info)) haptics(Haptic.heavy);
      case DealerCue.seatJoin:
        // The viewer's own arrival is voiced by the table screen.
        if (!_mine(info)) sound.play(Sfx.seatJoin, volume: 0.8);
      case DealerCue.power:
        final s = powerSfx(info.power);
        if (s != null) sound.play(s, volume: _vol(info, other: 0.6));
        if (_mine(info)) haptics(Haptic.medium);
      case DealerCue.suspenseStart:
        if (!_suspense) {
          _suspense = true;
          sound.startLoop(SoundChannel.suspense, Sfx.drumrollLong, volume: 0.7);
        }
      case DealerCue.suspenseStop:
        if (_suspense) {
          _suspense = false;
          sound.stopLoop(SoundChannel.suspense);
        }
    }
  }

  static Sfx? powerSfx(String? power) => switch (power) {
        'freeSplit' => Sfx.powerFreeSplit,
        'freeDouble' => Sfx.powerFreeDouble,
        'freeInsurance' => Sfx.powerFreeInsurance,
        'peek' => Sfx.powerPeek,
        'secondChance' => Sfx.powerSecondChance,
        _ => null,
      };

  void _react(CueInfo info) {
    final reaction = info.reaction;
    if (info.seat == null) {
      if (reaction == 'dealerBust') {
        sound.play(Sfx.crowdCheer, volume: 0.7); // the whole table cheers
        sound.play(Sfx.dealerBust);
        if (mySeat() != null) _celebrate(CelebrationKind.dealerBust);
      } else if (reaction == 'dealerBlackjack') {
        sound.play(Sfx.crowdOoh, volume: 0.7);
        sound.play(Sfx.dealerBlackjack);
        haptics(Haptic.heavy);
      }
      return;
    }
    if (!_mine(info)) {
      // Others: the crowd reacts (quietly), nothing that could mask mine.
      switch (reaction) {
        case 'blackjack':
          sound.play(Sfx.crowdCheer, volume: 0.45);
          sound.play(Sfx.coinSingle, volume: 0.5);
        case 'win':
          sound.play(Sfx.coinSingle, volume: 0.5);
        case 'bust':
          sound.play(Sfx.crowdOoh, volume: 0.3);
      }
      return;
    }
    switch (reaction) {
      case 'blackjack':
        streak++;
        sound.play(Sfx.blackjackJackpot);
        _celebrate(CelebrationKind.blackjack, cents: info.cents, streak: streak);
      case 'win' || 'dealerBust':
        streak++;
        if (streak >= 5 && streak % 5 == 0) {
          sound.play(Sfx.winStreak5);
          _celebrate(CelebrationKind.streak, cents: info.cents, streak: streak);
        } else if (streak == 3) {
          sound.play(Sfx.winStreak3);
          _celebrate(CelebrationKind.streak, cents: info.cents, streak: streak);
        } else {
          switch (gradeWin(info.cents ?? 0, minBetCents())) {
            case WinGrade.small:
              sound.play(Sfx.winSmall);
              haptics(Haptic.light);
            case WinGrade.medium:
              sound.play(Sfx.winMedium);
              _celebrate(CelebrationKind.win, cents: info.cents);
            case WinGrade.big:
              sound.play(Sfx.slotJackpotBells, volume: 0.6);
              sound.play(Sfx.winBig);
              _celebrate(CelebrationKind.bigWin, cents: info.cents);
          }
        }
      case 'push':
        sound.play(Sfx.pushTie);
      case 'lose':
        streak = 0;
        sound.play(Sfx.loseHand);
      case 'bust':
        streak = 0;
        sound.play(Sfx.crowdOoh, volume: 0.8);
        sound.play(Sfx.bust);
        haptics(Haptic.heavy);
      case 'dealerBlackjack':
        streak = 0;
    }
  }

  /// Leaving the table: stop the loops this scape may have started.
  void dispose() {
    if (_suspense) sound.stopLoop(SoundChannel.suspense);
    _suspense = false;
    celebrations.dispose();
  }
}
