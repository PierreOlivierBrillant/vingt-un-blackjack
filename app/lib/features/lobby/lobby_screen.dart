import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ids.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../domain/card_style.dart';
import '../../domain/cards.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ads/ad_widgets.dart';
import '../cards/card_painters.dart';

String tierName(AppLocalizations l, String id) => switch (id) {
      'micro' => l.tierMicro,
      'low' => l.tierLow,
      'mid' => l.tierMid,
      'high' => l.tierHigh,
      'vip' => l.tierVip,
      _ => id,
    };

final _selectedTierProvider = NotifierProvider<_SelectedTier, String?>(_SelectedTier.new);

class _SelectedTier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = state == id ? null : id;
}

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  Future<void> _join(BuildContext context, WidgetRef ref, String tierId) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref
          .read(lobbyRepositoryProvider)
          .joinMatchmaking(mode: MatchMode.quick, stakeTier: tierId, idempotencyKey: newIdempotencyKey());
      if (context.mounted) await context.push('/table/${r.tableId}');
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final tiers = ref.watch(tiersProvider);
    final selected = ref.watch(_selectedTierProvider);
    final tables = ref.watch(liveTablesProvider(selected));
    final wins = ref.watch(recentWinsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(size: 18),
        actions: const [BalancePill()],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          AsyncBody(value: wins, builder: (w) => RecentWinsTicker(wins: w)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _Hero(
              onPlay: () => _join(context, ref, selected ?? 'low'),
              onDemo: () => context.push('/dealer-demo'),
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: AdBanner()),
          SectionHeader(l.lobbyStakes, icon: Icons.layers_outlined),
          SizedBox(
            height: 118,
            child: AsyncBody(
              value: tiers,
              builder: (list) => ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _TierCard(
                  tier: list[i],
                  selected: list[i].id == selected,
                  onTap: () => ref.read(_selectedTierProvider.notifier).select(list[i].id),
                ),
              ),
            ),
          ),
          SectionHeader(
            l.lobbyLiveTables,
            icon: Icons.sensors,
            trailing: selected == null
                ? null
                : TextButton(
                    onPressed: () => ref.read(_selectedTierProvider.notifier).select(selected),
                    child: Text(l.lobbyAllTiers),
                  ),
          ),
          AsyncBody(
            value: tables,
            builder: (list) => Column(
              children: [
                for (final t in list)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _TableCard(table: t, onPlay: () => context.push('/table/${t.id}')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Endless right-to-left marquee of recent wins.
class RecentWinsTicker extends StatefulWidget {
  const RecentWinsTicker({super.key, required this.wins});
  final List<RecentWin> wins;

  @override
  State<RecentWinsTicker> createState() => _RecentWinsTickerState();
}

class _RecentWinsTickerState extends State<RecentWinsTicker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final items = [
      for (final w in widget.wins)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                w.kind == WinKind.market ? Icons.show_chart : Icons.emoji_events,
                size: 14,
                color: w.kind == WinKind.blackjack ? p.gold : p.win,
              ),
              const SizedBox(width: 4),
              Text(w.username, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                switch (w.kind) {
                  WinKind.blackjack => l.winKindBlackjack,
                  WinKind.market => l.winKindMarket,
                  WinKind.bigWin => l.winKindWin,
                },
                style: TextStyle(color: p.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 4),
              Text(context.money(w.amountCents, signed: true), style: TextStyle(color: p.win, fontWeight: FontWeight.w800, fontSize: 12)),
            ],
          ),
        ),
    ];
    return Container(
      height: 34,
      color: p.surfaceSunken,
      child: ClipRect(
        child: LayoutBuilder(builder: (context, box) {
          return AnimatedBuilder(
            animation: _c,
            builder: (context, child) => OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: FractionalTranslation(
                translation: Offset(-_c.value * 0.5, 0),
                child: child,
              ),
            ),
            // Two copies so the loop is seamless at 50 %.
            child: Row(mainAxisSize: MainAxisSize.min, children: [...items, ...items]),
          );
        }),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.onPlay, required this.onDemo});
  final VoidCallback onPlay;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final style = ref.watch(equippedStyleProvider).value ?? const CardStyle();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [style.felt.light, style.felt.dark]),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            top: 10,
            child: Transform.rotate(
              angle: 0.18,
              child: Row(
                children: [
                  Transform.rotate(
                    angle: -0.3,
                    child: PlayingCardView(card: const PlayingCard(Rank.ace, Suit.spades), style: style, width: 56),
                  ),
                  Transform.translate(
                    offset: const Offset(-18, 6),
                    child: PlayingCardView(card: const PlayingCard(Rank.king, Suit.hearts), style: style, width: 56),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 110),
                  child: Text(
                    l.lobbyHeroTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 110),
                  child: Text(l.lobbyHeroSubtitle, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('lobby-play'),
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l.lobbyQuickPlay),
                    ),
                    OutlinedButton.icon(
                      key: const Key('lobby-demo'),
                      onPressed: onDemo,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: Text(l.lobbyDealerDemo),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.selected, required this.onTap});
  final StakeTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return SizedBox(
      width: 150,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          side: BorderSide(color: selected ? tier.accent : p.border, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: tier.accent, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tierName(l, tier.id),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '${context.money(tier.minBetCents, compact: true)} – ${context.money(tier.maxBetCents, compact: true)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  l.lobbyTierStats(tier.tablesLive, tier.playersOnline),
                  style: TextStyle(color: p.textMuted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table, required this.onPlay});
  final LiveTable table;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final full = table.seatsTaken - table.bots >= table.seatsTotal;
    return Panel(
      onTap: onPlay,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0B6B3A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.style, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(table.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: p.loss, borderRadius: BorderRadius.circular(4)),
                      child: Text(l.live, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${context.money(table.minBetCents, compact: true)} – ${context.money(table.maxBetCents, compact: true)} · ${l.handNumber(table.handNumber)}',
                  style: TextStyle(color: p.textMuted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    for (var i = 0; i < table.seatsTotal; i++)
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < table.seatsTaken - table.bots
                              ? p.win
                              : i < table.seatsTaken
                                  ? p.textMuted
                                  : Colors.transparent,
                          border: Border.all(color: p.textMuted),
                        ),
                      ),
                    if (table.queueLength > 0) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.hourglass_top, size: 13, color: p.textMuted),
                      const SizedBox(width: 2),
                      Text('${table.queueLength}', style: TextStyle(color: p.textMuted, fontSize: 11)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: full ? null : onPlay,
            style: FilledButton.styleFrom(minimumSize: const Size(64, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
            child: Text(full ? l.tableFull : l.play),
          ),
        ],
      ),
    );
  }
}
