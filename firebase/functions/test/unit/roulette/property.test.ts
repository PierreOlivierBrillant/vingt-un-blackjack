/**
 * Roulette properties (fast-check):
 *  1. board validation accepts exactly the valid boards (spot ids of the grammar, each amount
 *     between the table minimum and its type's cap) and returns them unchanged;
 *  2. settlement: for any valid board and any number, return ≥ 0, every winning spot covers the
 *     number, the shield only adds half of the even chances on 0;
 *  3. money conservation through the real kernel: random humans joining, betting random boards
 *     (valid or not, with or without the zero shield), leaving, and clock jumps — after EVERY step,
 *     wallet + board = initial + settled nets, no negative balance, a deadline never debits.
 */
import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { rouletteLimits, settleBoard, spotCap, SPOTS, validateBoard } from '../../../src/games/roulette/engine';
import { rouletteModule } from '../../../src/games/roulette/module';
import { AppError } from '../../../src/shared/errors';
import type { BetMap } from '../../../src/shared/games/common';
import type { StakeTier } from '../../../src/shared/types';
import { human, reasonOf, World } from '../kernel/harness';

const IDS = [...SPOTS.keys()];
const tierArb = fc.constantFrom<StakeTier>('low', 'mid', 'high');
const validSpot = fc.constantFrom(...IDS);
const badSpot = fc.oneof(
  fc.constantFrom('n37', 'sp3-4', 'co3', 'st2', 'ln34', 'dozen0', 'col4', 'zero', 'RED', 'n17 ', 'tr0-1-3', 'first5', 'heads'),
  fc.string({ maxLength: 6 }).filter((s) => !SPOTS.has(s)),
);

describe('board validation (fast-check)', () => {
  it('valid boards are accepted unchanged, any bad spot or amount is refused with the right reason', () => {
    fc.assert(fc.property(tierArb, fc.dictionary(validSpot, fc.nat(30), { maxKeys: 12 }), (tier, units) => {
      const lim = rouletteLimits(tier);
      const board: BetMap = {};
      for (const [id, u] of Object.entries(units)) {
        const cap = spotCap(SPOTS.get(id)!.type, lim);
        board[id] = Math.min(cap, Math.max(lim.minBetCents, u * lim.minBetCents));
      }
      expect(validateBoard(board, lim)).toEqual(board);
    }), { numRuns: 400 });

    fc.assert(fc.property(tierArb, validSpot, badSpot, fc.integer({ min: 1, max: 20 }), (tier, ok, bad, u) => {
      const lim = rouletteLimits(tier);
      expect(reasonOf(() => validateBoard({ [ok]: lim.minBetCents, [bad]: u * 100 }, lim))).toBe('BAD_BET_SPOT');
    }), { numRuns: 300 });

    fc.assert(fc.property(tierArb, validSpot, fc.boolean(), (tier, id, above) => {
      const lim = rouletteLimits(tier);
      const cap = spotCap(SPOTS.get(id)!.type, lim);
      const v = above ? cap + 100 : lim.minBetCents - 100;
      fc.pre(v > 0); // 0 means "no bet on this spot" (dropped), not an error
      expect(reasonOf(() => validateBoard({ [id]: v }, lim))).toBe('BET_OUT_OF_RANGE');
    }), { numRuns: 300 });
  });

  it('settlement of any board: non-negative, winners cover the number, the shield is exactly half the even chances on 0', () => {
    fc.assert(fc.property(fc.dictionary(validSpot, fc.integer({ min: 1, max: 50 }), { maxKeys: 15 }), fc.integer({ min: 0, max: 36 }), (units, n) => {
      const board: BetMap = Object.fromEntries(Object.entries(units).map(([k, u]) => [k, u * 100]));
      const plain = settleBoard(board, n);
      const shielded = settleBoard(board, n, true);
      expect(plain.returnCents).toBeGreaterThanOrEqual(0);
      for (const id of plain.wins) expect(SPOTS.get(id)!.numbers).toContain(n);
      const expected = Object.entries(board).reduce((acc, [id, v]) => {
        const s = SPOTS.get(id)!;
        return acc + (s.numbers.includes(n) ? v * (36 / s.numbers.length) : 0);
      }, 0);
      expect(plain.returnCents).toBe(expected);
      const evens = Object.entries(board).filter(([id]) => SPOTS.get(id)!.type === 'even').reduce((a, [, v]) => a + v, 0);
      expect(shielded.returnCents - plain.returnCents).toBe(n === 0 ? evens / 2 : 0);
      expect(Number.isInteger(shielded.returnCents)).toBe(true);
    }), { numRuns: 500 });
  });
});

// ------------------------------------------------------------------------------------------

const HUMANS = 4;
const START = 20_000; // $200 each: INSUFFICIENT_FUNDS happens

type Cmd =
  | { k: 'join'; h: number }
  | { k: 'leave'; h: number }
  | { k: 'bet'; h: number; spots: Array<[string, number]>; power: boolean }
  | { k: 'tick'; ms: number }
  | { k: 'expire' };

// mostly the two players seated at the start, sometimes the two others (who must join first)
const hArb = fc.oneof({ weight: 3, arbitrary: fc.integer({ min: 1, max: 2 }) }, { weight: 1, arbitrary: fc.integer({ min: 3, max: HUMANS }) });
const cmdArb: fc.Arbitrary<Cmd> = fc.oneof(
  { weight: 2, arbitrary: fc.record({ k: fc.constant('join' as const), h: hArb }) },
  { weight: 1, arbitrary: fc.record({ k: fc.constant('leave' as const), h: hArb }) },
  {
    weight: 10,
    arbitrary: fc.record({
      k: fc.constant('bet' as const), h: hArb, power: fc.integer({ min: 0, max: 3 }).map((v) => v === 0),
      // mostly valid boards (a few bad spots, amounts above a cap or a missing even chance for the shield)
      spots: fc.array(fc.tuple(
        fc.oneof({ weight: 6, arbitrary: validSpot }, { weight: 2, arbitrary: fc.constantFrom('red', 'black', 'odd', 'even', 'low', 'high') }, { weight: 1, arbitrary: badSpot }),
        fc.oneof({ weight: 12, arbitrary: fc.integer({ min: 0, max: 12 }) }, { weight: 1, arbitrary: fc.integer({ min: 13, max: 120 }) }),
      ), { maxLength: 6 }),
    }),
  },
  { weight: 2, arbitrary: fc.record({ k: fc.constant('tick' as const), ms: fc.integer({ min: 0, max: 25_000 }) }) },
  { weight: 4, arbitrary: fc.record({ k: fc.constant('expire' as const) }) },
);

function attempt(fn: () => unknown): void {
  try {
    fn();
  } catch (e) {
    if (e instanceof AppError || (e as Error)?.name === 'ZodError') return;
    throw e;
  }
}

function check(w: World, label: string): void {
  for (let i = 1; i <= HUMANS; i++) {
    const uid = `h${i}`;
    const wallet = w.wallets.get(uid)!;
    expect(wallet, label).toBeGreaterThanOrEqual(0);
    expect(wallet + w.boardTotal(uid), `${label} ${uid}`).toBe(START + (w.nets.get(uid) ?? 0));
  }
  if (w.pub.status === 'closed') expect(w.boards.size, label).toBe(0);
  if (w.pub.status === 'open' && ['betting', 'live', 'settled'].includes(w.pub.phase)) expect(w.pub.deadlineMs, label).not.toBeNull();
}

describe('money conservation through the kernel (fast-check)', () => {
  it('random players, boards, powers, leaves and clock jumps never create or lose a cent', () => {
    let settled = 0;
    let shielded = 0;
    fc.assert(fc.property(fc.integer({ min: 1, max: 10_000 }), fc.array(cmdArb, { minLength: 20, maxLength: 80, size: 'max' }), (seed, cmds) => {
      const w = new World(rouletteModule, { seed, isPrivate: true });
      for (let i = 1; i <= HUMANS; i++) {
        w.fund(`h${i}`, START);
        w.inventory.set(`h${i}:zeroShield`, 2);
      }
      check(w, 'start');
      // two players sit down at once (more may join / leave later)
      for (const i of [1, 2]) w.tx((m) => m.join(human(i)));
      check(w, 'joined');
      cmds.forEach((c, step) => {
        const label = `#${step} ${JSON.stringify(c)}`;
        switch (c.k) {
          case 'join':
            attempt(() => w.tx((m) => m.join(human(c.h))));
            break;
          case 'leave':
            attempt(() => w.tx((m) => m.leave(`h${c.h}`)));
            break;
          case 'bet': {
            const bets: BetMap = {};
            for (const [id, u] of c.spots) bets[id] = u * 100;
            attempt(() => w.setBets(`h${c.h}`, bets, c.power ? 'zeroShield' : undefined));
            break;
          }
          case 'tick': {
            const before = w.effects.length;
            attempt(() => w.tick(c.ms));
            expect(w.effects.slice(before).filter((e) => e.kind === 'debit'), label).toEqual([]);
            break;
          }
          case 'expire': {
            const before = w.effects.length;
            w.expire();
            expect(w.effects.slice(before).filter((e) => e.kind === 'debit'), label).toEqual([]);
            break;
          }
        }
        check(w, label);
      });
      const rows = w.ofKind('settle').flatMap((e) => e.rows);
      settled += rows.length;
      shielded += rows.filter((r) => r.counters.zeroShieldSaves).length;
    }), { numRuns: 150 });
    // the runs really played: many settled seats (and the shield fired at least once)
    expect(settled).toBeGreaterThan(300);
    expect(shielded).toBeGreaterThan(0);
  });
});
