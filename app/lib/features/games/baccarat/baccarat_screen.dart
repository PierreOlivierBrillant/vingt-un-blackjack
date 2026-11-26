/// The baccarat table screen (`/table/bc-…`). OWNER: baccarat implementer.
///
/// PLACEHOLDER (phase A): the generic [GameTableScaffold] around the generic
/// [GamePlaceholderStage]. TO PROVIDE (PLAN_SPRINT2.md):
///  * the stage (own `StageController` + `StageView`): shoe, cards pitched to
///    Player / Banker, 3rd card laid sideways, animated squeeze (no secret
///    information), Bead Plate / Big Road (Big Eye Boy bonus), fed by
///    `onTable` with the coup's events;
///  * `controls`: the Player / Banker / Tie / pairs board, sent whole with
///    `view.actions.setBets(board, power: PowerType.freeCommission?)`;
///  * your parsing of `table.g` / `seat.g` (`shared/games/baccarat.ts`).
/// Only touch this folder, `l10n/parts/baccarat.*.arb`,
/// `tools/sfx/games/baccarat.mjs` and your tests.
library;

import 'package:flutter/material.dart';

import '../common/game_table_scaffold.dart';
import '../common/placeholder_stage.dart';
import 'baccarat_game.dart';
import 'baccarat_geometry.dart';

class BaccaratScreen extends StatelessWidget {
  const BaccaratScreen({super.key, required this.tableId, this.privateCode});
  final String tableId;
  final String? privateCode;

  @override
  Widget build(BuildContext context) => GameTableScaffold(
        ui: baccaratGame,
        tableId: tableId,
        privateCode: privateCode,
        stage: (context, view) => GamePlaceholderStage(view: view, geometry: const BaccaratGeometry()),
      );
}
