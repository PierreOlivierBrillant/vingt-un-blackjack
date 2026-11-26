/// Sounds of the baccarat (group "baccarat": `tools/sfx/games/baccarat.mjs`,
/// quota in `tools/sfx/quotas.json`), and the stage cues that play them.
/// Every sound is listed in [BaccaratSfx.all] (`baccaratGame.sounds`):
/// `test/unit/sound_test.dart` checks WAVs and durations.
library;

import '../../../core/audio/sfx.dart';
import '../../../core/audio/sound_providers.dart' show Haptic;
import '../../stage/stage_controller.dart';

abstract final class BaccaratSfx {
  static const cardPitch = GameSfx('baccarat_card_pitch', 300, cooldownMs: 60);
  static const cardSqueeze = GameSfx('baccarat_card_squeeze', 600);
  static const cardReveal = GameSfx('baccarat_card_reveal', 280, cooldownMs: 60);
  static const cardSideways = GameSfx('baccarat_card_sideways', 360);
  static const burn = GameSfx('baccarat_burn', 900);
  static const shoeShuffle = GameSfx('baccarat_shoe_shuffle', 1600);
  static const cutCard = GameSfx('baccarat_cut_card', 450);
  static const winPlayer = GameSfx('baccarat_win_player', 1100, tier: SfxTier.fanfare);
  static const winBanker = GameSfx('baccarat_win_banker', 1100, tier: SfxTier.fanfare);
  static const tie = GameSfx('baccarat_tie', 1400, tier: SfxTier.fanfare);
  static const natural = GameSfx('baccarat_natural', 1000, tier: SfxTier.fanfare);
  static const pair = GameSfx('baccarat_pair', 800, tier: SfxTier.fanfare);

  static const all = <GameSfx>[cardPitch, cardSqueeze, cardReveal, cardSideways, burn, shoeShuffle, cutCard, winPlayer, winBanker, tie, natural, pair];
}

/// Stage cues of the baccarat animation (names are stable: tests).
abstract final class BaccaratCues {
  static const pitch = StageCue('pitch', sound: BaccaratSfx.cardPitch);
  static const sideways = StageCue('sideways', sound: BaccaratSfx.cardSideways);
  static const squeeze = StageCue('squeeze', sound: BaccaratSfx.cardSqueeze);
  static const reveal = StageCue('reveal', sound: BaccaratSfx.cardReveal, haptic: Haptic.light);
  static const burn = StageCue('burn', sound: BaccaratSfx.burn);
  static const shuffle = StageCue('shuffle', sound: BaccaratSfx.shoeShuffle);
  static const cut = StageCue('cut', sound: BaccaratSfx.cutCard);
  static const winPlayer = StageCue('winPlayer', sound: BaccaratSfx.winPlayer);
  static const winBanker = StageCue('winBanker', sound: BaccaratSfx.winBanker);
  static const tie = StageCue('tie', sound: BaccaratSfx.tie, haptic: Haptic.medium);
  static const natural = StageCue('natural', sound: BaccaratSfx.natural);
  static const pair = StageCue('pair', sound: BaccaratSfx.pair);
  static const collect = StageCue('collect', sound: Sfx.cardsCollect);
  static const chipsWin = StageCue('chipsWin', sound: Sfx.chipsPushWin);
  static const chipsLose = StageCue('chipsLose', sound: Sfx.chipsRakeLose);
}
