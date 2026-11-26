/// Registry entry of the BACCARAT (`kGames[GameId.baccarat]`).
/// OWNER: baccarat implementer — everything the rest of the app knows about
/// the baccarat comes from here (lobby selector, `/table/bc-…`, shop group,
/// market icons and questions, history line, fairness check, profile lines).
///
/// TO PROVIDE: [GameUi.playable] → true when the table plays;
/// [GameUi.roundSummary] ("Banquier 7 – 5"); [GameUi.verifyRound] (the
/// default already re-deals `fairDealOrder(remainingBefore, seed, decks)`
/// when `rounds/{n}.fairness` carries `remainingBefore` + `dealt` + `decks: 8`);
/// [GameUi.statLines] (naturals, pairs… from `gameStats.counters`); sounds.
library;

import 'package:flutter/material.dart';

import '../../../domain/games.dart';
import '../../../domain/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../game_ui.dart';
import 'baccarat_geometry.dart';
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
  sign: 'BACCARAT',
  cardMedallion: 'B',
  geometry: const BaccaratGeometry(),
  sounds: BaccaratSfx.all,
  marketIcon: (kind) => switch (kind) {
    MarketKind.baccaratPair => Icons.copy_all_outlined,
    _ => Icons.account_balance_outlined,
  },
  marketQuestion: _question,
);

String? _question(AppLocalizations l, Market m) => switch (m.kind) {
      MarketKind.baccaratBanker => l.mqBaccaratBanker,
      MarketKind.baccaratTie => l.mqBaccaratTie,
      MarketKind.baccaratPair => l.mqBaccaratPair,
      MarketKind.baccaratBankerShoe => l.mqBaccaratBankerShoe,
      _ => null,
    };
