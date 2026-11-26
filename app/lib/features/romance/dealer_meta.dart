/// SLOT FOR THE RENDEZ-VOUS META AT THE TABLE (owner: Rendez-vous implementer).
///
/// `GameTableScaffold` (every Sprint 2 game table) shows this widget in the
/// top-left corner of the stage, above the croupier. Today it draws nothing.
///
/// TO PROVIDE (PLAN_SPRINT2.md, « Méta en jeu »): the heart gauge of the
/// player's affinity with [characterId] (tier, progress), lines the croupier
/// says (calls you by your username, lines of your tier, reactions to your
/// rounds). Keep it compact (≤ 48 px high) and non-blocking (IgnorePointer
/// for the decorative parts); read your own providers from
/// `lib/features/romance/`. The blackjack table gets the same slot in phase D.
library;

import 'package:flutter/material.dart';

import '../../domain/games.dart';

class DealerMeta extends StatelessWidget {
  const DealerMeta({super.key, required this.characterId, required this.game, this.seated = false});

  /// `gameTables/{id}.dealer.characterId` (the croupier of the table).
  final String characterId;
  final GameId game;

  /// Whether the viewer is seated (spectators may get a lighter version).
  final bool seated;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
