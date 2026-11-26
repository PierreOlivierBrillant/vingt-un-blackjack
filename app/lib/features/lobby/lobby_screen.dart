import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/app_sound_events.dart';
import '../../core/audio/sfx.dart';
import '../../core/audio/sound_providers.dart';
import '../../core/characters/cast.dart';
import '../../core/characters/character_spec.dart';
import '../../core/characters/character_view.dart';
import '../../core/ids.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../domain/backend_constants.dart';
import '../../domain/card_style.dart';
import '../../domain/cards.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ads/ad_widgets.dart';
import '../cards/card_painters.dart';
import '../games/common/game_sheets.dart';
import '../games/game_join.dart';
import '../games/registry.dart';

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

/// Game picked in the lobby selector (blackjack by default).
final selectedGameProvider = NotifierProvider<SelectedGame, GameId>(SelectedGame.new);

class SelectedGame extends Notifier<GameId> {
  @override
  GameId build() => GameId.blackjack;
  void select(GameId g) => state = g;
}

/// Live public tables of [game] (blackjack: `tables`; others: `gameTables`).
final _lobbyTablesProvider = Provider.family<AsyncValue<List<LiveTable>>, (GameId, String?)>((ref, k) {
  final (game, tier) = k;
  return game == GameId.blackjack ? ref.watch(liveTablesProvider(tier)) : ref.watch(gameLiveTablesProvider((game, tier)));
});

/// Tier cards of a kernel game: counters from its tables, limits from them
/// when known (else the blackjack STAKE_TIER_LIMITS as an indication).
List<StakeTier> _gameTiers(List<LiveTable> tables) => [
      for (final id in Backend.stakeTiers)
        () {
          final base = StakeTier.of(id, tables: tables);
          final mine = tables.where((t) => t.tierId == id).toList();
          if (mine.isEmpty) return base;
          return StakeTier(
            id: id,
            minBetCents: mine.map((t) => t.minBetCents).reduce((a, b) => a < b ? a : b),
            maxBetCents: mine.map((t) => t.maxBetCents).reduce((a, b) => a > b ? a : b),
            tablesLive: base.tablesLive,
            playersOnline: base.playersOnline,
            accent: base.accent,
          );
        }(),
    ];

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  Future<void> _join(BuildContext context, WidgetRef ref, GameId game, String tierId) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (game.isKernel) {
      final r = await joinGameTable(context, ref, gameUi(game), mode: GameJoinMode.quick, stakeTier: tierId);
      if (r != null && context.mounted) await context.push('/table/${r.tableId}');
      return;
    }
    try {
      final r = await withMatchmakingSounds(
        ref.read(soundProvider),
        () => ref
            .read(lobbyRepositoryProvider)
            .joinMatchmaking(mode: MatchMode.quick, stakeTier: tierId, idempotencyKey: newIdempotencyKey()),
      );
      if (context.mounted) await context.push('/table/${r.tableId}');
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final game = ref.watch(selectedGameProvider);
    final ui = gameUi(game);
    final selected = ref.watch(_selectedTierProvider);
    final tables = ref.watch(_lobbyTablesProvider((game, selected)));
    final allTables = ref.watch(_lobbyTablesProvider((game, null)));
    final tiers = game == GameId.blackjack ? ref.watch(tiersProvider) : allTables.whenData(_gameTiers);
    final wins = ref.watch(recentWinsProvider);
    // Other players' wins ring around the casino floor.
    ref.listen(recentWinsProvider, (_, n) {
      final list = n.value;
      if (list != null) ref.read(recentWinsSoundsProvider).onWins(list);
    });

    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(size: 18),
        actions: [
          IconButton(
            key: const Key('lobby-leaderboard'),
            tooltip: l.navLeaderboard,
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => context.push('/leaderboard'),
          ),
          const BalancePill(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          AsyncBody(value: wins, builder: (w) => RecentWinsTicker(wins: w)),
          SectionHeader(l.lobbyChooseGame, icon: Icons.casino_outlined),
          GameSelector(
            selected: game,
            onSelect: (g) {
              if (g == game) return;
              context.sfx(Sfx.uiToggle);
              ref.read(selectedGameProvider.notifier).select(g);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a), child: child),
              ),
              child: game == GameId.blackjack
                  ? _Hero(
                      key: const ValueKey('hero-blackjack'),
                      onPlay: () => _join(context, ref, game, selected ?? 'low'),
                      onDemo: () => context.push('/dealer-demo'),
                      onPrivate: () => showPrivateTableSheet(context, stakeTier: selected ?? 'low'),
                    )
                  : _GameHero(
                      key: ValueKey('hero-${game.wire}'),
                      ui: ui,
                      onPlay: () => _join(context, ref, game, selected ?? 'low'),
                      onPrivate: () => showPrivateTableSheet(context, stakeTier: selected ?? 'low', game: game),
                    ),
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
            isEmpty: (list) => list.isEmpty,
            empty: EmptyState(icon: ui.icon, text: l.lobbyNoTables),
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

/// Animated game picker: one tile per game of the registry ([kGames]) with
/// its croupier's medallion; the selected one grows and glows in the
/// game's accent. Games not playable yet carry a "SOON" ribbon.
class GameSelector extends StatelessWidget {
  const GameSelector({super.key, required this.selected, required this.onSelect});
  final GameId selected;
  final ValueChanged<GameId> onSelect;

  @override
  Widget build(BuildContext context) {
    final games = kGames.values.toList();
    return SizedBox(
      height: 128,
      child: ListView.separated(
        key: const Key('game-selector'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: games.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _GameTile(ui: games[i], selected: games[i].id == selected, onTap: () => onSelect(games[i].id)),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.ui, required this.selected, required this.onTap});
  final GameUi ui;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return AnimatedScale(
      scale: selected ? 1 : 0.92,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 104,
        decoration: BoxDecoration(
          color: selected ? Color.alphaBlend(ui.accent.withValues(alpha: 0.16), p.surface) : p.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: selected ? ui.accent : p.border, width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: ui.accent.withValues(alpha: 0.35), blurRadius: 14)] : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key('game-chip-${ui.id.wire}'),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: onTap,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                  child: Column(
                    children: [
                      CharacterPortrait(spec: Cast.dealerOf(ui.id), size: 54),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(ui.icon, size: 14, color: ui.accent),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              ui.name(l),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: selected ? FontWeight.w900 : FontWeight.w700, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!ui.playable)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: ui.accent, borderRadius: BorderRadius.circular(4)),
                      child: Text(l.gameComingSoon, style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
                w.kind == WinKind.market ? Icons.show_chart : (w.game == GameId.blackjack ? Icons.emoji_events : gameUi(w.game).icon),
                size: 14,
                color: w.kind == WinKind.blackjack || w.kind == WinKind.jackpot ? p.gold : p.win,
              ),
              const SizedBox(width: 4),
              Text(w.username, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                switch (w.kind) {
                  WinKind.blackjack => l.winKindBlackjack,
                  WinKind.market => l.winKindMarket,
                  WinKind.bigWin => l.winKindWin,
                  WinKind.jackpot => l.winKindJackpot,
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
  const _Hero({super.key, required this.onPlay, required this.onDemo, required this.onPrivate});
  final VoidCallback onPlay;
  final VoidCallback onDemo;
  final VoidCallback onPrivate;

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
                    OutlinedButton.icon(
                      key: const Key('lobby-private'),
                      onPressed: onPrivate,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      icon: const Icon(Icons.lock_outline),
                      label: Text(l.lobbyPrivate),
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

/// Hero of a Sprint 2 game: its croupier's bust, name, tagline and the
/// quick play / private table / rules buttons (disabled while the game is
/// not playable yet).
class _GameHero extends StatelessWidget {
  const _GameHero({super.key, required this.ui, required this.onPlay, required this.onPrivate});
  final GameUi ui;
  final VoidCallback onPlay;
  final VoidCallback onPrivate;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dealer = Cast.dealerOf(ui.id);
    final dark = Color.lerp(ui.accent, Colors.black, 0.72)!;
    final outlined = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white38,
      side: const BorderSide(color: Colors.white54),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [Color.lerp(ui.accent, Colors.black, 0.45)!, dark]),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 4,
            bottom: 0,
            child: CharacterPortrait(spec: dealer, size: 104, framing: CharacterFraming.bust, expression: CharacterExpression.smile),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 104),
                  child: Text(l.gameHeroTitle(ui.name(l)), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 104),
                  child: Text(ui.tagline(l), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 104),
                  child: Text(
                    ui.playable ? l.gameDealer(dealer.name) : '${l.gameDealer(dealer.name)} · ${l.gameComingSoonBody}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5, fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('lobby-play'),
                      onPressed: ui.playable ? onPlay : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l.lobbyQuickPlay),
                    ),
                    OutlinedButton.icon(
                      key: const Key('lobby-private'),
                      onPressed: ui.playable ? onPrivate : null,
                      style: outlined,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(l.lobbyPrivate),
                    ),
                    OutlinedButton.icon(
                      key: const Key('lobby-rules'),
                      onPressed: () => showGameRulesSheet(context, ui),
                      style: outlined,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(l.gameRules),
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
    final ui = gameUi(table.game);
    final blackjack = table.game == GameId.blackjack;
    return Panel(
      onTap: onPlay,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: blackjack ? const Color(0xFF0B6B3A) : Color.lerp(ui.accent, Colors.black, 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ui.icon, color: Colors.white),
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
                  '${context.money(table.minBetCents, compact: true)} – ${context.money(table.maxBetCents, compact: true)} · ${blackjack ? l.handNumber(table.handNumber) : l.gameRoundNumber(table.handNumber)}',
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
            onPressed: onPlay,
            style: FilledButton.styleFrom(minimumSize: const Size(64, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
            child: Text(l.watch),
          ),
        ],
      ),
    );
  }
}

/// Create a private table (no bots, shareable 6-char code) or join one.
/// [game] blackjack uses `joinMatchmaking`; the other games `gameJoin`
/// (whose joinCode accepts a code of ANY game, the result says which).
Future<void> showPrivateTableSheet(BuildContext context, {required String stakeTier, GameId game = GameId.blackjack}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PrivateTableSheet(stakeTier: stakeTier, game: game),
    );

class _PrivateTableSheet extends ConsumerStatefulWidget {
  const _PrivateTableSheet({required this.stakeTier, required this.game});
  final String stakeTier;
  final GameId game;

  @override
  ConsumerState<_PrivateTableSheet> createState() => _PrivateTableSheetState();
}

class _PrivateTableSheetState extends ConsumerState<_PrivateTableSheet> {
  final _code = TextEditingController();
  late String _tier = widget.stakeTier;
  bool _busy = false;
  String? _error;
  final _keys = <String, String>{};

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _go(MatchMode mode) async {
    final l = context.l10n;
    final code = _code.text.trim().toUpperCase();
    if (mode == MatchMode.joinCode && !Backend.tableCodePattern.hasMatch(code)) {
      setState(() => _error = l.privateCodeInvalid);
      return;
    }
    final op = '${mode.name}|$_tier|$code';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String tableId;
      final String? resultCode;
      if (widget.game.isKernel) {
        final r = await joinGameTable(
          context,
          ref,
          gameUi(widget.game),
          mode: GameJoinMode.values.byName(mode.name),
          stakeTier: _tier,
          code: mode == MatchMode.joinCode ? code : null,
          idempotencyKey: _keys[op] ??= newIdempotencyKey(),
          rethrowErrors: true,
        );
        if (r == null) return;
        tableId = r.tableId;
        resultCode = r.code;
      } else {
        final r = await withMatchmakingSounds(
          ref.read(soundProvider),
          () => ref.read(lobbyRepositoryProvider).joinMatchmaking(
                mode: mode,
                stakeTier: _tier,
                code: mode == MatchMode.joinCode ? code : null,
                idempotencyKey: _keys[op] ??= newIdempotencyKey(),
              ),
        );
        tableId = r.tableId;
        resultCode = r.code;
      }
      _keys.remove(op);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      final c = resultCode ?? (mode == MatchMode.joinCode ? code : null);
      await router.push(c == null ? '/table/$tableId' : '/table/$tableId?code=$c');
    } on Object catch (e) {
      if (mounted) setState(() => _error = localizeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ui = gameUi(widget.game);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(ui.icon, color: ui.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.game == GameId.blackjack ? l.lobbyPrivate : '${l.lobbyPrivate} · ${ui.name(l)}', style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 4),
            Text(l.privateIntro, style: TextStyle(color: context.palette.textMuted, fontSize: 12.5)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [for (final t in Backend.stakeTiers) ButtonSegment(value: t, label: Text(tierName(l, t)))],
              selected: {_tier},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _tier = s.first),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('private-create'),
              onPressed: _busy ? null : () => _go(MatchMode.createPrivate),
              icon: const Icon(Icons.add),
              label: Text(l.privateCreate),
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('private-code'),
                    controller: _code,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: l.privateCodeLabel, counterText: ''),
                    onSubmitted: (_) => _go(MatchMode.joinCode),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('private-join'),
                  onPressed: _busy ? null : () => _go(MatchMode.joinCode),
                  child: Text(l.privateJoin),
                ),
              ],
            ),
            if (_error != null) InlineError(_error!),
          ],
        ),
      ),
    );
  }
}
