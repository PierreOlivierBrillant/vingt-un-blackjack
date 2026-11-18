/// Client mirror of the public table document `tables/{tableId}` (see
/// `firebase/functions/src/shared/types.ts`, `TableDoc`). Parsing from the
/// Firestore map lives in [TableState.fromDoc] so the Firebase repository,
/// the fakes and the tests all go through ONE code path.
///
/// Card codes: the backend uses `T` for ten (`"TH"`); [PlayingCard.parse]
/// accepts both `"TH"` and `"10H"` — [parseCardCode] is the only place where
/// wire codes become cards.
library;

import 'package:flutter/foundation.dart';

import 'cards.dart';
import 'models.dart' show PowerType, RankTier;

/// Single conversion point from a backend card code (`"AS"`, `"TH"`, `"9C"`).
PlayingCard parseCardCode(String code) => PlayingCard.parse(code);

/// Inverse of [parseCardCode], in the backend format (`T` for ten).
String cardToWire(PlayingCard c) => '${c.rank == Rank.ten ? 'T' : c.rank.label}${c.suit.name[0].toUpperCase()}';

enum ServerTablePhase { idle, betting, insurance, playerTurns, settled, closed }

enum HandResult { blackjack, win, push, lose, bust, surrender }

enum TableEventType {
  shuffle,
  bet,
  deal,
  dealerUp,
  dealerHole,
  peek,
  insurance,
  hit,
  double,
  split,
  stand,
  surrender,
  secondChance,
  power,
  timeout,
  reveal,
  dealerHit,
  settle,
  join,
  leave,
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
bool _bool(Object? v) => v == true;
String? _str(Object? v) => v is String ? v : null;
List<Object?> _list(Object? v) => v is List ? v.cast<Object?>() : const [];
Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val as Object?)) : const {};
DateTime? _ms(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

PowerType? powerFromWire(Object? v) => _enumByName(PowerType.values, v);
RankTier rankTierFromWire(Object? v) => _enumByName(RankTier.values, v) ?? RankTier.bronze;

List<PlayingCard> _cards(Object? v) => [
      for (final c in _list(v))
        if (c is String) parseCardCode(c),
    ];

@immutable
class SeatHand {
  const SeatHand({
    required this.cards,
    required this.total,
    required this.soft,
    required this.betCents,
    required this.stakedCents,
    this.doubled = false,
    this.fromSplit = false,
    this.splitAces = false,
    this.surrendered = false,
    this.busted = false,
    this.blackjack = false,
    this.done = false,
    this.result,
    this.returnCents,
  });

  factory SeatHand.fromDoc(Map<String, Object?> d) => SeatHand(
        cards: _cards(d['cards']),
        total: _int(d['total']),
        soft: _bool(d['soft']),
        betCents: _int(d['betCents']),
        stakedCents: _int(d['stakedCents']),
        doubled: _bool(d['doubled']),
        fromSplit: _bool(d['fromSplit']),
        splitAces: _bool(d['splitAces']),
        surrendered: _bool(d['surrendered']),
        busted: _bool(d['busted']),
        blackjack: _bool(d['blackjack']),
        done: _bool(d['done']),
        result: _enumByName(HandResult.values, d['result']),
        returnCents: _intOrNull(d['returnCents']),
      );

  final List<PlayingCard> cards;
  final int total;
  final bool soft;
  final int betCents;
  final int stakedCents;
  final bool doubled;
  final bool fromSplit;
  final bool splitAces;
  final bool surrendered;
  final bool busted;
  final bool blackjack;
  final bool done;
  final HandResult? result;
  final int? returnCents;
}

@immutable
class SeatInsurance {
  const SeatInsurance({required this.betCents, required this.stakedCents, required this.decided, this.won});
  factory SeatInsurance.fromDoc(Map<String, Object?> d) => SeatInsurance(
        betCents: _int(d['betCents']),
        stakedCents: _int(d['stakedCents']),
        decided: _bool(d['decided']),
        won: d['result'] == 'win' ? true : (d['result'] == 'lose' ? false : null),
      );
  final int betCents;
  final int stakedCents;
  final bool decided;

  /// null until resolved.
  final bool? won;
}

@immutable
class SeatState {
  const SeatState({
    required this.seatIndex,
    required this.uid,
    required this.username,
    this.avatar = 'avatar01',
    this.isBot = false,
    this.rankTier = RankTier.bronze,
    this.leaving = false,
    this.betCents = 0,
    this.hands = const [],
    this.insurance,
    this.powerUsed,
    this.roundNetCents,
    this.missedRounds = 0,
  });

  factory SeatState.fromDoc(Map<String, Object?> d) => SeatState(
        seatIndex: _int(d['seatIndex']),
        uid: _str(d['uid']) ?? '',
        username: _str(d['username']) ?? '?',
        avatar: _str(d['avatar']) ?? 'avatar01',
        isBot: _bool(d['isBot']),
        rankTier: rankTierFromWire(d['rankTier']),
        leaving: d['status'] == 'leaving',
        betCents: _int(d['betCents']),
        hands: [for (final h in _list(d['hands'])) SeatHand.fromDoc(_map(h))],
        insurance: d['insurance'] == null ? null : SeatInsurance.fromDoc(_map(d['insurance'])),
        powerUsed: powerFromWire(d['powerUsed']),
        roundNetCents: _intOrNull(d['roundNetCents']),
        missedRounds: _int(d['missedRounds']),
      );

  final int seatIndex;
  final String uid;
  final String username;
  final String avatar;
  final bool isBot;
  final RankTier rankTier;
  final bool leaving;
  final int betCents;
  final List<SeatHand> hands;
  final SeatInsurance? insurance;
  final PowerType? powerUsed;
  final int? roundNetCents;
  final int missedRounds;
}

@immutable
class DealerState {
  const DealerState({
    this.cards = const [],
    this.holeHidden = false,
    this.total,
    this.soft = false,
    this.blackjack = false,
    this.busted = false,
  });

  factory DealerState.fromDoc(Map<String, Object?> d) => DealerState(
        cards: _cards(d['cards']),
        holeHidden: _bool(d['holeHidden']),
        total: _intOrNull(d['total']),
        soft: _bool(d['soft']),
        blackjack: _bool(d['blackjack']),
        busted: _bool(d['busted']),
      );

  /// Visible cards; while [holeHidden] only the up card.
  final List<PlayingCard> cards;
  final bool holeHidden;
  final int? total;
  final bool soft;
  final bool blackjack;
  final bool busted;
}

@immutable
class TableEvent {
  const TableEvent({
    required this.seq,
    required this.type,
    this.seatIndex,
    this.handIndex,
    this.card,
    this.amountCents,
    this.result,
    this.power,
    this.dealerBlackjack,
    required this.at,
  });

  /// Returns null for an unknown event type (forward compatible).
  static TableEvent? fromDoc(Map<String, Object?> d) {
    final type = _enumByName(TableEventType.values, d['type']);
    if (type == null) return null;
    final c = _str(d['card']);
    return TableEvent(
      seq: _int(d['seq']),
      type: type,
      seatIndex: _intOrNull(d['seatIndex']),
      handIndex: _intOrNull(d['handIndex']),
      card: c == null ? null : parseCardCode(c),
      amountCents: _intOrNull(d['amountCents']),
      result: _enumByName(HandResult.values, d['result']),
      power: powerFromWire(d['power']),
      dealerBlackjack: d['dealerBlackjack'] is bool ? d['dealerBlackjack'] as bool : null,
      at: _ms(d['atMs']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final int seq;
  final TableEventType type;
  final int? seatIndex;
  final int? handIndex;
  final PlayingCard? card;
  final int? amountCents;
  final HandResult? result;
  final PowerType? power;
  final bool? dealerBlackjack;
  final DateTime at;

  @override
  String toString() => 'ev#$seq ${type.name}${seatIndex == null ? '' : ' s$seatIndex'}'
      '${handIndex == null ? '' : '/h$handIndex'}${card == null ? '' : ' $card'}'
      '${amountCents == null ? '' : ' $amountCents¢'}${result == null ? '' : ' ${result!.name}'}';
}

@immutable
class ShoeInfo {
  const ShoeInfo({
    this.shoeNumber = 1,
    this.totalCards = 312,
    this.cardsRemaining = 312,
    this.handsDealt = 0,
    this.dealerBusts = 0,
    this.naturals = 0,
  });
  factory ShoeInfo.fromDoc(Map<String, Object?> d) => ShoeInfo(
        shoeNumber: _int(d['shoeNumber'], 1),
        totalCards: _int(d['totalCards'], 312),
        cardsRemaining: _int(d['cardsRemaining'], 312),
        handsDealt: _int(d['handsDealt']),
        dealerBusts: _int(d['dealerBusts']),
        naturals: _int(d['naturals']),
      );
  final int shoeNumber;
  final int totalCards;
  final int cardsRemaining;
  final int handsDealt;
  final int dealerBusts;
  final int naturals;
}

@immutable
class FairnessInfo {
  const FairnessInfo({this.currentCommit, this.currentHandNumber = 0, this.lastHandNumber, this.lastCommit, this.lastSeed});
  factory FairnessInfo.fromDoc(Map<String, Object?> d) => FairnessInfo(
        currentCommit: _str(d['currentCommit']),
        currentHandNumber: _int(d['currentHandNumber']),
        lastHandNumber: _intOrNull(d['lastHandNumber']),
        lastCommit: _str(d['lastCommit']),
        lastSeed: _str(d['lastSeed']),
      );

  /// SHA-256 (hex) of the current hand's seed, published before the deal.
  final String? currentCommit;
  final int currentHandNumber;
  final int? lastHandNumber;
  final String? lastCommit;

  /// Seed of the last finished hand (revealed after settlement).
  final String? lastSeed;
}

@immutable
class TableTurn {
  const TableTurn(this.seatIndex, this.handIndex);
  final int seatIndex;
  final int handIndex;
  @override
  bool operator ==(Object other) => other is TableTurn && other.seatIndex == seatIndex && other.handIndex == handIndex;
  @override
  int get hashCode => Object.hash(seatIndex, handIndex);
}

@immutable
class TableMarkets {
  const TableMarkets({this.dealerBust, this.natural, this.shoe, this.players = const {}});
  factory TableMarkets.fromDoc(Map<String, Object?> d) => TableMarkets(
        dealerBust: _str(d['dealerBust']),
        natural: _str(d['natural']),
        shoe: _str(d['shoe']),
        players: {
          for (final e in _map(d['players']).entries)
            if (int.tryParse(e.key) != null && e.value is String) int.parse(e.key): e.value! as String,
        },
      );
  final String? dealerBust;
  final String? natural;
  final String? shoe;

  /// Seat index → market id.
  final Map<int, String> players;
  List<String> get all => [?dealerBust, ?natural, ?shoe, ...players.values];
}

@immutable
class QueuedPlayer {
  const QueuedPlayer({required this.uid, required this.username});
  final String uid;
  final String username;
}

/// Public state of one table, as the server last published it.
@immutable
class TableState {
  const TableState({
    required this.id,
    required this.name,
    this.stakeTier = 'low',
    required this.minBetCents,
    required this.maxBetCents,
    this.isPrivate = false,
    this.simManaged = false,
    this.closed = false,
    required this.phase,
    this.phaseStartedAt,
    this.deadline,
    required this.handNumber,
    this.shoe = const ShoeInfo(),
    required this.seats,
    this.dealer = const DealerState(),
    this.turn,
    this.fairness = const FairnessInfo(),
    this.events = const [],
    this.eventSeq = 0,
    this.humanCount = 0,
    this.botCount = 0,
    this.queue = const [],
    this.markets = const TableMarkets(),
    this.updatedAt,
    this.fromCache = false,
  });

  /// Parses `tables/{id}`. Missing/invalid fields fall back to safe values;
  /// `seats` is always padded to 5 entries.
  factory TableState.fromDoc(String id, Map<String, Object?> d, {bool fromCache = false}) {
    final rawSeats = _list(d['seats']);
    final seats = <SeatState?>[
      for (var i = 0; i < 5; i++)
        i < rawSeats.length && rawSeats[i] is Map ? SeatState.fromDoc(_map(rawSeats[i])) : null,
    ];
    final turn = d['turn'] is Map ? _map(d['turn']) : null;
    final events = <TableEvent>[
      for (final e in _list(d['events']))
        if (e is Map) ?TableEvent.fromDoc(_map(e)),
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    return TableState(
      id: _str(d['tableId']) ?? id,
      name: _str(d['name']) ?? id,
      stakeTier: _str(d['stakeTier']) ?? 'low',
      minBetCents: _int(d['minBetCents'], 100),
      maxBetCents: _int(d['maxBetCents'], 10000),
      isPrivate: _bool(d['isPrivate']),
      simManaged: _bool(d['simManaged']),
      closed: d['status'] == 'closed',
      phase: _enumByName(ServerTablePhase.values, d['phase']) ?? ServerTablePhase.idle,
      phaseStartedAt: _ms(d['phaseStartedAtMs']),
      deadline: _ms(d['deadlineMs']),
      handNumber: _int(d['handNumber']),
      shoe: ShoeInfo.fromDoc(_map(d['shoe'])),
      seats: seats,
      dealer: DealerState.fromDoc(_map(d['dealer'])),
      turn: turn == null ? null : TableTurn(_int(turn['seatIndex']), _int(turn['handIndex'])),
      fairness: FairnessInfo.fromDoc(_map(d['fairness'])),
      events: events,
      eventSeq: _int(d['eventSeq']),
      humanCount: _int(d['humanCount']),
      botCount: _int(d['botCount']),
      queue: [
        for (final q in _list(d['queue']))
          if (q is Map) QueuedPlayer(uid: _str(q['uid']) ?? '', username: _str(q['username']) ?? '?'),
      ],
      markets: TableMarkets.fromDoc(_map(d['markets'])),
      updatedAt: _ms(d['updatedAtMs']),
      fromCache: fromCache,
    );
  }

  final String id;
  final String name;

  /// `low` | `mid` | `high`.
  final String stakeTier;
  final int minBetCents;
  final int maxBetCents;
  final bool isPrivate;
  final bool simManaged;
  final bool closed;
  final ServerTablePhase phase;
  final DateTime? phaseStartedAt;

  /// Server deadline of the current phase / turn (null when nothing pending).
  final DateTime? deadline;
  final int handNumber;
  final ShoeInfo shoe;

  /// Always 5 entries; null = empty seat.
  final List<SeatState?> seats;
  final DealerState dealer;
  final TableTurn? turn;
  final FairnessInfo fairness;

  /// Event log of the CURRENT hand only (reset when betting opens), by seq.
  final List<TableEvent> events;
  final int eventSeq;
  final int humanCount;
  final int botCount;
  final List<QueuedPlayer> queue;
  final TableMarkets markets;
  final DateTime? updatedAt;

  /// True when the snapshot came from the local cache (offline).
  final bool fromCache;

  SeatState? seatOf(String uid) {
    for (final s in seats) {
      if (s != null && s.uid == uid) return s;
    }
    return null;
  }

  bool isQueued(String uid) => queue.any((q) => q.uid == uid);
}

/// `tables/{id}/peeks/{uid}` — the peek power's result, visible to me only.
@immutable
class PeekResult {
  const PeekResult({required this.handNumber, required this.holeCard, this.createdAt});

  /// `PeekDoc`; null when the hole card is missing/invalid.
  static PeekResult? fromDoc(Map<String, Object?> d) {
    final c = _str(d['holeCard']);
    if (c == null) return null;
    final PlayingCard card;
    try {
      card = parseCardCode(c);
    } on Object {
      return null;
    }
    return PeekResult(handNumber: _int(d['handNumber']), holeCard: card, createdAt: _ms(d['createdAtMs']));
  }

  final int handNumber;
  final PlayingCard holeCard;
  final DateTime? createdAt;
}

/// `tables/{id}/hands/{n}` — history + provably-fair proof of a finished hand.
@immutable
class HandHistory {
  const HandHistory({
    required this.tableId,
    required this.handNumber,
    required this.startedAt,
    required this.endedAt,
    required this.dealerCards,
    required this.dealerTotal,
    required this.seats,
    required this.commit,
    required this.seed,
    required this.remainingBefore,
    required this.dealt,
  });

  factory HandHistory.fromDoc(Map<String, Object?> d) {
    final f = _map(d['fairness']);
    return HandHistory(
      tableId: _str(d['tableId']) ?? '',
      handNumber: _int(d['handNumber']),
      startedAt: _ms(d['startedAtMs']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: _ms(d['endedAtMs']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      dealerCards: _cards(d['dealerCards']),
      dealerTotal: _int(d['dealerTotal']),
      seats: [
        for (final s in _list(d['seats']))
          if (s is Map)
            HandHistorySeat(
              seatIndex: _int(s['seatIndex']),
              uid: _str(s['uid']) ?? '',
              username: _str(s['username']) ?? '?',
              isBot: _bool(s['isBot']),
              hands: [for (final h in _list(s['hands'])) SeatHand.fromDoc(_map(h))],
              netCents: _int(s['netCents']),
            ),
      ],
      commit: _str(f['commit']) ?? '',
      seed: _str(f['seed']) ?? '',
      remainingBefore: [for (final c in _list(f['remainingBefore'])) if (c is String) c],
      dealt: [for (final c in _list(f['dealt'])) if (c is String) c],
    );
  }

  final String tableId;
  final int handNumber;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<PlayingCard> dealerCards;
  final int dealerTotal;
  final List<HandHistorySeat> seats;
  final String commit;
  final String seed;

  /// Wire codes (kept raw for the fairness re-computation).
  final List<String> remainingBefore;
  final List<String> dealt;
}

@immutable
class HandHistorySeat {
  const HandHistorySeat({
    required this.seatIndex,
    required this.uid,
    required this.username,
    required this.isBot,
    required this.hands,
    required this.netCents,
  });
  final int seatIndex;
  final String uid;
  final String username;
  final bool isBot;
  final List<SeatHand> hands;
  final int netCents;
}

/// Result of `joinMatchmaking`.
@immutable
class MatchResult {
  const MatchResult({required this.tableId, required this.seated, this.seatIndex, this.code});

  /// `JoinMatchmakingResponse {tableId, status: 'seated'|'queued', seatIndex, code}`.
  factory MatchResult.fromResponse(Map<String, Object?> r) => MatchResult(
        tableId: _str(r['tableId']) ?? '',
        seated: r['status'] == 'seated',
        seatIndex: _intOrNull(r['seatIndex']),
        code: _str(r['code']),
      );

  final String tableId;

  /// false = queued (seated at the next betting round).
  final bool seated;
  final int? seatIndex;

  /// Private table code (createPrivate / joinCode).
  final String? code;
}

enum MatchMode { quick, createPrivate, joinCode }

/// `PokeTableResponse`.
@immutable
class PokeResult {
  const PokeResult({required this.phase, required this.handNumber, this.deadline, required this.advanced});
  factory PokeResult.fromResponse(Map<String, Object?> r) => PokeResult(
        phase: _enumByName(ServerTablePhase.values, r['phase']) ?? ServerTablePhase.idle,
        handNumber: _int(r['handNumber']),
        deadline: _ms(r['deadlineMs']),
        advanced: _bool(r['advanced']),
      );
  final ServerTablePhase phase;
  final int handNumber;
  final DateTime? deadline;
  final bool advanced;
}
