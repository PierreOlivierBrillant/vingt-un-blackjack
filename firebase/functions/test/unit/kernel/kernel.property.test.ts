/**
 * Property tests of the kernel (fast-check), on the two test-only modules:
 *  - coin (bet boards: fast-path setBets, locking, settlement, carry = none),
 *  - duel (stacks: buy-in, rebuy, pot, deferred cash-out, sitting out).
 * Random sequences of player commands and clock jumps; after EVERY step:
 *  1. money conservation (humans: wallet + money on the table = initial + settled nets; duel: chips zero-sum),
 *  2. no negative balance, board amount or stack,
 *  3. a transition run by a deadline never debits anybody,
 *  4. a closed table holds nothing of any human (everything refunded / cashed out),
 *  5. no state without a legal action (pending phases have a deadline; a human on turn has a legal action).
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { GameTableMachine } from '../../../src/games/kernel/machine';
import { AppError } from '../../../src/shared/errors';
import { coinModule } from '../../../src/games/testing/coin';
import { duelModule, type DuelPublic, type DuelSeat } from '../../../src/games/testing/duel';
import type { GameSeatDoc } from '../../../src/shared/games/common';
import { BOTS, gameSimRoster, gameSimTableId } from '../../../src/sim/profiles';
import { bot, human, World } from './harness';

const HUMANS = 4;
const START = 5_000; // $50 each: small, so INSUFFICIENT_FUNDS happens

type Cmd =
  | { k: 'join'; h: number; buyIn: number }
  | { k: 'leave'; h: number }
  | { k: 'bet'; h: number; heads: number; tails: number; edge: number; power: boolean; odd: boolean }
  | { k: 'act'; h: number; pick: number }
  | { k: 'sit'; h: number; out: boolean }
  | { k: 'tick'; ms: number }
  | { k: 'expire' };

const h = fc.integer({ min: 1, max: HUMANS });
const cmdArb: fc.Arbitrary<Cmd> = fc.oneof(
  { weight: 2, arbitrary: fc.record({ k: fc.constant('join' as const), h, buyIn: fc.integer({ min: 0, max: 60 }) }) },
  { weight: 1, arbitrary: fc.record({ k: fc.constant('leave' as const), h }) },
  {
    weight: 4,
    arbitrary: fc.record({
      k: fc.constant('bet' as const), h, heads: fc.integer({ min: 0, max: 8 }), tails: fc.integer({ min: 0, max: 4 }),
      edge: fc.integer({ min: 0, max: 2 }), power: fc.boolean(), odd: fc.boolean(),
    }),
  },
  { weight: 4, arbitrary: fc.record({ k: fc.constant('act' as const), h, pick: fc.nat(3) }) },
  { weight: 1, arbitrary: fc.record({ k: fc.constant('sit' as const), h, out: fc.boolean() }) },
  { weight: 2, arbitrary: fc.record({ k: fc.constant('tick' as const), ms: fc.integer({ min: 0, max: 25_000 }) }) },
  { weight: 4, arbitrary: fc.record({ k: fc.constant('expire' as const) }) },
);

/** Runs a player command; refusals (AppError, schema errors) are fine, anything else is a kernel bug. */
function attempt(fn: () => unknown): void {
  try {
    fn();
  } catch (e) {
    if (e instanceof AppError || (e as Error)?.name === 'ZodError') return;
    throw e;
  }
}

function humanMoneyOnTable(w: World, uid: string): number {
  let t = w.pub.queue.filter((q) => q.uid === uid).reduce((a, q) => a + (q.buyInCents ?? 0), 0);
  const seat = w.seat(uid);
  if (seat) {
    t += seat.stackCents ?? 0;
    const g = seat.g as unknown as Partial<DuelSeat>;
    if (g.inHand) t += g.committed ?? 0; // duel: chips already pushed into the pot this hand
  }
  return t + w.boardTotal(uid);
}

function checkInvariants(w: World, step: string): void {
  const ctx = `${step} (phase ${w.pub.phase}, round ${w.pub.round})`;
  for (let i = 1; i <= HUMANS; i++) {
    const uid = `h${i}`;
    const wallet = w.wallets.get(uid)!;
    // 2. never negative
    expect(wallet, ctx).toBeGreaterThanOrEqual(0);
    // 1. conservation for each human
    expect(wallet + humanMoneyOnTable(w, uid), `${ctx} ${uid}`).toBe(START + (w.nets.get(uid) ?? 0));
  }
  for (const b of w.boards.values()) for (const v of Object.values(b.bets)) expect(v, ctx).toBeGreaterThan(0);
  for (const s of w.pub.seats) if (s && s.stackCents !== null) expect(s.stackCents, ctx).toBeGreaterThanOrEqual(0);
  // 4. a closed table holds nothing of any human
  if (w.pub.status === 'closed') {
    expect(w.pub.seats.every((s) => s === null), ctx).toBe(true);
    expect(w.pub.queue, ctx).toEqual([]);
    expect(w.boards.size, ctx).toBe(0);
  }
  // 5. no state without a legal action
  const p = w.pub;
  if (p.status === 'open' && (p.phase === 'betting' || p.phase === 'live' || p.phase === 'settled')) expect(p.deadlineMs, ctx).not.toBeNull();
  if (p.status === 'open' && p.phase === 'idle') expect(p.deadlineMs, ctx).toBeNull();
  if (p.status === 'open' && p.turn) {
    const s = p.seats[p.turn.seatIndex];
    expect(s, ctx).not.toBeNull();
    if (s && !s.isBot && s.status === 'active') {
      const m = new GameTableMachine(structuredClone(w.pub), structuredClone(w.priv), new Map(w.boards), w.module, w.deps, w.now);
      const legal = w.module.legalActions(m.ctx, m.pub.seats[p.turn.seatIndex]!);
      expect(legal.length, ctx).toBeGreaterThan(0);
      // every listed action is accepted
      for (const a of legal) {
        const probe = new GameTableMachine(structuredClone(w.pub), structuredClone(w.priv), new Map(w.boards), w.module, w.deps, w.now);
        expect(() => probe.action(s.uid, p.round, a), `${ctx} ${JSON.stringify(a)}`).not.toThrow();
      }
    }
  }
}

function run(w: World, cmds: Cmd[], opts: { stack: boolean }): void {
  for (let i = 1; i <= HUMANS; i++) w.fund(`h${i}`, START);
  checkInvariants(w, 'start');
  cmds.forEach((c, step) => {
    const uid = 'h' + ('h' in c ? c.h : 0);
    const label = `#${step} ${JSON.stringify(c)}`;
    switch (c.k) {
      case 'join':
        attempt(() => w.tx((m) => m.join(human(c.h), opts.stack ? c.buyIn * 100 : null)));
        break;
      case 'leave':
        attempt(() => w.tx((m) => m.leave(uid)));
        break;
      case 'bet': {
        if (opts.stack) break;
        const bets: Record<string, number> = {};
        const unit = c.odd ? 150 : 100;
        if (c.heads) bets.heads = c.heads * unit;
        if (c.tails) bets.tails = c.tails * unit;
        if (c.edge) bets.edge = c.edge * unit;
        if (c.power) w.inventory.set(`${uid}:zeroShield`, 1);
        attempt(() => w.setBets(uid, bets, c.power ? 'zeroShield' : undefined));
        break;
      }
      case 'act': {
        const seat = w.seat(uid);
        if (!seat) break;
        const m = new GameTableMachine(structuredClone(w.pub), structuredClone(w.priv), new Map(w.boards), w.module, w.deps, w.now);
        const legal = w.module.legalActions(m.ctx, m.pub.seats[seat.seatIndex]!);
        const a = legal.length > 0 ? legal[c.pick % legal.length] : { type: 'play' };
        attempt(() => w.tx((mm) => mm.action(uid, w.pub.round, a)));
        break;
      }
      case 'sit':
        attempt(() => w.tx((m) => m.action(uid, w.pub.round, { type: c.out ? 'sitOut' : 'sitIn' })));
        break;
      case 'tick':
        w.now += c.ms;
        w.tx((m) => m.advance());
        expect(w.ofKind('debit', w.last), label).toEqual([]); // 3. a deadline never debits
        break;
      case 'expire':
        w.expire();
        expect(w.ofKind('debit', w.last), label).toEqual([]);
        break;
    }
    checkInvariants(w, label);
  });
  // drain: everybody leaves, the clock runs; a non-simulated table must end closed with everything refunded
  for (let i = 1; i <= HUMANS; i++) attempt(() => w.tx((m) => m.leave(`h${i}`)));
  for (let k = 0; k < 400 && w.pub.status === 'open' && w.pub.deadlineMs !== null; k++) {
    w.expire();
    expect(w.ofKind('debit', w.last)).toEqual([]);
    checkInvariants(w, `drain ${k}`);
  }
  // (a table no human ever sat at cannot exist outside tests: gameJoin creates it with its first human)
  const used = w.ofKind('location').some((e) => e.tableId !== null);
  if (!w.pub.simManaged && used) {
    expect(w.pub.status).toBe('closed');
    for (let i = 1; i <= HUMANS; i++) expect(w.wallets.get(`h${i}`)).toBe(START + (w.nets.get(`h${i}`) ?? 0));
  }
}

const RUNS = Number(process.env.KERNEL_PROPERTY_RUNS ?? 120);

describe('kernel properties — coin (bet boards)', () => {
  it('public table with bots', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 5, maxLength: 70 }), fc.integer({ min: 1, max: 1e6 }), (cmds, seed) => {
      const w = new World(coinModule({ game: 'roulette', bettingMs: 5_000, flipMs: 1_000, settledMs: 1_000 }), { seed });
      w.tx((m) => { m.join(bot(48)); m.join(bot(49)); });
      run(w, cmds, { stack: false });
    }), { numRuns: RUNS });
  });

  it('private table (humans only)', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 5, maxLength: 70 }), fc.integer({ min: 1, max: 1e6 }), (cmds, seed) => {
      run(new World(coinModule({ game: 'roulette' }), { seed, isPrivate: true }), cmds, { stack: false });
    }), { numRuns: RUNS });
  });

  it('simulated table (churning bots, series markets)', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 5, maxLength: 70 }), fc.integer({ min: 1, max: 1e6 }), (cmds, seed) => {
      const id = gameSimTableId('rl', 1);
      const w = new World(coinModule({ game: 'roulette', bettingMs: 4_000, flipMs: 1_000, settledMs: 1_000 }), { seed, simManaged: true, tableId: id });
      w.tx((m) => { for (const b of gameSimRoster(id)!.slice(0, 3)) m.join(bot(BOTS.indexOf(b))); });
      run(w, cmds, { stack: false });
    }), { numRuns: RUNS });
  });
});

describe('kernel properties — duel (stacks, player vs player)', () => {
  const zeroSum = (w: World) => {
    for (const e of w.ofKind('settle')) expect(e.rows.reduce((a, r) => a + r.netCents, 0)).toBe(0);
    // chips on the table: stacks + pot only move between players (bots' chips are house money)
    const pot = (w.pub.g as unknown as DuelPublic).pot;
    expect(pot).toBeGreaterThanOrEqual(0);
    const inHand = w.pub.seats.filter((s): s is GameSeatDoc => !!s && !!(s.g as unknown as DuelSeat).inHand)
      .reduce((a, s) => a + (s.g as unknown as DuelSeat).committed, 0);
    if (w.pub.phase === 'live') expect(inHand).toBe(pot);
  };

  it('private table (humans only)', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 5, maxLength: 80 }), fc.integer({ min: 1, max: 1e6 }), (cmds, seed) => {
      const w = new World(duelModule({ game: 'holdem', decisionMs: 3_000, settledMs: 1_000 }), { seed, isPrivate: true, tableId: 'ho-p1' });
      run(w, cmds, { stack: true });
      zeroSum(w);
    }), { numRuns: RUNS });
  });

  it('public table with bots', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 5, maxLength: 80 }), fc.integer({ min: 1, max: 1e6 }), (cmds, seed) => {
      const w = new World(duelModule({ game: 'holdem', decisionMs: 3_000, settledMs: 1_000 }), { seed, tableId: 'ho-p2' });
      w.tx((m) => { m.join(bot(50)); m.join(bot(51)); });
      run(w, cmds, { stack: true });
      zeroSum(w);
    }), { numRuns: RUNS });
  });
});
