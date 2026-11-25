import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/audio/sfx.dart';
import '../../core/audio/sound_providers.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import 'markets_screen.dart';

class MarketDetailScreen extends ConsumerWidget {
  const MarketDetailScreen({super.key, required this.marketId});
  final String marketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final market = ref.watch(marketProvider(marketId));
    // Odds moving while you watch: micro-blips (rate-limited by the governor).
    ref.listen<AsyncValue<Market>>(marketProvider(marketId), (prev, next) {
      final a = prev?.value?.yesPrice;
      final b = next.value?.yesPrice;
      if (a == null || b == null || (a - b).abs() < 1e-6) return;
      ref.sfx(b > a ? Sfx.priceTickUp : Sfx.priceTickDown);
    });
    return Scaffold(
      appBar: AppBar(title: Text(l.marketTitle), actions: const [BalancePill()]),
      body: AsyncBody(
        value: market,
        builder: (m) => _Body(market: m),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.market});
  final Market market;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = context.palette;
    final m = market;
    final history = ref.watch(priceHistoryProvider(m.id));
    final activity = ref.watch(marketActivityProvider(m.id));
    final position = (ref.watch(positionsProvider).value ?? const <MarketPosition>[]).where((x) => x.marketId == m.id).firstOrNull;
    final positions = [
      if (position != null)
        for (final o in Outcome.values)
          if (position.sharesOf(o) > 0) (outcome: o, shares: position.sharesOf(o)),
    ];
    final now = ref.watch(clockProvider)();
    final firstPrice = history.value?.firstOrNull?.yes ?? m.priceYes;
    final change = ((m.priceYes - firstPrice) * 100).round();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(marketQuestion(l, m), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(marketSubtitle(l, m), style: TextStyle(color: p.textMuted)),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l.marketChanceLabel(formatPercent(m.yesPrice, locale: context.lang)),
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: p.yes),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Icon(change >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                            color: change >= 0 ? p.win : p.loss),
                        Text(
                          '${change.abs()} pts',
                          style: TextStyle(color: change >= 0 ? p.win : p.loss, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 16, 0),
            child: AsyncBody(value: history, builder: (pts) => PriceChart(points: pts)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.marketVolume(compactVolume(context, m.volumeCents)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textMuted, fontSize: 12),
                ),
              ),
              Flexible(
                child: TextButton.icon(
                  onPressed: () => context.push('/table/${m.tableId}'),
                  icon: const Icon(Icons.live_tv, size: 18),
                  label: Text(l.marketWatchTable, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
        if (m.status == MarketStatus.open)
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: OrderTicket(market: m))
        else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Panel(child: Text(l.marketClosedNotice, textAlign: TextAlign.center)),
          ),
        if (positions.isNotEmpty) ...[
          SectionHeader(l.marketYourPositions, icon: Icons.account_balance_wallet_outlined),
          for (final pos in positions)
            ListTile(
              leading: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (pos.outcome == Outcome.yes ? p.yes : p.no).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(pos.outcome == Outcome.yes ? l.yes : l.no,
                    style: TextStyle(color: pos.outcome == Outcome.yes ? p.yes : p.no, fontWeight: FontWeight.w800)),
              ),
              title: Text(l.positionShares(pos.shares, formatPriceCents(position!.avgPrice * 100))),
              subtitle: Text(l.positionValue(context.money((pos.shares * m.priceOf(pos.outcome) * 100).round()))),
              trailing: positions.length > 1
                  ? null
                  : Text(
                      context.money(position.pnlCents(m.priceYes), signed: true),
                      style: TextStyle(color: position.pnlCents(m.priceYes) >= 0 ? p.win : p.loss, fontWeight: FontWeight.w800),
                    ),
            ),
        ],
        SectionHeader(l.marketActivity, icon: Icons.bolt),
        AsyncBody(
          value: activity,
          builder: (trades) => Column(
            children: [
              for (final t in trades)
                ListTile(
                  dense: true,
                  leading: AppAvatar(name: t.username, hue: stableHash(t.username) % 360, size: 28),
                  title: Text.rich(TextSpan(children: [
                    TextSpan(text: t.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' ${t.isBuy ? l.tradeBought : l.tradeSold} ${t.shares} '),
                    TextSpan(
                      text: t.outcome == Outcome.yes ? l.yes : l.no,
                      style: TextStyle(color: t.outcome == Outcome.yes ? p.yes : p.no, fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: ' @ ${formatPriceCents(t.price * 100)}'),
                  ])),
                  trailing: Text(relativeTime(context, t.at, now), style: TextStyle(color: p.textMuted, fontSize: 11)),
                ),
            ],
          ),
        ),
        SectionHeader(l.marketRules, icon: Icons.gavel_outlined),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l.marketRulesBody, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
        ),
      ],
    );
  }
}

class PriceChart extends StatelessWidget {
  const PriceChart({super.key, required this.points});
  final List<PricePoint> points;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (points.isEmpty) return const SizedBox.shrink();
    final t0 = points.first.t;
    final spots = [
      for (final pt in points) FlSpot(pt.t.difference(t0).inSeconds / 60, (pt.yes * 100).roundToDouble()),
    ];
    // A brand-new market has one price point (or several within the same second): give the chart a
    // non-zero time span, otherwise the axis interval is 0 and fl_chart asserts.
    if (spots.last.x <= 0) spots.add(FlSpot(1 / 60, spots.last.y));
    final fmt = DateFormat.Hm(context.lang);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 25,
              getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: TextStyle(color: p.textMuted, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: spots.last.x / 3,
              getTitlesWidget: (v, meta) {
                if (v == meta.max || v == meta.min) return const SizedBox.shrink();
                return Text(fmt.format(t0.add(Duration(seconds: (v * 60).round()))),
                    style: TextStyle(color: p.textMuted, fontSize: 10));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => p.surfaceRaised,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem('${s.y.toInt()}¢', TextStyle(color: p.yes, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            color: p.yes,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.yes.withValues(alpha: 0.3), p.yes.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

/// Buy/sell YES/NO shares. Shows the LMSR estimate from the repository; the
/// server recomputes the price inside its transaction.
class OrderTicket extends ConsumerStatefulWidget {
  const OrderTicket({super.key, required this.market});
  final Market market;

  @override
  ConsumerState<OrderTicket> createState() => _OrderTicketState();
}

class _OrderTicketState extends ConsumerState<OrderTicket> {
  bool _buy = true;
  Outcome _outcome = Outcome.yes;
  int _shares = 10;
  TradeQuote? _quote;

  @override
  void initState() {
    super.initState();
    _refreshQuote();
  }

  /// The market doc is live: re-quote whenever its LMSR state changes, so the
  /// estimate (and the slippage guard sent with the order) stays current.
  @override
  void didUpdateWidget(OrderTicket old) {
    super.didUpdateWidget(old);
    final a = old.market;
    final b = widget.market;
    if (a.id != b.id || a.qYes != b.qYes || a.qNo != b.qNo || a.b != b.b || a.status != b.status) _refreshQuote();
  }

  Future<void> _refreshQuote() async {
    try {
      final q = await ref.read(marketsRepositoryProvider).quote(widget.market.id, _outcome, _shares, buy: _buy);
      if (mounted) setState(() => _quote = q);
    } on Object {
      if (mounted) setState(() => _quote = null);
    }
  }

  void _update(VoidCallback f) {
    setState(f);
    _refreshQuote();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final m = widget.market;
    final q = _quote;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(l.buy)),
              ButtonSegment(value: false, label: Text(l.sell)),
            ],
            selected: {_buy},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _update(() => _buy = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutcomeButton(
                  outcome: Outcome.yes,
                  price: m.yesPrice,
                  selected: _outcome == Outcome.yes,
                  onTap: () => _update(() => _outcome = Outcome.yes),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutcomeButton(
                  outcome: Outcome.no,
                  price: m.noPrice,
                  selected: _outcome == Outcome.no,
                  onTap: () => _update(() => _outcome = Outcome.no),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(l.shares, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton.outlined(
                key: const Key('shares-minus'),
                onPressed: _shares > 1 ? () => _update(() => _shares = (_shares - 5).clamp(1, 1000)) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 56,
                child: Text('$_shares', key: const Key('shares-count'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              IconButton.outlined(
                key: const Key('shares-plus'),
                onPressed: () => _update(() => _shares = (_shares + 5).clamp(1, 1000)),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const Divider(height: 20),
          _row(l.ticketAvgPrice, q == null ? '—' : formatPriceCents(q.avgPrice * 100)),
          _row(_buy ? l.ticketCost : l.ticketProceeds, q == null ? '—' : context.money(q.costCents.abs())),
          if (_buy) _row(l.ticketPayout, q == null ? '—' : context.money(q.maxPayoutCents), color: p.win),
          _row(l.ticketPriceAfter, q == null ? '—' : formatPriceCents(q.priceAfter * 100)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('ticket-submit'),
            style: FilledButton.styleFrom(backgroundColor: _outcome == Outcome.yes ? p.yes : p.no, foregroundColor: Colors.white),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                // The quote is the exact server LMSR amount: use it as the slippage guard.
                await ref.read(marketsRepositoryProvider).trade(
                      m.id,
                      _outcome,
                      _shares,
                      buy: _buy,
                      maxCostCents: _buy ? q?.amountCents : null,
                      minProceedsCents: _buy ? null : q?.amountCents,
                      idempotencyKey: newIdempotencyKey(),
                    );
                messenger.showSnackBar(SnackBar(content: Text(l.ticketDone)));
              } on Object catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
              }
              await _refreshQuote();
            },
            child: Text(l.ticketSubmit(_buy ? l.buy : l.sell, _outcome == Outcome.yes ? l.yes : l.no)),
          ),
          const SizedBox(height: 6),
          Text(l.ticketDisclaimer, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.palette.textMuted)),
            ),
            const SizedBox(width: 8),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );
}
