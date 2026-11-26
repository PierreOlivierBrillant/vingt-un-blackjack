/// Registry entry of the TEXAS HOLD'EM (`kGames[GameId.holdem]`): the table
/// screen, rules, sounds, buy-in picker, history summary ("Pot 240 $ · Paire
/// de rois"), fairness check (deal order + every hand rebuilt from the
/// revealed seed, `holdem_fairness.dart`) and the profile lines. No powers in
/// hold'em (PvP): the shop shows an empty group with an explanation.
library;

import 'package:flutter/material.dart';

import '../../../domain/game_table.dart';
import '../../../domain/games.dart';
import '../../../domain/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../game_ui.dart';
import 'holdem_buy_in.dart';
import 'holdem_evaluator.dart';
import 'holdem_fairness.dart';
import 'holdem_geometry.dart';
import 'holdem_labels.dart';
import 'holdem_rules.dart';
import 'holdem_screen.dart';
import 'holdem_sounds.dart';
import 'holdem_state.dart';

final holdemGame = GameUi(
  id: GameId.holdem,
  name: (l) => l.gameHoldem,
  tagline: (l) => l.gameTaglineHoldem,
  icon: Icons.groups_outlined,
  accent: const Color(0xFF7C5CFF),
  screen: (tableId, code) => HoldemScreen(tableId: tableId, privateCode: code),
  rules: holdemRules,
  playable: true,
  sign: "HOLD'EM",
  cardMedallion: '♠',
  geometry: const HoldemGeometry(),
  sounds: HoldemSfx.all,
  pickBuyIn: holdemPickBuyIn,
  marketIcon: (kind) => Icons.style_outlined,
  marketQuestion: _question,
  roundSummary: holdemRoundSummary,
  verifyRound: verifyHoldemRound,
  statLines: holdemStatLines,
);

String? _question(AppLocalizations l, Market m) => switch (m.kind) {
      MarketKind.holdemBoardAce => l.mqHoldemBoardAce,
      MarketKind.holdemBoardFlush => l.mqHoldemBoardFlush,
      _ => null,
    };

/// "Pot 240 $ · Paire de rois" / "Pot 12 $ · sans abattage".
String? holdemRoundSummary(AppLocalizations l, GameRound round) {
  final r = HoldemResult.fromDoc(round.result);
  if (r == null) return null;
  final pot = holdemMoney(l, r.potCents);
  final hand = r.showdown ? r.winningHand : null;
  if (hand == null || hand.category == null) return l.holdemSummaryNoShowdown(pot);
  return l.holdemSummary(pot, holdemHandName(l, HandValue(hand.category!, hand.score, hand.best)));
}

/// Profile lines from `gameStats.holdem.counters` (pots, showdowns, showdownsWon, allIns, bestHand).
List<StatLine> holdemStatLines(AppLocalizations l, GameStats s) {
  final c = s.counters;
  final best = c['bestHand'] ?? 0;
  return [
    (l.holdemStatPots, '${c['pots'] ?? 0}'),
    (l.holdemStatShowdowns, '${c['showdownsWon'] ?? 0} / ${c['showdowns'] ?? 0}'),
    (l.holdemStatAllIns, '${c['allIns'] ?? 0}'),
    if (best >= 1 && best <= HoldemCategory.values.length) (l.holdemStatBestHand, holdemCategoryName(l, HoldemCategory.values[best - 1])),
  ];
}
