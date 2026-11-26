/// Sounds of the Rendez-vous meta (group "romance": `tools/sfx/games/romance.mjs`,
/// quota in `tools/sfx/quotas.json`). OWNER: Rendez-vous implementer.
///
/// Declare every sound of the group here and list it in [RomanceSfx.all]
/// (`kSfxGroups` in `lib/features/sound_catalog.dart` reads it):
/// `test/unit/sound_test.dart` checks WAVs and durations. Location ambiences
/// are loops (mono 22 kHz) on `SoundChannel.game`.
library;

import '../../core/audio/sfx.dart';

abstract final class RomanceSfx {
  /// Example: affinity goes up (soft rising chime).
  static const heartUp = GameSfx('romance_heart_up', 900, tier: SfxTier.fanfare);

  static const all = <GameSfx>[heartUp];
}
