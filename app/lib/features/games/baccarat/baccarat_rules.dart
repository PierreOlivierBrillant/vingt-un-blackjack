/// Rules sheet of the baccarat (texts: `l10n/parts/baccarat.*.arb`).
library;

import 'package:flutter/material.dart';

import '../../../core/widgets.dart';
import '../common/game_sheets.dart';

Widget baccaratRules(BuildContext context) {
  final l = context.l10n;
  return Column(
    key: const Key('baccarat-rules'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RulesSection(icon: Icons.style_outlined, body: l.baccaratRulesSummary),
      RulesSection(icon: Icons.calculate_outlined, body: l.baccaratRulesValues),
      RulesSection(icon: Icons.table_chart_outlined, body: l.baccaratRulesDrawing),
      RulesSection(icon: Icons.payments_outlined, body: l.baccaratRulesPayouts),
      RulesSection(icon: Icons.tune, body: l.baccaratRulesLimits),
      RulesSection(icon: Icons.timer_outlined, body: l.baccaratRulesRound),
      RulesSection(icon: Icons.percent, body: l.baccaratRulesPower),
      RulesSection(icon: Icons.grid_on, body: l.baccaratRulesRoads),
      RulesSection(icon: Icons.show_chart, body: l.baccaratRulesMarkets),
      RulesSection(icon: Icons.event_seat_outlined, body: l.baccaratSeats),
      RulesSection(icon: Icons.verified_user_outlined, title: l.fairTitle, body: l.gameFairBody),
    ],
  );
}
