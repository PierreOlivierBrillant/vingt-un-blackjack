import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/fairness.dart';
import '../../domain/table_state.dart';

Future<void> showFairnessSheet(BuildContext context, TableState t) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FairnessSheet(tableId: t.id, fairness: t.fairness),
    );

/// Provably-fair panel: the commitment of the current hand and a local
/// re-computation of the last finished hand (`tables/{id}/hands/{n}`).
class FairnessSheet extends ConsumerStatefulWidget {
  const FairnessSheet({super.key, required this.tableId, required this.fairness});
  final String tableId;
  final FairnessInfo fairness;

  @override
  ConsumerState<FairnessSheet> createState() => _FairnessSheetState();
}

class _FairnessSheetState extends ConsumerState<FairnessSheet> {
  FairnessVerdict? _verdict;
  int? _verifiedHand;

  void _verify(HandHistory h) {
    setState(() {
      _verifiedHand = h.handNumber;
      _verdict = verifyFairness(commit: h.commit, seed: h.seed, remainingBefore: h.remainingBefore, dealt: h.dealt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final history = ref.watch(tableHistoryProvider(widget.tableId));
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 11.5);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.fairTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.fairBody, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
            const SizedBox(height: 12),
            Text(l.fairCurrentCommit, style: const TextStyle(fontWeight: FontWeight.w700)),
            SelectableText((ref.watch(tableViewProvider(widget.tableId)).value?.fairness ?? widget.fairness).currentCommit ?? '—', key: const Key('fair-commit'), style: mono),
            const SizedBox(height: 12),
            AsyncBody(
              value: history,
              isEmpty: (l) => l.isEmpty,
              empty: Text(l.fairNoHistory, style: TextStyle(color: p.textMuted)),
              builder: (hands) {
                final h = hands.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.fairLastHand(h.handNumber), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('fair-verify'),
                      onPressed: () => _verify(h),
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(l.fairVerify),
                    ),
                    if (_verdict != null && _verifiedHand == h.handNumber)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _verdict == FairnessVerdict.verified ? l.fairVerified(h.dealt.length) : l.fairFailed,
                          key: const Key('fair-verdict'),
                          style: TextStyle(
                            color: _verdict == FairnessVerdict.verified ? p.win : p.loss,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SelectableText('seed   ${h.seed}', style: mono),
                    SelectableText('commit ${h.commit}', style: mono),
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
