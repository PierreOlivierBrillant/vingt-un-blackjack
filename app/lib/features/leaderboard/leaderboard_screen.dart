import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.leaderboardTitle),
          bottom: TabBar(tabs: [
            Tab(text: l.lbGlobal),
            Tab(text: l.lbFriends),
            Tab(text: l.lbWeekly),
          ]),
        ),
        body: const TabBarView(children: [
          _Board(scope: LeaderboardScope.global),
          _Board(scope: LeaderboardScope.friends),
          _Board(scope: LeaderboardScope.weekly),
        ]),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.scope});
  final LeaderboardScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = context.palette;
    return AsyncBody(
      value: ref.watch(leaderboardProvider(scope)),
      builder: (entries) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (entries.length >= 3) _Podium(top: entries.take(3).toList()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(l.lbPointsRule, style: TextStyle(color: p.textMuted, fontSize: 11.5)),
          ),
          for (final e in entries.length >= 3 ? entries.skip(3) : entries)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: e.isMe ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : null,
                borderRadius: BorderRadius.circular(10),
                border: e.isMe ? Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)) : null,
              ),
              child: ListTile(
                leading: SizedBox(
                  width: 72,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text('${e.rank}', style: TextStyle(fontWeight: FontWeight.w800, color: p.textMuted)),
                      ),
                      AppAvatar(name: e.username, hue: e.avatarHue, size: 34),
                    ],
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(e.isMe ? '${e.username} (${l.you})' : e.username,
                          style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    TierBadge(e.tier),
                  ],
                ),
                subtitle: Text(l.lbHandsWinRate(e.handsPlayed, formatPercent(e.winRate, locale: context.lang))),
                trailing: Text(l.lbPoints(groupDigits(e.points, context.lang == 'fr' ? ' ' : ',')),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top});
  final List<LeaderboardEntry> top;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const medal = [Color(0xFFF5C451), Color(0xFFB8C2CC), Color(0xFFCD7F32)];
    Widget column(int i, double height) {
      final e = top[i];
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: medal[i], width: 3)),
                  child: AppAvatar(name: e.username, hue: e.avatarHue, size: i == 0 ? 58 : 48),
                ),
                if (i == 0) Positioned(top: -20, child: Icon(Icons.workspace_premium, color: medal[0], size: 26)),
              ],
            ),
            const SizedBox(height: 6),
            Text(e.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(groupDigits(e.points, context.lang == 'fr' ? ' ' : ','), style: TextStyle(color: p.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [medal[i].withValues(alpha: 0.5), p.surface],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              ),
              alignment: Alignment.center,
              child: Text('${i + 1}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      child: SizedBox(
        height: 236,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [column(1, 70), column(0, 96), column(2, 54)],
        ),
      ),
    );
  }
}
