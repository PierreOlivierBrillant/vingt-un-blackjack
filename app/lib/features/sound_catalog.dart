/// Every synthesised sound of the app, by group of `tools/sfx/quotas.json`:
/// `core` = the [Sfx] enum (Sprint 1), then one group per game (from the
/// `kGames` registry) and `romance`. `test/unit/sound_test.dart` checks this
/// catalogue against `assets/sfx/` (files, durations, loops, quotas).
library;

import '../core/audio/sfx.dart';
import '../domain/games.dart';
import 'games/registry.dart';
import 'romance/romance_sounds.dart';

final Map<String, List<SoundCue>> kSfxGroups = Map.unmodifiable({
  'core': Sfx.values,
  for (final g in GameId.values)
    if (g.isKernel) g.wire: kGames[g]!.sounds,
  'romance': RomanceSfx.all,
});
