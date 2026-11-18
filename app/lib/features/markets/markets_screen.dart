import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';

String marketQuestion(AppLocalizations l, Market m) => switch (m.kind) {
      MarketKind.dealerBust => l.mqDealerBusts,
      MarketKind.playerWins => l.mqPlayerWins(m.playerName ?? '?'),
      MarketKind.natural => l.mqNatural,
      MarketKind.shoeDealerBustRate => l.mqShoe,
    };

String marketSubtitle(AppLocalizations l, Market m) => m.kind == MarketKind.shoeDealerBustRate || m.handNumber == null
    ? '${m.tableName} · ${l.marketPerShoe}'
    : '${m.tableName} · ${l.handNumber(m.handNumber!)}';

String compactVolume(BuildContext context, int cents) {
  final dollars = cents ~/ 100;
  final fr = context.lang == 'fr';
  if (dollars >= 1000000) return fr ? '${(dollars / 1e6).toStringAsFixed(1).replaceAll('.', ',')} M \$' : '\$${(dollars / 1e6).toStringAsFixed(1)}M';
  if (dollars >= 1000) return fr ? '${(dollars / 1e3).toStringAsFixed(1).replaceAll('.', ',')} k \$' : '\$${(dollars / 1e3).toStringAsFixed(1)}K';
  return context.money(cents, compact: true);
}

enum _Filter { all, hand, shoe, mine }

class MarketsScreen extends ConsumerStatefulWidget {
  const MarketsScreen({super.key});

  @override
  ConsumerState<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends ConsumerState<MarketsScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final markets = ref.watch(marketsProvider);
    final positions = ref.watch(positionsProvider).value ?? const [];
    final prices = {for (final m in markets.value ?? const <Market>[]) m.id: m.priceYes};
    final portfolio = positions.fold<int>(0, (a, p) => a + p.valueCents(prices[p.marketId] ?? 0.5));
    final pnl = positions.fold<int>(0, (a, p) => a + p.pnlCents(prices[p.marketId] ?? 0.5));

    return Scaffold(
      appBar: AppBar(title: Text(l.marketsTitle), actions: const [BalancePill()]),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Panel(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.marketsPortfolio, style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                        Text(context.money(portfolio), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(l.marketsPnl, style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                      Text(
                        context.money(pnl, signed: true),
                        style: TextStyle(fontWeight: FontWeight.w800, color: pnl >= 0 ? context.palette.win : context.palette.loss),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (f) {
                        _Filter.all => l.filterAll,
                        _Filter.hand => l.filterHand,
                        _Filter.shoe => l.filterShoe,
                        _Filter.mine => l.filterMine,
                      }),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          AsyncBody(
            value: markets,
            builder: (list) {
              final ids = positions.map((p) => p.marketId).toSet();
              final shown = list.where((m) => switch (_filter) {
                    _Filter.all => true,
                    _Filter.hand => m.kind != MarketKind.shoeDealerBustRate,
                    _Filter.shoe => m.kind == MarketKind.shoeDealerBustRate,
                    _Filter.mine => ids.contains(m.id),
                  });
              return Column(
                children: [
                  for (final m in shown)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: MarketCard(market: m, onTap: () => context.push('/markets/${m.id}')),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.market, required this.onTap});
  final Market market;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final m = market;
    final settled = m.status == MarketStatus.resolved;
    final yesWon = m.outcome == Outcome.yes;
    return Panel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(8)),
                child: Icon(switch (m.kind) {
                  MarketKind.dealerBust => Icons.local_fire_department_outlined,
                  MarketKind.playerWins => Icons.person_outline,
                  MarketKind.natural => Icons.auto_awesome,
                  MarketKind.shoeDealerBustRate => Icons.inventory_2_outlined,
                }, color: p.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(marketQuestion(l, m), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(marketSubtitle(l, m), style: TextStyle(color: p.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ProbabilityGauge(probability: m.yesPrice),
            ],
          ),
          const SizedBox(height: 12),
          if (settled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: (yesWon ? p.yes : p.no).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                yesWon ? l.marketResolvedYes : l.marketResolvedNo,
                style: TextStyle(fontWeight: FontWeight.w800, color: yesWon ? p.yes : p.no),
              ),
            )
          else
            Row(
              children: [
                Expanded(child: OutcomeButton(outcome: Outcome.yes, price: m.yesPrice, onTap: onTap)),
                const SizedBox(width: 8),
                Expanded(child: OutcomeButton(outcome: Outcome.no, price: m.noPrice, onTap: onTap)),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(l.marketVolume(compactVolume(context, m.volumeCents)), style: TextStyle(color: p.textMuted, fontSize: 11.5)),
              const SizedBox(width: 10),
              Icon(Icons.group_outlined, size: 14, color: p.textMuted),
              const SizedBox(width: 2),
              Text('${m.tradeCount}', style: TextStyle(color: p.textMuted, fontSize: 11.5)),
              const Spacer(),
              if (!settled)
                Row(children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: p.loss, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(l.live, style: TextStyle(color: p.loss, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}

class OutcomeButton extends StatelessWidget {
  const OutcomeButton({super.key, required this.outcome, required this.price, this.onTap, this.selected = false});
  final Outcome outcome;
  final double price;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final color = outcome == Outcome.yes ? p.yes : p.no;
    return Material(
      color: selected ? color : color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('outcome-${outcome.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              '${outcome == Outcome.yes ? l.yes : l.no} ${formatPriceCents(price * 100)}',
              style: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProbabilityGauge extends StatelessWidget {
  const _ProbabilityGauge({required this.probability});
  final double probability;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = probability >= 0.5 ? p.yes : p.no;
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: probability,
              strokeWidth: 4,
              backgroundColor: p.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatPercent(probability, locale: context.lang),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
              Text(context.l10n.chance, style: TextStyle(color: p.textMuted, fontSize: 8.5)),
            ],
          ),
        ],
      ),
    );
  }
}
