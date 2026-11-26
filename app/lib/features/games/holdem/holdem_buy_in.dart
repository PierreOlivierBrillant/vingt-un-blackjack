/// Buy-in picker of the hold'em ([GameUi.pickBuyIn]), asked before joining.
/// OWNER: hold'em implementer — minimal version: a slider from 40 to 100 big
/// blinds of the tier (PLAN_SPRINT2.md: blinds 1/2, 5/10, 25/50 $). The
/// server is authoritative (limits.extra.minBuyInCents..maxBuyInCents,
/// BUY_IN_OUT_OF_RANGE); keep these numbers in sync with the hold'em module.
library;

import 'package:flutter/material.dart';

import '../../../core/widgets.dart';

/// Big blind (cents) of each stake tier.
const kHoldemBigBlindCents = <String, int>{'low': 200, 'mid': 1000, 'high': 5000};

/// (min, max) buy-in in cents: 40 to 100 big blinds.
(int, int) holdemBuyInRange(String tier) {
  final bb = kHoldemBigBlindCents[tier] ?? 200;
  return (bb * 40, bb * 100);
}

Future<int?> holdemPickBuyIn(BuildContext context, String stakeTier) {
  final (min, max) = holdemBuyInRange(stakeTier);
  final bb = kHoldemBigBlindCents[stakeTier] ?? 200;
  var value = max;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final l = ctx.l10n;
        return AlertDialog(
          title: Text(l.holdemBuyInTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.holdemBuyInBody(ctx.money(min), ctx.money(max))),
              const SizedBox(height: 12),
              Text(ctx.money(value), key: const Key('holdem-buy-in-amount'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Slider(
                key: const Key('holdem-buy-in-slider'),
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: (max - min) ~/ bb,
                onChanged: (v) => setState(() => value = (v / bb).round() * bb),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.back)),
            FilledButton(key: const Key('holdem-buy-in-sit'), onPressed: () => Navigator.pop(ctx, value), child: Text(l.holdemBuyInSit)),
          ],
        );
      },
    ),
  );
}
