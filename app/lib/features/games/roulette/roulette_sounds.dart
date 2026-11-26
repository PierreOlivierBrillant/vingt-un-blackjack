/// Sounds of the roulette (group "roulette": `tools/sfx/games/roulette.mjs`,
/// quota in `tools/sfx/quotas.json`, ~0.6 MiB of 1.25). OWNER: roulette implementer.
///
/// Every sound of the group is declared here and listed in [RouletteSfx.all]
/// (`rouletteGame.sounds`): `test/unit/sound_test.dart` checks that each one
/// has its WAV with the same duration, and that every WAV of the group is
/// declared. The loop is mono 22 kHz and plays on `SoundChannel.game`.
library;

import '../../../core/audio/sfx.dart';

abstract final class RouletteSfx {
  /// The ball hits a fret (a decreasing burst while it settles).
  static const ballTick = GameSfx('roulette_ball_tick', 160, tier: SfxTier.ui, cooldownMs: 30);

  /// The ball rolling on the track (loop, `SoundChannel.game`).
  static const spinLoop = GameSfx('roulette_spin_loop', 2000, loop: true);
  static const ballLaunch = GameSfx('roulette_ball_launch', 500);
  static const ballDrop = GameSfx('roulette_ball_drop', 700);

  /// « Faites vos jeux » / « Rien ne va plus ».
  static const placeBets = GameSfx('roulette_place_bets', 900, tier: SfxTier.ui);
  static const noMoreBets = GameSfx('roulette_no_more_bets', 1200);
  static const chipPlace = GameSfx('roulette_chip_place', 180, tier: SfxTier.ui, cooldownMs: 40);
  static const dolly = GameSfx('roulette_dolly', 350);
  static const rake = GameSfx('roulette_rake', 800);
  static const payout = GameSfx('roulette_payout', 600);
  static const straightWin = GameSfx('roulette_straight_win', 1800, tier: SfxTier.fanfare);
  static const zero = GameSfx('roulette_zero', 1200, tier: SfxTier.fanfare);

  static const all = <GameSfx>[ballTick, spinLoop, ballLaunch, ballDrop, placeBets, noMoreBets, chipPlace, dolly, rake, payout, straightWin, zero];
}
