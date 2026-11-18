import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/card_style.dart';
import '../../l10n/gen/app_localizations.dart';
import '../cards/card_painters.dart';
import 'dealer_controller.dart';
import 'dealer_painters.dart';
import 'table_geometry.dart';

/// Who sits where (display only).
@immutable
class DealerSeat {
  const DealerSeat({required this.name, this.stackCents = 0, this.isMe = false, this.isBot = false});
  final String name;
  final int stackCents;
  final bool isMe;
  final bool isBot;
}

/// Renders a [DealerController]'s scene: dealer, felt, shoe, cards, chips,
/// arms, seat plates, totals, badges and the turn ring. Drives the controller
/// with a [Ticker] unless [drive] is false (then the owner calls `advance`).
class DealerStage extends StatefulWidget {
  const DealerStage({
    super.key,
    required this.controller,
    required this.style,
    this.seats = const [null, null, null, null, null],
    this.drive = true,
  });

  final DealerController controller;
  final CardStyle style;
  final List<DealerSeat?> seats;
  final bool drive;

  @override
  State<DealerStage> createState() => _DealerStageState();
}

class _DealerStageState extends State<DealerStage> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.drive) {
      _ticker = createTicker((elapsed) {
        var dt = elapsed - _last;
        _last = elapsed;
        // After a hitch, don't teleport: cap a frame at 50 ms.
        if (dt > const Duration(milliseconds: 50)) dt = const Duration(milliseconds: 50);
        widget.controller.advance(dt);
      })..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AspectRatio(
      aspectRatio: TableGeometry.size.width / TableGeometry.size.height,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.maxWidth / TableGeometry.size.width;
        final size = Size(box.maxWidth, box.maxHeight);
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: DealerBodyPainter(widget.controller))),
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: FeltPainter(
                      felt: widget.style.felt,
                      payoutLine: l.feltPayout,
                      ruleLine: l.feltRule,
                      insuranceLine: l.feltInsurance,
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: CustomPaint(painter: FurniturePainter(widget.controller, widget.style))),
              ..._seatPlates(context, s),
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ..._turnRing(context, s),
                      ..._cardWidgets(s),
                    ],
                  ),
                ),
              ),
              Positioned.fill(child: CustomPaint(painter: ChipsLayerPainter(widget.controller))),
              Positioned.fill(child: CustomPaint(painter: ArmsPainter(widget.controller, widget.style), size: size)),
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => Stack(clipBehavior: Clip.none, children: _totalsAndBadges(context, s)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  List<Widget> _cardWidgets(double s) {
    final out = <Widget>[];
    for (final c in widget.controller.cards) {
      if (!c.visible || c.opacity <= 0.01) continue;
      final cw = TableGeometry.cardWidth * s * (1 + 0.12 * c.lift);
      final ch = cw / kCardAspect;
      final p = c.pos * s;
      final showFace = c.flip >= 0.5;
      final angle = showFace ? math.pi * c.flip - math.pi : math.pi * c.flip;
      out.add(Positioned(
        key: ValueKey('shadow-${c.id}'),
        left: p.dx - cw / 2 + c.lift * 16 * s,
        top: p.dy - ch / 2 + c.lift * 26 * s,
        child: IgnorePointer(
          child: Transform.rotate(
            angle: c.rotation,
            child: Opacity(
              opacity: (c.opacity * (0.45 - 0.2 * c.lift)).clamp(0.0, 1.0),
              child: Container(
                width: cw,
                height: ch,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(cw * 0.08),
                  boxShadow: [BoxShadow(color: Colors.black, blurRadius: 2 + 14 * c.lift)],
                ),
              ),
            ),
          ),
        ),
      ));
      out.add(Positioned(
        key: ValueKey('card-${c.id}'),
        left: p.dx - cw / 2,
        top: p.dy - ch / 2 - c.lift * 22 * s,
        child: Opacity(
          opacity: c.opacity.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0014)
              ..rotateZ(c.rotation)
              ..rotateY(angle),
            child: RepaintBoundary(
              child: PlayingCardView(
                card: c.card,
                faceUp: showFace,
                style: widget.style,
                width: cw,
                elevation: 0,
              ),
            ),
          ),
        ),
      ));
    }
    return out;
  }

  List<Widget> _seatPlates(BuildContext context, double s) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final palette = context.palette;
    final out = <Widget>[];
    for (var i = 0; i < TableGeometry.seatCount; i++) {
      final seat = i < widget.seats.length ? widget.seats[i] : null;
      final spot = TableGeometry.seatSpots[i] * s;
      final w = 210 * s;
      out.add(Positioned(
        left: spot.dx - w / 2,
        top: spot.dy + 72 * s,
        width: w,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: seat == null
                ? Colors.black.withValues(alpha: 0.25)
                : (seat.isMe ? palette.win.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              fontFamily: kAppFont,
              color: seat?.isMe == true ? BrandColors.onGreen : Colors.white,
              fontSize: 10,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seat == null ? l.seatOpen : (seat.isMe ? l.you : seat.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (seat != null)
                  Text(
                    formatCents(seat.stackCents, locale: locale, compact: true),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        ),
      ));
    }
    return out;
  }

  List<Widget> _turnRing(BuildContext context, double s) {
    final c = widget.controller;
    final seat = c.turnSeat;
    if (seat == null) return const [];
    final spot = TableGeometry.seatSpots[seat] * s;
    final d = 160 * s;
    final f = c.turnFraction;
    final color = f > 0.75 ? context.palette.loss : (f > 0.5 ? context.palette.warning : context.palette.win);
    return [
      Positioned(
        left: spot.dx - d / 2,
        top: spot.dy - d / 2,
        width: d,
        height: d,
        child: CustomPaint(
          painter: TurnRingPainter(fraction: f, color: color, track: Colors.black.withValues(alpha: 0.3)),
          child: Center(
            child: Text(
              '${(c.turnRemaining.inMilliseconds / 1000).ceil()}',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _totalsAndBadges(BuildContext context, double s) {
    final c = widget.controller;
    final l = AppLocalizations.of(context);
    final palette = context.palette;
    final out = <Widget>[];
    final targets = <HandTarget>{for (final card in c.cards) card.target};
    for (final t in targets) {
      final total = c.visibleTotal(t);
      final cards = c.cardsFor(t).where((x) => x.visible).toList();
      if (total == null || cards.isEmpty || c.currentCommand is CollectAllCommand) continue;
      // Anchor on the resting slot of the last card (not its live position)
      // so the pill never chases a card in flight or one being flipped.
      final top = DealerController.geometry.cardRest(
        t,
        cards.last.index,
        handCount: t.isDealer ? 1 : c.handCount(t.seat),
      );
      final anchor = (t.isDealer
              ? top + const Offset(TableGeometry.cardWidth * 0.5 + 34, 0)
              : top - const Offset(0, TableGeometry.cardHeight / 2 + 26)) *
          s;
      final soft = total.soft && total.total < 21;
      final label = soft ? '${total.total - 10}/${total.total}' : '${total.total}';
      final color = total.isBust ? palette.loss : (total.total == 21 ? palette.win : Colors.black.withValues(alpha: 0.75));
      out.add(Positioned(
        left: anchor.dx - 24,
        top: anchor.dy - 10,
        width: 48,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Text(
              label,
              style: TextStyle(
                color: total.total == 21 && !total.isBust ? BrandColors.onGreen : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ));
    }
    c.badges.forEach((key, badge) {
      final (seat, hand) = key;
      final spot = TableGeometry.seatSpots[seat];
      final hands = c.handCount(seat);
      final rest = DealerController.geometry.cardRest(HandTarget.seat(seat, hand: hand), 0, handCount: hands);
      final anchor = Offset(hands > 1 ? rest.dx : spot.dx, spot.dy - 90) * s;
      final (text, bg, fg) = switch (badge) {
        SeatBadge.blackjack => (l.badgeBlackjack, palette.gold, Colors.black),
        SeatBadge.bust => (l.badgeBust, palette.loss, Colors.white),
        SeatBadge.win => (l.badgeWin, palette.win, BrandColors.onGreen),
        SeatBadge.lose => (l.badgeLose, Colors.black87, Colors.white),
        SeatBadge.push => (l.badgePush, BrandColors.blue, Colors.white),
      };
      out.add(Positioned(
        left: anchor.dx - 50,
        top: anchor.dy - 11,
        width: 100,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.6), blurRadius: 10)],
            ),
            child: Text(
              text,
              maxLines: 1,
              style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ),
        ),
      ));
    });
    return out;
  }
}
