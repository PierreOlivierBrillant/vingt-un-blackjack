/// Localized words of the hold'em: hand names ("Paire de rois", "Kings full
/// of sevens"), categories, streets, seat badges, the status strip and the
/// second line of the seats bar. Texts: `l10n/parts/holdem.*.arb`.
library;

import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../core/widgets.dart';
import '../../../domain/game_table.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../common/game_table_view.dart';
import 'holdem_evaluator.dart';
import 'holdem_state.dart';

/// ICU select key of a card's rank (`holdemOfRank`, `holdemToRank`…).
String holdemRankKey(String card) => switch (card[0]) {
      'A' => 'ace',
      'K' => 'king',
      'Q' => 'queen',
      'J' => 'jack',
      'T' => 'ten',
      '9' => 'nine',
      '8' => 'eight',
      '7' => 'seven',
      '6' => 'six',
      '5' => 'five',
      '4' => 'four',
      '3' => 'three',
      _ => 'two',
    };

/// Short name of a category ("Full", "Full house").
String holdemCategoryName(AppLocalizations l, HoldemCategory c) => switch (c) {
      HoldemCategory.highCard => l.holdemCatHighCard,
      HoldemCategory.pair => l.holdemCatPair,
      HoldemCategory.twoPair => l.holdemCatTwoPair,
      HoldemCategory.trips => l.holdemCatTrips,
      HoldemCategory.straight => l.holdemCatStraight,
      HoldemCategory.flush => l.holdemCatFlush,
      HoldemCategory.fullHouse => l.holdemCatFullHouse,
      HoldemCategory.quads => l.holdemCatQuads,
      HoldemCategory.straightFlush => l.holdemCatStraightFlush,
    };

/// Full name of a hand ("Brelan de dames", "Ace-high flush").
String holdemHandName(AppLocalizations l, HandValue v) {
  final b = v.best;
  if (b.length < 5) return holdemCategoryName(l, v.category);
  // `best` is in significance order (a wheel starts with its five).
  String key(int i) => holdemRankKey(b[i]);
  final top = key(0);
  return switch (v.category) {
    HoldemCategory.highCard => l.holdemHandHighCard(l.holdemRankName(key(0))),
    HoldemCategory.pair => l.holdemHandPair(l.holdemOfRank(key(0))),
    HoldemCategory.twoPair => l.holdemHandTwoPair(l.holdemRankPlural(key(0)), l.holdemRankPlural(key(2))),
    HoldemCategory.trips => l.holdemHandTrips(l.holdemOfRank(key(0))),
    HoldemCategory.straight => l.holdemHandStraight(l.holdemToRank(top)),
    HoldemCategory.flush => l.holdemHandFlush(l.holdemToRank(key(0))),
    HoldemCategory.fullHouse => l.holdemHandFullHouse(l.holdemRankPlural(key(0)), l.holdemRankPlural(key(3))),
    HoldemCategory.quads => l.holdemHandQuads(l.holdemOfRank(key(0))),
    HoldemCategory.straightFlush => v.royal ? l.holdemHandRoyalFlush : l.holdemHandStraightFlush(l.holdemToRank(top)),
  };
}

String holdemStepName(AppLocalizations l, HoldemStep s) => switch (s) {
      HoldemStep.preflop => l.holdemStreetPreflop,
      HoldemStep.flop => l.holdemStreetFlop,
      HoldemStep.turn => l.holdemStreetTurn,
      HoldemStep.river => l.holdemStreetRiver,
      HoldemStep.showdown => l.holdemStreetShowdown,
      HoldemStep.folded => l.holdemStreetShowdown,
      HoldemStep.waiting => l.holdemWaitingChips,
    };

/// Badge under a seat plate: (text, colour), or null.
(String, Color)? holdemSeatBadge(AppLocalizations l, GameSeat s, HoldemSeatState hs, {required bool live}) {
  if (s.leaving) return (l.holdemBadgeLeaving, const Color(0xFF6B6B6B));
  if (s.sittingOut) return (l.holdemBadgePaused, const Color(0xFF6B6B6B));
  if (live && hs.inHand) {
    if (hs.allIn) return (l.holdemBadgeAllIn, const Color(0xFFC81E2B));
    return switch (hs.lastAction) {
      HoldemLastAction.fold => (l.holdemBadgeFold, const Color(0xFF555555)),
      HoldemLastAction.check => (l.holdemBadgeCheck, const Color(0xFF2E7D32)),
      HoldemLastAction.call => (l.holdemBadgeCall, const Color(0xFF1565C0)),
      HoldemLastAction.bet => (l.holdemBadgeBet, const Color(0xFFEF6C00)),
      HoldemLastAction.raise => (l.holdemBadgeRaise, const Color(0xFFEF6C00)),
      HoldemLastAction.allIn => (l.holdemBadgeAllIn, const Color(0xFFC81E2B)),
      _ => null,
    };
  }
  if (hs.waitBB) return (l.holdemBadgeWaitBB, const Color(0xFF455A64));
  return null;
}

/// Status strip of the hold'em table (street, whose turn, countdown).
String holdemStatusText(BuildContext context, GameTableView v) {
  final l = context.l10n;
  final t = v.table;
  if (t.closed) return l.tableClosedNotice;
  final secs = v.secondsLeft;
  final step = holdemStepOf(t);
  if (t.phase == GamePhase.live && step == HoldemStep.waiting) return l.holdemWaitingChips;
  final turn = t.turnSeatState;
  if (t.phase == GamePhase.live && turn != null) {
    final who = turn.uid == v.myUid ? l.tableYourTurn(secs) : l.tableTurnOf(turn.username, secs);
    return step == null ? who : l.holdemStatusStreet(holdemStepName(l, step), who);
  }
  return switch (t.phase) {
    GamePhase.idle || GamePhase.closed => l.holdemWaitingPlayers,
    GamePhase.betting => l.gamePhaseBetting(secs),
    GamePhase.live => t.deadline == null ? l.gamePhaseLive : l.gamePhaseLiveSecs(secs),
    GamePhase.settled => v.mine?.roundNetCents != null && HoldemSeatState.of(v.mine!).inHand
        ? l.gameRoundResult(context.money(v.mine!.roundNetCents!, signed: true))
        : l.gamePhaseSettled(secs),
  };
}

/// Second line of a seat in the seats bar: stack and state.
String? holdemSeatInfo(BuildContext context, GameSeat s, GameTableView v) {
  final l = context.l10n;
  final stack = s.stackCents == null ? null : l.gameStack(context.money(s.stackCents!, compact: true));
  final hs = HoldemSeatState.of(s);
  final live = v.table.phase == GamePhase.live && holdemStepOf(v.table) != HoldemStep.waiting;
  final badge = holdemSeatBadge(l, s, hs, live: live);
  if (badge == null) return stack;
  return stack == null ? badge.$1 : '$stack · ${badge.$1}';
}

/// Money in a locale given by its l10n (no BuildContext: history, profile).
String holdemMoney(AppLocalizations l, int cents) => formatCents(cents, locale: l.localeName, compact: true);
