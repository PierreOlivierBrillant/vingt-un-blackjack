/// Rules sheet of the craps (texts: `l10n/parts/craps.*.arb`).
/// OWNER: craps implementer.
library;

import 'package:flutter/material.dart';

import '../../../core/widgets.dart';
import '../common/game_sheets.dart';

Widget crapsRules(BuildContext context) {
  final l = context.l10n;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RulesSection(icon: Icons.casino_outlined, body: l.crapsRulesSummary),
      RulesSection(icon: Icons.payments_outlined, body: l.crapsRulesPayouts),
      RulesSection(icon: Icons.timer_outlined, body: l.crapsRulesRound),
      RulesSection(icon: Icons.event_seat_outlined, body: l.crapsSeats),
      RulesSection(icon: Icons.verified_user_outlined, title: l.fairTitle, body: l.gameFairBody),
    ],
  );
}
