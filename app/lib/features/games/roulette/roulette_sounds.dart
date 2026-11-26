/// Sounds of the roulette (group "roulette": `tools/sfx/games/roulette.mjs`,
/// quota in `tools/sfx/quotas.json`). OWNER: roulette implementer.
///
/// Declare every sound of the group here and list it in [RouletteSfx.all]
/// (`rouletteGame.sounds`): `test/unit/sound_test.dart` checks that each one
/// has its WAV with the same duration, and that every WAV of the group is
/// declared. Loops are mono 22 kHz and play on `SoundChannel.game`.
library;

import '../../../core/audio/sfx.dart';

abstract final class RouletteSfx {
  /// Example: the ball hits a fret (play in a decreasing burst as it settles).
  static const ballTick = GameSfx('roulette_ball_tick', 160, tier: SfxTier.ui, cooldownMs: 30);

  static const all = <GameSfx>[ballTick];
}
