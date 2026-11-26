/**
 * Property tests of the craps module on the real kernel (fast-check): random sequences of joins,
 * leaves, whole boards (built from the current one: raises, removals, odds, increments…), throws
 * by anyone, clock jumps and deadlines, with bots at the table. After EVERY step:
 *  1. money conservation for each human: wallet + board = initial + settled nets;
 *  2. no negative balance or bet;
 *  3. no player command ever takes a contract bet off the board (Pass with a point, Come numbers):
 *     only a roll decides them (or the table closing, which refunds everything);
 *  4. a closed table holds nothing of any human;
 *  5. a pending phase always has a deadline (the kernel asserts it) and the shooter can act.
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { contractBets } from '../../../src/games/craps/engine';
import { AppError } from '../../../src/shared/errors';
import type { BetMap } from '../../../src/shared/games/common';
import { CRAPS_SPOT_IDS } from '../../../src/shared/games/craps';
import { FREE_BOTS } from '../../../src/sim/profiles';
import { human } from '../kernel/harness';
import { CrapsWorld } from './helpers';

const HUMANS = 4;
const START = 20_000; // $200 each: small, so INSUFFICIENT_FUNDS happens
const AMOUNTS = [0, 1, 2, 3, 5, 6, 9, 10, 12, 15, 30, 60];

type Cmd =
  | { k: 'join'; h: number }
  | { k: 'leave'; h: number }
  | { k: 'bet'; h: number; ops: Array<[number, number, number]>; power: boolean }
  | { k: 'roll'; h: number }
  | { k: 'tick'; ms: number }
  | { k: 'expire' }
  | { k: 'window' };

const h = fc.integer({ min: 1, max: HUMANS });
const cmdArb: fc.Arbitrary<Cmd> = fc.oneof(
  { weight: 1, arbitrary: fc.record({ k: fc.constant('join' as const), h }) },
  { weight: 1, arbitrary: fc.record({ k: fc.constant('leave' as const), h }) },
  { weight: 3, arbitrary: fc.record({ k: fc.constant('window' as const) }) },
  {
    weight: 9,
    arbitrary: fc.record({
      k: fc.constant('bet' as const), h,
      ops: fc.array(fc.tuple(fc.nat(9), fc.nat(60), fc.nat(60)), { minLength: 1, maxLength: 3 }),
      power: fc.integer({ min: 0, max: 4 }).map((n) => n === 0),
    }),
  },
  { weight: 3, arbitrary: fc.record({ k: fc.constant('roll' as const), h }) },
  { weight: 2, arbitrary: fc.record({ k: fc.constant('tick' as const), ms: fc.integer({ min: 0, max: 8_000 }) }) },
  { weight: 3, arbitrary: fc.record({ k: fc.constant('expire' as const) }) },
);

/** Spots most likely to matter get extra weight (indexes past the list map onto them). */
const FAVOURITES = ['pass', 'dontPass', 'come', 'odds:pass', 'place6', 'field', 'odds:come6', 'come6', 'come8'];
const spotOf = (i: number) => (i < CRAPS_SPOT_IDS.length ? CRAPS_SPOT_IDS[i] : FAVOURITES[i - CRAPS_SPOT_IDS.length]);
const DOLLARS = [1, 2, 3, 5, 6, 10, 12, 20];
const ONE_ROLL = ['field', 'any7', 'anyCraps', 'two', 'three', 'yo', 'twelve', 'hard4', 'hard6', 'hard8', 'hard10'];

/**
 * A plausible edit of the current board (most of them legal, some not): 0-1 line bet, 2 odds behind
 * an existing flat bet (up to 6×: sometimes above the maximum), 3 come / don't come, 4 place
 * (multiples of $3 or not), 5 one-roll / hardway, 6-7 take a bet down (contract bets included),
 * 8-9 any spot, any amount.
 */
function edit(next: BetMap, [op, a, b]: [number, number, number]): void {
  const amount = DOLLARS[b % DOLLARS.length] * 100;
  switch (op) {
    case 0:
    case 1:
      next[a % 2 ? 'dontPass' : 'pass'] = amount;
      break;
    case 2: {
      const flats = Object.keys(next).filter((k) => /^(pass|dontPass|comed+|dontComed+)$/.test(k));
      const base = flats.length ? flats[a % flats.length] : 'pass';
      const flat = next[base] ?? 500;
      const raw = flat * (1 + (b % 6));
      next[`odds:${base}`] = b % 3 === 0 ? Math.max(300, Math.floor(raw / 300) * 300) : raw;
      break;
    }
    case 3:
      next[a % 3 ? 'come' : 'dontCome'] = amount;
      break;
    case 4:
      next[`place${[4, 5, 6, 8, 9, 10][a % 6]}`] = (b % 2 ? 3 : 1) * (1 + (b % 5)) * 100;
      break;
    case 5:
      next[ONE_ROLL[a % ONE_ROLL.length]] = amount;
      break;
    case 6:
    case 7: {
      const keys = Object.keys(next);
      if (keys.length) delete next[keys[a % keys.length]];
      break;
    }
    default: {
      const v = AMOUNTS[b % AMOUNTS.length] * 100;
      if (v === 0) delete next[spotOf(a % (CRAPS_SPOT_IDS.length + FAVOURITES.length))];
      else next[spotOf(a % (CRAPS_SPOT_IDS.length + FAVOURITES.length))] = v;
    }
  }
}

/** Coverage of the generated runs (asserted at the end: the properties must really be exercised). */
const seen = { rolls: 0, bets: 0, contractChecks: 0, nets: 0, leavesWithContract: 0 };

const reasons: Record<string, number> = {};
function attempt(fn: () => unknown): boolean {
  try {
    fn();
    return true;
  } catch (e) {
    if (e instanceof AppError || (e as Error)?.name === 'ZodError') { const r = e instanceof AppError ? e.reason : 'ZOD'; reasons[r] = (reasons[r] ?? 0) + 1; return false; }
    throw e;
  }
}

function check(w: CrapsWorld, step: string): void {
  const ctx = `${step} (phase ${w.pub.phase}, round ${w.pub.round}, point ${w.g.point})`;
  for (let i = 1; i <= HUMANS; i++) {
    const uid = `h${i}`;
    const wallet = w.wallets.get(uid)!;
    expect(wallet, ctx).toBeGreaterThanOrEqual(0);
    expect(wallet + w.boardTotal(uid), `${ctx} ${uid}`).toBe(START + (w.nets.get(uid) ?? 0));
    for (const v of Object.values(w.board(uid))) expect(v > 0 && v % 100 === 0, ctx).toBe(true);
  }
  if (w.pub.status === 'closed') {
    for (let i = 1; i <= HUMANS; i++) expect(w.boardTotal(`h${i}`), ctx).toBe(0);
  } else if (w.pub.phase !== 'idle') {
    expect(w.pub.deadlineMs, ctx).not.toBeNull();
  }
  if (w.pub.status === 'open' && w.pub.phase === 'betting' && w.g.shooter !== null) {
    const s = w.pub.seats[w.g.shooter];
    expect(s?.uid, ctx).toBe(w.g.shooterUid);
    expect(s?.status, ctx).toBe('active');
    expect(w.pub.turn, ctx).toEqual({ seatIndex: w.g.shooter });
  }
}

function run(cmds: Cmd[], seed: number): void {
  const w = new CrapsWorld({ seed });
  for (let i = 1; i <= HUMANS; i++) {
    w.fund(`h${i}`, START);
    w.inventory.set(`h${i}:safetyNet`, 3);
  }
  for (const b of FREE_BOTS.slice(0, 2)) w.tx((m) => m.join({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true }));
  for (let i = 1; i <= HUMANS; i++) w.tx((m) => m.join(human(i)));
  cmds.forEach((c, n) => {
    const step = `#${n} ${JSON.stringify(c)}`;
    const contract = new Map<string, BetMap>();
    for (let i = 1; i <= HUMANS; i++) contract.set(`h${i}`, contractBets(w.board(`h${i}`), w.g.point));
    const wasOpen = w.pub.status === 'open';
    switch (c.k) {
      case 'join':
        attempt(() => w.tx((m) => m.join(human(c.h))));
        break;
      case 'leave':
        if (attempt(() => w.tx((m) => m.leave(`h${c.h}`))) && Object.keys(contract.get(`h${c.h}`)!).length > 0) seen.leavesWithContract++;
        break;
      case 'bet': {
        const next: BetMap = { ...w.board(`h${c.h}`) };
        for (const o of c.ops) edit(next, o);
        if (attempt(() => w.setBets(`h${c.h}`, next, c.power ? 'safetyNet' : undefined))) seen.bets++;
        break;
      }
      case 'roll':
        attempt(() => w.roll(`h${c.h}`));
        break;
      case 'tick':
        w.tick(c.ms);
        break;
      case 'expire':
        w.expire();
        break;
      case 'window':
        for (let i = 0; i < 4 && w.pub.status === 'open' && w.pub.phase !== 'betting' && w.pub.deadlineMs !== null; i++) w.expire();
        break;
    }
    if (c.k !== 'tick' && c.k !== 'expire' && c.k !== 'window' && wasOpen && w.pub.status === 'open') {
      // 3. a player's own command never takes a contract bet down
      for (const [uid, bets] of contract) {
        for (const [spot, v] of Object.entries(bets)) {
          expect(w.board(uid)[spot], `${step} ${uid} ${spot}`).toBe(v);
          seen.contractChecks++;
        }
      }
    }
    seen.rolls += w.ofKind('history', w.last).filter((e) => !(e.doc.result as { noRoll: boolean }).noRoll).length;
    seen.nets += w.pub.events.filter((e) => e.type === 'power').length;
    check(w, step);
  });
  // drain: every human leaves, the deadlines alone settle what is left
  for (let i = 1; i <= HUMANS; i++) attempt(() => w.tx((m) => m.leave(`h${i}`)));
  for (let i = 0; i < 400 && w.pub.status === 'open' && w.pub.seats.some((s) => s && !s.isBot); i++) {
    w.expire();
    check(w, `drain ${i}`);
  }
  expect(w.pub.seats.some((s) => s && !s.isBot)).toBe(false);
  for (let i = 1; i <= HUMANS; i++) expect(w.boardTotal(`h${i}`)).toBe(0);
}

describe('craps properties (fast-check)', () => {
  it('money is conserved, nothing goes negative, contract bets are never taken down', () => {
    fc.assert(fc.property(fc.array(cmdArb, { minLength: 20, maxLength: 120 }), fc.integer({ min: 1, max: 1_000 }), (cmds, seed) => run(cmds, seed)), {
      numRuns: 300,
    });
    console.log(`[craps-props] ${JSON.stringify(seen)} ${JSON.stringify(reasons)}`);
    expect(seen.rolls).toBeGreaterThan(800);
    expect(seen.bets).toBeGreaterThan(600);
    expect(seen.contractChecks).toBeGreaterThan(300);
    expect(seen.leavesWithContract).toBeGreaterThan(3);
  });
});
