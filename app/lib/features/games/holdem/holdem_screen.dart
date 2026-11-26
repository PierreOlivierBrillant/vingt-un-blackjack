/// The hold'em table screen (`/table/ho-…`): the generic [GameTableScaffold]
/// (app bar, status strip, seats bar, spectator panel, sheets, pubs,
/// celebrations) around the hold'em stage ([HoldemStageView], driven by its
/// own [StageController] through [HoldemScene]) and the seated controls
/// ([HoldemControls]). The scene is fed by the scaffold's `onTable` with the
/// hand's events (first snapshot: rebuilt from the state, no animation).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sound_providers.dart';
import '../../stage/stage_controller.dart';
import '../common/game_table_scaffold.dart';
import 'holdem_controls.dart';
import 'holdem_game.dart';
import 'holdem_labels.dart';
import 'holdem_last_hand.dart';
import 'holdem_stage.dart';

class HoldemScreen extends ConsumerStatefulWidget {
  const HoldemScreen({super.key, required this.tableId, this.privateCode, this.drive = true});
  final String tableId;
  final String? privateCode;

  /// false in tests that advance the stage by hand.
  final bool drive;

  @override
  ConsumerState<HoldemScreen> createState() => _HoldemScreenState();
}

class _HoldemScreenState extends ConsumerState<HoldemScreen> {
  late final StageController _stage = StageController(geometry: kHoldemGeometry, feedback: SoundStageFeedback(ref.read(soundProvider)));
  late final HoldemScene _scene = HoldemScene(_stage);

  @override
  void dispose() {
    _stage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GameTableScaffold(
        ui: holdemGame,
        tableId: widget.tableId,
        privateCode: widget.privateCode,
        onTable: _scene.onTable,
        statusText: holdemStatusText,
        seatInfo: holdemSeatInfo,
        stage: (context, view) => HoldemStageView(
          stage: _stage,
          scene: _scene,
          view: view,
          drive: widget.drive,
          onLastHand: () => showHoldemLastHandSheet(context, widget.tableId),
        ),
        controls: (context, view) => HoldemControls(view: view),
      );
}
