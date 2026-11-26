/// Registry entry of the BLACKJACK (Sprint 1 game, kept as is): its screen is
/// the original `TableScreen` (`tables/{id}`, `joinMatchmaking`), not the
/// Sprint 2 `GameTableScaffold`.
library;

import 'package:flutter/material.dart';

import '../../core/widgets.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../table/table_screen.dart';
import 'common/game_sheets.dart';
import 'game_ui.dart';

final blackjackGame = GameUi(
  id: GameId.blackjack,
  name: (l) => l.gameBlackjack,
  tagline: (l) => l.lobbyHeroSubtitle,
  icon: Icons.style,
  accent: const Color(0xFF00E701),
  playable: true,
  screen: (tableId, code) => TableScreen(tableId: tableId, privateCode: code),
  rules: _rules,
  sign: 'VINGT·UN',
  marketIcon: (kind) => switch (kind) {
    MarketKind.dealerBust => Icons.local_fire_department_outlined,
    MarketKind.playerWins => Icons.person_outline,
    MarketKind.natural => Icons.auto_awesome,
    MarketKind.shoeDealerBustRate => Icons.inventory_2_outlined,
    _ => Icons.style_outlined,
  },
  marketQuestion: _question,
  statLines: (l, s) => [(l.badgeBlackjack, '${s.counters['blackjacks'] ?? 0}'), (l.badgePush, '${s.counters['pushes'] ?? 0}')],
);

String? _question(AppLocalizations l, Market m) => switch (m.kind) {
      MarketKind.dealerBust => l.mqDealerBusts,
      MarketKind.playerWins => l.mqPlayerWins(m.playerName ?? '?'),
      MarketKind.natural => l.mqNatural,
      MarketKind.shoeDealerBustRate => l.mqShoe,
      _ => null,
    };

Widget _rules(BuildContext context) {
  final l = context.l10n;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RulesSection(icon: Icons.style_outlined, body: l.lobbyHeroSubtitle),
      RulesSection(icon: Icons.payments_outlined, body: '${l.feltPayout} · ${l.feltInsurance}'),
      RulesSection(icon: Icons.rule, body: l.feltRule),
      RulesSection(icon: Icons.leaderboard_outlined, body: l.lbPointsRule),
      RulesSection(icon: Icons.verified_user_outlined, title: l.fairTitle, body: l.fairBody),
    ],
  );
}
