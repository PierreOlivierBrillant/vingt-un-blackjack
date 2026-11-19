import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/sfx.dart';
import '../../core/audio/sound_providers.dart';
import '../../core/ids.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../domain/backend_constants.dart';
import '../../domain/card_style.dart';
import '../../domain/cards.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ads/ad_widgets.dart';
import '../cards/chips.dart';
import '../dealer/dealer_controller.dart';
import '../dealer/dealer_stage.dart';
import '../markets/markets_screen.dart';
import '../shop/shop_screen.dart';
import '../dealer/table_geometry.dart';
import 'casino_backdrop.dart';
import 'celebration_overlay.dart';
import 'fairness_sheet.dart';
import 'table_director.dart';
import 'table_rules.dart';
import 'table_sounds.dart';

String actionLabel(AppLocalizations l, PlayerAction a) => switch (a) {
      PlayerAction.hit => l.actionHit,
      PlayerAction.stand => l.actionStand,
      PlayerAction.double => l.actionDouble,
      PlayerAction.split => l.actionSplit,
      PlayerAction.surrender => l.actionSurrender,
      PlayerAction.insurance => l.actionInsurance,
      PlayerAction.peek => l.actionPeek,
    };

/// Live table, driven by the `tables/{id}` snapshots: every snapshot goes
/// through a [TableDirector] that animates the new events on the
/// [DealerController]. The bottom panel depends on the viewer's role
/// (seated player: bet / insurance / actions; queued; spectator).
class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key, required this.tableId, this.privateCode, this.interstitialEvery = 4});
  final String tableId;

  /// Code of a private table (shown so it can be shared), from matchmaking.
  final String? privateCode;

  /// Show a parody interstitial after every N hands played here (0 = never).
  final int interstitialEvery;

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  late final DealerController _dealer;
  late final TableDirector _director;
  late final TableSoundscape _sounds;
  int? _mySeat;
  int _minBet = 0;
  int _maxBet = 0;
  Timer? _tick;
  DateTime? _pokedFor;
  DateTime? _lastPokeAt;
  int _pendingBet = 0;
  int? _lastBet;
  PowerType? _armed;
  bool _busy = false;
  int _handsPlayed = 0;
  bool _adShowing = false;

  /// Same key while the user retries the same decision (server de-dup).
  final _keys = <String, String>{};

  DateTime _now() => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    _sounds = TableSoundscape(
      sound: ref.read(soundProvider),
      haptics: ref.read(hapticsProvider),
      random: ref.read(sfxRandomProvider),
      mySeat: () => _mySeat,
      minBetCents: () => _minBet,
      maxBetCents: () => _maxBet,
    );
    _dealer = DealerController(feedback: _sounds);
    _director = TableDirector(_dealer, now: _now);
    ref.listenManual<AsyncValue<TableState>>(tableViewProvider(widget.tableId), (_, next) {
      final t = next.value;
      if (t != null) _onSnapshot(t);
    }, fireImmediately: true);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _dealer.dispose();
    _sounds.dispose();
    super.dispose();
  }

  void _onSnapshot(TableState t) {
    final me = ref.read(tableRepositoryProvider).myUid;
    final mine = me == null ? null : t.seatOf(me);
    final wasSeated = _mySeat != null;
    _mySeat = mine?.seatIndex;
    // Sat down (after matchmaking or from the queue): chip + chime.
    if (!wasSeated && _mySeat != null) ref.sfx(Sfx.seatJoin);
    _minBet = t.minBetCents;
    _maxBet = t.maxBetCents;
    final notices = _director.apply(t);
    if (mine != null && mine.betCents > 0) _lastBet = mine.betCents;
    if (t.phase != ServerTablePhase.betting) _pendingBet = 0;
    for (final n in notices) {
      _notice(n, t, mine);
    }
    if (mounted) setState(() {});
  }

  void _notice(TableNotice n, TableState t, SeatState? mine) {
    if (!mounted) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    switch (n) {
      case SecondChanceNotice(:final seatIndex, :final discarded) when seatIndex == mine?.seatIndex:
        messenger.showSnackBar(SnackBar(content: Text(l.tableSecondChance(discarded.toString()))));
      case PowerUsedNotice(:final seatIndex, :final power) when seatIndex == mine?.seatIndex:
        if (_armed == power) _armed = null;
      case HandSettledNotice():
        if (mine != null && mine.roundNetCents != null) {
          _handsPlayed++;
          if (widget.interstitialEvery > 0 && _handsPlayed % widget.interstitialEvery == 0) {
            unawaited(_showInterstitial());
          }
        }
      default:
        break;
    }
  }

  Future<void> _showInterstitial() async {
    if (_adShowing) return;
    _adShowing = true;
    // Let the payouts play first, then a short forced ad between two hands.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) await showInterstitialAd(context, lock: const Duration(seconds: 3));
    _adShowing = false;
  }

  /// No server scheduler: when the deadline passed and nothing changed, ask
  /// the server to apply it (it re-checks its own clock).
  void _onTick() {
    if (!mounted) return;
    final t = ref.read(tableViewProvider(widget.tableId)).value;
    setState(() {}); // countdown text
    if (t == null || t.closed) return;
    final deadline = t.deadline;
    if (deadline == null) return;
    final now = _now();
    if (!now.isAfter(deadline.add(const Duration(milliseconds: Backend.pokeGraceMs)))) return;
    // At most one poke per overdue deadline every 1.5 s (rate limit 30/10 s).
    if (_pokedFor == deadline && _lastPokeAt != null && now.difference(_lastPokeAt!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _pokedFor = deadline;
    _lastPokeAt = now;
    unawaited(ref.read(tableRepositoryProvider).poke(widget.tableId).then<void>((_) {}, onError: (Object e) {
      debugPrint('[table] poke failed: $e');
    }));
  }

  String _key(String op) => _keys[op] ??= newIdempotencyKey();

  Future<void> _run(String op, Future<void> Function(String key) call) async {
    if (_busy) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await call(_key(op));
      _keys.remove(op);
    } on Object catch (e) {
      // A definitive server answer: next attempt is a new operation.
      if (e is! RepositoryException || e.failure != RepositoryFailure.unavailable) _keys.remove(op);
      messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _placeBet(TableState t) => _run('bet-${t.handNumber}-$_pendingBet', (key) async {
        await ref.read(tableRepositoryProvider).placeBet(widget.tableId, t.handNumber, _pendingBet, idempotencyKey: key);
        _lastBet = _pendingBet;
      });

  Future<void> _act(TableState t, PlayerAction a, {int? amountCents}) {
    final turn = t.turn;
    final power = _armed != null && powerAppliesTo(_armed!, a, amountCents: amountCents) ? _armed : null;
    final handIndex = a == PlayerAction.insurance ? null : turn?.handIndex;
    return _run('act-${t.handNumber}-${a.name}-$handIndex-${t.eventSeq}', (key) async {
      await ref.read(tableRepositoryProvider).act(
            widget.tableId,
            t.handNumber,
            a,
            handIndex: handIndex,
            amountCents: amountCents,
            power: power,
            idempotencyKey: key,
          );
      if (power != null && mounted) setState(() => _armed = null);
    });
  }

  Future<void> _openPowers(TableState t0, SeatState mine0) async {
    final me = mine0.uid;
    // Usability follows the live table while the sheet is open (the turn may
    // arrive after it was opened).
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Consumer(builder: (context, ref, _) {
        final t = ref.watch(tableViewProvider(widget.tableId)).value ?? t0;
        final mine = t.seatOf(me) ?? mine0;
        return PowersSheet(
          armed: _armed,
          usedThisHand: mine.powerUsed,
          usable: (p) => powerUsableNow(p, t, mine, currentHandOf(t, mine)),
        );
      }),
    );
    if (!mounted || picked == null) return;
    final t = ref.read(tableViewProvider(widget.tableId)).value ?? t0;
    if (picked == kDisarmPower) {
      setState(() => _armed = null);
    } else if (picked == PowerType.peek) {
      // Peek is its own action: it reveals the hole card to me only.
      setState(() => _armed = PowerType.peek);
      await _act(t, PlayerAction.peek);
    } else if (picked is PowerType) {
      setState(() => _armed = picked);
    }
  }

  Future<void> _leave(TableState? t, bool involved) async {
    final l = context.l10n;
    if (!involved) {
      if (context.mounted) context.pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.leaveTable),
        content: Text(l.tableLeaveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.back)),
          FilledButton(key: const Key('leave-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(l.leaveTable)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tableRepositoryProvider).leave(widget.tableId);
      if (mounted) context.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
    }
  }

  void _showMarkets() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TableMarketsSheet(tableId: widget.tableId),
    );
  }

  int _secondsLeft(TableState t) {
    final d = t.deadline;
    if (d == null) return 0;
    final ms = d.difference(_now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final table = ref.watch(tableViewProvider(widget.tableId));
    final style = ref.watch(equippedStyleProvider).value ?? const CardStyle();
    final me = ref.watch(tableRepositoryProvider).myUid;
    final t = table.value;
    final mine = t == null || me == null ? null : t.seatOf(me);
    final queued = t != null && me != null && t.isQueued(me);
    final involved = mine != null || queued;
    return Scaffold(
      backgroundColor: const Color(0xFF0A1620),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1620),
        foregroundColor: Colors.white,
        // The casino room is always dark, whatever the app theme.
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
        title: t == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name, overflow: TextOverflow.ellipsis),
                  Text(
                    '${l.handNumber(t.handNumber)} · ${context.money(t.minBetCents, compact: true)}–${context.money(t.maxBetCents, compact: true)}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
        actions: [
          if (t != null && !t.isPrivate)
            IconButton(
              key: const Key('table-markets'),
              tooltip: l.tableBetsHere,
              icon: const Icon(Icons.show_chart),
              onPressed: _showMarkets,
            ),
          if (t != null)
            IconButton(
              key: const Key('table-fairness'),
              tooltip: l.fairTitle,
              icon: const Icon(Icons.verified_user_outlined),
              onPressed: () => showFairnessSheet(context, t),
            ),
          IconButton(
            key: const Key('table-leave'),
            tooltip: l.leaveTable,
            icon: Icon(involved ? Icons.logout : Icons.close),
            onPressed: () => _leave(t, involved),
          ),
        ],
      ),
      body: AmbienceScope(
        zone: AmbienceZone.table,
        child: AsyncBody(
        value: table,
        builder: (t) {
          final seats = [
            for (final s in t.seats)
              s == null
                  ? null
                  : DealerSeat(
                      name: s.username,
                      stackCents: s.hands.isEmpty ? s.betCents : s.hands.fold<int>(0, (a, h) => a + h.betCents),
                      isMe: s.uid == me,
                      isBot: s.isBot,
                    ),
          ];
          return Column(
            children: [
              if (t.fromCache) _Banner(text: l.tableOffline, color: context.palette.warning),
              _StatusStrip(
                text: _statusText(l, t, mine),
                code: widget.privateCode,
                shoe: l.tableShoeInfo(t.shoe.shoeNumber, t.shoe.cardsRemaining),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Table sits on the controls; on tall screens the (seamless)
                    // room extends above instead of leaving a gap in the middle.
                    Positioned.fill(
                      child: LayoutBuilder(builder: (context, box) {
                        final stageH = box.maxWidth * TableGeometry.size.height / TableGeometry.size.width;
                        final free = box.maxHeight - stageH;
                        return Column(
                          children: [
                            if (free > 0) SizedBox(height: free, width: double.infinity, child: const CasinoBackdrop()),
                            Expanded(child: DealerStage(controller: _dealer, style: style, seats: seats)),
                          ],
                        );
                      }),
                    ),
                    Positioned.fill(child: CelebrationOverlay(celebrations: _sounds.celebrations)),
                  ],
                ),
              ),
              _PeekBanner(tableId: widget.tableId, handNumber: t.handNumber, mySeated: mine != null),
              // Never let the controls push the table off screen (small
              // phones, large system font): they scroll instead.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
                child: SingleChildScrollView(child: _bottomPanel(context, t, mine, queued)),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  String _statusText(AppLocalizations l, TableState t, SeatState? mine) {
    final secs = _secondsLeft(t);
    if (t.closed) return l.tableClosedNotice;
    switch (t.phase) {
      case ServerTablePhase.idle || ServerTablePhase.closed:
        return t.closed ? l.tableClosedNotice : l.tableIdle;
      case ServerTablePhase.betting:
        return l.tableBetting(secs);
      case ServerTablePhase.insurance:
        return l.tableInsuranceWait(secs);
      case ServerTablePhase.playerTurns:
        final turn = t.turn;
        final s = turn == null ? null : t.seats[turn.seatIndex];
        if (s == null) return l.tableDealerPlays;
        return s.uid == mine?.uid ? l.tableYourTurn(secs) : l.tableTurnOf(s.username, secs);
      case ServerTablePhase.settled:
        final net = mine?.roundNetCents;
        return net == null ? l.tableSettled : l.tableResult(context.money(net, signed: true));
    }
  }

  Widget _bottomPanel(BuildContext context, TableState t, SeatState? mine, bool queued) {
    final l = context.l10n;
    if (mine == null) {
      return _InfoPanel(
        icon: queued ? Icons.hourglass_top : Icons.visibility_outlined,
        title: queued ? l.tableQueued : l.tableSpectating,
        subtitle: queued ? null : l.tableSpectatorHint,
        action: t.isPrivate
            ? null
            : FilledButton.icon(
                key: const Key('spectator-markets'),
                onPressed: _showMarkets,
                icon: const Icon(Icons.show_chart),
                label: Text(l.tableBetsHere, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
      );
    }
    final inHand = mine.hands.isNotEmpty;
    switch (t.phase) {
      case ServerTablePhase.betting when mine.betCents == 0:
        return _BetPanel(
          minBet: t.minBetCents,
          maxBet: t.maxBetCents,
          pending: _pendingBet,
          suggested: _lastBet ?? t.minBetCents,
          busy: _busy,
          onChange: (v) => setState(() => _pendingBet = v),
          onBet: () => _placeBet(t),
        );
      case ServerTablePhase.betting:
        return _InfoPanel(icon: Icons.check_circle_outline, title: l.tableBetPlaced(context.money(mine.betCents)));
      case ServerTablePhase.insurance when mine.insurance != null && !mine.insurance!.decided && inHand:
        final max = maxInsuranceCents(mine);
        return _InsurancePanel(
          maxCents: max,
          busy: _busy,
          freeArmed: _armed == PowerType.freeInsurance,
          onTake: () => _act(t, PlayerAction.insurance, amountCents: max),
          onDecline: () => _act(t, PlayerAction.insurance, amountCents: 0),
          onPowers: () => _openPowers(t, mine),
        );
      case ServerTablePhase.playerTurns || ServerTablePhase.insurance || ServerTablePhase.settled:
        if (!inHand) return _InfoPanel(icon: Icons.hourglass_top, title: l.tableWaitingNextHand);
        final hand = currentHandOf(t, mine);
        final legal = legalActions(t, mine);
        return _ActionBar(
          legal: _busy ? const {} : legal,
          onAction: (a) => _act(t, a),
          onPowers: () => _openPowers(t, mine),
          armed: _armed,
          powerUsed: mine.powerUsed,
          hand: hand,
        );
      case ServerTablePhase.idle || ServerTablePhase.closed:
        return _InfoPanel(icon: Icons.hourglass_empty, title: t.closed ? l.tableClosedNotice : l.tableIdle);
    }
  }
}

// --------------------------------------------------------------- widgets --

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(text, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.text, required this.shoe, this.code});
  final String text;
  final String shoe;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: Colors.black.withValues(alpha: 0.35),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              key: const Key('table-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          if (code != null)
            Container(
              key: const Key('table-code'),
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: BrandColors.blue, borderRadius: BorderRadius.circular(6)),
              child: SelectableText(
                l.tablePrivateCode(code!),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            )
          else
            Text(shoe, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Peek power result, visible to me only, for the current hand.
class _PeekBanner extends ConsumerWidget {
  const _PeekBanner({required this.tableId, required this.handNumber, required this.mySeated});
  final String tableId;
  final int handNumber;
  final bool mySeated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!mySeated) return const SizedBox.shrink();
    final peek = ref.watch(peekProvider(tableId)).value;
    if (peek == null || peek.handNumber != handNumber) return const SizedBox.shrink();
    return Container(
      key: const Key('peek-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: powerColor(PowerType.peek),
      child: Row(
        children: [
          const Icon(Icons.visibility, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            context.l10n.tablePeekCard('${peek.holeCard.rank.label}${peek.holeCard.suit.symbol}'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      color: p.surface,
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(icon, color: p.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, key: const Key('table-info'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(color: p.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), Flexible(child: action!)],
          ],
        ),
      ),
    );
  }
}

class _BetPanel extends StatelessWidget {
  const _BetPanel({
    required this.minBet,
    required this.maxBet,
    required this.pending,
    required this.suggested,
    required this.busy,
    required this.onChange,
    required this.onBet,
  });
  final int minBet;
  final int maxBet;
  final int pending;
  final int suggested;
  final bool busy;
  final ValueChanged<int> onChange;
  final VoidCallback onBet;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final chips = [for (final d in kChipDenominations.reversed) if (d.cents <= maxBet) d].take(5).toList();
    final amount = pending == 0 ? suggested.clamp(minBet, maxBet) : pending;
    final valid = isValidBet(amount, minBet, maxBet);
    return Container(
      color: p.surface,
      padding: const EdgeInsets.all(8),
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
                        for (final d in chips)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChipButton(
                              key: Key('chip-${d.cents}'),
                              denomination: d,
                              size: 40,
                              selected: false,
                              onTap: () {
                                context.sfx(SfxVariants.chipClink[d.cents % SfxVariants.chipClink.length]);
                                onChange((pending + d.cents).clamp(0, maxBet));
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('bet-clear'),
                  onPressed: pending == 0
                      ? null
                      : () {
                          context.sfx(Sfx.chipStack, volume: 0.6);
                          onChange(0);
                        },
                  child: Text(l.tableClearBet),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('bet-place'),
                onPressed: valid && !busy
                    ? () {
                        if (pending == 0) onChange(amount);
                        onBet();
                      }
                    : null,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                icon: const Icon(Icons.casino_outlined),
                label: Text(l.tablePlaceBet(context.money(amount))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsurancePanel extends StatelessWidget {
  const _InsurancePanel({
    required this.maxCents,
    required this.busy,
    required this.freeArmed,
    required this.onTake,
    required this.onDecline,
    required this.onPowers,
  });
  final int maxCents;
  final bool busy;
  final bool freeArmed;
  final VoidCallback onTake;
  final VoidCallback onDecline;
  final VoidCallback onPowers;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return Container(
      color: p.surface,
      padding: const EdgeInsets.all(10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.tableInsuranceTitle, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(l.tableInsuranceBody(context.money(maxCents)), style: TextStyle(color: p.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('insurance-decline'),
                    onPressed: busy ? null : onDecline,
                    child: Text(l.tableInsuranceDecline),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('insurance-take'),
                    onPressed: busy || maxCents <= 0 ? null : onTake,
                    child: Text(freeArmed ? l.powerFreeInsurance : l.tableInsuranceTake(context.money(maxCents))),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(onPressed: onPowers, icon: Icon(Icons.bolt, color: p.gold), tooltip: l.powers),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.legal,
    required this.onAction,
    required this.onPowers,
    required this.armed,
    required this.powerUsed,
    required this.hand,
  });
  final Set<PlayerAction> legal;
  final ValueChanged<PlayerAction> onAction;
  final VoidCallback onPowers;
  final PowerType? armed;
  final PowerType? powerUsed;
  final SeatHand? hand;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    Widget btn(PlayerAction a, IconData icon, {Color? color}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FilledButton(
              key: Key('action-${a.name}'),
              onPressed: legal.contains(a)
                  ? () {
                      context.sfx(Sfx.uiTap);
                      onAction(a);
                    }
                  : null,
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
    final h = hand;
    final total = h == null || h.cards.isEmpty ? null : handTotal(h.cards);
    final powerLabel = powerUsed != null
        ? l.tablePowerUsed(powerCopy(l, powerUsed!).$1)
        : armed != null
            ? l.tablePowerArmed(powerCopy(l, armed!).$1)
            : null;
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
                if (total != null)
                  Container(
                    key: const Key('my-total'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      handTotalLabel(total, cardCount: h!.cards.length),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    powerLabel ?? '',
                    key: const Key('power-status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.gold, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('table-powers'),
                  onPressed: () {
                    context.sfx(Sfx.uiTap);
                    onPowers();
                  },
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

/// Spectator markets of one table (open first), tap → market detail.
class _TableMarketsSheet extends ConsumerWidget {
  const _TableMarketsSheet({required this.tableId});
  final String tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final markets = ref.watch(tableMarketsProvider(tableId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => AsyncBody(
        value: markets,
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
