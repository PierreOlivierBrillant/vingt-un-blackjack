/// Deterministic placeholder content (no randomness at runtime, so screens
/// and golden tests are stable). Everything is built as BACKEND-SHAPED maps
/// (exactly the documents of `firebase/functions/src/shared/types.ts`) and
/// parsed with the same `fromDoc` parsers the Firebase layer uses.
library;

import 'dart:math';

import 'package:flutter/painting.dart';

import '../../core/ids.dart';
import '../../domain/backend_constants.dart';
import '../../domain/lmsr.dart';
import '../../domain/models.dart';
import '../../domain/wire.dart';

typedef Doc = Map<String, Object?>;

abstract final class FakeData {
  /// uid of `FakeAuthRepository.demoUser` (kept here to avoid an import cycle).
  static const demoUid = 'u-demo';
  static const demoUsername = 'Joueur21';
  static const demoAvatar = 'avatar10';

  /// Stable fake avatar id of [uid].
  static String avatarFor(String uid) => 'avatar${((stableHash(uid) % 24) + 1).toString().padLeft(2, '0')}';

  /// Reference instant of the static docs (tests pin the clock to it).
  static final baseNow = DateTime(2026, 11, 18, 20, 30);

  /// ISO week of [baseNow].
  static const currentWeekId = '2026-W47';

  static int _ms(DateTime now, Duration ago) => now.subtract(ago).millisecondsSinceEpoch;

  // ------------------------------------------------------------ profiles --

  static Doc profileDoc({
    required String uid,
    required String username,
    required String avatar,
    bool isBot = false,
    required int rankPoints,
    int weeklyPoints = 0,
    String weekId = currentWeekId,
    int handsPlayed = 0,
    double winRate = 0.45,
    String? currentTableId,
    required int lastSeenAtMs,
    bool kycVerified = false,
    int createdAtMs = 0,
  }) {
    final won = (handsPlayed * winRate).round();
    final pushed = (handsPlayed * 0.08).round();
    return {
      'uid': uid,
      'username': username,
      'usernameLower': username.toLowerCase(),
      'avatar': avatar,
      'isBot': isBot,
      'rankPoints': rankPoints,
      'rankTier': rankTierForPoints(rankPoints).name,
      'weeklyPoints': weeklyPoints,
      'weekId': weekId,
      'stats': {
        'handsPlayed': handsPlayed,
        'handsWon': won,
        'handsLost': handsPlayed - won - pushed,
        'handsPushed': pushed,
        'blackjacks': handsPlayed ~/ 21,
        'netCents': (won - (handsPlayed - won - pushed)) * 750,
        'biggestWinCents': 3750 + handsPlayed * 5,
      },
      'currentTableId': currentTableId,
      'lastSeenAtMs': lastSeenAtMs,
      'kycVerified': kycVerified,
      'createdAtMs': createdAtMs,
    };
  }

  /// (uid, username, isBot, rankPoints, tableId, seen minutes ago)
  static const _people = <(String, String, bool, int, String?, int)>[
    ('u-countess', 'TheCountess', false, 9450, 't-onyx-1', 0),
    ('u-luna', 'LunaRiver', false, 8120, 't-cobalt-1', 0),
    ('u-yuki', 'yuki', false, 4310, null, 95),
    ('bot_003', 'AceOfBase', true, 3980, 't-emeraude-1', 0),
    ('u-max', 'max_dbl', false, 3420, 't-cobalt-1', 1),
    ('bot_011', 'soft17', true, 2890, 't-saphir-2', 0),
    ('u-ines', 'Ines', false, 2410, 't-saphir-1', 0),
    ('u-nova', 'nova', false, 2075, null, 12),
    ('bot_007', 'Ada', true, 1820, 't-saphir-1', 0),
    ('u-ophelie', 'OphelieK', false, 1690, null, 300),
    ('bot_014', 'splitzilla', true, 1480, 't-emeraude-2', 0),
    ('bot_022', 'Mlle_Jetons', true, 1310, null, 4),
    (demoUid, demoUsername, false, 1205, null, 0),
    ('u-karim', 'Karim_21', false, 1100, 't-saphir-1', 0),
    ('u-quentin', 'quentin_b', false, 940, null, 1440),
    ('bot_031', 'Hit_Me_Baby', true, 780, 't-emeraude-2', 0),
    ('u-sacha', 'Sacha', false, 610, null, 4000),
    ('bot_040', 'rouge_noir', true, 520, null, 2),
    ('u-cold', 'ColdDeck', false, 430, null, 600),
    ('u-bastien', 'Bastien', false, 260, null, 2880),
    ('bot_052', 'DoubleDown_D', true, 140, 't-jade-1', 0),
    ('u-marguerite', 'Marguerite', false, 60, null, 9000),
  ];

  /// All public profiles (humans + bots), `profiles/{uid}` shape.
  static List<Doc> profileDocs(DateTime now) {
    final rng = Random(stableHash('profiles'));
    return [
      for (var i = 0; i < _people.length; i++)
        () {
          final (uid, name, bot, points, table, seenMin) = _people[i];
          final weekly = i == 13 ? 0 : 40 + rng.nextInt(620);
          return profileDoc(
            uid: uid,
            username: name,
            avatar: uid == demoUid ? demoAvatar : avatarFor(uid),
            isBot: bot,
            rankPoints: points,
            weeklyPoints: uid == demoUid ? 318 : weekly,
            // Two players have not played this week (stale week id).
            weekId: i == 9 || i == 19 ? '2026-W45' : currentWeekId,
            handsPlayed: 200 + rng.nextInt(2400),
            winRate: 0.38 + rng.nextDouble() * 0.12,
            currentTableId: table,
            lastSeenAtMs: _ms(now, Duration(minutes: seenMin, seconds: 20)),
            kycVerified: !bot,
            createdAtMs: _ms(now, Duration(days: 30 + i)),
          );
        }(),
    ];
  }

  static List<PlayerProfile> profiles(DateTime now) => [for (final d in profileDocs(now)) PlayerProfile.fromDoc(d)];

  static PlayerProfile? profile(String uid, DateTime now) {
    for (final p in profiles(now)) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  // ---------------------------------------------------------- user docs --

  static Doc userSettingsDoc(DateTime now) => {
        'theme': 'dark',
        'language': 'fr',
        'cardBack': 'classicBlue',
        'cardFace': 'classic',
        'felt': 'green',
        'updatedAtMs': _ms(now, const Duration(days: 3)),
      };

  static Doc kycDoc(DateTime now, {String status = 'verified'}) => {
        'status': status,
        'docType': status == 'none' ? null : 'idCard',
        'submittedAtMs': status == 'none' ? null : _ms(now, const Duration(days: 2, minutes: 5)),
        'verifyAfterMs': status == 'pending' ? now.millisecondsSinceEpoch + Backend.kycReviewMs : null,
        'verifiedAtMs': status == 'verified' ? _ms(now, const Duration(days: 2, minutes: 4)) : null,
        'rejectionReason': status == 'rejected' ? 'underage' : null,
      };

  /// Sum of [ledgerDocs] (the history adds up from 0).
  static const walletBalanceCents = 128640;

  static Doc walletDoc(DateTime now) => {
        'balanceCents': walletBalanceCents,
        'totalDepositedCents': 50000,
        'totalWithdrawnCents': 20000,
        'dailyDeposit': {'day': utcDayId(now.subtract(const Duration(days: 2))), 'amountCents': 50000},
        'updatedAtMs': _ms(now, const Duration(minutes: 4)),
      };

  /// `users/{uid}/ledger`, newest first; `balanceAfterCents` derived
  /// backwards from [walletBalanceCents] so the history always adds up.
  static List<Doc> ledgerDocs(DateTime now) {
    // (id, type, amount, ago, tableId, hand, marketId, powerId, method)
    final raw = <(String, String, int, Duration, String?, int?, String?, String?, String?)>[
      ('l11', 'payout', 5000, const Duration(minutes: 4), 't-saphir-1', 440, null, null, null),
      ('l10', 'bet', -2500, const Duration(minutes: 5), 't-saphir-1', 440, null, null, null),
      ('l9', 'marketBuy', -960, const Duration(minutes: 22), null, null, 'm-cobalt1-205-bust', null, null),
      ('l8', 'adReward', 500, const Duration(hours: 1), null, null, null, null, null),
      ('l7', 'powerPurchase', -2000, const Duration(hours: 2), null, null, null, 'freeSplit', null),
      ('l6', 'payout', 1000, const Duration(hours: 3), 't-emeraude-1', 311, null, null, null),
      ('l5', 'bet', -1000, const Duration(hours: 3, minutes: 1), 't-emeraude-1', 311, null, null, null),
      ('l4', 'withdrawal', -20000, const Duration(days: 1), null, null, null, null, 'bankTransfer'),
      ('l3', 'marketBuy', -1400, const Duration(days: 1, hours: 6), null, null, 'm-onyx1-76-luna', null, null),
      ('l2', 'deposit', 50000, const Duration(days: 2), null, null, null, null, 'card'),
      ('l1', 'welcomeBonus', 100000, const Duration(days: 3), null, null, null, null, null),
    ];
    final out = <Doc>[];
    var balance = walletBalanceCents;
    for (final (id, type, amount, ago, tableId, hand, marketId, powerId, method) in raw) {
      out.add({
        'entryId': id,
        'type': type,
        'amountCents': amount,
        'balanceAfterCents': balance,
        'createdAtMs': _ms(now, ago),
        'tableId': tableId,
        'handNumber': hand,
        'marketId': marketId,
        'powerId': powerId,
        'method': method,
      });
      balance -= amount;
    }
    return out;
  }

  /// Parsed ledger with the table / market name joined as `detail`.
  static List<LedgerEntry> ledger(DateTime now) => [
        for (final d in ledgerDocs(now))
          if (LedgerEntry.fromDoc(d) case final e?) e.withDetail(ledgerDetail(e, now)),
      ];

  static String? ledgerDetail(LedgerEntry e, DateTime now) {
    if (e.tableId != null) {
      final name = tables.where((t) => t.id == e.tableId).firstOrNull?.name ?? e.tableId!;
      return e.handNumber == null ? name : '$name #${e.handNumber}';
    }
    if (e.marketId != null) {
      final m = markets(now).where((m) => m.id == e.marketId).firstOrNull;
      if (m != null) return m.handNumber == null ? m.tableName : '${m.tableName} #${m.handNumber}';
    }
    return null;
  }

  static List<Doc> inventoryDocs(DateTime now) => [
        {'powerId': 'freeSplit', 'quantity': 1, 'updatedAtMs': _ms(now, const Duration(hours: 2))},
        {'powerId': 'freeInsurance', 'quantity': 2, 'updatedAtMs': _ms(now, const Duration(days: 1))},
      ];

  static Doc adStateDoc(DateTime now) => {
        'day': utcDayId(now),
        'claimedToday': 1,
        'lastClaimAtMs': _ms(now, const Duration(hours: 1)),
      };

  // --------------------------------------------------------------- lobby --

  /// (id, name, tier, handNumber, humans, bots, phase)
  static const _tables = <(String, String, String, int, int, int, String)>[
    ('t-emeraude-1', 'Émeraude 1', 'low', 312, 2, 2, 'playerTurns'),
    ('t-emeraude-2', 'Émeraude 2', 'low', 188, 2, 3, 'betting'),
    ('t-jade-1', 'Jade 1', 'low', 57, 0, 1, 'idle'),
    ('t-saphir-1', 'Saphir 1', 'low', 441, 3, 1, 'playerTurns'),
    ('t-saphir-2', 'Saphir 2', 'mid', 97, 1, 4, 'settled'),
    ('t-cobalt-1', 'Cobalt 1', 'mid', 205, 2, 2, 'betting'),
    ('t-cobalt-2', 'Cobalt 2', 'mid', 12, 1, 0, 'insurance'),
    ('t-onyx-1', 'Onyx 1', 'high', 76, 2, 1, 'playerTurns'),
    ('t-or-1', 'Salon Or', 'high', 33, 2, 0, 'betting'),
  ];

  /// Lobby view of `tables/{id}` (the fields the lobby query returns).
  static List<Doc> lobbyTableDocs(DateTime now) => [
        for (final (i, (id, name, tier, hand, humans, bots, phase)) in _tables.indexed)
          {
            'tableId': id,
            'name': name,
            'stakeTier': tier,
            'minBetCents': Backend.stakeTierLimits[tier]!.$1,
            'maxBetCents': Backend.stakeTierLimits[tier]!.$2,
            'isPrivate': false,
            'simManaged': true,
            'status': 'open',
            'phase': phase,
            'handNumber': hand,
            'humanCount': humans,
            'botCount': bots,
            'queue': <Object?>[],
            'markets': _tableMarkets(id, hand),
            'rankTier': rankTierForPoints(4000 - i * 400).name,
            'updatedAtMs': _ms(now, Duration(seconds: 3 + i * 7)),
          },
      ];

  static final List<LiveTable> tables = [for (final d in lobbyTableDocs(baseNow)) LiveTable.fromDoc(d)];

  /// `TableDoc.markets` for [tableId] at [hand], from the fake market docs.
  static Doc _tableMarkets(String tableId, int hand) {
    String? find(String kind, {bool perHand = true}) {
      for (final m in _marketSpecs) {
        if (m.tableId == tableId && m.kind == kind && m.status == 'open' && (!perHand || m.hand == hand)) return m.id;
      }
      return null;
    }

    return {
      'dealerBust': find('dealerBust'),
      'natural': find('natural'),
      'shoe': find('shoeDealerBustRate', perHand: false),
      'players': {
        for (final m in _marketSpecs)
          if (m.tableId == tableId && m.kind == 'playerWins' && m.status == 'open' && m.hand == hand) '${m.seat}': m.id,
      },
    };
  }

  static List<Doc> feedDocs(DateTime now) {
    final raw = <(String, String, bool, String, int, String?, int)>[
      ('LunaRiver', 'u-luna', false, 'blackjack', 37500, 't-cobalt-1', 40),
      ('max_dbl', 'u-max', false, 'bigWin', 12000, 't-saphir-1', 95),
      ('OphelieK', 'u-ophelie', false, 'market', 4400, 't-onyx-1', 160),
      ('TheCountess', 'u-countess', false, 'blackjack', 150000, 't-or-1', 230),
      ('splitzilla', 'bot_014', true, 'bigWin', 20000, 't-emeraude-1', 310),
      ('Karim_21', 'u-karim', false, 'blackjack', 1500, 't-emeraude-2', 400),
      ('nova', 'u-nova', false, 'market', 26000, 't-cobalt-1', 520),
    ];
    return [
      for (final (name, uid, bot, kind, amount, table, agoS) in raw)
        {
          'username': name,
          'avatar': avatarFor(uid),
          'isBot': bot,
          'kind': kind,
          'amountCents': amount,
          'tableId': table,
          'createdAtMs': _ms(now, Duration(seconds: agoS)),
        },
    ];
  }

  static List<RecentWin> recentWins(DateTime now) => [
        for (final (i, d) in feedDocs(now).indexed) ?RecentWin.fromDoc(d, id: 'feed-$i'),
      ];

  // -------------------------------------------------------------- powers --

  static List<PowerOffer> powers(DateTime now) =>
      PowerOffer.fromInventory([for (final d in inventoryDocs(now)) ?InventoryItem.fromDoc(d)]);

  // ------------------------------------------------------------- friends --

  static const friendUids = ['u-luna', 'u-karim', 'u-ines', 'u-bastien', 'u-yuki'];

  static List<Doc> friendshipDocs(DateTime now) => [
        for (final (i, uid) in friendUids.indexed)
          {
            'uids': [demoUid, uid]..sort(),
            'usernames': {demoUid: demoUsername, uid: profile(uid, now)?.username ?? uid},
            'sinceMs': _ms(now, Duration(days: 20 - i * 3)),
          },
      ];

  static List<Doc> friendRequestDocs(DateTime now) => [
        {
          'fromUid': 'bot_014',
          'toUid': demoUid,
          'fromUsername': 'splitzilla',
          'toUsername': demoUsername,
          'fromAvatar': avatarFor('bot_014'),
          'createdAtMs': _ms(now, const Duration(hours: 5)),
        },
        {
          'fromUid': 'bot_022',
          'toUid': demoUid,
          'fromUsername': 'Mlle_Jetons',
          'toUsername': demoUsername,
          'fromAvatar': avatarFor('bot_022'),
          'createdAtMs': _ms(now, const Duration(days: 1)),
        },
        {
          'fromUid': demoUid,
          'toUid': 'u-cold',
          'fromUsername': demoUsername,
          'toUsername': 'ColdDeck',
          'fromAvatar': demoAvatar,
          'createdAtMs': _ms(now, const Duration(hours: 2)),
        },
      ];

  static Doc suggestionsDoc(DateTime now) => {
        'uids': ['bot_003', 'bot_011', 'bot_040'],
        'updatedAtMs': _ms(now, const Duration(days: 1)),
      };

  // ------------------------------------------------------------- markets --

  static const _questions = <String, (String, String)>{
    'dealerBust': ('Le croupier saute ?', 'Will the dealer bust?'),
    'natural': ('Un blackjack naturel ?', 'A natural blackjack?'),
    'shoeDealerBustRate': (
      'Le croupier saute dans ≥ 28 % des mains de ce sabot ?',
      'Will the dealer bust in ≥ 28% of this shoe’s hands?'
    ),
  };

  static final _marketSpecs = <_MarketSpec>[
    const _MarketSpec('m-cobalt1-205-bust', 't-cobalt-1', 'Cobalt 1', 'dealerBust', 205, 3, 10, 64, 1843200, 64, 'open', ageMin: 1),
    const _MarketSpec('m-onyx1-76-luna', 't-onyx-1', 'Onyx 1', 'playerWins', 76, 2, 40, 47, 3120500, 112, 'open',
        subjectUid: 'u-countess', subject: 'TheCountess', seat: 1, ageMin: 2),
    const _MarketSpec('m-saphir1-441-bj', 't-saphir-1', 'Saphir 1', 'natural', 441, 4, 5, 96, 512000, 29, 'open', ageMin: 3),
    const _MarketSpec('m-or-shoe', 't-or-1', 'Salon Or', 'shoeDealerBustRate', null, 1, 160, 62, 8904000, 203, 'open', ageMin: 50),
    const _MarketSpec('m-emeraude1-312-bust', 't-emeraude-1', 'Émeraude 1', 'dealerBust', 312, 5, 20, 63, 98000, 11, 'open', ageMin: 4),
    const _MarketSpec('m-cobalt1-204-max', 't-cobalt-1', 'Cobalt 1', 'playerWins', 204, 3, 90, 30, 1210000, 58, 'resolved',
        subjectUid: 'u-max', subject: 'max_dbl', seat: 3, outcome: 'yes', ageMin: 6),
    const _MarketSpec('m-onyx1-75-bust', 't-onyx-1', 'Onyx 1', 'dealerBust', 75, 2, 30, 12, 402000, 37, 'closed', ageMin: 7),
    const _MarketSpec('m-cobalt1-203-bust', 't-cobalt-1', 'Cobalt 1', 'dealerBust', 203, 3, 0, 0, 0, 0, 'void', ageMin: 9),
  ];

  static List<Doc> marketDocs(DateTime now) => [
        for (final s in _marketSpecs)
          () {
            final b = Backend.marketLiquidity[MarketKind.values.byName(s.kind)]!;
            final q = s.kind == 'playerWins'
                ? ('${s.subject} gagne ?', 'Will ${s.subject} win?')
                : _questions[s.kind]!;
            final created = _ms(now, Duration(minutes: s.ageMin));
            final open = s.status == 'open';
            final settled = s.status == 'resolved' || s.status == 'void';
            return <String, Object?>{
              'marketId': s.id,
              'tableId': s.tableId,
              'tableName': s.tableName,
              'kind': s.kind,
              'handNumber': s.hand,
              'shoeNumber': s.shoe,
              'subjectUid': s.subjectUid,
              'subjectUsername': s.subject,
              'subjectSeatIndex': s.seat,
              'question': {'fr': q.$1, 'en': q.$2},
              'status': s.status,
              'outcome': s.outcome,
              'b': b,
              'qYes': s.qYes,
              'qNo': s.qNo,
              'priceYes': lmsrPriceYes(LmsrState(b: b, qYes: s.qYes.toDouble(), qNo: s.qNo.toDouble())),
              'volumeCents': s.volume,
              'tradeCount': s.trades,
              'payoutsDone': settled,
              'createdAtMs': created,
              'closedAtMs': open ? null : created + 40000,
              'resolvedAtMs': settled ? created + 52000 : null,
            };
          }(),
      ];

  static List<Market> markets(DateTime now) => [for (final d in marketDocs(now)) ?Market.fromDoc(d)];

  /// Deterministic random walk ending at the market's current price,
  /// `priceHistory` docs ordered by atMs.
  static List<Doc> priceHistoryDocs(Market m, DateTime now, {int points = 60}) {
    final rng = Random(stableHash(m.id));
    final values = List<double>.filled(points, m.priceYes);
    for (var i = points - 2; i >= 0; i--) {
      final step = (rng.nextDouble() - 0.5) * 0.06;
      values[i] = (values[i + 1] - step).clamp(0.03, 0.97);
    }
    return [
      for (var i = 0; i < points; i++) {'atMs': _ms(now, Duration(minutes: (points - 1 - i) * 2)), 'priceYes': values[i]},
    ];
  }

  static List<PricePoint> priceHistory(Market m, DateTime now) =>
      [for (final d in priceHistoryDocs(m, now)) PricePoint.fromDoc(d)];

  static const _traders = [
    ('u-countess', 'TheCountess', false),
    ('bot_003', 'AceOfBase', true),
    ('u-nova', 'nova', false),
    ('u-max', 'max_dbl', false),
    ('bot_022', 'Mlle_Jetons', true),
    ('u-ophelie', 'OphelieK', false),
    ('u-quentin', 'quentin_b', false),
  ];

  /// `trades` docs, newest first.
  static List<Doc> tradeDocs(Market m, DateTime now) {
    final rng = Random(stableHash('act-${m.id}'));
    return [
      for (var i = 0; i < 12; i++)
        () {
          final (uid, name, bot) = _traders[(i * 5 + 3) % _traders.length];
          final yes = rng.nextBool();
          final buy = rng.nextInt(4) != 0;
          final shares = 5 + rng.nextInt(120);
          final pYes = (m.priceYes + (rng.nextDouble() - 0.5) * 0.08).clamp(0.02, 0.98);
          final price = yes ? pYes : 1 - pYes;
          return <String, Object?>{
            'tradeId': '${m.id}-t$i',
            'uid': uid,
            'username': name,
            'isBot': bot,
            'side': yes ? 'yes' : 'no',
            'direction': buy ? 'buy' : 'sell',
            'shares': shares,
            'amountCents': (shares * price * 100).round(),
            'priceYesAfter': pYes,
            'createdAtMs': _ms(now, Duration(seconds: 25 + i * 47)),
          };
        }(),
    ];
  }

  static List<MarketTrade> activity(Market m, DateTime now) => [for (final d in tradeDocs(m, now)) ?MarketTrade.fromDoc(d)];

  static List<Doc> positionDocs(DateTime now) {
    final byId = {for (final m in markets(now)) m.id: m};
    Doc pos(String id, {int yes = 0, int no = 0, required int cost}) {
      final m = byId[id]!;
      return {
        'marketId': id,
        'tableId': m.tableId,
        'kind': m.kind.name,
        'question': {'fr': m.question.fr, 'en': m.question.en},
        'yesShares': yes,
        'noShares': no,
        'costCents': cost,
        'proceedsCents': 0,
        'payoutCents': 0,
        'status': 'open',
        'updatedAtMs': _ms(now, const Duration(minutes: 22)),
      };
    }

    return [
      pos('m-cobalt1-205-bust', yes: 40, cost: 960),
      pos('m-onyx1-76-luna', no: 25, cost: 1400),
    ];
  }

  static List<MarketPosition> positions(DateTime now) => [for (final d in positionDocs(now)) MarketPosition.fromDoc(d)];

  // ----------------------------------------------------------------- ads --

  static const ads = <ParodyAd>[
    ParodyAd(id: 'coin', brand: 'NopeCoin™', color: Color(0xFFF7931A)),
    ParodyAd(id: 'bank', brand: 'Banque Imaginaire', color: Color(0xFF1475E1)),
    ParodyAd(id: 'ai', brand: 'ToasterGPT', color: Color(0xFF9B59FF)),
    ParodyAd(id: 'nft', brand: 'PixelPets NFT', color: Color(0xFFED4163)),
  ];

  // --------------------------------------------------------------- table --

  /// A mid-hand table document in the exact backend shape (`TableDoc`), so
  /// fakes and widget tests exercise the same parser as Firebase.
  static Map<String, Object?> tableDoc(String id, {DateTime? now}) {
    final t = tables.firstWhere((x) => x.id == id, orElse: () => tables[3]);
    final at = (now ?? DateTime(2026, 11, 18, 20, 30)).millisecondsSinceEpoch;
    Map<String, Object?> hand(List<String> cards, int total, int bet, {bool soft = false, bool done = false}) => {
          'cards': cards, 'total': total, 'soft': soft, 'betCents': bet, 'stakedCents': bet, 'doubled': false,
          'fromSplit': false, 'splitAces': false, 'surrendered': false, 'busted': false, 'blackjack': false,
          'done': done, 'result': null, 'returnCents': null,
        };
    Map<String, Object?> seat(int i, String uid, String name, int bet, List<Map<String, Object?>> hands, {bool bot = false}) => {
          'seatIndex': i, 'uid': uid, 'username': name, 'avatar': 'avatar0${i + 1}', 'isBot': bot,
          'rankTier': bot ? 'silver' : 'gold', 'status': 'active', 'joinedAtMs': at - 600000, 'betCents': bet,
          'hands': hands, 'insurance': null, 'powerUsed': null, 'roundNetCents': null, 'missedRounds': 0,
        };
    final seats = <Map<String, Object?>?>[
      seat(0, 'u-luna', 'LunaRiver', 2500, [hand(['9D', '7S'], 16, 2500, done: true)]),
      seat(1, 'bot_007', 'Ada', 1000, [hand(['QC', '8H'], 18, 1000, done: true)], bot: true),
      seat(2, demoUid, demoUsername, 5000, [hand(['AH', '6D'], 17, 5000, soft: true)]),
      null,
      seat(4, 'u-karim', 'Karim_21', 500, [hand(['TS', 'TH'], 20, 500)]),
    ];
    var seq = 100;
    Map<String, Object?> ev(String type, {int? seat, int? hand, String? card, int? amount}) => {
          'seq': ++seq, 'type': type, 'seatIndex': seat, 'handIndex': hand, 'card': card, 'amountCents': amount,
          'result': null, 'power': null, 'dealerBlackjack': null, 'atMs': at - 20000 + seq * 100,
        };
    final events = [
      for (final s in seats.nonNulls) ev('bet', seat: s['seatIndex'] as int, amount: s['betCents'] as int),
      for (var r = 0; r < 2; r++) ...[
        for (final s in seats.nonNulls)
          ev('deal', seat: s['seatIndex'] as int, hand: 0, card: ((s['hands'] as List).first as Map)['cards'][r] as String),
        r == 0 ? ev('dealerUp', card: '9C') : ev('dealerHole'),
      ],
      ev('stand', seat: 0, hand: 0),
      ev('stand', seat: 1, hand: 0),
    ];
    return {
      'tableId': t.id, 'name': t.name, 'stakeTier': t.tierId, 'minBetCents': t.minBetCents, 'maxBetCents': t.maxBetCents,
      'isPrivate': false, 'simManaged': true, 'status': 'open', 'phase': 'playerTurns', 'phaseStartedAtMs': at - 9000,
      'deadlineMs': at + 14000, 'handNumber': t.handNumber,
      'shoe': {'shoeNumber': 3, 'totalCards': 312, 'cardsRemaining': 201, 'handsDealt': 14, 'dealerBusts': 4, 'naturals': 2},
      'seats': seats,
      'dealer': {'cards': ['9C'], 'holeHidden': true, 'total': 9, 'soft': false, 'blackjack': false, 'busted': false},
      'turn': {'seatIndex': 2, 'handIndex': 0},
      'fairness': {
        'currentCommit': '9f2c4e1ab07d53e8c6f1d2a4b9e07c3d5a1f8e2b4c6d9a0e3f7b1c5d8e2a4f6b',
        'currentHandNumber': t.handNumber, 'lastHandNumber': t.handNumber - 1,
        'lastCommit': '1b6f0c2d9e8a7b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4',
        'lastSeed': '5e0d3c2b1a09f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c5b4a39281706f',
      },
      'events': events, 'eventSeq': seq, 'humanCount': 3, 'botCount': 1,
      'seatedUids': [for (final s in seats.nonNulls) s['uid']], 'queue': <Object?>[],
      'markets': _tableMarkets(t.id, t.handNumber),
      'rankTier': 'gold', 'createdAtMs': at - 3600000, 'updatedAtMs': at,
    };
  }
}

class _MarketSpec {
  const _MarketSpec(
    this.id,
    this.tableId,
    this.tableName,
    this.kind,
    this.hand,
    this.shoe,
    this.qYes,
    this.qNo,
    this.volume,
    this.trades,
    this.status, {
    this.subjectUid,
    this.subject,
    this.seat,
    this.outcome,
    this.ageMin = 1,
  });
  final String id;
  final String tableId;
  final String tableName;
  final String kind;
  final int? hand;
  final int shoe;
  final int qYes;
  final int qNo;
  final int volume;
  final int trades;
  final String status;
  final String? subjectUid;
  final String? subject;
  final int? seat;
  final String? outcome;
  final int ageMin;
}
