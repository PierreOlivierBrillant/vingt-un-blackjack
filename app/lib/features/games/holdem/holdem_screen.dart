/// The hold'em table screen (`/table/ho-…`). OWNER: hold'em implementer.
///
/// PLACEHOLDER (phase A): the generic [GameTableScaffold] around the generic
/// [GamePlaceholderStage]. TO PROVIDE (PLAN_SPRINT2.md):
///  * the stage (own `StageController` + `StageView`): cards pitched to each
///    seat, burn, flop / turn / river, bets pushed to the pot, side pots,
///    dealer button, fed by `onTable` with the hand's events;
///  * `controls`: fold / check / call / bet / raise (slider, min raise),
///    all-in, rebuy and sit out / in, via `view.actions.act({...})`;
///  * my hole cards: `gameHoleProvider(tableId)` (`holes/{me}`, wire codes);
///  * stacks are already shown by the generic seats bar (`seatInfo` to change).
/// Only touch this folder, `l10n/parts/holdem.*.arb`,
/// `tools/sfx/games/holdem.mjs` and your tests.
library;

import 'package:flutter/material.dart';

import '../common/game_table_scaffold.dart';
import '../common/placeholder_stage.dart';
import 'holdem_game.dart';
import 'holdem_geometry.dart';

class HoldemScreen extends StatelessWidget {
  const HoldemScreen({super.key, required this.tableId, this.privateCode});
  final String tableId;
  final String? privateCode;

  @override
  Widget build(BuildContext context) => GameTableScaffold(
        ui: holdemGame,
        tableId: tableId,
        privateCode: privateCode,
        stage: (context, view) => GamePlaceholderStage(view: view, geometry: const HoldemGeometry()),
      );
}
