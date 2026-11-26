/// Rules sheet of the hold'em (texts: `l10n/parts/holdem.*.arb`).
/// OWNER: hold'em implementer.
library;

import 'package:flutter/material.dart';

import '../../../core/widgets.dart';
import '../common/game_sheets.dart';

Widget holdemRules(BuildContext context) {
  final l = context.l10n;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RulesSection(icon: Icons.people_outline, body: l.holdemRulesSummary),
      RulesSection(icon: Icons.timer_outlined, body: l.holdemRulesRound),
      RulesSection(icon: Icons.event_seat_outlined, body: l.holdemSeats),
      RulesSection(icon: Icons.verified_user_outlined, title: l.fairTitle, body: '${l.gameFairBody}\n${l.holdemRulesFairness}'),
    ],
  );
}
