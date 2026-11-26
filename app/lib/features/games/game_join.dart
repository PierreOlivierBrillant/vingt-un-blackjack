/// Joining a Sprint 2 game table from the UI (lobby, private table sheet,
/// "play this game" of a spectator): asks the hold'em buy-in
/// ([GameUi.pickBuyIn]), plays the matchmaking sounds, calls `gameJoin` and
/// shows a localized snackbar on failure. Navigation is left to the caller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_providers.dart';
import '../../core/ids.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../domain/game_table.dart';
import 'game_ui.dart';

/// Null when cancelled (buy-in dialog) or failed (snackbar shown, or the
/// error rethrown with [rethrowErrors]). Pass the same [idempotencyKey] to
/// retry the same logical join.
Future<GameJoinResult?> joinGameTable(
  BuildContext context,
  WidgetRef ref,
  GameUi ui, {
  required GameJoinMode mode,
  String stakeTier = 'low',
  String? code,
  String? idempotencyKey,
  bool rethrowErrors = false,
}) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  int? buyIn;
  // A code typed with hold'em selected is (almost surely) a hold'em table: ask
  // the buy-in too (see tools/sprint2/requests/a2.md for codes of other games).
  if (ui.pickBuyIn != null) {
    buyIn = await ui.pickBuyIn!(context, stakeTier);
    if (buyIn == null) return null;
  }
  try {
    return await withMatchmakingSounds(
      ref.read(soundProvider),
      () => ref.read(gameTableRepositoryProvider).join(
            game: ui.id,
            mode: mode,
            stakeTier: stakeTier,
            code: code,
            buyInCents: buyIn,
            idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
          ),
    );
  } on Object catch (e) {
    if (rethrowErrors) rethrow;
    messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
    return null;
  }
}
