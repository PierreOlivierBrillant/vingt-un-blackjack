/**
 * Roulette engine: wheel, colours, every bet type and every payout exact to the cent, the zero
 * shield, the per-type caps, board validation and the call bets.
 */
import { describe, expect, it } from 'vitest';
import {
  ANNOUNCES, announceBoard, colorOf, coveredNumbers, hasEvenMoney, RED_NUMBERS, rouletteLimits, settleBoard, spotCap, spotOf,
  spotReturn, SPOTS, validateBoard, WHEEL_ORDER, wheelNeighbours,
} from '../../../src/games/roulette/engine';
import { ROULETTE_LIMIT_KEYS, ROULETTE_PAYOUTS, ROULETTE_SPOT_TYPES } from '../../../src/shared/games/roulette';
import { STAKE_TIER_LIMITS } from '../../../src/shared/types';
import { reasonOf } from '../kernel/harness';

const ALL = Array.from({ length: 37 }, (_, i) => i);

describe('wheel and colours', () => {
  it('37 pockets, each number once, the real European order', () => {
    expect(WHEEL_ORDER).toHaveLength(37);
    expect([...WHEEL_ORDER].sort((a, b) => a - b)).toEqual(ALL);
    expect(WHEEL_ORDER.slice(0, 6)).toEqual([0, 32, 15, 19, 4, 21]);
    expect(WHEEL_ORDER.at(-1)).toBe(26);
  });

  it('18 red, 18 black, the zero green; colours alternate around the wheel', () => {
    expect(RED_NUMBERS).toHaveLength(18);
    expect(colorOf(0)).toBe('green');
    expect(ALL.filter((n) => colorOf(n) === 'black')).toHaveLength(18);
    for (let i = 1; i < 36; i++) expect(colorOf(WHEEL_ORDER[i])).not.toBe(colorOf(WHEEL_ORDER[i + 1]));
    expect(colorOf(32)).toBe('red');
    expect(colorOf(26)).toBe('black');
  });

  it('neighbours wrap around the zero', () => {
    expect(wheelNeighbours(0)).toEqual([3, 26, 0, 32, 15]);
    expect(wheelNeighbours(17, 1)).toEqual([25, 17, 34]);
    expect(() => wheelNeighbours(37)).toThrow(RangeError);
  });
});

describe('spot grammar', () => {
  const ofType = (t: string) => [...SPOTS.values()].filter((s) => s.type === t);

  it('157 spots: 37 pleins, 60 chevaux, 12 transversales, 2 trios, 22 carrés, 1 premier quatre, 11 sixains, 3 + 3 + 6', () => {
    expect(SPOTS.size).toBe(157);
    const counts = Object.fromEntries(ROULETTE_SPOT_TYPES.map((t) => [t, ofType(t).length]));
    expect(counts).toEqual({ straight: 37, split: 60, street: 12, trio: 2, corner: 22, firstFour: 1, line: 11, dozen: 3, column: 3, even: 6 });
  });

  it('each type covers the right count of numbers, and the payout is 36 / k − 1', () => {
    const k: Record<string, number> = { straight: 1, split: 2, street: 3, trio: 3, corner: 4, firstFour: 4, line: 6, dozen: 12, column: 12, even: 18 };
    for (const s of SPOTS.values()) {
      expect(s.numbers).toHaveLength(k[s.type]);
      expect(ROULETTE_PAYOUTS[s.type]).toBe(36 / k[s.type] - 1);
    }
  });

  it('chevaux are layout neighbours; carrés are 2×2 squares; ids are canonical', () => {
    for (const s of ofType('split')) {
      const [a, b] = s.numbers;
      expect(a === 0 ? [1, 2, 3].includes(b) : b === a + 3 || (b === a + 1 && a % 3 !== 0)).toBe(true);
      expect(s.id).toBe(`sp${a}-${b}`);
    }
    expect(spotOf('sp3-4')).toBeNull(); // 3 and 4 are not adjacent on the layout
    expect(spotOf('sp17-20')!.numbers).toEqual([17, 20]);
    expect(spotOf('co1')!.numbers).toEqual([1, 2, 4, 5]);
    expect(spotOf('co3')).toBeNull();
    expect(spotOf('co32')!.numbers).toEqual([32, 33, 35, 36]);
    expect(spotOf('st34')!.numbers).toEqual([34, 35, 36]);
    expect(spotOf('ln31')!.numbers).toEqual([31, 32, 33, 34, 35, 36]);
    expect(spotOf('tr0-1-2')!.numbers).toEqual([0, 1, 2]);
    expect(spotOf('first4')!.numbers).toEqual([0, 1, 2, 3]);
    expect(spotOf('col1')!.numbers).toEqual([1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31, 34]);
    expect(spotOf('col3')!.numbers.at(-1)).toBe(36);
    expect(spotOf('dozen2')!.numbers).toEqual(Array.from({ length: 12 }, (_, i) => 13 + i));
    expect(spotOf('low')!.numbers.at(-1)).toBe(18);
    expect(spotOf('even')!.numbers).not.toContain(0);
    for (const bad of ['n37', 'n-1', 'n01', 'sp1-1', 'st2', 'ln34', 'dozen4', 'col0', 'zero', 'RED', '', '__proto__', 'constructor']) {
      expect(spotOf(bad)).toBeNull();
    }
  });

  it('every number is covered by the same total "weight": each spot is fair before the zero', () => {
    // For every spot, sum over the 37 numbers of the return of 1 unit = 36 (house edge exactly 1/37).
    for (const s of SPOTS.values()) {
      const total = ALL.reduce((acc, n) => acc + spotReturn(s, 100, n), 0);
      expect(total, s.id).toBe(3_600);
    }
  });
});

describe('payouts exact to the cent', () => {
  const cases: Array<[string, number, number]> = [
    // spot, winning number, X of "X to 1"
    ['n0', 0, 35], ['n17', 17, 35], ['n36', 36, 35],
    ['sp0-1', 1, 17], ['sp17-20', 20, 17], ['sp35-36', 35, 17],
    ['st1', 3, 11], ['st34', 34, 11], ['tr0-1-2', 0, 11], ['tr0-2-3', 3, 11],
    ['co1', 5, 8], ['co32', 33, 8], ['first4', 0, 8], ['first4', 3, 8],
    ['ln1', 6, 5], ['ln31', 31, 5],
    ['dozen1', 12, 2], ['dozen3', 25, 2], ['col2', 35, 2], ['col1', 1, 2],
    ['red', 32, 1], ['black', 26, 1], ['odd', 35, 1], ['even', 2, 1], ['low', 1, 1], ['high', 36, 1],
  ];
  for (const [id, n, x] of cases) {
    it(`${id} on ${n} pays ${x}:1`, () => {
      const s = spotOf(id)!;
      expect(spotReturn(s, 700, n)).toBe(700 * (x + 1));
      const out = settleBoard({ [id]: 700 }, n);
      expect(out.returnCents - 700).toBe(700 * x);
      expect(out.wins).toEqual([id]);
    });
  }

  it('a losing bet returns nothing; the even chances all lose on 0 without the shield', () => {
    expect(settleBoard({ n17: 500 }, 18)).toEqual({ returnCents: 0, wins: [], straightHit: false, shieldCents: 0 });
    for (const id of ['red', 'black', 'odd', 'even', 'low', 'high']) expect(settleBoard({ [id]: 1_000 }, 0).returnCents).toBe(0);
  });

  it('zero shield ("la partage"): half of every even-money bet back on 0, nothing else changes', () => {
    const board = { red: 1_100, odd: 300, n0: 100, dozen1: 500, n5: 200 };
    const out = settleBoard(board, 0, true);
    expect(out.shieldCents).toBe(550 + 150); // whole dollars → halves are whole cents
    expect(out.returnCents).toBe(550 + 150 + 3_600);
    expect(out.wins).toEqual(['n0']);
    expect(out.straightHit).toBe(true);
    // no effect when the ball does not land on 0
    expect(settleBoard(board, 5, true)).toEqual(settleBoard(board, 5, false));
  });

  it('a full board: winnings + winning stakes, every winning spot listed', () => {
    const board = { n17: 100, 'sp17-20': 200, st16: 300, co16: 400, ln13: 500, dozen2: 600, col2: 700, black: 800, odd: 900, low: 1_000, red: 1_100 };
    const out = settleBoard(board, 17);
    expect(out.returnCents).toBe(100 * 36 + 200 * 18 + 300 * 12 + 400 * 9 + 500 * 6 + 600 * 3 + 700 * 3 + 800 * 2 + 900 * 2 + 1_000 * 2);
    expect(out.wins).toEqual(['n17', 'sp17-20', 'st16', 'co16', 'ln13', 'dozen2', 'col2', 'black', 'odd', 'low']);
    expect(out.straightHit).toBe(true);
    expect(() => settleBoard({ n99: 100 }, 1)).toThrow();
  });
});

describe('limits and validation', () => {
  it('limits per tier follow STAKE_TIER_LIMITS, inside bets capped by the numbers they cover', () => {
    const low = rouletteLimits('low');
    expect(low).toEqual({
      minBetCents: 100, maxBetCents: 10_000, maxRoundCents: 50_000,
      extra: { straightMaxCents: 2_500, splitMaxCents: 5_000, streetMaxCents: 7_500, cornerMaxCents: 10_000, lineMaxCents: 10_000, dozenMaxCents: 10_000, evenMaxCents: 10_000 },
    });
    for (const tier of ['low', 'mid', 'high'] as const) {
      const l = rouletteLimits(tier);
      expect(l.minBetCents).toBe(STAKE_TIER_LIMITS[tier].minBetCents);
      expect(l.maxBetCents).toBe(STAKE_TIER_LIMITS[tier].maxBetCents);
      for (const v of Object.values(l.extra)) expect(v % 100).toBe(0);
      for (const t of ROULETTE_SPOT_TYPES) expect(l.extra[ROULETTE_LIMIT_KEYS[t]]).toBeGreaterThanOrEqual(l.minBetCents);
    }
    expect(spotCap('straight', rouletteLimits('high'))).toBe(62_500);
    expect(spotCap('trio', low)).toBe(7_500);
    expect(spotCap('firstFour', low)).toBe(10_000);
  });

  it('validateBoard: unknown spot → BAD_BET_SPOT, below the minimum or above the type cap → BET_OUT_OF_RANGE', () => {
    const low = rouletteLimits('low');
    expect(validateBoard({ n17: 2_500, red: 10_000, 'sp0-1': 0 }, low)).toEqual({ n17: 2_500, red: 10_000 });
    expect(reasonOf(() => validateBoard({ n37: 100 }, low))).toBe('BAD_BET_SPOT');
    expect(reasonOf(() => validateBoard({ zero: 100 }, low))).toBe('BAD_BET_SPOT');
    expect(reasonOf(() => validateBoard({ n17: 2_600 }, low))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => validateBoard({ 'sp1-2': 5_100 }, low))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => validateBoard({ red: 10_100 }, low))).toBe('BET_OUT_OF_RANGE');
    const mid = rouletteLimits('mid');
    expect(reasonOf(() => validateBoard({ red: 400 }, mid))).toBe('BET_OUT_OF_RANGE'); // below $5
    expect(validateBoard({ red: 500 }, mid)).toEqual({ red: 500 });
  });

  it('hasEvenMoney only looks at the even chances with money on them', () => {
    expect(hasEvenMoney({ red: 100 })).toBe(true);
    expect(hasEvenMoney({ n0: 100, dozen1: 100 })).toBe(false);
    expect(hasEvenMoney({ red: 0, n1: 100 })).toBe(false);
  });
});

describe('call bets (annonces)', () => {
  it('voisins du zéro: 17 numbers, 9 chips; tiers 12 / 6; orphelins 8 / 5; jeu zéro 7 / 4', () => {
    const chips = (id: keyof typeof ANNOUNCES) => Object.values(ANNOUNCES[id]).reduce((a, b) => a + b, 0);
    expect([chips('voisins'), chips('tiers'), chips('orphelins'), chips('jeuZero')]).toEqual([9, 6, 5, 4]);
    const cov = (id: keyof typeof ANNOUNCES) => coveredNumbers(announceBoard(id, 100));
    expect(cov('voisins')).toEqual([0, 2, 3, 4, 7, 12, 15, 18, 19, 21, 22, 25, 26, 28, 29, 32, 35]);
    expect(cov('tiers')).toEqual([5, 8, 10, 11, 13, 16, 23, 24, 27, 30, 33, 36]);
    expect(cov('orphelins')).toEqual([1, 6, 9, 14, 17, 20, 31, 34]);
    expect(cov('jeuZero')).toEqual([0, 3, 12, 15, 26, 32, 35]);
    // voisins + tiers + orphelins cover the whole wheel exactly once
    expect([...cov('voisins'), ...cov('tiers'), ...cov('orphelins')].sort((a, b) => a - b)).toEqual(ALL);
    // each sector is a contiguous arc of the wheel
    const arc = (nums: number[]) => {
      const idx = nums.map((n) => WHEEL_ORDER.indexOf(n)).sort((a, b) => a - b);
      const gaps = idx.map((v, i) => (idx[(i + 1) % idx.length] - v + 37) % 37).filter((g) => g !== 1);
      return gaps.length;
    };
    expect(arc(cov('voisins'))).toBe(1);
    expect(arc(cov('tiers'))).toBe(1);
    expect(arc(cov('jeuZero'))).toBe(1);
    expect(arc(cov('orphelins'))).toBe(2); // two arcs on either side of the wheel
  });

  it('every spot of every call bet is valid; neighbours are 5 pleins', () => {
    for (const id of Object.keys(ANNOUNCES) as (keyof typeof ANNOUNCES)[]) {
      expect(validateBoard(announceBoard(id, 100), rouletteLimits('low'))).toEqual(announceBoard(id, 100));
    }
    expect(announceBoard('voisins', 500)).toMatchObject({ 'tr0-2-3': 1_000, co25: 1_000, 'sp4-7': 500 });
    expect(announceBoard('neighbours', 200, 0)).toEqual({ n3: 200, n26: 200, n0: 200, n32: 200, n15: 200 });
  });
});
