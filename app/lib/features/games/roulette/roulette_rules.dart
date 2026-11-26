/// Rules sheet of the roulette (texts: `l10n/parts/roulette.*.arb`).
/// OWNER: roulette implementer (refine freely; keep PLAN_SPRINT2.md's rules).
library;

import 'package:flutter/material.dart';

import '../../../core/widgets.dart';
import '../common/game_sheets.dart';

Widget rouletteRules(BuildContext context) {
  final l = context.l10n;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RulesSection(icon: Icons.casino_outlined, body: l.rouletteRulesSummary),
      RulesSection(icon: Icons.payments_outlined, body: l.rouletteRulesPayouts),
      RulesSection(icon: Icons.timer_outlined, body: l.rouletteRulesRound),
      RulesSection(icon: Icons.event_seat_outlined, body: l.rouletteSeats),
      RulesSection(icon: Icons.verified_user_outlined, title: l.fairTitle, body: l.gameFairBody),
    ],
  );
}
