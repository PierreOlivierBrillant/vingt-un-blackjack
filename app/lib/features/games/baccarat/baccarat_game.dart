/// Registry entry of the BACCARAT (`kGames[GameId.baccarat]`): everything the
/// rest of the app knows about the baccarat comes from here (lobby selector,
/// `/table/bc-…`, shop group, market icons and questions, history line,
/// fairness check, profile lines, sounds).
library;

import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../domain/game_table.dart';
import '../../../domain/games.dart';
import '../../../domain/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../game_ui.dart';
import 'baccarat_fairness.dart';
import 'baccarat_geometry.dart';
import 'baccarat_model.dart';
import 'baccarat_rules.dart';
import 'baccarat_screen.dart';
import 'baccarat_sounds.dart';

final baccaratGame = GameUi(
  id: GameId.baccarat,
  name: (l) => l.gameBaccarat,
  tagline: (l) => l.gameTaglineBaccarat,
  icon: Icons.account_balance_outlined,
  accent: const Color(0xFFE0B24A),
  screen: (tableId, code) => BaccaratScreen(tableId: tableId, privateCode: code),
  rules: baccaratRules,
  playable: true,
  sign: 'BACCARAT',
  cardMedallion: 'B',
  geometry: const BaccaratGeometry(),
  sounds: BaccaratSfx.all,
  marketIcon: (kind) => switch (kind) {
    MarketKind.baccaratPair => Icons.copy_all_outlined,
    MarketKind.baccaratTie => Icons.drag_handle,
    MarketKind.baccaratBankerShoe => Icons.inventory_2_outlined,
    _ => Icons.account_balance_outlined,
  },
  marketQuestion: _question,
  roundSummary: baccaratRoundSummary,
  verifyRound: verifyBaccaratRound,
  statLines: (l, s) => [
    (l.baccaratStatBankerWins, '${s.counters['bankerWins'] ?? 0}'),
    (l.baccaratStatPlayerWins, '${s.counters['playerWins'] ?? 0}'),
    (l.baccaratStatTieWins, '${s.counters['tieWins'] ?? 0}'),
    (l.baccaratStatPairWins, '${s.counters['pairWins'] ?? 0}'),
    (l.baccaratStatNaturals, '${s.counters['naturals'] ?? 0}'),
    if ((s.counters['commissionSaved'] ?? 0) > 0)
      (l.baccaratStatCommission, formatCents(s.counters['commissionSaved'] ?? 0, locale: l.localeName)),
  ],
);

String? _question(AppLocalizations l, Market m) => switch (m.kind) {
      MarketKind.baccaratBanker => l.mqBaccaratBanker,
      MarketKind.baccaratTie => l.mqBaccaratTie,
      MarketKind.baccaratPair => l.mqBaccaratPair,
      MarketKind.baccaratBankerShoe => l.mqBaccaratBankerShoe,
      _ => null,
    };

/// "Banquier 7 – 5 · naturel · paire" (history sheet).
String? baccaratRoundSummary(AppLocalizations l, GameRound round) {
  final c = BaccaratCoup.fromDoc(round.result);
  if (c == null) return null;
  final head = switch (c.winner) {
    BaccaratWinner.banker => l.baccaratSummaryBanker(c.bankerTotal, c.playerTotal),
    BaccaratWinner.player => l.baccaratSummaryPlayer(c.playerTotal, c.bankerTotal),
    BaccaratWinner.tie => l.baccaratSummaryTie(c.playerTotal),
  };
  return [head, if (c.natural) l.baccaratSummaryNatural, if (c.anyPair) l.baccaratSummaryPair].join(' · ');
}

/// Localized winner line ("Banquier gagne").
String baccaratWinnerText(AppLocalizations l, BaccaratWinner w) => switch (w) {
      BaccaratWinner.banker => l.baccaratWinsBanker,
      BaccaratWinner.player => l.baccaratWinsPlayer,
      BaccaratWinner.tie => l.baccaratWinsTie,
    };
