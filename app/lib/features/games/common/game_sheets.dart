/// Bottom sheets of every Sprint 2 game table: rules ([GameUi.rules]),
/// history and fairness (`gameTables/{id}/rounds`, [GameUi.verifyRound]),
/// spectator markets of the table.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets.dart';
import '../../../data/providers.dart';
import '../../../domain/fairness.dart';
import '../../../domain/game_table.dart';
import '../../markets/markets_screen.dart' show MarketCard;
import '../game_ui.dart';

Future<void> showGameRulesSheet(BuildContext context, GameUi ui) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          key: const Key('game-rules-sheet'),
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(children: [
              Icon(ui.icon, color: ui.accent),
              const SizedBox(width: 8),
              Expanded(child: Text('${context.l10n.gameRules} · ${ui.name(context.l10n)}', style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            ui.rules(context),
          ],
        ),
      ),
    );

/// A rules paragraph (title + body), for [GameUi.rules] builders.
class RulesSection extends StatelessWidget {
  const RulesSection({super.key, this.title, required this.body, this.icon});
  final String? title;
  final String body;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: context.palette.textMuted), const SizedBox(width: 8)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) Text(title!, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(body, style: const TextStyle(height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );
}

Future<void> showGameHistorySheet(BuildContext context, GameUi ui, String tableId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HistorySheet(ui: ui, tableId: tableId),
    );

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.ui, required this.tableId});
  final GameUi ui;
  final String tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = context.palette;
    final me = ref.watch(gameTableRepositoryProvider).myUid;
    final now = ref.watch(clockProvider)();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => AsyncBody(
        value: ref.watch(gameRoundsProvider(tableId)),
        isEmpty: (r) => r.isEmpty,
        empty: EmptyState(icon: Icons.history, text: l.gameHistoryEmpty),
        builder: (rounds) => ListView(
          key: const Key('game-history-sheet'),
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(l.gameHistory, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final r in rounds)
              ListTile(
                key: Key('round-${r.round}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(ui.icon, color: ui.accent),
                title: Text(l.gameRoundNumber(r.round), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  [
                    ?ui.roundSummary?.call(l, r),
                    if (r.endedAt != null) relativeTime(context, r.endedAt!, now),
                  ].join(' · '),
                ),
                trailing: switch (r.seatOf(me)) {
                  final s? => Text(
                      context.money(s.netCents, signed: true),
                      style: TextStyle(fontWeight: FontWeight.w800, color: s.netCents >= 0 ? p.win : p.loss),
                    ),
                  null => null,
                },
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showGameFairnessSheet(BuildContext context, GameUi ui, GameTableState table) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GameFairnessSheet(ui: ui, tableId: table.id, commit: table.fairness.currentCommit),
    );

/// Provably-fair panel: commitment of the current round, local
/// re-computation of the last finished round with [GameUi.verifyRound].
class GameFairnessSheet extends ConsumerStatefulWidget {
  const GameFairnessSheet({super.key, required this.ui, required this.tableId, this.commit});
  final GameUi ui;
  final String tableId;
  final String? commit;

  @override
  ConsumerState<GameFairnessSheet> createState() => _GameFairnessSheetState();
}

class _GameFairnessSheetState extends ConsumerState<GameFairnessSheet> {
  FairnessVerdict? _verdict;
  int? _round;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 11.5);
    final commit = ref.watch(gameTableProvider(widget.tableId)).value?.fairness.currentCommit ?? widget.commit;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.fairTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.gameFairBody, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
            const SizedBox(height: 12),
            Text(l.gameFairCurrentCommit, style: const TextStyle(fontWeight: FontWeight.w700)),
            SelectableText(commit ?? '—', key: const Key('game-fair-commit'), style: mono),
            const SizedBox(height: 12),
            AsyncBody(
              value: ref.watch(gameRoundsProvider(widget.tableId)),
              isEmpty: (r) => r.isEmpty,
              empty: Text(l.gameHistoryEmpty, style: TextStyle(color: p.textMuted)),
              builder: (rounds) {
                final r = rounds.first;
                final ok = _verdict == FairnessVerdict.verified;
                final full = widget.ui.verifyRound != verifyRoundCommit || verifiesDraw(r);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.gameFairLastRound(r.round), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('game-fair-verify'),
                      onPressed: () => setState(() {
                        _round = r.round;
                        _verdict = widget.ui.verifyRound(r);
                      }),
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(l.gameFairVerify),
                    ),
                    if (_verdict != null && _round == r.round)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          ok ? (full ? l.gameFairVerified : l.gameFairCommitOnly) : l.fairFailed,
                          key: const Key('game-fair-verdict'),
                          style: TextStyle(color: ok ? p.win : p.loss, fontWeight: FontWeight.w800),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SelectableText('seed   ${r.fairness.seed}', style: mono),
                    SelectableText('commit ${r.fairness.commit}', style: mono),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showGameMarketsSheet(BuildContext context, String tableId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MarketsSheet(tableId: tableId),
    );

class _MarketsSheet extends ConsumerWidget {
  const _MarketsSheet({required this.tableId});
  final String tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => AsyncBody(
        value: ref.watch(tableMarketsProvider(tableId)),
        isEmpty: (list) => list.where((m) => m.isOpen).isEmpty,
        empty: EmptyState(icon: Icons.show_chart, text: l.marketsEmpty),
        builder: (list) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(l.tableBetsHere, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final m in list.where((m) => m.isOpen))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MarketCard(
                  market: m,
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/markets/${m.id}');
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
