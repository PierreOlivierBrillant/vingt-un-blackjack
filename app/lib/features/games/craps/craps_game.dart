/// Registry entry of the CRAPS (`kGames[GameId.craps]`).
/// OWNER: craps implementer — everything the rest of the app knows about the
/// craps comes from here (lobby selector, `/table/cr-…`, shop group, market
/// icons and questions, history line, fairness check, profile lines).
///
/// TO PROVIDE: [GameUi.playable] → true when the table plays;
/// [GameUi.roundSummary] ("4 + 3 = 7, seven-out"); [GameUi.verifyRound]
/// (recompute `nextInt(6)+1` twice from the seed against `rounds/{n}.result`);
/// [GameUi.statLines] (points made, hard ways… from `gameStats.counters`); sounds.
library;

import 'package:flutter/material.dart';

import '../../../domain/games.dart';
import '../../../domain/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../game_ui.dart';
import 'craps_geometry.dart';
import 'craps_rules.dart';
import 'craps_screen.dart';
import 'craps_sounds.dart';

final crapsGame = GameUi(
  id: GameId.craps,
  name: (l) => l.gameCraps,
  tagline: (l) => l.gameTaglineCraps,
  icon: Icons.casino_outlined,
  accent: const Color(0xFF2FBF71),
  screen: (tableId, code) => CrapsScreen(tableId: tableId, privateCode: code),
  rules: crapsRules,
  sign: 'CRAPS',
  cardMedallion: '7',
  geometry: const CrapsGeometry(),
  sounds: CrapsSfx.all,
  marketIcon: (kind) => Icons.casino_outlined,
  marketQuestion: _question,
);

String? _question(AppLocalizations l, Market m) => switch (m.kind) {
      MarketKind.crapsSeven => l.mqCrapsSeven,
      MarketKind.crapsPoint => l.mqCrapsPoint,
      _ => null,
    };
