/// The animated hold'em table: Alex the croupier (CharacterPainter bust, IK
/// arms), the deck, cards pitched to each seat (two passes from the small
/// blind), burn cards, flop / turn / river flipped on the board, bets pushed
/// in front of the seats then swept into the pot, side pots, the showdown and
/// the pot pushed to the winners.
///
/// [HoldemScene] turns the table's events into [StageController] commands.
/// After every batch it RECONCILES the scene with the snapshot (cards in play,
/// board, bets, pot), so the picture is always what the server says even if
/// an event was missed; on the first snapshot (`catchUp`) the scene is built
/// directly from the state. [HoldemStageView] paints it and adds the pixel
/// overlays (seat plates, badges, bet and pot amounts, dealer button, blind
/// markers, hand names at the showdown, turn ring, "last hand" button).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx.dart';
import '../../../core/characters/cast.dart';
import '../../../core/characters/character_spec.dart';
import '../../../core/widgets.dart';
import '../../../data/providers.dart';
import '../../../domain/card_style.dart';
import '../../../domain/game_table.dart';
import '../../../domain/wire.dart';
import '../../cards/card_painters.dart';
import '../../cards/chips.dart';
import '../../stage/stage_controller.dart';
import '../../stage/stage_view.dart';
import '../common/game_table_view.dart';
import '../common/placeholder_stage.dart' show GameFeltPainter;
import 'holdem_evaluator.dart';
import 'holdem_geometry.dart';
import 'holdem_labels.dart';
import 'holdem_sounds.dart';
import 'holdem_state.dart';

const kHoldemGeometry = HoldemGeometry();

/// Mutable data of a card prop.
class HoldemCard {
  HoldemCard({this.code, this.seat, this.index = 0, this.mine = false, this.flip = 0});

  /// Face (board, shown hands); null = unknown to everyone (or mine: from `holes/{me}`).
  String? code;
  final int? seat;
  final int index;

  /// My own hole card (its face comes from `holes/{me}`).
  final bool mine;

  /// 0 = back up, 1 = face up (scale-x flip in between).
  double flip;
  bool highlight = false;
  bool dim = false;
}

/// Mutable data of a chip prop.
class HoldemChips {
  HoldemChips(this.cents, {this.big = false});
  int cents;
  final bool big;
}

/// Events → commands, and snapshot → scene.
class HoldemScene {
  HoldemScene(this.stage, {this.geometry = kHoldemGeometry});
  final StageController stage;
  final HoldemGeometry geometry;
  int _fly = 0;

  /// The table of the last reconciliation (overlays read it).
  GameTableView? view;

  // ------------------------------------------------------------- entry --

  /// Fed by the scaffold's `onTable`.
  void onTable(GameTableView v, List<GameEvent> fresh, bool catchUp) {
    if (catchUp) {
      stage.reset();
      reconcile(v);
      return;
    }
    // Never lag far behind the server: skip what is still queued.
    if (stage.remainingDuration > const Duration(milliseconds: 3000)) stage.fastForward();
    for (final e in fresh) {
      _event(v, e);
    }
    stage.enqueue(CallbackCommand((_) => reconcile(v), name: 'reconcile'));
  }

  String? _uidAt(GameTableView v, int? seat) => seat == null || seat >= v.table.seats.length ? null : v.table.seats[seat]?.uid;
  bool _mine(GameTableView v, int seat) => v.myUid != null && _uidAt(v, seat) == v.myUid;

  // ---------------------------------------------------------- reconcile --

  /// Makes the scene match the snapshot [v] exactly (no animation).
  void reconcile(GameTableView v) {
    view = v;
    final g = geometry;
    final t = v.table;
    final h = HoldemTable.of(t);
    final step = holdemStepOf(t);
    final live = t.phase == GamePhase.live && step != HoldemStep.waiting;
    final handOn = live || t.phase == GamePhase.settled;
    final keep = <String>{};

    // Hole cards of the players still in the hand.
    for (var i = 0; i < t.seats.length && i < g.seatCount; i++) {
      final s = t.seats[i];
      if (s == null || !handOn) continue;
      final hs = HoldemSeatState.of(s);
      if (!hs.live) continue;
      final mine = s.uid == v.myUid;
      for (var k = 0; k < 2; k++) {
        final id = 'hole-$i-$k';
        keep.add(id);
        final p = stage.prop(id) ?? stage.addProp(StageProp(id: id, kind: 'card', data: HoldemCard(seat: i, index: k, mine: mine)));
        final c = p.data! as HoldemCard;
        final shown = hs.shown != null && hs.shown!.length > k ? hs.shown![k] : null;
        c.code = shown;
        c.flip = shown != null || mine ? 1 : 0;
        p
          ..pos = g.holeCardSpot(i, k, mine: mine)
          ..rotation = g.seatRotation(i) + (k - 0.5) * 0.12
          ..opacity = 1
          ..scale = 1
          ..lift = 0
          ..z = mine ? 25 : 20;
      }
    }
    // Board and burnt cards.
    final board = handOn ? h.board : const <String>[];
    for (var i = 0; i < board.length && i < 5; i++) {
      final id = 'board-$i';
      keep.add(id);
      final p = stage.prop(id) ?? stage.addProp(StageProp(id: id, kind: 'card', data: HoldemCard()));
      (p.data! as HoldemCard)
        ..code = board[i]
        ..flip = 1;
      p
        ..pos = g.boardSlot(i)
        ..rotation = 0
        ..opacity = 1
        ..scale = 1
        ..lift = 0
        ..z = 10;
    }
    final burns = board.isEmpty ? 0 : (board.length <= 3 ? 1 : board.length == 4 ? 2 : 3);
    for (var i = 0; i < burns; i++) {
      final id = 'burn-$i';
      keep.add(id);
      final p = stage.prop(id) ?? stage.addProp(StageProp(id: id, kind: 'card', data: HoldemCard()));
      p
        ..pos = _burnPos(i)
        ..rotation = -0.18 + i * 0.12
        ..opacity = 1
        ..scale = 0.85
        ..z = 5;
    }
    // Bets in front of the seats, the pot.
    for (var i = 0; i < t.seats.length && i < g.seatCount; i++) {
      final s = t.seats[i];
      final bet = s == null || !live ? 0 : HoldemSeatState.of(s).betCents;
      if (bet <= 0) continue;
      final id = 'bet-$i';
      keep.add(id);
      final p = stage.prop(id) ?? stage.addProp(StageProp(id: id, kind: 'chips', data: HoldemChips(bet)));
      (p.data! as HoldemChips).cents = bet;
      p
        ..pos = g.betSpot(i)
        ..opacity = 1
        ..z = 30;
    }
    if (live && h.potCents > 0) {
      keep.add('pot');
      final p = stage.prop('pot') ?? stage.addProp(StageProp(id: 'pot', kind: 'chips', data: HoldemChips(h.potCents, big: true)));
      (p.data! as HoldemChips).cents = h.potCents;
      p
        ..pos = g.potCenter
        ..opacity = 1
        ..z = 30;
    }
    for (final p in [...stage.props]) {
      if (!keep.contains(p.id)) stage.removeProp(p.id);
    }
    _highlight(t, h);
  }

  /// Settled showdown: the winning five cards glow, losing hands dim.
  void _highlight(GameTableState t, HoldemTable h) {
    final r = t.phase == GamePhase.settled ? h.result : null;
    final best = <String>{};
    final winners = <int>{...?r?.winners};
    if (r != null && r.showdown) {
      for (final w in r.winners) {
        best.addAll(r.hands[w]?.best ?? const []);
      }
    }
    for (final p in stage.propsOf('card')) {
      final c = p.data! as HoldemCard;
      final code = c.code;
      c.highlight = r != null && r.showdown && code != null && best.contains(code);
      c.dim = r != null && r.showdown && c.seat != null && !winners.contains(c.seat);
    }
  }

  Offset _burnPos(int i) => geometry.burnSpot + Offset(i * 10.0, -i * 6.0);

  // ------------------------------------------------------------- events --

  void _event(GameTableView v, GameEvent e) {
    final g = geometry;
    final seat = e.seatIndex;
    final d = e.d;
    switch (e.type) {
      case 'button':
        _clearTable();
      case 'blind':
        if (seat != null) _chipsTo(seat, asInt(d['cents']), cue: HoldemSfx.chipsBet);
      case 'deal':
        final order = [for (final x in asList(d['order'])) if (x is num) x.toInt()];
        for (var pass = 0; pass < 2; pass++) {
          for (final s in order) {
            if (s < g.seatCount) _pitch(v, s, pass);
          }
        }
        final me = order.where((s) => _mine(v, s)).firstOrNull;
        if (me != null) _flip(['hole-$me-0', 'hole-$me-1'], cue: HoldemSfx.boardFlip);
      case 'fold':
        if (seat != null) _fold(seat);
      case 'check':
        stage.enqueue(CueCommand(_cue(HoldemSfx.checkKnock, seat)));
        stage.enqueue(PauseCommand(const Duration(milliseconds: 160)));
      case 'call' || 'bet' || 'raise':
        if (seat != null) _chipsTo(seat, asInt(d['toCents']), cue: asBool(d['allIn']) ? HoldemSfx.allIn : HoldemSfx.chipsBet);
      case 'uncalled':
        if (seat != null) _uncalled(seat, asInt(d['cents']));
      case 'collect':
        _collect(asInt(d['potCents']));
      case 'burn':
        _burn();
      case 'flop':
        _board(asStringList(d['cards']), 0);
      case 'turn':
        _board(asStringList(d['cards']), 3);
      case 'river':
        _board(asStringList(d['cards']), 4);
      case 'showdown':
        _showdown(asMap(d['hands']));
      case 'win':
        if (seat != null) _win(seat, asInt(d['cents']));
      default:
        break; // timeout, sitOut, sitIn, rebuy, topUp, waiting, join, leave: the overlays follow the state
    }
  }

  StageCue _cue(GameSfx s, int? seat) => StageCue(s.file, sound: s, seat: seat);

  void _clearTable() {
    final ids = [for (final p in stage.props) p.id];
    if (ids.isEmpty) return;
    stage.enqueue(TweenCommand(
      const Duration(milliseconds: 380),
      name: 'clear',
      onStep: (s, t) {
        for (final id in ids) {
          final p = s.prop(id);
          if (p == null) continue;
          if (p.kind == 'card') p.pos = Offset.lerp(p.pos, geometry.muckSpot, t * 0.35)!;
          p.opacity = (1 - t).clamp(0.0, 1.0);
        }
      },
      onFinish: (s) {
        for (final id in ids) {
          s.removeProp(id);
        }
      },
    ));
  }

  void _pitch(GameTableView v, int seat, int pass) {
    final g = geometry;
    final id = 'hole-$seat-$pass';
    final mine = _mine(v, seat);
    final to = g.holeCardSpot(seat, pass, mine: mine);
    stage.enqueue(CallbackCommand((s) {
      s.removeProp(id);
      s.addProp(StageProp(id: id, kind: 'card', pos: g.deckSpot, scale: 0.85, rotation: -0.3, z: mine ? 25 : 20, data: HoldemCard(seat: seat, index: pass, mine: mine)));
      s.emit(_cue(HoldemSfx.cardPitch, seat));
    }, name: 'spawn($id)'));
    stage.enqueue(ParallelCommand([
      ReachCommand(Offset.lerp(g.deckSpot, to, 0.22)!, duration: const Duration(milliseconds: 150), left: false, grip: 0.4),
      MovePropCommand(id, to: to, duration: const Duration(milliseconds: 170), rotation: g.seatRotation(seat) + (pass - 0.5) * 0.12, scale: 1, arc: 26),
    ]));
  }

  void _flip(List<String> ids, {required GameSfx cue}) {
    stage.enqueue(TweenCommand(
      const Duration(milliseconds: 260),
      name: 'flip',
      onBegin: (s) => s.emit(_cue(cue, null)),
      onStep: (s, t) {
        for (final id in ids) {
          final c = s.prop(id)?.data;
          if (c is HoldemCard) c.flip = t;
        }
      },
    ));
  }

  void _fold(int seat) {
    final ids = ['hole-$seat-0', 'hole-$seat-1'];
    stage.enqueue(CueCommand(_cue(HoldemSfx.fold, seat)));
    stage.enqueue(ParallelCommand([
      for (final id in ids) MovePropCommand(id, to: geometry.muckSpot, duration: const Duration(milliseconds: 320), opacity: 0, rotation: 0.9, arc: 18),
    ]));
    stage.enqueue(CallbackCommand((s) {
      for (final id in ids) {
        s.removeProp(id);
      }
    }, name: 'muck($seat)'));
  }

  /// Chips from the seat to its bet spot; the bet becomes [toCents].
  void _chipsTo(int seat, int toCents, {required GameSfx cue}) {
    final g = geometry;
    final fly = 'fly-${_fly++}';
    stage.enqueue(CallbackCommand((s) {
      final before = (s.prop('bet-$seat')?.data as HoldemChips?)?.cents ?? 0;
      s.addProp(StageProp(id: fly, kind: 'chips', pos: g.pocket(seat), z: 40, data: HoldemChips(math.max(100, toCents - before))));
      s.emit(_cue(cue, seat));
    }, name: 'chips($seat)'));
    stage.enqueue(MovePropCommand(fly, to: g.betSpot(seat), duration: const Duration(milliseconds: 260), arc: 10));
    stage.enqueue(CallbackCommand((s) {
      s.removeProp(fly);
      if (toCents <= 0) return;
      final p = s.prop('bet-$seat') ?? s.addProp(StageProp(id: 'bet-$seat', kind: 'chips', pos: g.betSpot(seat), z: 30, data: HoldemChips(0)));
      (p.data! as HoldemChips).cents = toCents;
    }, name: 'bet($seat)'));
  }

  void _uncalled(int seat, int cents) {
    final g = geometry;
    final fly = 'fly-${_fly++}';
    stage.enqueue(CallbackCommand((s) {
      final p = s.prop('bet-$seat');
      if (p != null) {
        final c = p.data! as HoldemChips;
        c.cents -= cents;
        if (c.cents <= 0) s.removeProp(p.id);
      }
      s.addProp(StageProp(id: fly, kind: 'chips', pos: g.betSpot(seat), z: 40, data: HoldemChips(cents)));
    }, name: 'uncalled($seat)'));
    stage.enqueue(MovePropCommand(fly, to: g.pocket(seat), duration: const Duration(milliseconds: 300), opacity: 0.2));
    stage.enqueue(CallbackCommand((s) => s.removeProp(fly), name: 'uncalled-done'));
  }

  void _collect(int potCents) {
    final g = geometry;
    final bets = [for (final p in stage.propsOf('chips')) if (p.id.startsWith('bet-')) p.id];
    stage.enqueue(CueCommand(_cue(HoldemSfx.chipsCollect, null)));
    stage.enqueue(ParallelCommand([
      ReachCommand(g.potCenter + const Offset(-70, -30), duration: const Duration(milliseconds: 260), left: true, grip: 0.2),
      ReachCommand(g.potCenter + const Offset(70, -30), duration: const Duration(milliseconds: 260), left: false, grip: 0.2),
      for (final id in bets) MovePropCommand(id, to: g.potCenter, duration: const Duration(milliseconds: 420)),
    ]));
    stage.enqueue(CallbackCommand((s) {
      for (final id in bets) {
        s.removeProp(id);
      }
      if (potCents > 0) {
        final p = s.prop('pot') ?? s.addProp(StageProp(id: 'pot', kind: 'chips', pos: g.potCenter, z: 30, data: HoldemChips(0, big: true)));
        (p.data! as HoldemChips).cents = potCents;
      }
    }, name: 'pot'));
    stage.enqueue(RestArmsCommand());
  }

  void _burn() {
    final g = geometry;
    final n = stage.propsOf('card').where((p) => p.id.startsWith('burn-')).length;
    final id = 'burn-$n';
    stage.enqueue(CallbackCommand((s) {
      s.removeProp(id);
      s.addProp(StageProp(id: id, kind: 'card', pos: g.deckSpot, scale: 0.85, z: 5, data: HoldemCard()));
      s.emit(_cue(HoldemSfx.cardBurn, null));
    }, name: 'burn'));
    stage.enqueue(ParallelCommand([
      ReachCommand(Offset.lerp(g.deckSpot, g.burnSpot, 0.5)!, duration: const Duration(milliseconds: 220), left: true, grip: 0.6),
      MovePropCommand(id, to: _burnPos(n), duration: const Duration(milliseconds: 240), rotation: -0.18 + n * 0.12, arc: 8),
    ]));
  }

  void _board(List<String> cards, int first) {
    final g = geometry;
    final ids = <String>[];
    for (var k = 0; k < cards.length && first + k < 5; k++) {
      final i = first + k;
      final id = 'board-$i';
      ids.add(id);
      final code = cards[k];
      stage.enqueue(CallbackCommand((s) {
        s.removeProp(id);
        s.addProp(StageProp(id: id, kind: 'card', pos: g.deckSpot, scale: 0.85, z: 10, data: HoldemCard(code: code)));
        s.emit(_cue(HoldemSfx.cardPitch, null));
      }, name: 'spawn($id)'));
      stage.enqueue(ParallelCommand([
        ReachCommand(g.boardSlot(i) + const Offset(0, -80), duration: const Duration(milliseconds: 190), grip: 0.5),
        MovePropCommand(id, to: g.boardSlot(i), duration: const Duration(milliseconds: 210), scale: 1, rotation: 0, arc: 14),
      ]));
    }
    _flip(ids, cue: HoldemSfx.boardFlip);
    stage.enqueue(PauseCommand(const Duration(milliseconds: 220)));
  }

  void _showdown(Map<String, Object?> hands) {
    final g = geometry;
    final ids = <String>[];
    for (final e in hands.entries) {
      final seat = int.tryParse(e.key);
      if (seat == null || seat >= g.seatCount) continue;
      final cards = asStringList(asMap(e.value)['cards']);
      for (var k = 0; k < 2 && k < cards.length; k++) {
        final id = 'hole-$seat-$k';
        ids.add(id);
        final code = cards[k];
        stage.enqueue(CallbackCommand((s) {
          final p = s.prop(id) ??
              s.addProp(StageProp(
                id: id,
                kind: 'card',
                pos: g.holeCardSpot(seat, k),
                rotation: g.seatRotation(seat),
                z: 20,
                data: HoldemCard(seat: seat, index: k),
              ));
          final c = p.data! as HoldemCard;
          c.code = code;
          if (c.mine) c.flip = 1;
        }, name: 'show($id)'));
      }
    }
    if (ids.isEmpty) return;
    stage.enqueue(ExpressionCommand(CharacterExpression.surprised, hold: const Duration(milliseconds: 900)));
    _flip(ids, cue: HoldemSfx.showdown);
    stage.enqueue(PauseCommand(const Duration(milliseconds: 500)));
  }

  void _win(int seat, int cents) {
    final g = geometry;
    if (seat >= g.seatCount || cents <= 0) return;
    final fly = 'fly-${_fly++}';
    stage.enqueue(CallbackCommand((s) {
      final p = s.prop('pot');
      if (p != null) {
        final c = p.data! as HoldemChips;
        c.cents -= cents;
        if (c.cents <= 0) s.removeProp('pot');
      }
      s.addProp(StageProp(id: fly, kind: 'chips', pos: g.potCenter, z: 40, data: HoldemChips(cents, big: true)));
      s.emit(_cue(HoldemSfx.potWin, seat));
    }, name: 'win($seat)'));
    stage.enqueue(ParallelCommand([
      ReachCommand(Offset.lerp(g.potCenter, g.seatSpot(seat), 0.3)!, duration: const Duration(milliseconds: 420), grip: 0.3),
      MovePropCommand(fly, to: g.pocket(seat), duration: const Duration(milliseconds: 560), arc: 12),
    ]));
    stage.enqueue(CallbackCommand((s) => s.removeProp(fly), name: 'win-done'));
    stage.enqueue(ExpressionCommand(CharacterExpression.smile));
    stage.enqueue(RestArmsCommand());
  }
}

// ---------------------------------------------------------------- painting --

/// Cards and chips of the scene, in z order.
class HoldemPropsPainter extends StagePainter {
  HoldemPropsPainter(super.stage, {required this.style, required this.myHole, this.medallion = '♠'});
  final CardStyle style;

  /// My hole cards (wire codes) for the current hand, or null.
  final List<String>? myHole;
  final String medallion;

  @override
  void paintStage(Canvas canvas) {
    final g = stage.geometry is HoldemGeometry ? stage.geometry as HoldemGeometry : kHoldemGeometry;
    for (final p in stage.props) {
      if (p.opacity <= 0.01) continue;
      final data = p.data;
      if (data is HoldemCard) {
        final mine = data.mine;
        final width = (data.seat == null ? g.boardCardWidth : (mine ? g.myHoleCardWidth : g.holeCardWidth)) * p.scale;
        final code = data.code ?? (mine && myHole != null && myHole!.length > data.index ? myHole![data.index] : null);
        _card(canvas, p, width, code, data);
      } else if (data is HoldemChips && data.cents > 0) {
        canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: p.opacity.clamp(0.0, 1.0)));
        paintChipStack(canvas, p.pos - Offset(0, p.lift), data.big ? 30 : 22, data.cents);
        canvas.restore();
      }
    }
  }

  void _card(Canvas canvas, StageProp p, double w, String? code, HoldemCard c) {
    final h = w / kCardAspect;
    final flipScale = (math.cos(math.pi * c.flip)).abs().clamp(0.04, 1.0);
    final face = c.flip >= 0.5 && code != null;
    final card = face ? cardFromWireOrNull(code) : null;
    final size = Size(w, h);
    canvas.save();
    canvas.translate(p.pos.dx, p.pos.dy - p.lift);
    canvas.rotate(p.rotation);
    canvas.scale(flipScale, 1);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.08));
    final alpha = p.opacity.clamp(0.0, 1.0);
    // shadow
    canvas.drawRRect(rr.shift(Offset(3, 4 + p.lift * 0.4)), Paint()..color = Colors.black.withValues(alpha: 0.28 * alpha));
    canvas.saveLayer(rect.inflate(6), Paint()..color = Colors.white.withValues(alpha: alpha));
    canvas.translate(-w / 2, -h / 2);
    if (card != null) {
      CardFacePainter(card: card, style: style.face).paint(canvas, size);
    } else {
      CardBackPainter(design: style.back, color: style.backColor, medallion: medallion).paint(canvas, size);
    }
    canvas.translate(w / 2, h / 2);
    if (c.dim) canvas.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.38));
    canvas.restore();
    if (c.highlight) {
      canvas.drawRRect(
        rr.inflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = const Color(0xFFFFD54F),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HoldemPropsPainter oldDelegate) =>
      oldDelegate.stage != stage || oldDelegate.style != style || oldDelegate.medallion != medallion || !_same(oldDelegate.myHole, myHole);

  static bool _same(List<String>? a, List<String>? b) => a == null ? b == null : b != null && a.join() == b.join();
}

// ---------------------------------------------------------------- the view --

/// The hold'em stage widget (inside the scaffold's room).
class HoldemStageView extends ConsumerStatefulWidget {
  const HoldemStageView({super.key, required this.stage, required this.scene, required this.view, this.drive = true, this.onLastHand});
  final StageController stage;
  final HoldemScene scene;
  final GameTableView view;
  final bool drive;
  final VoidCallback? onLastHand;

  @override
  ConsumerState<HoldemStageView> createState() => _HoldemStageViewState();
}

class _HoldemStageViewState extends ConsumerState<HoldemStageView> {
  int? _turnFor;

  @override
  void initState() {
    super.initState();
    _syncTurn(first: true);
  }

  @override
  void didUpdateWidget(HoldemStageView old) {
    super.didUpdateWidget(old);
    _syncTurn();
  }

  /// The ring follows the server's turn; my turn pings once.
  void _syncTurn({bool first = false}) {
    final t = widget.view.table;
    final seat = t.phase == GamePhase.live ? t.turnSeat : null;
    final key = seat == null ? null : seat * 100000 + t.round * 10 + (t.deadline?.millisecondsSinceEpoch ?? 0) % 10;
    if (key == _turnFor) return;
    _turnFor = key;
    if (seat == null || seat >= kHoldemGeometry.seatCount) {
      widget.stage.stopTurnTimer();
      return;
    }
    final remaining = t.remainingAt(widget.view.now);
    final s = t.seats[seat];
    final total = s != null && s.isBot ? (remaining > Duration.zero ? remaining : const Duration(seconds: 1)) : const Duration(milliseconds: HoldemTiming.decisionMs);
    widget.stage.startTurnTimer(seat, total, remaining: remaining);
    if (!first && widget.view.myTurn) widget.stage.emit(StageCue(HoldemSfx.yourTurn.file, sound: HoldemSfx.yourTurn, seat: seat));
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final t = view.table;
    final felt = (ref.watch(equippedStyleProvider).value ?? const CardStyle()).felt;
    final style = ref.watch(equippedStyleProvider).value ?? const CardStyle();
    final hole = ref.watch(gameHoleProvider(t.id)).value;
    final myHole = hole != null && hole.round == t.round && hole.cards.length == 2 ? hole.cards : null;
    final spec = Cast.of(t.dealerCharacterId);
    final ui = view.ui;
    return StageView(
      stage: widget.stage,
      drive: widget.drive,
      layers: [
        StageDealerPainter(widget.stage, spec),
        GameFeltPainter(widget.stage, light: felt.light, dark: felt.dark, accent: ui.accent),
        HoldemPropsPainter(widget.stage, style: style, myHole: myHole, medallion: ui.cardMedallion),
        StageArmsPainter(widget.stage, spec),
      ],
      overlays: (context, scale) => HoldemOverlays(view: view, scale: scale, stage: widget.stage, myHole: myHole, onLastHand: widget.onLastHand).build(context),
    );
  }
}

/// Pixel-space widgets above the felt (rebuilt on every stage notify).
class HoldemOverlays {
  HoldemOverlays({required this.view, required this.scale, required this.stage, this.myHole, this.onLastHand});
  final GameTableView view;
  final double scale;
  final StageController stage;
  final List<String>? myHole;
  final VoidCallback? onLastHand;

  HoldemGeometry get g => kHoldemGeometry;

  List<Widget> build(BuildContext context) {
    final l = context.l10n;
    final t = view.table;
    final h = HoldemTable.of(t);
    final step = holdemStepOf(t);
    final live = t.phase == GamePhase.live && step != HoldemStep.waiting;
    final settled = t.phase == GamePhase.settled;
    final handOn = live || settled;
    final result = settled ? h.result : null;
    final fs = 6 + 11 * scale;
    final out = <Widget>[StageTurnRing(stage: stage, scale: scale, color: view.ui.accent)];

    // Seat plates.
    for (var i = 0; i < g.seatCount && i < t.seats.length; i++) {
      final s = t.seats[i];
      if (s == null) continue;
      final hs = HoldemSeatState.of(s);
      final me = s.uid == view.myUid;
      final badge = holdemSeatBadge(l, s, hs, live: live);
      final winner = result != null && result.winners.contains(i);
      final c = g.seatSpot(i) * scale;
      final w = 150 * scale + 10;
      out.add(Positioned(
        key: Key('holdem-plate-$i'),
        left: c.dx - w / 2,
        top: c.dy + 18 * scale,
        width: w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: me ? const Color(0xFF00A800) : Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: winner ? const Color(0xFFFFD54F) : Colors.transparent, width: 2),
              ),
              child: Text(
                me ? l.gameYou : s.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fs),
              ),
            ),
            if (badge != null)
              Container(
                key: Key('holdem-badge-$i'),
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: badge.$2, borderRadius: BorderRadius.circular(4)),
                child: Text(badge.$1, maxLines: 1, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fs * 0.78)),
              ),
          ],
        ),
      ));
      // Bet amount next to the chips.
      if (live && hs.betCents > 0) {
        final b = g.betSpot(i) * scale;
        out.add(Positioned(
          left: b.dx + 26 * scale,
          top: b.dy - fs * 0.7,
          child: _pill(context.money(hs.betCents, compact: true), fs * 0.85, key: Key('holdem-bet-$i')),
        ));
      }
      // Hand name at the showdown.
      final shown = result?.hands[i];
      if (shown != null && shown.category != null) {
        final p = g.holeSpot(i) * scale;
        final hw = 190 * scale + 20;
        out.add(Positioned(
          left: p.dx - hw / 2,
          top: p.dy + 52 * scale,
          width: hw,
          child: Center(
            child: _pill(
              holdemHandName(l, HandValue(shown.category!, shown.score, shown.best)),
              fs * 0.8,
              color: winner ? const Color(0xFFB8860B) : Colors.black.withValues(alpha: 0.65),
              key: Key('holdem-hand-$i'),
            ),
          ),
        ));
      }
    }

    // Dealer button and blind markers.
    if (handOn && h.button >= 0 && h.button < g.seatCount) {
      out.add(_marker('D', g.buttonSpot(h.button), const Color(0xFFF5F5F5), Colors.black, const Key('holdem-button')));
      final heads = h.sb == h.button;
      if (h.sb != null && h.sb! < g.seatCount && !heads) {
        out.add(_marker(l.holdemBadgeSb, g.buttonSpot(h.sb!), const Color(0xFF1475E1), Colors.white, const Key('holdem-sb')));
      }
      if (h.bb != null && h.bb! < g.seatCount) {
        out.add(_marker(l.holdemBadgeBb, g.buttonSpot(h.bb!), const Color(0xFFE0B23A), Colors.black, const Key('holdem-bb')));
      }
    }

    // Pot(s).
    if (live && (h.potCents > 0 || holdemChipsInMiddle(t) > 0)) {
      final p = g.potCenter * scale;
      final lines = <String>[
        if (h.pots.length > 1) ...[
          l.holdemMainPot(context.money(h.pots.first.cents, compact: true)),
          for (var k = 1; k < h.pots.length; k++) l.holdemSidePot(k, context.money(h.pots[k].cents, compact: true)),
        ] else if (h.potCents > 0)
          l.holdemPot(context.money(h.potCents, compact: true)),
      ];
      if (lines.isNotEmpty) {
        final w = 330 * scale + 30;
        out.add(Positioned(
          key: const Key('holdem-pots'),
          left: p.dx - w / 2,
          top: p.dy + 40 * scale,
          width: w,
          child: Column(mainAxisSize: MainAxisSize.min, children: [for (final s in lines) _pill(s, fs * 0.85)]),
        ));
      }
    }
    if (settled && result != null && result.potCents > 0) {
      final p = g.potCenter * scale;
      final w = 360 * scale + 30;
      final hand = result.winningHand;
      out.add(Positioned(
        key: const Key('holdem-result'),
        left: p.dx - w / 2,
        top: p.dy - fs,
        width: w,
        child: Center(
          child: _pill(
            hand?.category == null
                ? l.holdemSummaryNoShowdown(context.money(result.potCents, compact: true))
                : l.holdemSummary(context.money(result.potCents, compact: true), holdemHandName(l, HandValue(hand!.category!, hand.score, hand.best))),
            fs * 0.9,
            color: const Color(0xFF3A2463),
          ),
        ),
      ));
    }

    // Waiting plaque.
    if (!handOn) {
      final text = step == HoldemStep.waiting ? l.holdemWaitingChips : (t.phase == GamePhase.idle ? l.holdemWaitingPlayers : null);
      if (text != null) {
        final w = 520 * scale + 40;
        out.add(Positioned(
          key: const Key('holdem-waiting'),
          left: g.boardCenter.dx * scale - w / 2,
          top: g.boardCenter.dy * scale - fs,
          width: w,
          child: Center(child: _pill(text, fs, color: Colors.black.withValues(alpha: 0.55))),
        ));
      }
    }

    // "Last hand" (every hole card, verified from the revealed seed).
    if (onLastHand != null && t.fairness.lastSeed != null) {
      out.add(Positioned(
        right: 6,
        top: (g.felt.top + 12) * scale,
        child: Material(
          color: Colors.black.withValues(alpha: 0.45),
          shape: const StadiumBorder(),
          child: IconButton(
            key: const Key('holdem-last-hand'),
            tooltip: l.holdemLastHand,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: Colors.white,
            icon: const Icon(Icons.visibility_outlined),
            onPressed: onLastHand,
          ),
        ),
      ));
    }
    return out;
  }

  Widget _pill(String text, double size, {Color? color, Key? key}) => Container(
        key: key,
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color ?? Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size)),
      );

  Widget _marker(String text, Offset at, Color bg, Color fg, Key key) {
    final r = 24 * scale + 4;
    final c = at * scale;
    return AnimatedPositioned(
      key: key,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
      left: c.dx - r,
      top: c.dy - r,
      width: r * 2,
      height: r * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1.5))],
        ),
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: r * 0.8)),
            ),
          ),
        ),
      ),
    );
  }
}
