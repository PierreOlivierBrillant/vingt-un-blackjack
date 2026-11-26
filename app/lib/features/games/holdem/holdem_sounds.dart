/// Sounds of the Texas hold'em (group "holdem": `tools/sfx/games/holdem.mjs`,
/// quota in `tools/sfx/quotas.json`, manifest `assets/sfx/MANIFEST.holdem.md`).
/// Played by the stage (`holdem_stage.dart`) through its cues.
///
/// Every sound of the group is listed in [HoldemSfx.all] (`holdemGame.sounds`):
/// `test/unit/sound_test.dart` checks WAVs, durations and the quota.
library;

import '../../../core/audio/sfx.dart';

abstract final class HoldemSfx {
  /// "Check": two knocks on the table.
  static const checkKnock = GameSfx('holdem_check_knock', 320);

  /// A card pitched by the croupier (hole cards, board cards leaving the deck).
  static const cardPitch = GameSfx('holdem_card_pitch', 200, cooldownMs: 20);

  /// A burnt card.
  static const cardBurn = GameSfx('holdem_card_burn', 240);

  /// Board cards (or my hole cards) turned face up.
  static const boardFlip = GameSfx('holdem_board_flip', 220);

  /// Blind / bet / raise / call pushed in front of a seat.
  static const chipsBet = GameSfx('holdem_chips_bet', 340);

  /// The bets swept into the pot at the end of a street.
  static const chipsCollect = GameSfx('holdem_chips_collect', 600);

  /// Somebody is all-in.
  static const allIn = GameSfx('holdem_all_in', 950, tier: SfxTier.fanfare);

  /// Cards mucked.
  static const fold = GameSfx('holdem_fold', 260);

  /// Hands turned over at the showdown.
  static const showdown = GameSfx('holdem_showdown', 700, tier: SfxTier.fanfare);

  /// The pot (or a side pot) pushed to a winner.
  static const potWin = GameSfx('holdem_pot_win', 750);

  /// It is my turn.
  static const yourTurn = GameSfx('holdem_your_turn', 360, tier: SfxTier.ui);

  static const all = <GameSfx>[checkKnock, cardPitch, cardBurn, boardFlip, chipsBet, chipsCollect, allIn, fold, showdown, potWin, yourTurn];
}
