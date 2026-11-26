/// Registry entry of the TEXAS HOLD'EM (`kGames[GameId.holdem]`).
/// OWNER: hold'em implementer — everything the rest of the app knows about
/// the hold'em comes from here. No powers in hold'em (PvP): the shop shows
/// an empty group with an explanation.
///
/// TO PROVIDE: [GameUi.playable] → true when the table plays;
/// [GameUi.pickBuyIn] (a minimal slider is in `holdem_buy_in.dart`);
/// [GameUi.roundSummary] ("Pot 240 $ · paire de rois"); [GameUi.verifyRound]
/// (the default re-deals `fairDealOrder(buildShoe(1), seed, 1)` when
/// `rounds/{n}.fairness` carries `remainingBefore` + `dealt` + `decks: 1`);
/// [GameUi.statLines] (pots won, showdowns… from `gameStats.counters`); sounds.
library;

import 'package:flutter/material.dart';

import '../../../domain/games.dart';
import '../../../domain/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../game_ui.dart';
import 'holdem_buy_in.dart';
import 'holdem_geometry.dart';
import 'holdem_rules.dart';
import 'holdem_screen.dart';
import 'holdem_sounds.dart';

final holdemGame = GameUi(
  id: GameId.holdem,
  name: (l) => l.gameHoldem,
  tagline: (l) => l.gameTaglineHoldem,
  icon: Icons.groups_outlined,
  accent: const Color(0xFF7C5CFF),
  screen: (tableId, code) => HoldemScreen(tableId: tableId, privateCode: code),
  rules: holdemRules,
  sign: "HOLD'EM",
  cardMedallion: '♠',
  geometry: const HoldemGeometry(),
  sounds: HoldemSfx.all,
  pickBuyIn: holdemPickBuyIn,
  marketIcon: (kind) => Icons.style_outlined,
  marketQuestion: _question,
);

String? _question(AppLocalizations l, Market m) => switch (m.kind) {
      MarketKind.holdemBoardAce => l.mqHoldemBoardAce,
      MarketKind.holdemBoardFlush => l.mqHoldemBoardFlush,
      _ => null,
    };
