/// "Last hand" sheet: the latest finished hand re-dealt locally from its
/// revealed seed — every hole card, the folded ones included (assumed choice
/// shown in the rules: the seed makes folded cards verifiable, hence
/// visible), each player's best hand with the full board and the verdict of
/// [verifyHoldemRound].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets.dart';
import '../../../data/providers.dart';
import '../../../domain/card_style.dart';
import '../../../domain/fairness.dart';
import '../../../domain/wire.dart';
import '../../cards/card_painters.dart';
import 'holdem_fairness.dart';
import 'holdem_labels.dart';

Future<void> showHoldemLastHandSheet(BuildContext context, String tableId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HoldemLastHandSheet(tableId: tableId),
    );

class HoldemLastHandSheet extends ConsumerWidget {
  const HoldemLastHandSheet({super.key, required this.tableId});
  final String tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = context.palette;
    final style = ref.watch(equippedStyleProvider).value ?? const CardStyle();
    final me = ref.watch(gameTableRepositoryProvider).myUid;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => AsyncBody(
        value: ref.watch(gameRoundsProvider(tableId)),
        isEmpty: (r) => r.isEmpty,
        empty: EmptyState(icon: Icons.style_outlined, text: l.holdemLastHandNone),
        builder: (rounds) {
          final reveal = revealHoldemRound(rounds.first);
          return ListView(
            key: const Key('holdem-last-hand-sheet'),
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(l.holdemLastHand, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(l.holdemLastHandBody, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
              if (reveal == null)
                Text(l.holdemLastHandNone, style: TextStyle(color: p.textMuted))
              else ...[
                Text(l.holdemLastHandRound(reveal.round), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  reveal.verdict == FairnessVerdict.verified ? l.holdemLastHandVerified : l.holdemLastHandFailed,
                  key: const Key('holdem-last-hand-verdict'),
                  style: TextStyle(color: reveal.verdict == FairnessVerdict.verified ? p.win : p.loss, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(l.holdemLastHandBoard, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                _cards(reveal.board, style, 44, shown: reveal.result?.boardShown ?? 5),
                const Divider(height: 24),
                for (final s in reveal.seats)
                  Padding(
                    key: Key('holdem-reveal-${s.seat}'),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        _cards(s.cards, style, 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  rounds.first.seatOf(me)?.seatIndex == s.seat ? l.gameYou : s.username,
                                  if (s.folded) l.holdemLastHandFolded,
                                  if (reveal.result?.winners.contains(s.seat) ?? false) l.holdemLastHandWinner,
                                ].join(' · '),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              if (s.hand != null)
                                Text(
                                  s.folded ? '${holdemHandName(l, s.hand!)} (${l.holdemLastHandIfDealt})' : holdemHandName(l, s.hand!),
                                  style: TextStyle(color: p.textMuted, fontSize: 12.5),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          context.money(s.netCents, signed: true, compact: true),
                          style: TextStyle(fontWeight: FontWeight.w800, color: s.netCents >= 0 ? p.win : p.loss),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _cards(List<String> cards, CardStyle style, double width, {int shown = 5}) => Wrap(
        spacing: 4,
        children: [
          for (var i = 0; i < cards.length; i++)
            Opacity(
              opacity: i < shown ? 1 : 0.55,
              child: PlayingCardView(card: cardFromWireOrNull(cards[i]), style: style, width: width, elevation: 1, backMedallion: '♠'),
            ),
        ],
      );
}
