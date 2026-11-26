/// Rules sheet of the hold'em (texts: `l10n/parts/holdem.*.arb`), shown from
/// the table (scaffold) and the lobby hero. The last section states the
/// assumed choice: the revealed seed makes folded cards verifiable, hence
/// visible.
library;

import 'package:flutter/material.dart';

import '../../../core/widgets.dart';
import '../common/game_sheets.dart';

Widget holdemRules(BuildContext context) {
  final l = context.l10n;
  return Column(
    key: const Key('holdem-rules'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RulesSection(icon: Icons.people_outline, body: '${l.holdemRulesSummary} ${l.holdemSeats}'),
      RulesSection(icon: Icons.account_balance_wallet_outlined, body: l.holdemRulesBlinds),
      RulesSection(icon: Icons.radio_button_checked, body: l.holdemRulesButton),
      RulesSection(icon: Icons.trending_up, body: l.holdemRulesBetting),
      RulesSection(icon: Icons.all_inclusive, body: l.holdemRulesAllIn),
      RulesSection(icon: Icons.pie_chart_outline, body: l.holdemRulesPots),
      RulesSection(icon: Icons.style_outlined, body: l.holdemRulesShowdown),
      RulesSection(icon: Icons.timer_outlined, body: l.holdemRulesTimeouts),
      RulesSection(icon: Icons.show_chart, body: l.holdemRulesMarkets),
      RulesSection(icon: Icons.verified_user_outlined, title: l.fairTitle, body: '${l.gameFairBody}\n${l.holdemRulesFairness}'),
    ],
  );
}
