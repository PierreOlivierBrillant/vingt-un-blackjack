/// The craps table screen (`/table/cr-…`). OWNER: craps implementer.
///
/// PLACEHOLDER (phase A): the generic [GameTableScaffold] around the generic
/// [GamePlaceholderStage]. TO PROVIDE (PLAN_SPRINT2.md):
///  * the stage (own `StageController` + `StageView`): the stickman and his
///    stick, dice bouncing on the pyramid wall then landing on the drawn
///    faces, ON/OFF puck, chips on the layout, fed by `onTable` with events;
///  * `controls`: the betting layout (whole board via
///    `view.actions.setBets(board, power: PowerType.safetyNet?)`, multiples
///    of $3 where required) and, for the shooter, the throw gesture
///    (`view.actions.act({'type': 'roll'})`; auto-roll after 15 s server-side);
///  * your parsing of `table.g` / `seat.g` (`shared/games/craps.ts`).
/// Only touch this folder, `l10n/parts/craps.*.arb`,
/// `tools/sfx/games/craps.mjs` and your tests.
library;

import 'package:flutter/material.dart';

import '../common/game_table_scaffold.dart';
import '../common/placeholder_stage.dart';
import 'craps_game.dart';
import 'craps_geometry.dart';

class CrapsScreen extends StatelessWidget {
  const CrapsScreen({super.key, required this.tableId, this.privateCode});
  final String tableId;
  final String? privateCode;

  @override
  Widget build(BuildContext context) => GameTableScaffold(
        ui: crapsGame,
        tableId: tableId,
        privateCode: privateCode,
        stage: (context, view) => GamePlaceholderStage(view: view, geometry: const CrapsGeometry()),
      );
}
