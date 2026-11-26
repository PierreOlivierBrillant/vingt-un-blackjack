/// Sounds of the craps (group "craps": `tools/sfx/games/craps.mjs`, quota in
/// `tools/sfx/quotas.json`). OWNER: craps implementer.
///
/// Declare every sound of the group here and list it in [CrapsSfx.all]
/// (`crapsGame.sounds`): `test/unit/sound_test.dart` checks WAVs and durations.
library;

import '../../../core/audio/sfx.dart';

abstract final class CrapsSfx {
  /// Example: the shooter shakes the two dice.
  static const diceShake = GameSfx('craps_dice_shake', 500);

  static const all = <GameSfx>[diceShake];
}
