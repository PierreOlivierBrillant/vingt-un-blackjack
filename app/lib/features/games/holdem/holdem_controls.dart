/// Bottom panel of a seated hold'em player: my hand and what is going on,
/// then — on my turn — fold / check or call / bet or raise with a slider
/// that respects the server's minimum raise and my stack ([HoldemRaiseModel]),
/// presets (min, ½ pot, pot, all-in); rebuy between hands; sit out / sit in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets.dart';
import '../../../data/providers.dart';
import '../../../domain/game_table.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../common/game_table_view.dart';
import 'holdem_evaluator.dart';
import 'holdem_labels.dart';
import 'holdem_raise.dart';
import 'holdem_state.dart';

/// "A♠ K♦" (wire codes, `T` shown as 10).
String holdemCardsText(List<String> cards) => cards.map((c) {
      final r = c[0] == 'T' ? '10' : c[0];
      final s = switch (c[1]) { 'S' => '♠', 'H' => '♥', 'D' => '♦', _ => '♣' };
      return '$r$s';
    }).join(' ');

/// My hand in words: the cards preflop, then the best hand with the board.
String? holdemMyHandText(AppLocalizations l, List<String>? hole, List<String> board) {
  if (hole == null || hole.length != 2) return null;
  if (board.length < 3) return l.holdemMyHand(holdemCardsText(hole));
  return l.holdemMyHand(holdemHandName(l, evaluateHoldemHand([...hole, ...board])));
}

class HoldemControls extends ConsumerStatefulWidget {
  const HoldemControls({super.key, required this.view});
  final GameTableView view;

  @override
  ConsumerState<HoldemControls> createState() => _HoldemControlsState();
}

class _HoldemControlsState extends ConsumerState<HoldemControls> {
  int? _to;
  String? _forKey;

  GameTableView get v => widget.view;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final t = v.table;
    final me = v.mine!;
    final hs = HoldemSeatState.of(me);
    final h = HoldemTable.of(t);
    final step = holdemStepOf(t);
    final live = t.phase == GamePhase.live && step != HoldemStep.waiting;
    final hole = ref.watch(gameHoleProvider(t.id)).value;
    final myHole = hole != null && hole.round == t.round && hole.cards.length == 2 && hs.inHand ? hole.cards : null;
    final toAct = h.toAct;
    final myTurn = live && toAct != null && toAct.seat == me.seatIndex && v.myTurn;
    final raise = myTurn ? HoldemRaiseModel.of(toAct, currentBet: h.currentBetCents, myBet: hs.betCents, middleCents: holdemChipsInMiddle(t)) : null;
    // Reset the slider for each new decision.
    final key = '${t.round}/${step?.name}/${h.currentBetCents}/${toAct?.seat}';
    if (key != _forKey) {
      _forKey = key;
      _to = raise?.low;
    }
    final maxBuyIn = t.limits.extra['maxBuyInCents'] ?? 0;
    final room = maxBuyIn - (me.stackCents ?? 0);
    final canRebuy = !holdemInLiveHand(t, me) && room >= 100;

    final info = _info(l, hs, live, step, myTurn, toAct);
    final hand = live || t.phase == GamePhase.settled ? holdemMyHandText(l, myHole, h.board) : null;

    return ValueListenableBuilder<bool>(
      valueListenable: v.actions.busy,
      builder: (context, busy, _) => Container(
        color: p.surface,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hand != null)
                          Text(hand, key: const Key('holdem-my-hand'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(info, key: const Key('holdem-info'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (canRebuy)
                    TextButton(
                      key: const Key('holdem-rebuy'),
                      onPressed: busy ? null : () => _rebuy(context, room),
                      child: Text(l.holdemRebuy),
                    ),
                  if (me.sittingOut)
                    FilledButton.tonal(key: const Key('holdem-sit-in'), onPressed: busy ? null : v.actions.sitIn, child: Text(l.holdemSitIn))
                  else
                    TextButton(key: const Key('holdem-sit-out'), onPressed: busy ? null : v.actions.sitOut, child: Text(l.holdemSitOut)),
                ],
              ),
              if (myTurn) ...[
                if (raise != null && !raise.allInOnly) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          key: const Key('holdem-slider'),
                          value: raise.positionOf(_to ?? raise.low),
                          onChanged: busy ? null : (x) => setState(() => _to = raise.amountAt(x)),
                        ),
                      ),
                      Text(
                        context.money(raise.clamp(_to ?? raise.low), compact: true),
                        key: const Key('holdem-amount'),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final (preset, amount) in raise.presets)
                        ActionChip(
                          key: Key('holdem-preset-${preset.name}'),
                          visualDensity: VisualDensity.compact,
                          label: Text(_presetLabel(l, preset)),
                          onPressed: busy ? null : () => setState(() => _to = amount),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('holdem-fold'),
                        onPressed: busy ? null : () => v.actions.act(const {'type': 'fold'}),
                        child: Text(l.holdemFold, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: toAct.canCheck
                          ? FilledButton.tonal(
                              key: const Key('holdem-check'),
                              onPressed: busy ? null : () => v.actions.act(const {'type': 'check'}),
                              child: Text(l.holdemCheck, maxLines: 1, overflow: TextOverflow.ellipsis),
                            )
                          : FilledButton.tonal(
                              key: const Key('holdem-call'),
                              onPressed: busy ? null : () => v.actions.act(const {'type': 'call'}),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  toAct.callCents >= (me.stackCents ?? 0)
                                      ? l.holdemAllInTo(context.money(toAct.callCents, compact: true))
                                      : l.holdemCall(context.money(toAct.callCents, compact: true)),
                                ),
                              ),
                            ),
                    ),
                    if (raise != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: FilledButton(
                          key: const Key('holdem-raise'),
                          onPressed: busy ? null : () => v.actions.act(raise.actionFor(_to ?? raise.low)),
                          child: FittedBox(fit: BoxFit.scaleDown, child: Text(_raiseLabel(context, l, raise, _to ?? raise.low))),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _info(AppLocalizations l, HoldemSeatState hs, bool live, HoldemStep? step, bool myTurn, HoldemToAct? toAct) {
    final t = v.table;
    final me = v.mine!;
    if (me.sittingOut) return l.holdemYouPaused;
    final noChips = (me.stackCents ?? 0) <= 0 && !hs.live;
    if (step == HoldemStep.waiting && t.phase == GamePhase.live) return noChips ? l.holdemNoChips : l.holdemWaitingChips;
    if (t.phase == GamePhase.idle) return noChips ? l.holdemNoChips : l.holdemWaitingPlayers;
    if (live) {
      if (hs.inHand) {
        if (hs.folded) return l.holdemYouFolded;
        if (hs.allIn) return l.holdemYouAllIn;
        if (myTurn && toAct != null) {
          return toAct.callCents > 0 ? l.holdemToCall(context.money(toAct.callCents, compact: true)) : l.tableYourTurn(v.secondsLeft);
        }
        final turn = t.turnSeatState;
        return turn == null ? l.gamePhaseLive : l.holdemWaitTurn(turn.username);
      }
      if (noChips) return l.holdemNoChips;
      if (hs.waitBB) return l.holdemYouWaitBB;
      return l.holdemNextHand;
    }
    return noChips ? l.holdemNoChips : l.holdemNextHand;
  }

  String _presetLabel(AppLocalizations l, HoldemPreset p) => switch (p) {
        HoldemPreset.min => l.holdemPresetMin,
        HoldemPreset.halfPot => l.holdemPresetHalfPot,
        HoldemPreset.pot => l.holdemPresetPot,
        HoldemPreset.allIn => l.holdemPresetAllIn,
      };

  String _raiseLabel(BuildContext context, AppLocalizations l, HoldemRaiseModel m, int to) {
    final amount = context.money(m.clamp(to), compact: true);
    if (m.isAllIn(to)) return l.holdemAllInTo(amount);
    return m.isBet ? l.holdemBetTo(amount) : l.holdemRaiseTo(amount);
  }

  Future<void> _rebuy(BuildContext context, int room) async {
    final cents = await showHoldemRebuyDialog(context, room: room, bigBlind: v.table.limits.extra['bigBlindCents'] ?? 200);
    if (cents != null && cents > 0) await v.actions.act({'type': 'rebuy', 'cents': cents});
  }
}

/// Picks a rebuy amount (whole dollars, 1 $..[room]); null = cancelled.
Future<int?> showHoldemRebuyDialog(BuildContext context, {required int room, required int bigBlind}) {
  final step = room % bigBlind == 0 && room >= bigBlind ? bigBlind : 100;
  final min = step;
  var value = room;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final l = ctx.l10n;
        final divisions = (room - min) ~/ step;
        return AlertDialog(
          title: Text(l.holdemRebuyTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.holdemRebuyBody(ctx.money(room, compact: true))),
              const SizedBox(height: 12),
              Text(ctx.money(value, compact: true), key: const Key('holdem-rebuy-amount'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              if (divisions > 0)
                Slider(
                  key: const Key('holdem-rebuy-slider'),
                  value: value.toDouble(),
                  min: min.toDouble(),
                  max: room.toDouble(),
                  divisions: divisions,
                  onChanged: (x) => setState(() => value = ((x / step).round() * step).clamp(min, room)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.back)),
            FilledButton(
              key: const Key('holdem-rebuy-confirm'),
              onPressed: () => Navigator.pop(ctx, value),
              child: Text(l.holdemRebuyConfirm(ctx.money(value, compact: true))),
            ),
          ],
        );
      },
    ),
  );
}
