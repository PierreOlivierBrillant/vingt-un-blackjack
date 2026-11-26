// Sprint 2 game tables: parsing of gameTables/{id} + bets / holes / rounds and
// of the callable responses, exactly as in shared/games/common.ts; payloads;
// the fake repository's money flow.
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/data/fake/fake_game_data.dart';
import 'package:vingtun/data/fake/fake_game_repository.dart';
import 'package:vingtun/data/fake/fake_repositories.dart';
import 'package:vingtun/data/firebase/backend_api.dart';
import 'package:vingtun/data/repositories.dart';
import 'package:vingtun/domain/fairness.dart';
import 'package:vingtun/domain/games.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/features/games/game_ui.dart';

final now = DateTime(2026, 11, 18, 20, 30);
final t0 = now.millisecondsSinceEpoch;

Map<String, Object?> seat(int i, String uid, {bool bot = false, int? stack}) => {
      'seatIndex': i, 'uid': uid, 'username': 'U$i', 'avatar': 'avatar0${i + 1}', 'isBot': bot, 'rankTier': 'gold',
      'status': i == 2 ? 'sittingOut' : 'active', 'joinedAtMs': t0 - 1000, 'missedRounds': i, 'stakeCents': 500 * i,
      'stackCents': stack, 'powerUsed': i == 1 ? 'zeroShield' : null, 'roundNetCents': i == 0 ? 2500 : null,
      'g': {'chipColor': 'red'},
    };

Map<String, Object?> tableDoc() => {
      'tableId': 'rl-abc', 'game': 'roulette', 'name': 'Rubis', 'stakeTier': 'mid',
      'limits': {'minBetCents': 500, 'maxBetCents': 50000, 'maxRoundCents': 250000, 'extra': {'foo': 3, 'bad': 'x'}},
      'isPrivate': false, 'simManaged': true, 'status': 'open', 'phase': 'live', 'step': 'spinning',
      'phaseStartedAtMs': t0 - 4000, 'deadlineMs': t0 + 4000, 'round': 17, 'turn': {'seatIndex': 1},
      'seats': [seat(0, 'me'), seat(1, 'b1', bot: true), seat(2, 'u2'), null],
      'queue': [{'uid': 'q1', 'username': 'Q', 'joinedAtMs': t0, 'buyInCents': null}],
      'seatedUids': ['me', 'b1', 'u2'], 'humanCount': 2, 'botCount': 1, 'rankTier': 'gold',
      'dealer': {'characterId': 'camille'},
      'fairness': {'currentCommit': 'abc', 'currentHandNumber': 17, 'lastHandNumber': 16, 'lastCommit': 'def', 'lastSeed': 's16'},
      'events': [
        {'seq': 9, 'type': 'spin', 'seatIndex': null, 'atMs': t0, 'd': {'number': 17}},
        {'seq': 8, 'type': 'setBets', 'seatIndex': 0, 'atMs': t0 - 10, 'd': null},
      ],
      'eventSeq': 9,
      'markets': {'round': {'rouletteRed': 'm1', 'futureKind': 'm9'}, 'series': {'rouletteZeroSeries': 'm2'}},
      'g': {'wheel': 'european'}, 'createdAtMs': t0 - 99999, 'updatedAtMs': t0,
    };

void main() {
  group('GameTableDoc', () {
    test('every field of the contract', () {
      final t = GameTableState.fromDoc('ignored', tableDoc());
      expect(t.id, 'rl-abc');
      expect(t.game, GameId.roulette);
      expect(t.stakeTier, 'mid');
      expect((t.limits.minBetCents, t.limits.maxBetCents, t.limits.maxRoundCents), (500, 50000, 250000));
      expect(t.limits.extra, {'foo': 3});
      expect(t.simManaged, isTrue);
      expect(t.closed, isFalse);
      expect(t.phase, GamePhase.live);
      expect(t.step, 'spinning');
      expect(t.round, 17);
      expect(t.turnSeat, 1);
      expect(t.turnSeatState?.uid, 'b1');
      expect(t.seats.length, 7, reason: 'padded to GAME_SEATS');
      expect(t.seats.whereType<GameSeat>().length, 3);
      final me = t.seatOf('me')!;
      expect(me.roundNetCents, 2500);
      expect(me.g['chipColor'], 'red');
      expect(t.seats[1]!.powerUsed, PowerType.zeroShield);
      expect(t.seats[1]!.isBot, isTrue);
      expect(t.seats[2]!.sittingOut, isTrue);
      expect(t.seats[2]!.missedRounds, 2);
      expect(t.queuePositionOf('q1'), 0);
      expect(t.isQueued('me'), isFalse);
      expect(t.humanCount, 2);
      expect(t.dealerCharacterId, 'camille');
      expect(t.fairness.currentCommit, 'abc');
      expect(t.fairness.lastSeed, 's16');
      expect([for (final e in t.events) e.seq], [8, 9], reason: 'sorted by seq');
      expect(t.events.last.d['number'], 17);
      expect(t.eventsAfter(8).single.type, 'spin');
      expect(t.markets.of(MarketKind.rouletteRed), 'm1');
      expect(t.markets.of(MarketKind.rouletteZeroSeries), 'm2');
      expect(t.markets.round['futureKind'], 'm9', reason: 'unknown kinds are kept');
      expect(t.markets.all, containsAll(['m1', 'm9', 'm2']));
      expect(t.g['wheel'], 'european');
    });

    test('tolerant: garbage, missing fields, closed status, dealer from the game', () {
      final t = GameTableState.fromDoc('cr-x', {'seats': 'nope', 'phase': 'warp', 'status': 'closed', 'turn': 3, 'events': [1, 'x']});
      expect(t.game, GameId.craps);
      expect(t.seats.length, 8);
      expect(t.seats.every((s) => s == null), isTrue);
      expect(t.phase, GamePhase.idle);
      expect(t.closed, isTrue);
      expect(t.turnSeat, isNull);
      expect(t.events, isEmpty);
      expect(t.dealerCharacterId, 'marco');
      expect(t.limits.minBetCents, 100);
    });

    test('clock helpers: remaining, progress, poke after deadline + grace', () {
      final t = GameTableState.fromDoc('rl-abc', tableDoc());
      expect(t.remainingAt(now), const Duration(seconds: 4));
      expect(t.phaseProgressAt(now), closeTo(0.5, 1e-9));
      expect(t.shouldPokeAt(now.add(const Duration(seconds: 5))), isFalse);
      expect(t.shouldPokeAt(now.add(const Duration(milliseconds: 4000 + GameTiming.pokeGraceMs + 1))), isTrue);
      expect(t.remainingAt(now.add(const Duration(seconds: 10))), Duration.zero);
    });
  });

  test('bets / holes / rounds documents', () {
    final b = GameBet.fromDoc({'uid': 'me', 'seatIndex': 0, 'round': 17, 'bets': {'red': 500, 'n17': 100, 'x': 'bad'}, 'power': 'zeroShield', 'previous': {'red': 500}});
    expect(b.bets, {'red': 500, 'n17': 100});
    expect(b.totalCents, 600, reason: 'derived when absent');
    expect(b.power, PowerType.zeroShield);
    expect(b.isFor(17), isTrue);
    expect(b.isFor(18), isFalse);
    expect(GameBet.fromDoc({}, id: 'u9').uid, 'u9');

    final h = GameHole.fromDoc({'round': 4, 'cards': ['AS', 'TH'], 'createdAtMs': t0});
    expect(h.cards, ['AS', 'TH']);

    final r = GameRound.fromDoc({
      'tableId': 'ho-1', 'round': 12, 'startedAtMs': t0 - 1, 'endedAtMs': t0,
      'seats': [{'seatIndex': 0, 'uid': 'me', 'username': 'Me', 'isBot': false, 'stakedCents': 200, 'netCents': -200}],
      'result': {'pot': 400},
      'fairness': {'commit': sha256Hex('s'), 'seed': 's', 'remainingBefore': null, 'dealt': null, 'decks': null},
    });
    expect(r.game, GameId.holdem);
    expect(r.seatOf('me')?.netCents, -200);
    expect(r.result['pot'], 400);
    expect(r.fairness.dealt, isNull);
    expect(GameRound.fromDoc({}, id: '00000042').round, 42);
    expect(GameRound.docId(42), '00000042');
  });

  test('callable responses', () {
    final j = GameJoinResult.fromResponse({'tableId': 't-private-abc', 'game': 'blackjack', 'status': 'seated', 'seatIndex': 1, 'code': 'ABC123'});
    expect(j.game, GameId.blackjack, reason: 'joinCode may land on another game');
    expect(j.seated, isTrue);
    expect(GameJoinResult.fromResponse({'tableId': 'cr-1', 'status': 'queued'}).game, GameId.craps);
    expect(GameJoinResult.fromResponse({'tableId': 'cr-1', 'status': 'queued'}).seated, isFalse);
    final lv = GameLeaveResult.fromResponse({'left': true, 'refundedCents': 500, 'cashOutCents': 12000, 'deferred': true});
    expect((lv.refundedCents, lv.cashOutCents, lv.deferred), (500, 12000, true));
    final a = GameActionResult.fromResponse({'phase': 'betting', 'round': 3, 'balanceCents': 9000, 'stackCents': null, 'data': {'bets': {}}});
    expect((a.phase, a.round, a.balanceCents, a.stackCents), (GamePhase.betting, 3, 9000, null));
    expect(a.data, {'bets': {}});
    final p = GamePokeResult.fromResponse({'phase': 'settled', 'round': 3, 'deadlineMs': t0, 'advanced': true});
    expect((p.phase, p.advanced, p.deadline), (GamePhase.settled, true, now));
  });

  test('payloads follow GameJoinRequest / GameActionRequest (optional fields omitted)', () {
    expect(Payloads.gameJoin(GameId.roulette, GameJoinMode.quick, 'low'), {'game': 'roulette', 'mode': 'quick', 'stakeTier': 'low'});
    expect(Payloads.gameJoin(GameId.holdem, GameJoinMode.createPrivate, 'mid', buyInCents: 40000),
        {'game': 'holdem', 'mode': 'createPrivate', 'stakeTier': 'mid', 'buyInCents': 40000});
    expect(Payloads.gameJoin(GameId.craps, GameJoinMode.joinCode, 'low', code: ' ab12cd '),
        {'game': 'craps', 'mode': 'joinCode', 'stakeTier': 'low', 'code': 'AB12CD'});
    expect(Payloads.gameJoin(GameId.craps, GameJoinMode.quick, 'low', code: 'AB12CD'), isNot(contains('code')));
    expect(() => Payloads.gameJoin(GameId.blackjack, GameJoinMode.quick, 'low'), throwsArgumentError);
    expect(Payloads.gameAction('rl-1', 4, {'type': 'sitOut'}), {'tableId': 'rl-1', 'round': 4, 'action': {'type': 'sitOut'}});
    expect(() => Payloads.gameAction('rl-1', 4, {'bets': {}}), throwsArgumentError);
    expect(Payloads.setBetsAction({'red': 500, 'black': 0}), {'type': 'setBets', 'bets': {'red': 500}});
    expect(Payloads.setBetsAction({}, power: PowerType.safetyNet), {'type': 'setBets', 'bets': {}, 'power': 'safetyNet'});
    expect(Payloads.gameLeave('x'), {'tableId': 'x'});
    expect(Payloads.gamePoke('x'), {'tableId': 'x'});
    expect(FirestorePaths.anyTable('bc-1'), 'gameTables/bc-1');
    expect(FirestorePaths.anyTable('sim-01'), 'tables/sim-01');
    expect(FirestorePaths.gameRounds('bc-1'), 'gameTables/bc-1/rounds');
    expect(FirestorePaths.gameHole('ho-1', 'u'), 'gameTables/ho-1/holes/u');
  });

  test('LiveTable.game and gameTables documents in the lobby', () {
    final l = LiveTable.fromDoc(tableDoc());
    expect(l.game, GameId.roulette);
    expect((l.minBetCents, l.maxBetCents, l.handNumber, l.seatsTotal), (500, 50000, 17, 7));
    expect(l.phase, ServerTablePhase.playerTurns);
    expect(l.hasMarket, isTrue);
    expect(l.humans, 2);
    final bj = LiveTable.fromDoc({'tableId': 'sim-01', 'minBetCents': 100, 'maxBetCents': 10000, 'handNumber': 5});
    expect((bj.game, bj.seatsTotal, bj.handNumber), (GameId.blackjack, 5, 5));
  });

  test('profiles: gameStats per kernel game, title, blackjack adapted from stats', () {
    final p = PlayerProfile.fromDoc({
      'uid': 'u', 'username': 'U', 'title': 'rv_camille_title',
      'stats': {'handsPlayed': 10, 'handsWon': 4, 'handsLost': 5, 'handsPushed': 1, 'blackjacks': 2, 'netCents': 100, 'biggestWinCents': 900},
      'gameStats': {
        'craps': {'rounds': 5, 'won': 2, 'lost': 3, 'netCents': -100, 'biggestWinCents': 700, 'counters': {'pointsMade': 1}},
        'blackjack': {'rounds': 99},
        'warp': {'rounds': 1},
      },
    });
    expect(p.title, 'rv_camille_title');
    expect(p.gameStats.keys, [GameId.craps]);
    expect(p.statsFor(GameId.craps).counters, {'pointsMade': 1});
    expect(p.statsFor(GameId.roulette).isEmpty, isTrue);
    final bj = p.statsFor(GameId.blackjack);
    expect((bj.rounds, bj.won, bj.lost, bj.netCents, bj.biggestWinCents), (10, 4, 5, 100, 900));
    expect(bj.counters, {'blackjacks': 2, 'pushes': 1});
    expect(PlayerProfile.fromDoc({'uid': 'x'}).title, isNull);
  });

  test('default fairness check: commitment, and the re-deal when cards are given', () {
    GameRound round(String seed, {String? commit, List<String>? remaining, List<String>? dealt, int? decks}) => GameRound.fromDoc({
          'tableId': 'bc-1',
          'round': 1,
          'fairness': {'commit': commit ?? sha256Hex(seed), 'seed': seed, 'remainingBefore': remaining, 'dealt': dealt, 'decks': decks},
        });
    expect(verifyRoundCommit(round('abc')), FairnessVerdict.verified);
    expect(verifyRoundCommit(round('abc', commit: sha256Hex('abd'))), FairnessVerdict.badCommit);
    expect(verifyRoundCommit(round('')), FairnessVerdict.badCommit);
    final deck = buildWireShoe(1);
    final order = fairDealOrder(deck, 'seed-1', decks: 1);
    expect(verifyRoundCommit(round('seed-1', remaining: deck, dealt: order.take(9).toList(), decks: 1)), FairnessVerdict.verified);
    expect(verifyRoundCommit(round('seed-1', remaining: deck, dealt: [order[1], order[0]], decks: 1)), FairnessVerdict.badOrder);
    expect(verifiesDraw(round('seed-1', remaining: deck, dealt: order.take(2).toList())), isTrue);
    expect(verifiesDraw(round('abc')), isFalse);
  });

  group('fake repository', () {
    late FakeWalletRepository wallet;
    late FakeGameTableRepository repo;
    setUp(() {
      wallet = FakeWalletRepository(() => now);
      repo = FakeGameTableRepository(now: () => now, wallet: wallet);
    });

    test('lists the public tables of one game, by tier', () async {
      final all = await repo.watchLiveTables(GameId.roulette).first;
      expect(all.map((t) => t.id), containsAll(['rl-sim-01', 'rl-sim-02']));
      expect(all.every((t) => t.game == GameId.roulette), isTrue);
      expect((await repo.watchLiveTables(GameId.roulette, tierId: 'mid').first).map((t) => t.id), ['rl-sim-02']);
      expect(await repo.watchLiveTables(GameId.blackjack).first, isEmpty);
    });

    test('quick join seats me; setBets debits only the difference (ledger bet / refund); leave refunds', () async {
      final j = await repo.join(game: GameId.roulette, mode: GameJoinMode.quick, stakeTier: 'low', idempotencyKey: 'k1');
      expect(j.tableId, 'rl-sim-01');
      final t = await repo.watchTable(j.tableId).first;
      expect(t.seatOf(repo.myUid)?.seatIndex, j.seatIndex);
      // Same key → same answer (idempotency).
      expect((await repo.join(game: GameId.roulette, mode: GameJoinMode.quick, stakeTier: 'low', idempotencyKey: 'k1')).tableId, j.tableId);
      final before = wallet.balanceCents;
      await repo.setBets(j.tableId, t.round, {'red': 500, 'n17': 100}, idempotencyKey: 'b1');
      expect(wallet.balanceCents, before - 600);
      await repo.setBets(j.tableId, t.round, {'red': 500}, idempotencyKey: 'b2');
      expect(wallet.balanceCents, before - 500);
      final ledger = await wallet.watchLedger().first;
      expect(ledger.first.kind, LedgerKind.refund);
      expect(ledger[1].kind, LedgerKind.bet);
      final mine = (await repo.watchBets(j.tableId).first).where((b) => b.uid == repo.myUid).single;
      expect(mine.bets, {'red': 500});
      await expectLater(
        repo.setBets(j.tableId, t.round - 1, {'red': 500}, idempotencyKey: 'b3'),
        throwsA(isA<RepositoryException>().having((e) => e.reason, 'reason', ServerReason.STALE_HAND)),
      );
      final left = await repo.leave(j.tableId);
      expect(left.refundedCents, 500);
      expect(wallet.balanceCents, before);
      expect(repo.calls.first, 'join:roulette/quick/low');
    });

    test("hold'em buy-in is checked and debited; joinCode may land on a blackjack table", () async {
      await expectLater(
        repo.join(game: GameId.holdem, mode: GameJoinMode.quick, stakeTier: 'low', idempotencyKey: 'h1'),
        throwsA(isA<RepositoryException>().having((e) => e.reason, 'reason', ServerReason.BUY_IN_OUT_OF_RANGE)),
      );
      final before = wallet.balanceCents;
      final j = await repo.join(game: GameId.holdem, mode: GameJoinMode.quick, stakeTier: 'low', buyInCents: 20000, idempotencyKey: 'h2');
      expect(wallet.balanceCents, before - 20000);
      expect((await repo.watchTable(j.tableId).first).seatOf(repo.myUid)?.stackCents, 20000);
      expect((await repo.watchMyHole(j.tableId).first)?.cards, ['AS', 'KD']);
      final code = await repo.join(game: GameId.roulette, mode: GameJoinMode.joinCode, code: 'abc123', idempotencyKey: 'c1');
      expect(code.game, GameId.blackjack);
      await expectLater(
        repo.join(game: GameId.roulette, mode: GameJoinMode.joinCode, code: 'ZZZ999', idempotencyKey: 'c2'),
        throwsA(isA<RepositoryException>().having((e) => e.reason, 'reason', ServerReason.BAD_CODE)),
      );
      final priv = await repo.join(game: GameId.craps, mode: GameJoinMode.createPrivate, stakeTier: 'mid', idempotencyKey: 'p1');
      expect(priv.code, hasLength(6));
      final t = await repo.watchTable(priv.tableId).first;
      expect((t.isPrivate, t.game, t.seatOf(repo.myUid) != null), (true, GameId.craps, true));
    });

    test('fake rounds carry valid commitments', () {
      final table = FakeGameData.tableDoc('bc-sim-01', now);
      final rounds = FakeGameData.rounds(table, now);
      expect(rounds, isNotEmpty);
      for (final r in rounds) {
        expect(verifyRoundCommit(r), FairnessVerdict.verified);
      }
      expect(FakeGameData.bets(FakeGameData.tableDoc('ho-sim-01', now)), isEmpty);
    });
  });
}
