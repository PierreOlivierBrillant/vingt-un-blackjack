/// Backend-shaped documents of the Sprint 2 game tables (`gameTables/{id}`
/// and sub-collections, `shared/games/common.ts`) for the fakes and tests.
/// Game-specific parts (`g`, bet spot ids, round `result`) are plausible but
/// minimal: each game implementer refines them in its own folder/tests.
library;

import '../../domain/fairness.dart';
import '../../domain/game_table.dart';
import '../../domain/games.dart';
import 'fake_data.dart';

abstract final class FakeGameData {
  static int _ms(DateTime t) => t.millisecondsSinceEpoch;

  /// (min, max per spot, max per round) of a stake tier (whole dollars).
  static const tierLimits = <String, (int, int, int)>{
    'low': (100, 10000, 50000),
    'mid': (500, 50000, 250000),
    'high': (2500, 250000, 1000000),
  };

  /// Hold'em blinds per tier (cents): 1/2, 5/10, 25/50 $.
  static const holdemBlinds = <String, (int, int)>{'low': (100, 200), 'mid': (500, 1000), 'high': (2500, 5000)};

  static Map<String, Object?> limits(GameId game, String tier) {
    final (min, max, round) = tierLimits[tier] ?? tierLimits['low']!;
    final (sb, bb) = holdemBlinds[tier] ?? holdemBlinds['low']!;
    return {
      'minBetCents': game == GameId.holdem ? bb : min,
      'maxBetCents': max,
      'maxRoundCents': round,
      'extra': game == GameId.holdem
          ? {'smallBlindCents': sb, 'bigBlindCents': bb, 'minBuyInCents': bb * 40, 'maxBuyInCents': bb * 100}
          : <String, Object?>{},
    };
  }

  static const _bots = ['Ada', 'soft17', 'rouge_noir', 'Mlle_Jetons', 'splitzilla', 'DoubleDown_D', 'AceOfBase', 'Hit_Me_Baby'];

  /// (tableId, name, tier, phase, step, bots seated, humans seated)
  static const _tables = <(String, String, String, String, String?, int, int)>[
    ('rl-sim-01', 'Roulette Rubis', 'low', 'betting', null, 4, 1),
    ('rl-sim-02', 'Roulette Grenat', 'mid', 'live', 'spinning', 3, 0),
    ('bc-sim-01', 'Baccarat Perle', 'low', 'betting', null, 3, 1),
    ('bc-sim-02', 'Baccarat Nacre', 'high', 'settled', null, 2, 0),
    ('ho-sim-01', "Hold'em Onyx", 'low', 'live', 'preflop', 4, 1),
    ('ho-sim-02', "Hold'em Jais", 'mid', 'idle', null, 1, 0),
    ('cr-sim-01', 'Craps Topaze', 'low', 'live', 'comeOut', 5, 1),
    ('cr-sim-02', 'Craps Ambre', 'mid', 'betting', null, 2, 0),
  ];

  /// Public tables of every kernel game (newest first within a game).
  static List<Map<String, Object?>> tableDocs(DateTime now) => [
        for (final (id, name, tier, phase, step, bots, humans) in _tables)
          tableDoc(id, now, name: name, tier: tier, phase: phase, step: step, bots: bots, humans: humans),
      ];

  /// A `gameTables/{id}` document. [seatDemo] seats the demo user at seat 0
  /// ([demoStackCents] for hold'em). Unknown ids get a generic table.
  static Map<String, Object?> tableDoc(
    String id,
    DateTime now, {
    String? name,
    String tier = 'low',
    String phase = 'betting',
    String? step,
    int bots = 3,
    int humans = 0,
    bool seatDemo = false,
    bool isPrivate = false,
    int round = 42,
  }) {
    final game = gameOfTableId(id);
    final g = game.isKernel ? game : GameId.roulette;
    final seats = List<Map<String, Object?>?>.filled(g.seats, null);
    var next = 0;
    Map<String, Object?> seat(String uid, String username, {required bool bot}) => {
          'seatIndex': next,
          'uid': uid,
          'username': username,
          'avatar': FakeData.avatarFor(uid),
          'isBot': bot,
          'rankTier': bot ? 'silver' : 'gold',
          'status': 'active',
          'joinedAtMs': _ms(now.subtract(Duration(minutes: 10 + next))),
          'missedRounds': 0,
          'stakeCents': phase == 'idle' ? 0 : (next + 1) * (tierLimits[tier]!.$1) * 5,
          'stackCents': g == GameId.holdem ? (next + 3) * 4000 : null,
          'powerUsed': null,
          'roundNetCents': phase == 'settled' ? (next.isEven ? 2500 : -1000) : null,
          'g': <String, Object?>{},
        };
    if (seatDemo) {
      seats[next] = {
        ...seat(FakeData.demoUid, FakeData.demoUsername, bot: false),
        'avatar': FakeData.demoAvatar,
        if (g == GameId.holdem) 'stackCents': 20000,
      };
      next++;
    }
    for (var i = 0; i < humans && next < g.seats; i++) {
      seats[next] = seat('u-guest-$id-$i', ['LunaRiver', 'max_dbl', 'Karim_21'][i % 3], bot: false);
      next++;
    }
    for (var i = 0; i < bots && next < g.seats; i++) {
      final n = _bots[(i + id.length) % _bots.length];
      seats[next] = seat('bot_${(i * 7 + id.length) % 60}', n, bot: true);
      next++;
    }
    final taken = seats.whereType<Map<String, Object?>>().toList();
    final deadline = switch (phase) {
      'betting' => now.add(const Duration(seconds: 14)),
      'live' => now.add(const Duration(seconds: 12)),
      'settled' => now.add(const Duration(seconds: 4)),
      _ => null,
    };
    final seed = 'fake-seed-$id-$round';
    return {
      'tableId': id,
      'game': g.wire,
      'name': name ?? 'Table $id',
      'stakeTier': tier,
      'limits': limits(g, tier),
      'isPrivate': isPrivate,
      'simManaged': id.contains('-sim-'),
      'status': phase == 'closed' ? 'closed' : 'open',
      'phase': phase,
      'step': step,
      'phaseStartedAtMs': _ms(now.subtract(const Duration(seconds: 6))),
      'deadlineMs': deadline == null ? null : _ms(deadline),
      'round': round,
      'turn': phase == 'live' && (g == GameId.holdem || g == GameId.craps) ? {'seatIndex': taken.length > 1 ? 1 : 0} : null,
      'seats': seats,
      'queue': <Object?>[],
      'seatedUids': [for (final s in taken) s['uid']],
      'humanCount': taken.where((s) => s['isBot'] != true).length,
      'botCount': taken.where((s) => s['isBot'] == true).length,
      'rankTier': 'silver',
      'dealer': {'characterId': g.dealerCharacterId},
      'fairness': {
        'currentCommit': sha256Hex(seed),
        'currentHandNumber': round,
        'lastHandNumber': round - 1,
        'lastCommit': sha256Hex('fake-seed-$id-${round - 1}'),
        'lastSeed': 'fake-seed-$id-${round - 1}',
      },
      'events': [
        {'seq': 1, 'type': 'join', 'seatIndex': 0, 'atMs': _ms(now.subtract(const Duration(seconds: 8))), 'd': null},
      ],
      'eventSeq': 1,
      'markets': {
        'round': {
          if (g == GameId.roulette) 'rouletteRed': '${id}__r${round}__rouletteRed',
          if (g == GameId.baccarat) 'baccaratBanker': '${id}__r${round}__baccaratBanker',
          if (g == GameId.craps) 'crapsSeven': '${id}__r${round}__crapsSeven',
          if (g == GameId.holdem) 'holdemBoardAce': '${id}__r${round}__holdemBoardAce',
        },
        'series': <String, Object?>{},
      },
      'g': <String, Object?>{},
      'createdAtMs': _ms(now.subtract(const Duration(hours: 2))),
      'updatedAtMs': _ms(now.subtract(Duration(seconds: id.length))),
    };
  }

  /// A plausible spot id of [game] for the fake boards.
  static String _spot(GameId game, int i) => switch (game) {
        GameId.roulette => ['red', 'n17', 'dozen2', 'odd'][i % 4],
        GameId.baccarat => ['banker', 'player', 'tie'][i % 3],
        GameId.craps => ['pass', 'field', 'place6'][i % 3],
        _ => 'main',
      };

  /// `bets/*` of a bet-board table (none for hold'em).
  static List<Map<String, Object?>> betDocs(Map<String, Object?> table) {
    final game = GameId.fromWire(table['game']) ?? GameId.roulette;
    if (game == GameId.holdem) return const [];
    final round = table['round'] as int? ?? 0;
    final min = ((table['limits'] as Map?)?['minBetCents'] as int?) ?? 100;
    return [
      for (final s in (table['seats'] as List).whereType<Map<String, Object?>>())
        {
          'uid': s['uid'],
          'seatIndex': s['seatIndex'],
          'isBot': s['isBot'],
          'round': round,
          'bets': {_spot(game, s['seatIndex']! as int): min * 5, _spot(game, (s['seatIndex']! as int) + 1): min},
          'totalCents': min * 6,
          'power': null,
          'previous': {_spot(game, 0): min * 5},
          'updatedAtMs': table['updatedAtMs'],
        },
    ];
  }

  /// Finished rounds of [table], newest first, with valid commit/seed pairs.
  static List<Map<String, Object?>> roundDocs(Map<String, Object?> table, DateTime now, {int count = 3}) {
    final id = table['tableId']! as String;
    final game = GameId.fromWire(table['game']) ?? GameId.roulette;
    final round = table['round'] as int? ?? 1;
    final seats = (table['seats'] as List).whereType<Map<String, Object?>>().toList();
    return [
      for (var n = round - 1; n >= 1 && n > round - 1 - count; n--)
        {
          'tableId': id,
          'game': game.wire,
          'round': n,
          'startedAtMs': _ms(now.subtract(Duration(minutes: (round - n) * 1, seconds: 40))),
          'endedAtMs': _ms(now.subtract(Duration(minutes: (round - n) * 1))),
          'seats': [
            for (final s in seats)
              {
                'seatIndex': s['seatIndex'],
                'uid': s['uid'],
                'username': s['username'],
                'isBot': s['isBot'],
                'stakedCents': 1000,
                'netCents': (n + (s['seatIndex']! as int)).isEven ? 1000 : -1000,
              },
          ],
          'result': switch (game) {
            GameId.roulette => {'number': (n * 7) % 37},
            GameId.craps => {'dice': [1 + n % 6, 1 + (n * 5) % 6]},
            _ => <String, Object?>{},
          },
          'fairness': {
            'commit': sha256Hex('fake-seed-$id-$n'),
            'seed': 'fake-seed-$id-$n',
            'remainingBefore': null,
            'dealt': null,
            'decks': null,
          },
        },
    ];
  }

  /// Parsed boards / rounds (tests).
  static List<GameBet> bets(Map<String, Object?> table) => [for (final d in betDocs(table)) GameBet.fromDoc(d)];
  static List<GameRound> rounds(Map<String, Object?> table, DateTime now) =>
      [for (final d in roundDocs(table, now)) GameRound.fromDoc(d)];
}
