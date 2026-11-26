/// Sounds of the baccarat (group "baccarat": `tools/sfx/games/baccarat.mjs`,
/// quota in `tools/sfx/quotas.json`). OWNER: baccarat implementer.
///
/// Declare every sound of the group here and list it in [BaccaratSfx.all]
/// (`baccaratGame.sounds`): `test/unit/sound_test.dart` checks WAVs and durations.
library;

import '../../../core/audio/sfx.dart';

abstract final class BaccaratSfx {
  /// Example: squeeze, the card is bent slowly before being revealed.
  static const cardSqueeze = GameSfx('baccarat_card_squeeze', 600);

  static const all = <GameSfx>[cardSqueeze];
}
