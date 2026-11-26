/**
 * Generic kernel (GameTableMachine) driven by the test-only modules: coin (bet boards) and duel
 * (stacks). Deterministic scenarios; the randomized invariants are in kernel.property.test.ts.
 */
import { describe, expect, it } from 'vitest';
import { seededRng, sha256Hex } from '../../../src/engine';
import { planSetBets } from '../../../src/games/kernel/bets';
import { GameTableMachine } from '../../../src/games/kernel/machine';
import { defaultRankOutcome, defineGameModule } from '../../../src/games/kernel/module';
import { applyRankOutcome } from '../../../src/games/kernel/rank';
import { unavailableModule } from '../../../src/games/kernel/unavailable';
import { availableGames, gameModule, moduleOfTableId, overrideGameModuleForTests, PRODUCTION_GAME_MODULES } from '../../../src/games/registry';
import { coinModule, coinReturn, sideOf } from '../../../src/games/testing/coin';
import { duelModule } from '../../../src/games/testing/duel';
import {
  GAME_EVENTS_CAP, GAME_MISSED_ROUNDS_LIMIT, GAME_SEATS, GAME_TIMING, RANK_POINTS_DAILY_CAP_PER_GAME, type GameSeatSettlement,
} from '../../../src/shared/games/common';
import type { ProfileDoc } from '../../../src/shared/types';
import { DECISION_GRACE_MS } from '../../../src/shared/types';
import { BOTS, FREE_BOTS, gameSimRoster, gameSimTableId } from '../../../src/sim/profiles';
import { bot, human, reasonOf, World } from './harness';

const coin = () => coinModule({ game: 'roulette' });

function seatedWorld(n = 2, opts: ConstructorParameters<typeof World>[1] = {}): World {
  const w = new World(coin(), opts);
  for (let i = 1; i <= n; i++) {
    w.fund(`h${i}`, 100_000);
    w.tx((m) => m.join(human(i)));
  }
  return w;
}

describe('registry and stubs', () => {
  it('every game has a module file; phase-A stubs are unavailable and safe', () => {
    for (const g of ['roulette', 'baccarat', 'holdem', 'craps'] as const) {
      expect(PRODUCTION_GAME_MODULES[g].game).toBe(g);
      expect(PRODUCTION_GAME_MODULES[g].available).toBe(false);
    }
    expect(availableGames()).toEqual([]);
    expect(moduleOfTableId('sim-01')).toBeNull();
    expect(moduleOfTableId('rl-abc')!.game).toBe('roulette');
    overrideGameModuleForTests('baccarat', coinModule({ game: 'baccarat' }));
    expect(gameModule('baccarat').available).toBe(true);
    expect(availableGames()).toEqual(['baccarat']);
    overrideGameModuleForTests('baccarat', null);
    expect(gameModule('baccarat').available).toBe(false);
  });

  it('a stub refuses to seat anyone (FEATURE_UNAVAILABLE)', () => {
    const w = new World(unavailableModule('craps'));
    w.fund('h1', 1000);
    expect(reasonOf(() => w.tx((m) => m.join(human(1))))).toBe('FEATURE_UNAVAILABLE');
  });

  it('an open table whose game is withdrawn closes at its next transaction and refunds every board (locked ones included)', () => {
    const w = seatedWorld(2);
    w.setBets('h1', { heads: 500 });
    w.setBets('h2', { edge: 300 });
    w.expire(); // betting closed: boards are locked, coin is flipping
    expect(w.pub.phase).toBe('live');
    const stub = unavailableModule('roulette');
    const m = new GameTableMachine(w.pub, w.priv, w.boards, stub, w.deps, w.now);
    expect(m.advance()).toBe(true);
    expect(m.pub.status).toBe('closed');
    const credits = m.effects.filter((e) => e.kind === 'credit');
    expect(credits).toEqual(expect.arrayContaining([
      expect.objectContaining({ uid: 'h1', cents: 500, ledger: 'refund' }),
      expect.objectContaining({ uid: 'h2', cents: 300, ledger: 'refund' }),
    ]));
    expect([...m.dirtyBoards].sort()).toEqual(['h1', 'h2']);
    expect(m.boards.size).toBe(0);
  });
});

describe('lifecycle: seats, commit, betting, close, settle', () => {
  it('joining an idle table opens round 1 with a commitment, a market, betting deadline; location effect', () => {
    const w = new World(coin());
    w.fund('h1', 10_000);
    expect(w.tx((m) => m.join(human(1)))).toEqual({ status: 'seated', seatIndex: 0 });
    expect(w.pub.phase).toBe('betting');
    expect(w.pub.round).toBe(1);
    expect(w.pub.deadlineMs).toBe(w.now + 20_000);
    expect(w.pub.fairness.currentCommit).toBe(sha256Hex(w.priv.seed!));
    expect(w.pub.seats).toHaveLength(GAME_SEATS.roulette);
    expect(w.pub.dealer.characterId).toBe('camille');
    expect(w.ofKind('marketCreate').map((e) => [e.market.kind, e.market.game, e.market.marketId])).toEqual([['rouletteRed', 'roulette', 'rl-t1__r1__rouletteRed']]);
    expect(w.ofKind('location')).toEqual([{ kind: 'location', uid: 'h1', tableId: 'rl-t1' }]);
    expect(JSON.stringify(w.pub)).not.toContain(w.priv.seed!);
  });

  it('a full round: boards locked at the deadline, provably-fair draw, markets closed+resolved in that transaction, payout at settle', () => {
    const w = seatedWorld(2);
    w.setBets('h1', { heads: 1_000, edge: 200 });
    w.setBets('h2', { tails: 500 });
    expect(w.wallets.get('h1')).toBe(100_000 - 1_200);
    const seed = w.priv.seed!;
    w.expire();
    expect(w.pub.phase).toBe('live');
    const n = seededRng(seed).nextInt(37);
    expect((w.pub.g as { outcome: number }).outcome).toBe(n);
    expect(w.pub.seats[0]!.stakeCents).toBe(1_200);
    const st = w.ofKind('marketStatus', w.last).map((e) => e.status);
    expect(st).toEqual(['closed', 'resolved']);
    expect(w.pub.markets.round).toEqual({});
    // setBets refused once betting closed
    expect(reasonOf(() => w.setBets('h2', { tails: 600 }))).toBe('BAD_PHASE');
    w.expire();
    expect(w.pub.phase).toBe('settled');
    const ret1 = coinReturn({ heads: 1_000, edge: 200 }, n, false);
    const ret2 = coinReturn({ tails: 500 }, n, false);
    expect(w.wallets.get('h1')).toBe(100_000 - 1_200 + ret1);
    expect(w.wallets.get('h2')).toBe(100_000 - 500 + ret2);
    expect(w.nets.get('h1')).toBe(ret1 - 1_200);
    const hist = w.ofKind('history')[0].doc;
    expect(hist.fairness.seed).toBe(seed);
    expect(hist.fairness.commit).toBe(sha256Hex(seed));
    expect(hist.result).toEqual({ n, side: sideOf(n) });
    expect(w.pub.fairness).toMatchObject({ lastHandNumber: 1, lastSeed: seed, lastCommit: sha256Hex(seed) });
    // boards emptied, previous kept for "Rejouer"
    expect(w.boards.get('h1')).toMatchObject({ bets: {}, totalCents: 0, previous: { heads: 1_000, edge: 200 } });
    w.expire();
    expect(w.pub.round).toBe(2);
    expect(w.pub.phase).toBe('betting');
    expect(w.pub.events.every((e) => e.atMs === w.now)).toBe(true); // events were reset with the round
  });

  it('setBets: whole board diff, validation and powers', () => {
    const w = seatedWorld(1);
    const r = w.pub.round;
    expect(w.setBets('h1', { heads: 1_000 }).debitCents).toBe(1_000);
    const p2 = w.setBets('h1', { heads: 400, tails: 100 });
    expect([p2.debitCents, p2.refundCents]).toEqual([0, 500]);
    expect(w.wallets.get('h1')).toBe(100_000 - 500);
    expect(reasonOf(() => w.setBets('h1', { zero: 100 }))).toBe('BAD_BET_SPOT');
    expect(reasonOf(() => w.setBets('h1', { heads: 150 }))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => w.setBets('h1', { heads: 10_100 }))).toBe('BET_OUT_OF_RANGE'); // per spot
    expect(reasonOf(() => w.setBets('h1', { heads: 10_000, tails: 10_000, edge: 10_000, x: 0 }))).toBe('NO_ERROR'); // 0 = remove
    expect(reasonOf(() => w.setBets('h1', { heads: 10_000, tails: 10_000, edge: 10_000 }))).toBe('NO_ERROR');
    expect(w.boardTotal('h1')).toBe(30_000);
    expect(reasonOf(() => w.setBets('h1', {}, undefined, r + 1))).toBe('STALE_HAND');
    expect(reasonOf(() => w.setBets('h9', { heads: 100 }))).toBe('NOT_SEATED');
    expect(reasonOf(() => w.setBets('h1', { heads: 100 }, 'freeCommission'))).toBe('WRONG_GAME');
    expect(reasonOf(() => w.setBets('h1', { heads: 100 }, 'zeroShield'))).toBe('POWER_NOT_OWNED');
    w.inventory.set('h1:zeroShield', 1);
    expect(reasonOf(() => w.setBets('h1', { edge: 100 }, 'zeroShield'))).toBe('POWER_NOT_APPLICABLE');
    expect(w.setBets('h1', { heads: 100 }, 'zeroShield').powerConsumed).toBe('zeroShield');
    expect(w.inventory.get('h1:zeroShield')).toBe(0);
    // the power stays attached for the round; sending it again does not consume another one
    expect(w.setBets('h1', { heads: 200 }, 'zeroShield').powerConsumed).toBeNull();
    expect(w.setBets('h1', { heads: 300 }).doc.power).toBe('zeroShield');
    expect(w.wallets.get('h1')).toBe(100_000 - 300);
    // late: after the deadline + the human grace
    w.now = w.pub.deadlineMs! + DECISION_GRACE_MS - 1;
    expect(reasonOf(() => w.setBets('h1', { heads: 400 }))).toBe('NO_ERROR');
    w.now += 2;
    expect(reasonOf(() => w.setBets('h1', { heads: 500 }))).toBe('BAD_PHASE');
  });

  it('a min-total board and a max-total board', () => {
    const w = new World(coinModule({ game: 'roulette' }), { stakeTier: 'mid' });
    w.fund('h1', 1_000_000);
    w.tx((m) => m.join(human(1)));
    expect(reasonOf(() => w.setBets('h1', { heads: 100 }))).toBe('BET_OUT_OF_RANGE'); // below mid minimum ($5)
    expect(reasonOf(() => w.setBets('h1', { heads: 500 }))).toBe('NO_ERROR');
    expect(reasonOf(() => w.setBets('h1', { heads: 50_000, tails: 50_000, edge: 50_000 }))).toBe('NO_ERROR');
    expect(reasonOf(() => w.setBets('h1', {}))).toBe('NO_ERROR'); // clearing the board is always allowed
    expect(w.wallets.get('h1')).toBe(1_000_000);
  });

  it('nobody bets: betting restarts in the same round; missed rounds remove the human; the table then closes', () => {
    const w = seatedWorld(1);
    w.fund('h2', 100);
    for (let k = 0; k < GAME_MISSED_ROUNDS_LIMIT; k++) {
      expect(w.pub.round).toBe(1);
      w.expire();
    }
    expect(w.pub.status).toBe('closed');
    expect(w.seat('h1')).toBeNull();
    expect(w.ofKind('location').at(-1)).toEqual({ kind: 'location', uid: 'h1', tableId: null });
  });

  it('a private table waiting for friends does not count missed rounds', () => {
    const w = seatedWorld(1, { isPrivate: true });
    for (let k = 0; k < GAME_MISSED_ROUNDS_LIMIT + 3; k++) w.expire();
    expect(w.pub.status).toBe('open');
    expect(w.seat('h1')!.missedRounds).toBe(0);
  });

  it('leaving during betting refunds the board; leaving during the flip waits for the settlement', () => {
    const w = seatedWorld(2);
    w.setBets('h1', { heads: 700 });
    expect(w.tx((m) => m.leave('h1'))).toEqual({ refundedCents: 700, cashOutCents: 0, deferred: false });
    expect(w.wallets.get('h1')).toBe(100_000);
    expect(w.seat('h1')).toBeNull();
    expect(w.boards.has('h1')).toBe(false);
    w.fund('h3', 10_000);
    w.tx((m) => m.join(human(3)));
    w.setBets('h3', { tails: 1_000 });
    w.setBets('h2', { heads: 100 });
    w.expire();
    expect(w.pub.phase).toBe('live');
    expect(w.tx((m) => m.leave('h3'))).toEqual({ refundedCents: 0, cashOutCents: 0, deferred: true });
    expect(w.seat('h3')!.status).toBe('leaving');
    expect(w.ofKind('location', w.last)).toEqual([{ kind: 'location', uid: 'h3', tableId: null }]);
    expect(reasonOf(() => w.tx((m) => m.action('h3', w.pub.round, { type: 'cheer' })))).toBe('NOT_SEATED');
    w.expire(); // settles: h3 is paid although leaving
    const n = (w.pub.g as { outcome: number }).outcome;
    expect(w.wallets.get('h3')).toBe(10_000 - 1_000 + coinReturn({ tails: 1_000 }, n, false));
    w.expire(); // next round: the leaving seat is removed, without touching its owner's location again
    expect(w.seat('h3')).toBeNull();
    expect(w.ofKind('location', w.last).some((e) => e.uid === 'h3')).toBe(false);
  });

  it('the last human leaving closes a matchmaking table: bots removed, markets voided', () => {
    const w = new World(coin());
    w.fund('h1', 10_000);
    w.tx((m) => { m.join(bot(50)); m.join(bot(51)); });
    expect(w.pub.phase).toBe('idle'); // bots alone must not open (and close) a fresh table
    w.tx((m) => m.join(human(1)));
    expect(w.pub.phase).toBe('betting');
    w.tx((m) => m.leave('h1'));
    expect(w.pub.status).toBe('closed');
    expect(w.pub.botCount).toBe(0);
    expect(w.ofKind('marketStatus', w.last).map((e) => e.status)).toEqual(['void']);
  });

  it('bots yield their seat to humans during betting; mid-round humans are queued then seated', () => {
    const w = new World(coin());
    w.tx((m) => { for (let i = 0; i < GAME_SEATS.roulette; i++) m.join(bot(48 + (i % 12))); });
    w.fund('h1', 10_000);
    w.tx((m) => m.join(human(1)));
    expect(w.pub.humanCount).toBe(1);
    expect(w.pub.botCount).toBe(GAME_SEATS.roulette - 1);
    w.setBets('h1', { heads: 100 });
    w.expire();
    expect(w.pub.phase).toBe('live');
    w.fund('h2', 10_000);
    expect(w.tx((m) => m.join(human(2)))).toEqual({ status: 'queued', seatIndex: null });
    expect(w.pub.queue.map((q) => q.uid)).toEqual(['h2']);
    w.until((t) => t.phase === 'betting');
    expect(w.seat('h2')).not.toBeNull();
    expect(w.pub.queue).toEqual([]);
  });

  it('a private table is never completed with bots and refuses a full table', () => {
    const w = new World(coin(), { isPrivate: true });
    for (let i = 1; i <= GAME_SEATS.roulette; i++) { w.fund(`h${i}`, 100); w.tx((m) => m.join(human(i))); }
    w.fund('h99', 100);
    expect(reasonOf(() => w.tx((m) => m.join(human(99))))).toBe('TABLE_FULL');
  });

  it('events are reset each round and capped at GAME_EVENTS_CAP (seq keeps growing)', () => {
    const w = seatedWorld(1);
    for (let i = 0; i < GAME_EVENTS_CAP + 30; i++) w.tx((m) => m.action('h1', w.pub.round, { type: 'cheer' }));
    expect(w.pub.events).toHaveLength(GAME_EVENTS_CAP);
    expect(w.pub.events.at(-1)!.seq).toBe(w.pub.eventSeq);
    expect(reasonOf(() => w.tx((m) => m.action('h1', w.pub.round, { type: 'cheer', x: 1 })))).toBe('INVALID_ARGUMENT');
    expect(reasonOf(() => w.tx((m) => m.action('h1', w.pub.round, { type: 'dance' })))).toBe('INVALID_ARGUMENT');
    expect(reasonOf(() => w.tx((m) => m.action('h1', w.pub.round - 1, { type: 'cheer' })))).toBe('STALE_HAND');
    expect(reasonOf(() => w.tx((m) => m.action('h1', w.pub.round, { type: 'sitOut' })))).toBe('ILLEGAL_ACTION');
  });

  it('sim tables: series markets only there; bots come and go within their roster', () => {
    const id = gameSimTableId('rl', 0);
    const w = new World(coin(), { tableId: id, simManaged: true });
    const roster = gameSimRoster(id)!;
    w.tx((m) => { for (const b of roster.slice(0, 3)) m.join(bot(BOTS.indexOf(b))); });
    expect(w.pub.phase).toBe('betting');
    expect(Object.keys(w.pub.markets.series)).toEqual(['rouletteZeroSeries']);
    const seen = new Set<string>();
    for (let k = 0; k < 120; k++) {
      w.expire();
      for (const s of w.pub.seats) if (s) seen.add(s.uid);
      expect(w.pub.status).toBe('open');
    }
    for (const uid of seen) expect(roster.some((b) => b.uid === uid)).toBe(true);
    expect(w.pub.round).toBeGreaterThan(20);
    const statuses = w.ofKind('marketStatus').filter((e) => e.marketId.includes('__w')).map((e) => e.status);
    expect(statuses).toContain('resolved');
    const plain = new World(coin());
    plain.fund('h1', 100);
    plain.tx((m) => m.join(human(1)));
    expect(plain.pub.markets.series).toEqual({});
  });
});

describe('stack games (duel)', () => {
  const duel = () => duelModule({ game: 'holdem' });

  it('buy-in validated and debited at join; queued buy-ins credited back when leaving the queue', () => {
    const w = new World(duel(), { tableId: 'ho-t1' });
    w.fund('h1', 50_000);
    expect(reasonOf(() => w.tx((m) => m.join(human(1))))).toBe('BUY_IN_REQUIRED');
    expect(reasonOf(() => w.tx((m) => m.join(human(1), 999)))).toBe('BUY_IN_OUT_OF_RANGE');
    expect(reasonOf(() => w.tx((m) => m.join(human(1), 10_000)))).toBe('BUY_IN_OUT_OF_RANGE'); // > 50 antes
    expect(reasonOf(() => w.tx((m) => m.join(human(1), 2_050)))).toBe('BUY_IN_OUT_OF_RANGE'); // whole dollars
    w.fund('h2', 500);
    expect(reasonOf(() => w.tx((m) => m.join(human(2), 1_000)))).toBe('INSUFFICIENT_FUNDS');
    expect(w.seat('h2')).toBeNull(); // rolled back
    expect(w.tx((m) => m.join(human(1), 2_000)).status).toBe('seated');
    expect(w.wallets.get('h1')).toBe(48_000);
    expect(w.seat('h1')!.stackCents).toBe(2_000);
    expect(w.pub.phase).toBe('idle'); // one player cannot start a hand
  });

  it('a hand: antes from stacks (no wallet debit at a deadline), private cards, turns, timeouts, showdown zero-sum', () => {
    const w = new World(duel(), { tableId: 'ho-t1' });
    for (const i of [1, 2, 3]) { w.fund(`h${i}`, 10_000); w.tx((m) => m.join(human(i), 5_000)); }
    expect(w.pub.phase).toBe('live');
    expect(w.ofKind('secret').map((e) => e.uid).sort()).toEqual(['h1', 'h2']);
    const turn = w.pub.seats[w.pub.turn!.seatIndex]!;
    const other = w.pub.seats.find((s) => s && s.uid !== turn.uid && (s.g as { inHand: boolean }).inHand)!;
    expect(reasonOf(() => w.tx((m) => m.action(other.uid, w.pub.round, { type: 'play' })))).toBe('NOT_YOUR_TURN');
    expect(reasonOf(() => w.tx((m) => m.action(turn.uid, w.pub.round, { type: 'rebuy', cents: 100 })))).toBe('REBUY_NOT_ALLOWED');
    w.tx((m) => m.action(turn.uid, w.pub.round, { type: 'play' }));
    const before = new Map([...w.wallets]);
    w.expire(); // the other one times out (fold): no debit ever at a deadline
    expect(w.ofKind('debit', w.last)).toEqual([]);
    expect(w.wallets).toEqual(before);
    expect(w.pub.phase).toBe('settled');
    const settle = w.ofKind('settle', w.last)[0];
    expect(settle.rows.reduce((a, r) => a + r.netCents, 0)).toBe(0);
    const stacks = w.pub.seats.filter(Boolean).reduce((a, s) => a + s!.stackCents!, 0);
    expect(stacks).toBe(15_000);
    expect(w.ofKind('marketStatus', w.last).map((e) => e.status)).toEqual(['closed', 'resolved']);
  });

  it('rebuy is the user\'s own debit; leaving mid-hand defers the cash-out to the end of the hand', () => {
    const w = new World(duel(), { tableId: 'ho-t1' });
    for (const i of [1, 2, 3]) { w.fund(`h${i}`, 10_000); w.tx((m) => m.join(human(i), 2_000)); }
    w.until((t) => t.phase === 'settled'); // the first hand started with two players
    w.expire(); // the second hand deals the three of them
    const r = w.pub.round;
    const order = (w.pub.g as unknown as { order: number[] }).order.map((i) => w.pub.seats[i]!.uid);
    expect(order).toHaveLength(3);
    const [first, second, last] = order;
    expect(w.pub.seats[w.pub.turn!.seatIndex]!.uid).toBe(first);
    const lastStack = w.seat(last)!.stackCents!;
    const lastWallet = w.wallets.get(last)!;
    const res = w.tx((m) => m.leave(last)); // leaves mid-hand: folded, cash-out deferred
    expect(res).toEqual({ refundedCents: 0, cashOutCents: 0, deferred: true });
    expect(w.seat(last)!.status).toBe('leaving');
    w.tx((m) => m.action(first, r, { type: 'play' }));
    w.tx((m) => m.action(second, r, { type: 'play' }));
    expect(w.pub.phase).toBe('settled');
    expect(w.wallets.get(last)).toBe(lastWallet);
    w.expire();
    expect(w.seat(last)).toBeNull();
    expect(w.ofKind('credit', w.last)).toEqual([expect.objectContaining({ uid: last, cents: lastStack, ledger: 'cashOut' })]);
    expect(w.wallets.get(last)).toBe(lastWallet + lastStack);
    // rebuy between hands (the next hand started: wait for it to end)
    w.until((t) => t.phase === 'settled');
    const stack = w.seat(first)!.stackCents!;
    const wallet = w.wallets.get(first)!;
    expect(reasonOf(() => w.tx((m) => m.action(first, w.pub.round, { type: 'rebuy', cents: 1_000_000 })))).toBe('BUY_IN_OUT_OF_RANGE');
    w.tx((m) => m.action(first, w.pub.round, { type: 'rebuy', cents: 1_000 }));
    expect(w.ofKind('debit', w.last)).toEqual([expect.objectContaining({ uid: first, cents: 1_000, ledger: 'buyIn' })]);
    expect(w.wallets.get(first)).toBe(wallet - 1_000);
    expect(w.seat(first)!.stackCents).toBe(stack + 1_000);
    expect(w.tx((m) => m.leave(first))).toEqual({ refundedCents: 0, cashOutCents: stack + 1_000, deferred: false });
    expect(w.wallets.get(first)).toBe(wallet + stack);
  });

  it('two timeouts sit a player out, three hands out free the seat (stack cashed out)', () => {
    const w = new World(duel(), { tableId: 'ho-t1' });
    w.fund('h1', 10_000);
    w.tx((m) => { m.join(bot(50)); m.join(bot(51)); m.join(human(1), 2_000); });
    // the human never acts; the bots keep playing
    for (let k = 0; k < 200 && w.seat('h1') !== null; k++) w.expire();
    expect(w.seat('h1')).toBeNull();
    expect(w.ofKind('credit').filter((e) => e.uid === 'h1').map((e) => e.ledger)).toEqual(['cashOut']);
    expect(w.wallets.get('h1')! - 8_000 - w.nets.get('h1')!).toBe(2_000);
    expect(w.pub.status).toBe('closed'); // no human left on a matchmaking table
  });

  it('all humans sitting out on a private table: the table idles, seats and stacks stay theirs', () => {
    const w = new World(duel(), { tableId: 'ho-t1', isPrivate: true });
    for (const i of [1, 2, 3]) { w.fund(`h${i}`, 10_000); w.tx((m) => m.join(human(i), 2_000)); }
    for (let k = 0; k < 60 && w.pub.phase !== 'idle'; k++) w.expire();
    expect(w.pub.phase).toBe('idle');
    expect(w.pub.deadlineMs).toBeNull();
    let total = 0;
    for (const i of [1, 2, 3]) total += w.wallets.get(`h${i}`)! + w.seat(`h${i}`)!.stackCents!;
    expect(total).toBe(30_000);
  });

  it('sitIn reopens an idle table', () => {
    const w = new World(duel(), { tableId: 'ho-t1', isPrivate: true });
    for (const i of [1, 2]) { w.fund(`h${i}`, 10_000); w.tx((m) => m.join(human(i), 2_000)); }
    w.until((t) => t.phase === 'settled');
    w.tx((m) => m.action('h1', w.pub.round, { type: 'sitOut' }));
    w.expire();
    expect(w.pub.phase).toBe('idle');
    w.tx((m) => m.action('h1', w.pub.round, { type: 'sitIn' }));
    expect(w.pub.phase).toBe('live');
  });
});

describe('rank points (anti-farming, daily cap)', () => {
  const row = (staked: number, ret: number): GameSeatSettlement => ({
    uid: 'u', username: 'u', avatar: 'avatar01', isBot: false, seatIndex: 0, stakedCents: staked, returnCents: ret,
    netCents: ret - staked, counters: {}, highlight: null,
  });
  it('covering everything never counts as a win; thresholds at ±0.5× and 5× the stake', () => {
    expect(defaultRankOutcome(row(3_600, 3_600))).toBe('none'); // all 36 numbers, hit: net 0
    expect(defaultRankOutcome(row(3_700, 3_600))).toBe('none');
    expect(defaultRankOutcome(row(1_000, 1_500))).toBe('win');
    expect(defaultRankOutcome(row(1_000, 1_499))).toBe('none');
    expect(defaultRankOutcome(row(1_000, 500))).toBe('lose');
    expect(defaultRankOutcome(row(1_000, 501))).toBe('none');
    expect(defaultRankOutcome(row(100, 3_600))).toBe('bigWin');
    expect(defaultRankOutcome(row(0, 0))).toBe('none');
  });
  it('gains are capped per game and UTC day, losses always apply, never below 0', () => {
    const p = { rankPoints: 0, rankTier: 'bronze', weekId: '', weeklyPoints: 0 } as unknown as ProfileDoc;
    const day = Date.UTC(2026, 10, 26, 12);
    let granted = 0;
    for (let i = 0; i < 40; i++) granted += applyRankOutcome(p, 'roulette', 'bigWin', day).granted;
    expect(granted).toBe(RANK_POINTS_DAILY_CAP_PER_GAME);
    expect(applyRankOutcome(p, 'baccarat', 'win', day).granted).toBe(10); // other game: own cap
    expect(applyRankOutcome(p, 'roulette', 'lose', day).granted).toBe(-4);
    expect(applyRankOutcome(p, 'roulette', 'win', day).granted).toBe(0); // still capped
    expect(applyRankOutcome(p, 'roulette', 'win', day + 86_400_000).granted).toBe(10); // next day
    const q = { rankPoints: 2, rankTier: 'bronze', weekId: '', weeklyPoints: 0 } as unknown as ProfileDoc;
    applyRankOutcome(q, 'craps', 'lose', day);
    expect(q.rankPoints).toBe(0);
  });
});

describe('kernel safety nets', () => {
  it('a module that tries to move money it does not own is stopped (settlement checks)', () => {
    const base = coin();
    const greedy = defineGameModule({
      ...base,
      onDeadline: (ctx) => ctx.settle({
        rows: ctx.seats().map((s) => ({ uid: s.uid, username: s.username, avatar: s.avatar, isBot: s.isBot, seatIndex: s.seatIndex, stakedCents: 0, returnCents: 0, netCents: 0, counters: {}, highlight: null })),
        result: {}, fairness: { remainingBefore: null, dealt: null, decks: null },
      }),
    });
    const w = new World(greedy);
    w.fund('h1', 1_000);
    w.tx((m) => m.join(human(1)));
    w.setBets('h1', { heads: 500 });
    w.expire();
    expect(() => w.expire()).toThrow(/row stake must equal/);
    expect(w.pub.phase).toBe('live'); // rolled back: nothing lost
  });

  it('a bot move that throws leaves no trace and falls back to the timeout', () => {
    const base = duelModule();
    const clumsy = defineGameModule({ ...base, bot: () => ({ kind: 'action', action: { type: 'rebuy', cents: 1 } }) });
    const w = new World(clumsy, { tableId: 'ho-t1' });
    w.fund('h1', 10_000);
    w.tx((m) => { m.join(bot(FREE_BOTS.length > 0 ? BOTS.indexOf(FREE_BOTS[0]) : 50)); m.join(human(1), 2_000); });
    for (let k = 0; k < 10 && w.pub.phase === 'live'; k++) w.expire();
    expect(w.pub.phase).toBe('settled');
    expect(w.ofKind('debit').filter((e) => e.ledger === 'buyIn').map((e) => e.uid)).toEqual(['h1']);
  });

  it('a module leaving a phase without deadline is refused', () => {
    const lazy = defineGameModule({ ...coin(), openRound: () => undefined });
    const w = new World(lazy);
    w.fund('h1', 100);
    expect(() => w.tx((m) => m.join(human(1)))).toThrow(/openRound must set the phase/);
  });

  it('planSetBets never writes the table document (pure, no table mutation)', () => {
    const w = seatedWorld(1);
    const before = JSON.stringify(w.pub);
    planSetBets({ table: w.pub, module: w.module, uid: 'h1', round: w.pub.round, bets: { heads: 100 }, board: null, inventoryQty: 0, now: w.now });
    expect(JSON.stringify(w.pub)).toBe(before);
  });

  it('timing defaults', () => {
    expect(GAME_TIMING.bettingMs).toBe(20_000);
  });
});
