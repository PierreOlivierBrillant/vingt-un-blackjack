/// Registry entry of the ROULETTE (`kGames[GameId.roulette]`).
/// OWNER: roulette implementer — everything the rest of the app knows about
/// the roulette comes from here (lobby selector, `/table/rl-…`, shop group,
/// market icons and questions, history line, fairness check, profile lines).
///
/// TO PROVIDE (see the placeholder files of this folder):
///  * [GameUi.playable] → true once the table plays end to end;
///  * [GameUi.roundSummary] ("17 rouge"), [GameUi.verifyRound] (recompute
///    `seededRng(seed).nextInt(37)` against `rounds/{n}.result`),
///    [GameUi.statLines] (e.g. straight-up hits from `gameStats.counters`);
///  * the sounds of `roulette_sounds.dart`.
library;

import 'package:flutter/material.dart';

import '../../../domain/games.dart';
import '../../../domain/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../game_ui.dart';
import 'roulette_geometry.dart';
import 'roulette_rules.dart';
import 'roulette_screen.dart';
import 'roulette_sounds.dart';

final rouletteGame = GameUi(
  id: GameId.roulette,
  name: (l) => l.gameRoulette,
  tagline: (l) => l.gameTaglineRoulette,
  icon: Icons.album_outlined,
  accent: const Color(0xFFE5484D),
  screen: (tableId, code) => RouletteScreen(tableId: tableId, privateCode: code),
  rules: rouletteRules,
  sign: 'ROULETTE',
  cardMedallion: '0',
  geometry: const RouletteGeometry(),
  sounds: RouletteSfx.all,
  marketIcon: (kind) => switch (kind) {
    MarketKind.rouletteZero || MarketKind.rouletteZeroSeries => Icons.exposure_zero,
    _ => Icons.album_outlined,
  },
  marketQuestion: _question,
);

String? _question(AppLocalizations l, Market m) => switch (m.kind) {
      MarketKind.rouletteRed => l.mqRouletteRed,
      MarketKind.rouletteZero => l.mqRouletteZero,
      MarketKind.rouletteDozen3 => l.mqRouletteDozen3,
      MarketKind.rouletteZeroSeries => l.mqRouletteZeroSeries,
      _ => null,
    };
