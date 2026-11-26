/// What [GameTableScaffold] hands to a game's builders every frame: the
/// table as published, my seat, the bet boards of the round, the clock, and
/// [GameTableActions] to talk to the server (errors already shown).
library;

import 'package:flutter/foundation.dart';

import '../../../domain/game_table.dart';
import '../../../domain/models.dart' show PowerType;
import '../../table/table_sounds.dart' show CelebrationKind;
import '../game_ui.dart';

/// Calls of the current table, made by the scaffold on behalf of the game.
/// Every method shows a localized snackbar on failure and returns false;
/// [busy] is true while a call is in flight (disable your buttons).
abstract interface class GameTableActions {
  ValueListenable<bool> get busy;

  /// Kernel `setBets`: the WHOLE board of the round (the server debits /
  /// refunds the difference). Compute undo / clear / repeat / double yourself.
  Future<bool> setBets(Map<String, int> bets, {PowerType? power});

  /// Any `gameAction` of the game (`{type: 'fold'}`, `{type: 'roll'}`…), for
  /// the current round.
  Future<bool> act(Map<String, Object?> action);

  /// `gameAction {type: 'sitOut'}` / `{type: 'sitIn'}`.
  Future<bool> sitOut();
  Future<bool> sitIn();

  /// Confirm, leave the table, go back.
  Future<void> leave();

  /// Shows the confetti / coin overlay (games' own big hits: [label]).
  void celebrate(CelebrationKind kind, {int? cents, String? label});
}

@immutable
class GameTableView {
  const GameTableView({
    required this.ui,
    required this.table,
    required this.myUid,
    required this.bets,
    required this.now,
    required this.actions,
  });

  final GameUi ui;
  final GameTableState table;
  final String? myUid;

  /// Bet boards of the CURRENT round only (bet-board games).
  final List<GameBet> bets;

  /// The clock of the app (pinned in tests): use it for countdowns.
  final DateTime now;
  final GameTableActions actions;

  GameSeat? get mine => table.seatOf(myUid);
  bool get seated => mine != null;
  bool get queued => table.isQueued(myUid);
  int get queuePosition => table.queuePositionOf(myUid);
  bool get spectator => !seated && !queued;
  bool get myTurn => mine != null && table.turnSeat == mine!.seatIndex;
  GameBet? get myBets => betOf(mine?.seatIndex);
  GameBet? betOf(int? seat) => seat == null ? null : bets.where((b) => b.seatIndex == seat).firstOrNull;

  /// Seconds left before the deadline (ceil), 0 when none.
  int get secondsLeft {
    final ms = table.remainingAt(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }
}
