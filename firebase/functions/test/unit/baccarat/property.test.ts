/**
 * Property tests of the baccarat module on the kernel (fast-check): random sequences of joins,
 * leaves, boards (every spot, the power, odd amounts), clock jumps and deadlines. After EVERY step:
 *  1. money conservation for each human: wallet + board = initial + settled nets;
 *  2. no negative balance or bet;
 *  3. a transition run by a deadline never debits anybody;
 *  4. every settlement row is exactly `settleBoard(board, coup, power)` of the locked board;
 *  5. the shoe is consistent: public counters = private shoe, cards never created or lost
 *     (undealt + dealt since the shuffle = 416), beads = coups;
 *  6. a per-coup market is never open once its coup is dealt; pending phases have a deadline;
 *  7. a closed table holds nothing of any human.
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { settleBoard } from '../../../src/games/baccarat/engine';
import { baccaratModule } from '../../../src/games/baccarat/module';
import { AppError } from '../../../src/shared/errors';
import type { BaccaratPrivate, BaccaratPublic } from '../../../src/shared/games/baccarat';
import { BOTS, gameSimRoster, gameSimTableId } from '../../../src/sim/profiles';
import { bot, human, World } from '../kernel/harness';

const HUMANS = 3;
const START = 20_000; // $200 each: small, so INSUFFICIENT_FUNDS happens

type Cmd =
  | { k: 'join'; h: number }
  | { k: 'leave'; h: number }
  | { k: 'bet'; h: number; player: number; banker: number; tie: number; pp: number; bp: number; power: boolean; odd: boolean }
  | { k: 'tick'; ms: number }
  | { k: 'expire' };

const h = fc.integer({ min: 1, max: HUMANS });
const u = (max: number) => fc.integer({ min: 0, max });
const cmdArb: fc.Arbitrary<Cmd> = fc.oneof(
  { weight: 3, arbitrary: fc.record({ k: fc.constant('join' as const), h }) },
  { weight: 1, arbitrary: fc.record({ k: fc.constant('leave' as const), h }) },
  {
    weight: 5,
    arbitrary: fc.record({
      k: fc.constant('bet' as const), h, player: u(40), banker: u(40), tie: u(3), pp: u(2), bp: u(2), power: fc.boolean(), odd: u(9).map((x) => x === 0),
    }),
  },
  { weight: 2, arbitrary: fc.record({ k: fc.constant('tick' as const), ms: fc.integer({ min: 0, max: 25_000 }) }) },
  { weight: 5, arbitrary: fc.record({ k: fc.constant('expire' as const) }) },
);

function attempt(fn: () => unknown): void {
  try {
    fn();
  } catch (e) {
    if (e instanceof AppError || (e as Error)?.name === 'ZodError') return;
    throw e;
  }
}

/** Cards dealt from the current shoe so far (from the round documents since the last shuffle). */
function dealtSinceShuffle(w: World): number {
  let n = 0;
  const shoe = (w.pub.g as unknown as BaccaratPublic).shoe.n;
  for (const e of w.ofKind('history')) {
    const r = e.doc.result as { shoe?: number };
    if (r.shoe === shoe) n += e.doc.fairness.dealt?.length ?? 0;
  }
  // the coup being dealt (phase live) is not settled yet
  const proof = (w.priv.g as unknown as BaccaratPrivate).proof;
  if (proof && w.pub.phase === 'live') n += proof.dealt.length;
  return n;
}

function check(w: World, step: string, lockedBefore: Map<string, Record<string, number>>, powers: Map<string, string | null>): void {
  const ctx = `${step} (phase ${w.pub.phase}, round ${w.pub.round})`;
  const s = w.pub.g as unknown as BaccaratPublic;
  const v = w.priv.g as unknown as BaccaratPrivate;
  for (let i = 1; i <= HUMANS; i++) {
    const uid = `h${i}`;
    const wallet = w.wallets.get(uid)!;
    expect(wallet, ctx).toBeGreaterThanOrEqual(0);
    expect(wallet + w.boardTotal(uid), `${ctx} ${uid}`).toBe(START + (w.nets.get(uid) ?? 0));
  }
  for (const b of w.boards.values()) for (const c of Object.values(b.bets)) expect(c, ctx).toBeGreaterThan(0);
  // 4. exact settlement of the boards locked at the deal
  for (const e of w.ofKind('settle', w.last)) {
    const doc = w.ofKind('history', w.last).find((x) => x.doc.round === e.round)!.doc;
    const coup = doc.result as unknown as Parameters<typeof settleBoard>[1];
    for (const r of e.rows) {
      const board = lockedBefore.get(r.uid);
      expect(board, `${ctx} row ${r.uid}`).toBeDefined();
      const exp = settleBoard(board!, coup, powers.get(r.uid) === 'freeCommission');
      expect([r.stakedCents, r.returnCents, r.netCents], `${ctx} ${r.uid}`).toEqual([exp.stakedCents, exp.returnCents, exp.netCents]);
      if (!r.isBot) checkedRows++;
    }
  }
  // 5. the shoe
  if (w.pub.status === 'open') {
    expect(s.shoe.remaining, ctx).toBe(v.remaining.length);
    expect(s.beads.length, ctx).toBe(s.shoe.coups);
    expect(s.shoe.banker + s.shoe.player + s.shoe.tie, ctx).toBe(s.shoe.coups);
    expect(v.remaining.length + dealtSinceShuffle(w), ctx).toBe(416);
  }
  // 6. markets and deadlines
  const p = w.pub;
  if (p.status === 'open' && p.phase !== 'betting' && p.phase !== 'idle') expect(p.markets.round, ctx).toEqual({});
  if (p.status === 'open' && (p.phase === 'betting' || p.phase === 'live' || p.phase === 'settled')) expect(p.deadlineMs, ctx).not.toBeNull();
  if (p.status === 'open' && p.phase === 'live') expect(s.coup, ctx).not.toBeNull();
  // 7.
  if (p.status === 'closed') {
    expect(p.seats.every((x) => x === null), ctx).toBe(true);
    expect(w.boards.size, ctx).toBe(0);
  }
}

function run(w: World, cmds: Cmd[]): void {
  for (let i = 1; i <= HUMANS; i++) w.fund(`h${i}`, START);
  const locked = new Map<string, Record<string, number>>();
  const powers = new Map<string, string | null>();
  /** Snapshot of the boards right before a transition (what betting would lock). */
  const snap = () => {
    if (w.pub.phase !== 'betting') return;
    locked.clear();
    powers.clear();
    for (const [uid, b] of w.boards) {
      locked.set(uid, { ...b.bets });
      powers.set(uid, b.power);
    }
  };
  cmds.forEach((c, step) => {
    const uid = 'h' + ('h' in c ? c.h : 0);
    const label = `#${step} ${JSON.stringify(c)}`;
    switch (c.k) {
      case 'join':
        attempt(() => w.tx((m) => m.join(human(c.h))));
        break;
      case 'leave':
        attempt(() => w.tx((m) => m.leave(uid)));
        break;
      case 'bet': {
        const unit = c.odd ? 150 : 100;
        const bets: Record<string, number> = {};
        if (c.player) bets.player = c.player * unit;
        if (c.banker) bets.banker = c.banker * unit;
        if (c.tie) bets.tie = c.tie * unit;
        if (c.pp) bets.playerPair = c.pp * unit;
        if (c.bp) bets.bankerPair = c.bp * unit;
        if (c.power) w.inventory.set(`${uid}:freeCommission`, 1);
        attempt(() => w.setBets(uid, bets, c.power ? 'freeCommission' : undefined));
        break;
      }
      case 'tick':
        snap();
        w.now += c.ms;
        w.tx((m) => m.advance());
        expect(w.ofKind('debit', w.last), label).toEqual([]);
        break;
      case 'expire':
        snap();
        w.expire();
        expect(w.ofKind('debit', w.last), label).toEqual([]);
        break;
    }
    check(w, label, locked, powers);
  });
  for (let i = 1; i <= HUMANS; i++) attempt(() => w.tx((m) => m.leave(`h${i}`)));
  for (let k = 0; k < 50 && w.pub.status === 'open' && w.pub.deadlineMs !== null; k++) {
    snap();
    w.expire();
    expect(w.ofKind('debit', w.last)).toEqual([]);
    check(w, `drain ${k}`, locked, powers);
  }
  const used = w.ofKind('location').some((e) => e.tableId !== null);
  if (!w.pub.simManaged && used) {
    expect(w.pub.status).toBe('closed');
    for (let i = 1; i <= HUMANS; i++) expect(w.wallets.get(`h${i}`)).toBe(START + (w.nets.get(`h${i}`) ?? 0));
  }
}

const RUNS = Number(process.env.BACCARAT_PROPERTY_RUNS ?? 100);
/** Settled human rows checked by property 4 (the properties must not hold vacuously). */
let checkedRows = 0;

describe('baccarat properties', () => {
  it('private table (humans only)', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 5, maxLength: 80 }), fc.integer({ min: 1, max: 1e6 }), (cmds, seed) => {
      run(new World(baccaratModule, { tableId: 'bc-p1', seed, isPrivate: true }), cmds);
    }), { numRuns: RUNS });
    expect(checkedRows).toBeGreaterThan(RUNS / 4); // many runs close the table early (everybody left)
  });

  it('public table with bots', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 5, maxLength: 80 }), fc.integer({ min: 1, max: 1e6 }), (cmds, seed) => {
      const w = new World(baccaratModule, { tableId: 'bc-q1', seed });
      w.tx((m) => { m.join(bot(110)); m.join(bot(111)); });
      run(w, cmds);
    }), { numRuns: RUNS });
  });

  it('simulated table (churning bots, series market, many coups)', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 20, maxLength: 120 }), fc.integer({ min: 1, max: 1e6 }), (cmds, seed) => {
      const id = gameSimTableId('bc', 0);
      const w = new World(baccaratModule, { tableId: id, seed, simManaged: true });
      w.tx((m) => { for (const b of gameSimRoster(id)!.slice(0, 3)) m.join(bot(BOTS.indexOf(b))); });
      run(w, cmds);
    }), { numRuns: Math.max(20, RUNS / 4) });
  });
});
