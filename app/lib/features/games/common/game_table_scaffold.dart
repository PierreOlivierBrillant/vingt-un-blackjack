/// The frame of every Sprint 2 game table (roulette, baccarat, hold'em,
/// craps): app bar (rules, history, fairness, markets, leave), status strip
/// with the countdown / turn, neon room behind the game's stage, seats bar,
/// celebrations, the Rendez-vous slot of the croupier ([DealerMeta]),
/// spectator / queue / seated bottom panel with ads for spectators, and the
/// background work (pokes overdue deadlines, preloads the game's sounds,
/// seat-join chime, stops the game loop on exit).
///
/// A game provides only:
///  * [stage]: its animated table (usually a `StageView` driven by its own
///    `StageController`), placed at the bottom of the room;
///  * [controls]: the bottom panel while seated (bet board, decisions…),
///    using `view.actions` (setBets / act / sitOut / leave / celebrate);
///  * optionally [onTable] to feed its animation queue with the events not
///    seen yet (`catchUp` on the first snapshot: fast-forward), [statusText],
///    [seatInfo].
/// Everything else comes from its [GameUi] (rules, sounds, fairness check…).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/audio/sound_providers.dart';
import '../../../core/audio/sound_service.dart';
import '../../../core/ids.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets.dart';
import '../../../data/error_messages.dart';
import '../../../data/providers.dart';
import '../../../data/repositories.dart';
import '../../../domain/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../ads/ad_widgets.dart';
import '../../romance/dealer_meta.dart';
import '../../table/casino_backdrop.dart';
import '../../table/celebration_overlay.dart';
import '../../table/table_sounds.dart' show Celebration, CelebrationKind;
import '../game_join.dart';
import '../game_ui.dart';
import 'game_sheets.dart';
import 'game_table_view.dart';

/// Background of the casino room (always dark, whatever the app theme).
const kRoomColor = Color(0xFF0A1620);

typedef GameViewBuilder = Widget Function(BuildContext context, GameTableView view);

class GameTableScaffold extends ConsumerStatefulWidget {
  const GameTableScaffold({
    super.key,
    required this.ui,
    required this.tableId,
    this.privateCode,
    required this.stage,
    this.controls,
    this.onTable,
    this.statusText,
    this.seatInfo,
    this.showSeatsBar = true,
    this.autoCelebrate = true,
  });

  final GameUi ui;
  final String tableId;

  /// `?code=` of a private table (shown so it can be shared).
  final String? privateCode;

  /// The game's animated table.
  final GameViewBuilder stage;

  /// Bottom panel while seated; null = a generic "you are in seat n" panel.
  final GameViewBuilder? controls;

  /// Every snapshot, with the events not seen yet (sorted by seq). [catchUp]
  /// is true for the first snapshot (rebuild the scene, fast-forward).
  final void Function(GameTableView view, List<GameEvent> fresh, bool catchUp)? onTable;

  /// Status strip text (default: phase, countdown, whose turn).
  final String Function(BuildContext context, GameTableView view)? statusText;

  /// Second line of a seat in the seats bar (default: stack, else stake).
  final String? Function(BuildContext context, GameSeat seat, GameTableView view)? seatInfo;

  /// Hide the generic seats bar when the stage draws its own seat plates.
  final bool showSeatsBar;

  /// Confetti when my round net is positive at settlement (big ≥ 5× stake).
  final bool autoCelebrate;

  @override
  ConsumerState<GameTableScaffold> createState() => _GameTableScaffoldState();
}

class _GameTableScaffoldState extends ConsumerState<GameTableScaffold> implements GameTableActions {
  final _celebrations = ValueNotifier<Celebration?>(null);
  final _busy = ValueNotifier<bool>(false);
  var _serial = 0;
  Timer? _tick;
  int _lastSeq = 0;
  int? _lastRound;
  bool _first = true;
  bool _wasSeated = false;
  int? _celebratedRound;
  DateTime? _pokedFor;
  DateTime? _lastPokeAt;
  late final SoundService _sound = ref.read(soundProvider);

  DateTime _now() => ref.read(clockProvider)();
  GameTableRepository get _repo => ref.read(gameTableRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_sound.preload([for (final s in widget.ui.sounds) if (!s.loop) s]));
    ref.listenManual<AsyncValue<GameTableState>>(gameTableProvider(widget.tableId), (_, next) {
      final t = next.value;
      if (t != null) _onSnapshot(t);
    }, fireImmediately: true);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sound.stopLoop(SoundChannel.game);
    _celebrations.dispose();
    _busy.dispose();
    super.dispose();
  }

  GameTableView _view(GameTableState t) {
    final bets = ref.read(gameBetsProvider(widget.tableId)).value ?? const <GameBet>[];
    return GameTableView(
      ui: widget.ui,
      table: t,
      myUid: _repo.myUid,
      bets: [for (final b in bets) if (b.isFor(t.round)) b],
      now: _now(),
      actions: this,
    );
  }

  void _onSnapshot(GameTableState t) {
    final view = _view(t);
    final mine = view.mine;
    if (!_wasSeated && mine != null && !_first) ref.sfx(Sfx.seatJoin);
    _wasSeated = mine != null;
    final fresh = t.round != _lastRound ? t.events : t.events.where((e) => e.seq > _lastSeq).toList();
    _lastRound = t.round;
    if (t.events.isNotEmpty) _lastSeq = t.events.last.seq;
    widget.onTable?.call(view, fresh, _first);
    _first = false;
    final net = mine?.roundNetCents;
    if (widget.autoCelebrate && t.phase == GamePhase.settled && net != null && net > 0 && _celebratedRound != t.round) {
      _celebratedRound = t.round;
      final big = mine!.stakeCents > 0 && net >= mine.stakeCents * 5;
      celebrate(big ? CelebrationKind.bigWin : CelebrationKind.win, cents: net);
    }
    if (mounted) setState(() {});
  }

  /// No server scheduler: past the deadline (+ grace), ask the server to
  /// apply it (at most once per deadline every 1.5 s).
  void _onTick() {
    if (!mounted) return;
    setState(() {}); // countdowns
    final t = ref.read(gameTableProvider(widget.tableId)).value;
    if (t == null) return;
    final now = _now();
    if (!t.shouldPokeAt(now)) return;
    if (_pokedFor == t.deadline && _lastPokeAt != null && now.difference(_lastPokeAt!) < const Duration(milliseconds: 1500)) return;
    _pokedFor = t.deadline;
    _lastPokeAt = now;
    unawaited(_repo.poke(widget.tableId).then<void>((_) {}, onError: (Object e) => debugPrint('[game] poke failed: $e')));
  }

  // ------------------------------------------------------------ actions --

  @override
  ValueListenable<bool> get busy => _busy;

  Future<bool> _run(Future<void> Function(String key) call) async {
    if (_busy.value) return false;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    _busy.value = true;
    try {
      await call(newIdempotencyKey());
      return true;
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
      return false;
    } finally {
      if (mounted) _busy.value = false;
    }
  }

  int get _round => ref.read(gameTableProvider(widget.tableId)).value?.round ?? 0;

  @override
  Future<bool> setBets(Map<String, int> bets, {PowerType? power}) =>
      _run((key) => _repo.setBets(widget.tableId, _round, bets, power: power, idempotencyKey: key));

  @override
  Future<bool> act(Map<String, Object?> action) => _run((key) => _repo.act(widget.tableId, _round, action, idempotencyKey: key));

  @override
  Future<bool> sitOut() => act(const {'type': 'sitOut'});

  @override
  Future<bool> sitIn() => act(const {'type': 'sitIn'});

  @override
  void celebrate(CelebrationKind kind, {int? cents, String? label}) =>
      _celebrations.value = Celebration(kind, ++_serial, cents: cents, label: label);

  @override
  Future<void> leave() async {
    final l = context.l10n;
    final t = ref.read(gameTableProvider(widget.tableId)).value;
    final me = _repo.myUid;
    final involved = t != null && (t.seatOf(me) != null || t.isQueued(me));
    if (!involved) {
      if (mounted) _close();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.leaveTable),
        content: Text(l.gameLeaveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.back)),
          FilledButton(key: const Key('game-leave-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(l.leaveTable)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await _run((_) => _repo.leave(widget.tableId)) && mounted) _close();
  }

  /// Back to where the table was opened from (the lobby when it is the root).
  void _close() => context.canPop() ? context.pop() : context.go('/lobby');

  Future<void> _playHere(GameTableState t) async {
    final r = await joinGameTable(context, ref, widget.ui, mode: GameJoinMode.quick, stakeTier: t.stakeTier);
    if (r != null && r.tableId != widget.tableId && mounted) context.pushReplacement('/table/${r.tableId}');
  }

  // ---------------------------------------------------------------- build --

  String _status(AppLocalizations l, GameTableView v) {
    final t = v.table;
    if (t.closed) return l.tableClosedNotice;
    final secs = v.secondsLeft;
    final turn = t.turnSeatState;
    if (t.phase == GamePhase.live && turn != null) {
      return turn.uid == v.myUid ? l.tableYourTurn(secs) : l.tableTurnOf(turn.username, secs);
    }
    return switch (t.phase) {
      GamePhase.idle || GamePhase.closed => l.tableIdle,
      GamePhase.betting => l.gamePhaseBetting(secs),
      GamePhase.live => t.deadline == null ? l.gamePhaseLive : l.gamePhaseLiveSecs(secs),
      GamePhase.settled => v.mine?.roundNetCents != null
          ? l.gameRoundResult(context.money(v.mine!.roundNetCents!, signed: true))
          : l.gamePhaseSettled(secs),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ui = widget.ui;
    final async = ref.watch(gameTableProvider(widget.tableId));
    ref.watch(gameBetsProvider(widget.tableId));
    final t = async.value;
    final view = t == null ? null : _view(t);
    final white = Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white);
    return Scaffold(
      backgroundColor: kRoomColor,
      appBar: AppBar(
        backgroundColor: kRoomColor,
        foregroundColor: Colors.white,
        titleTextStyle: white,
        title: t == null
            ? Text(ui.name(l))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name, overflow: TextOverflow.ellipsis),
                  Text(
                    '${ui.name(l)} · ${l.gameRoundNumber(t.round)} · ${context.money(t.limits.minBetCents, compact: true)}–${context.money(t.limits.maxBetCents, compact: true)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
        actions: [
          IconButton(key: const Key('game-rules'), tooltip: l.gameRules, icon: const Icon(Icons.menu_book_outlined), onPressed: () => showGameRulesSheet(context, ui)),
          if (t != null) ...[
            IconButton(
              key: const Key('game-history'),
              tooltip: l.gameHistory,
              icon: const Icon(Icons.history),
              onPressed: () => showGameHistorySheet(context, ui, t.id),
            ),
            IconButton(
              key: const Key('game-fairness'),
              tooltip: l.fairTitle,
              icon: const Icon(Icons.verified_user_outlined),
              onPressed: () => showGameFairnessSheet(context, ui, t),
            ),
            if (!t.isPrivate)
              IconButton(
                key: const Key('game-markets'),
                tooltip: l.tableBetsHere,
                icon: const Icon(Icons.show_chart),
                onPressed: () => showGameMarketsSheet(context, t.id),
              ),
          ],
          IconButton(
            key: const Key('game-leave'),
            tooltip: l.leaveTable,
            icon: Icon(view != null && !view.spectator ? Icons.logout : Icons.close),
            onPressed: leave,
          ),
        ],
      ),
      body: AmbienceScope(
        zone: AmbienceZone.table,
        child: async.hasError && t == null
            ? _NotFound(error: async.error!)
            : t == null || view == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (t.fromCache) _Strip(text: l.tableOffline, color: context.palette.warning, dark: true),
                      _StatusStrip(text: widget.statusText?.call(context, view) ?? _status(l, view), code: widget.privateCode, ui: ui),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(child: CasinoBackdrop(sign: ui.signText(l), neon: ui.accent)),
                            Positioned.fill(child: Align(alignment: Alignment.bottomCenter, child: widget.stage(context, view))),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: DealerMeta(characterId: t.dealerCharacterId, game: t.game, seated: view.seated),
                            ),
                            Positioned.fill(child: CelebrationOverlay(celebrations: _celebrations)),
                          ],
                        ),
                      ),
                      if (widget.showSeatsBar) _SeatsBar(view: view, info: widget.seatInfo),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
                        child: SingleChildScrollView(child: _bottom(context, view)),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _bottom(BuildContext context, GameTableView v) {
    final l = context.l10n;
    final t = v.table;
    if (t.closed) return _InfoPanel(icon: Icons.block, title: l.tableClosedNotice);
    if (v.queued) return _InfoPanel(icon: Icons.hourglass_top, title: l.gameQueuedAt(v.queuePosition + 1));
    if (v.spectator) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoPanel(
            icon: Icons.visibility_outlined,
            title: l.tableSpectating,
            subtitle: widget.ui.playable ? l.tableSpectatorHint : l.gameComingSoonBody,
            action: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (widget.ui.playable && !t.isPrivate)
                  FilledButton(key: const Key('game-play-here'), onPressed: () => _playHere(t), child: Text(l.gamePlayThis)),
                if (!t.isPrivate)
                  OutlinedButton.icon(
                    key: const Key('game-spectator-markets'),
                    onPressed: () => showGameMarketsSheet(context, t.id),
                    icon: const Icon(Icons.show_chart, size: 18),
                    label: Text(l.tableMarkets),
                  ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 8), child: AdBanner()),
        ],
      );
    }
    final controls = widget.controls;
    if (controls != null) return controls(context, v);
    return _InfoPanel(
      icon: Icons.event_seat_outlined,
      title: l.gameSeatedAt(v.mine!.seatIndex + 1),
      subtitle: widget.ui.playable ? null : l.gamePlaceholderBody,
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final notFound = error is RepositoryException && (error as RepositoryException).reason == ServerReason.TABLE_NOT_FOUND;
    return Theme(
      data: AppTheme.dark(),
      child: EmptyState(
        icon: notFound ? Icons.search_off : Icons.cloud_off,
        text: notFound ? l.gameNotFound : localizeError(l, error),
        action: FilledButton(onPressed: () => context.canPop() ? context.pop() : context.go('/lobby'), child: Text(l.gameBackToLobby)),
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.text, required this.color, this.dark = false});
  final String text;
  final Color color;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(text, style: TextStyle(color: dark ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.text, required this.ui, this.code});
  final String text;
  final GameUi ui;
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
          Icon(ui.icon, size: 16, color: ui.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: const Key('game-status'),
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
            ),
        ],
      ),
    );
  }
}

/// Every seat of the table: avatar, name, bot badge, stack / stake, the turn
/// and "you" highlighted. Scrolls horizontally (up to 8 seats).
class _SeatsBar extends StatelessWidget {
  const _SeatsBar({required this.view, this.info});
  final GameTableView view;
  final String? Function(BuildContext context, GameSeat seat, GameTableView view)? info;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = view.table;
    String? defaultInfo(GameSeat s) => s.stackCents != null
        ? l.gameStack(context.money(s.stackCents!, compact: true))
        : s.stakeCents > 0
            ? l.gameStake(context.money(s.stakeCents, compact: true))
            : null;
    return Container(
      key: const Key('game-seats'),
      color: const Color(0xFF0F202C),
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: t.seats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = t.seats[i];
          final me = s != null && s.uid == view.myUid;
          final turn = t.turnSeat == i;
          final border = turn ? view.ui.accent : me ? BrandColors.green : Colors.white24;
          return Container(
            key: Key('seat-$i'),
            width: 112,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: s == null ? 0.03 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: turn || me ? 2 : 1),
            ),
            child: s == null
                ? Center(child: Text(l.gameSeatFree, style: const TextStyle(color: Colors.white38, fontSize: 12)))
                : Row(
                    children: [
                      AppAvatar(name: s.username, hue: avatarHueOf(s.avatar), size: 28, avatarId: s.avatar),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(
                                  me ? l.gameYou : s.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                              ),
                              if (s.isBot) ...[
                                const SizedBox(width: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
                                  child: Text(l.gameBot, style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ]),
                            if ((info?.call(context, s, view) ?? defaultInfo(s)) case final text?)
                              Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
          );
        },
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
                  Text(title, key: const Key('game-info'), style: const TextStyle(fontWeight: FontWeight.w800)),
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
