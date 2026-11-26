/// Sounds of the Texas hold'em (group "holdem": `tools/sfx/games/holdem.mjs`,
/// quota in `tools/sfx/quotas.json`). OWNER: hold'em implementer.
///
/// Declare every sound of the group here and list it in [HoldemSfx.all]
/// (`holdemGame.sounds`): `test/unit/sound_test.dart` checks WAVs and durations.
library;

import '../../../core/audio/sfx.dart';

abstract final class HoldemSfx {
  /// Example: "check", two knocks on the table.
  static const checkKnock = GameSfx('holdem_check_knock', 320);

  static const all = <GameSfx>[checkKnock];
}
