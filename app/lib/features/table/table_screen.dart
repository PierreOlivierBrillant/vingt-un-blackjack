import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ids.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/card_style.dart';
import '../../domain/models.dart';
import '../../domain/table_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../cards/chips.dart';
import '../dealer/dealer_controller.dart';
import '../dealer/dealer_feedback.dart';
import '../dealer/dealer_stage.dart';
import '../shop/shop_screen.dart';

String actionLabel(AppLocalizations l, PlayerAction a) => switch (a) {
      PlayerAction.hit => l.actionHit,
      PlayerAction.stand => l.actionStand,
      PlayerAction.double => l.actionDouble,
      PlayerAction.split => l.actionSplit,
      PlayerAction.surrender => l.actionSurrender,
      PlayerAction.insurance => l.actionInsurance,
      PlayerAction.peek => l.actionInsurance,
    };

/// Live table. Phase 1: the scene is rebuilt from the static [TableView]
/// placeholder. The Firebase phase converts snapshot diffs into
/// [DealerController] commands (dealCard / revealHoleCard / payout ...).
class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key, required this.tableId});
  final String tableId;

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  late final DealerController _dealer;
  bool _staged = false;
  int _chip = 2500;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _dealer = DealerController(feedback: SystemDealerFeedback(sound: s.soundOn, haptics: s.hapticsOn));
  }

  @override
  void dispose() {
    _dealer.dispose();
    super.dispose();
  }

  void _stage(TableState t) {
    if (_staged) return;
    _staged = true;
  }

  Future<void> _act(PlayerAction a) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final t = ref.read(tableViewProvider(widget.tableId)).value;
    if (t == null) return;
    await ref.read(tableRepositoryProvider).act(widget.tableId, t.handNumber, a, idempotencyKey: newIdempotencyKey());
    messenger.showSnackBar(SnackBar(content: Text(l.actionSent(actionLabel(l, a))), duration: const Duration(seconds: 1)));
  }

  void _showFairness(TableState t) {
    final l = context.l10n;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.fairTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.fairBody),
            const SizedBox(height: 12),
            SelectableText(t.fairness.currentCommit ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final table = ref.watch(tableViewProvider(widget.tableId));
    final style = ref.watch(equippedStyleProvider).value ?? const CardStyle();
    return Scaffold(
      backgroundColor: const Color(0xFF0A1620),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1620),
        foregroundColor: Colors.white,
        // The casino room is always dark, whatever the app theme.
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
        title: table.value == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(table.value!.name),
                  Text(
                    '${l.handNumber(table.value!.handNumber)} · ${context.money(table.value!.minBetCents, compact: true)}–${context.money(table.value!.maxBetCents, compact: true)}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
        actions: [
          if (table.value != null)
            IconButton(
              tooltip: l.fairTitle,
              icon: const Icon(Icons.verified_user_outlined),
              onPressed: () => _showFairness(table.value!),
            ),
          IconButton(
            tooltip: l.leaveTable,
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(tableRepositoryProvider).leave(widget.tableId);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: AsyncBody(
        value: table,
        builder: (t) {
          _stage(t);
          final seats = [
            for (final s in t.seats)
              s == null
                  ? null
                  : DealerSeat(name: s.username, stackCents: s.betCents, isMe: s.uid == ref.read(tableRepositoryProvider).myUid, isBot: s.isBot),
          ];
          final me = ref.read(tableRepositoryProvider).myUid;
          final myTurn = t.phase == ServerTablePhase.playerTurns && t.turn != null && t.seats[t.turn!.seatIndex]?.uid == me;
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: DealerStage(controller: _dealer, style: style, seats: seats),
                ),
              ),
              _ActionBar(
                enabled: myTurn,
                onAction: _act,
                onPowers: () => showModalBottomSheet<void>(context: context, builder: (_) => const PowersSheet()),
                chip: _chip,
                onChip: (c) => setState(() => _chip = c),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.enabled, required this.onAction, required this.onPowers, required this.chip, required this.onChip});
  final bool enabled;
  final ValueChanged<PlayerAction> onAction;
  final VoidCallback onPowers;
  final int chip;
  final ValueChanged<int> onChip;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    Widget btn(PlayerAction a, IconData icon, {Color? color}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FilledButton(
              key: Key('action-${a.name}'),
              onPressed: enabled ? () => onAction(a) : null,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                minimumSize: const Size(0, 52),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  FittedBox(child: Text(actionLabel(l, a), style: const TextStyle(fontSize: 12))),
                ],
              ),
            ),
          ),
        );
    return Container(
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        for (final d in kChipDenominations.reversed.take(5))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChipButton(denomination: d, size: 38, selected: d.cents == chip, onTap: () => onChip(d.cents)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  key: const Key('table-powers'),
                  onPressed: onPowers,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  icon: Icon(Icons.bolt, color: p.gold),
                  label: Text(l.powers),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                btn(PlayerAction.hit, Icons.add_circle_outline),
                btn(PlayerAction.stand, Icons.pan_tool_outlined, color: BrandColors.blue),
                btn(PlayerAction.double, Icons.exposure_plus_2, color: p.gold),
                btn(PlayerAction.split, Icons.call_split, color: const Color(0xFF8E5CFF)),
                btn(PlayerAction.surrender, Icons.flag_outlined, color: p.loss),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
