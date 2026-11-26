/// Rules sheet of the baccarat (texts: `l10n/parts/baccarat.*.arb`).
/// OWNER: baccarat implementer.
library;

import 'package:flutter/material.dart';

import '../../../core/widgets.dart';
import '../common/game_sheets.dart';

Widget baccaratRules(BuildContext context) {
  final l = context.l10n;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RulesSection(icon: Icons.style_outlined, body: l.baccaratRulesSummary),
      RulesSection(icon: Icons.payments_outlined, body: l.baccaratRulesPayouts),
      RulesSection(icon: Icons.timer_outlined, body: l.baccaratRulesRound),
      RulesSection(icon: Icons.event_seat_outlined, body: l.baccaratSeats),
      RulesSection(icon: Icons.verified_user_outlined, title: l.fairTitle, body: l.gameFairBody),
    ],
  );
}
