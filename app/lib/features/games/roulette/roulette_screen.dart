/// The roulette table screen (`/table/rl-…`). OWNER: roulette implementer.
///
/// PLACEHOLDER (phase A): the generic [GameTableScaffold] around the generic
/// [GamePlaceholderStage]. TO PROVIDE (PLAN_SPRINT2.md):
///  * the stage: a `StageController` + `StageView` of your own (spinning
///    wheel, ball computed BACKWARDS to land in the drawn pocket, dolly,
///    rake, hot / cold numbers), fed by `onTable` with the round's events;
///  * `controls`: the tactile betting layout + racetrack, chip colour per
///    player, Undo / Clear / Repeat / Double and call bets computed locally,
///    sent with `view.actions.setBets(board, power: …)` (whole board);
///  * your parsing of `table.g`, `seat.g` and the spot ids (documented in
///    `firebase/functions/src/shared/games/roulette.ts`).
/// Only touch this folder, `l10n/parts/roulette.*.arb`,
/// `tools/sfx/games/roulette.mjs` and your tests.
library;

import 'package:flutter/material.dart';

import '../common/game_table_scaffold.dart';
import '../common/placeholder_stage.dart';
import 'roulette_game.dart';
import 'roulette_geometry.dart';

class RouletteScreen extends StatelessWidget {
  const RouletteScreen({super.key, required this.tableId, this.privateCode});
  final String tableId;
  final String? privateCode;

  @override
  Widget build(BuildContext context) => GameTableScaffold(
        ui: rouletteGame,
        tableId: tableId,
        privateCode: privateCode,
        stage: (context, view) => GamePlaceholderStage(view: view, geometry: const RouletteGeometry()),
      );
}
