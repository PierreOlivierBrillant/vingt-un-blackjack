/**
 * Craps engine: every spot, every payout and every resolution, exact to the cent; the validation
 * rules (contract bets, odds multiples, $3 increments, availability, the shooter's line bet).
 */
import { describe, expect, it } from 'vitest';
import {
  checkBoard, contractBets, maxOdds, parseSpot, pMakePoint, pointAfter, settleBoard, verdictOf, waysOf, type BoardRules,
  type RollContext,
} from '../../../src/games/craps/engine';
import { CRAPS_SPOT_IDS, type CrapsPoint } from '../../../src/shared/games/craps';
import { reasonOf } from '../kernel/harness';
import { diceFor } from './helpers';

const $ = (d: number) => d * 100;
const ctx = (pointBefore: CrapsPoint | null, d: [number, number] | number, extra: Partial<RollContext> = {}): RollContext => {
  const [d1, d2] = typeof d === 'number' ? diceFor(d) : d;
  return { pointBefore, d1, d2, safetyNet: false, leaving: false, ...extra };
};
/** One spot, one roll: { net, ret, carry, outcome }. */
function one(spot: string, stake: number, pointBefore: CrapsPoint | null, d: [number, number] | number, extra: Partial<RollContext> = {}) {
  const st = settleBoard({ [spot]: stake }, ctx(pointBefore, d, extra));
  expect(st.netCents).toBe(st.returnCents - st.stakedCents);
  expect(st.stakedCents).toBe(stake - Object.values(st.carry).reduce((a, v) => a + v, 0));
  return { net: st.netCents, ret: st.returnCents, carry: st.carry, outcome: st.outcomes[0]?.outcome ?? 'none', st };
}
const ALL_TOTALS = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

describe('spot grammar', () => {
  it('parses the 47 spot ids and nothing else', () => {
    expect(CRAPS_SPOT_IDS).toHaveLength(47);
    expect(new Set(CRAPS_SPOT_IDS).size).toBe(47);
    for (const id of CRAPS_SPOT_IDS) expect(parseSpot(id), id).not.toBeNull();
    for (const bad of ['place7', 'come7', 'hard5', 'odds:field', 'odds:come', 'Pass', 'field ', 'odds:place6', 'eleven', 'come11']) {
      expect(parseSpot(bad), bad).toBeNull();
    }
    expect(parseSpot('odds:dontCome9')).toEqual({ kind: 'oddsDontComeN', n: 9 });
  });

  it('dice arithmetic: ways, verdicts, point after', () => {
    expect(ALL_TOTALS.map(waysOf)).toEqual([1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1]);
    expect([4, 5, 6, 8, 9, 10].map((n) => pMakePoint(n as CrapsPoint))).toEqual([1 / 3, 2 / 5, 5 / 11, 5 / 11, 2 / 5, 1 / 3]);
    expect(ALL_TOTALS.map((t) => verdictOf(null, t))).toEqual(['craps', 'craps', 'pointOn', 'pointOn', 'pointOn', 'natural', 'pointOn', 'pointOn', 'pointOn', 'natural', 'craps']);
    expect(ALL_TOTALS.map((t) => verdictOf(6, t))).toEqual(['roll', 'roll', 'roll', 'roll', 'pointMade', 'sevenOut', 'roll', 'roll', 'roll', 'roll', 'roll']);
    expect(pointAfter(null, 8)).toBe(8);
    expect(pointAfter(null, 7)).toBeNull();
    expect(pointAfter(8, 8)).toBeNull();
    expect(pointAfter(8, 7)).toBeNull();
    expect(pointAfter(8, 3)).toBe(8);
  });
});

describe('line bets', () => {
  it('Pass Line: come-out 7/11 win (the bet stays up), 2/3/12 lose, a point keeps it', () => {
    for (const t of ALL_TOTALS) {
      const r = one('pass', $(10), null, t);
      if (t === 7 || t === 11) expect(r).toMatchObject({ net: $(10), ret: $(10), carry: { pass: $(10) }, outcome: 'win' });
      else if (t === 2 || t === 3 || t === 12) expect(r).toMatchObject({ net: -$(10), ret: 0, carry: {}, outcome: 'lose' });
      else expect(r).toMatchObject({ net: 0, ret: 0, carry: { pass: $(10) }, outcome: 'none' });
    }
  });

  it('Pass Line on a point: the point wins 1:1 (stays), 7 loses, anything else waits', () => {
    for (const p of [4, 5, 6, 8, 9, 10] as const) {
      for (const t of ALL_TOTALS) {
        const r = one('pass', $(5), p, t);
        if (t === p) expect(r, `${p}/${t}`).toMatchObject({ net: $(5), carry: { pass: $(5) }, outcome: 'win' });
        else if (t === 7) expect(r, `${p}/${t}`).toMatchObject({ net: -$(5), carry: {}, outcome: 'lose' });
        else expect(r, `${p}/${t}`).toMatchObject({ net: 0, carry: { pass: $(5) } });
      }
    }
  });

  it("Don't Pass: come-out 2/3 win, 12 barred (push, stays), 7/11 lose; on a point 7 wins, the point loses", () => {
    for (const t of ALL_TOTALS) {
      const r = one('dontPass', $(10), null, t);
      if (t === 2 || t === 3) expect(r).toMatchObject({ net: $(10), carry: { dontPass: $(10) }, outcome: 'win' });
      else if (t === 12) expect(r).toMatchObject({ net: 0, ret: 0, carry: { dontPass: $(10) }, outcome: 'push' });
      else if (t === 7 || t === 11) expect(r).toMatchObject({ net: -$(10), carry: {}, outcome: 'lose' });
      else expect(r).toMatchObject({ net: 0, carry: { dontPass: $(10) }, outcome: 'none' });
    }
    expect(one('dontPass', $(10), 4, 7)).toMatchObject({ net: $(10), carry: { dontPass: $(10) }, outcome: 'win' });
    expect(one('dontPass', $(10), 4, 4)).toMatchObject({ net: -$(10), carry: {}, outcome: 'lose' });
    expect(one('dontPass', $(10), 4, 9)).toMatchObject({ net: 0, carry: { dontPass: $(10) } });
  });

  it('Come: 7/11 win and come back, 2/3/12 lose, a number moves the bet there', () => {
    expect(one('come', $(10), 6, 7)).toMatchObject({ net: $(10), ret: $(20), carry: {}, outcome: 'win' });
    expect(one('come', $(10), 6, 11)).toMatchObject({ net: $(10), ret: $(20), carry: {} });
    for (const t of [2, 3, 12]) expect(one('come', $(10), 6, t)).toMatchObject({ net: -$(10), carry: {}, outcome: 'lose' });
    for (const t of [4, 5, 6, 8, 9, 10]) {
      const r = one('come', $(10), 6, t);
      expect(r).toMatchObject({ net: 0, ret: 0, carry: { [`come${t}`]: $(10) }, outcome: 'travel' });
      expect(r.st.outcomes[0].to).toBe(`come${t}`);
    }
  });

  it("Don't Come: 2/3 win, 12 push (comes back), 7/11 lose, a number moves it", () => {
    for (const t of [2, 3]) expect(one('dontCome', $(10), 8, t)).toMatchObject({ net: $(10), ret: $(20), carry: {} });
    expect(one('dontCome', $(10), 8, 12)).toMatchObject({ net: 0, ret: $(10), carry: {}, outcome: 'push' });
    for (const t of [7, 11]) expect(one('dontCome', $(10), 8, t)).toMatchObject({ net: -$(10), carry: {} });
    expect(one('dontCome', $(10), 8, 9)).toMatchObject({ net: 0, carry: { dontCome9: $(10) }, outcome: 'travel' });
  });

  it('Come / Don\'t Come numbers: decided by their number or 7, then come back', () => {
    expect(one('come5', $(10), 8, 5)).toMatchObject({ net: $(10), ret: $(20), carry: {} });
    expect(one('come5', $(10), 8, 7)).toMatchObject({ net: -$(10), carry: {} });
    expect(one('come5', $(10), 8, 9)).toMatchObject({ net: 0, carry: { come5: $(10) } });
    expect(one('come5', $(10), null, 5)).toMatchObject({ net: $(10), carry: {} }); // working on the come-out
    expect(one('dontCome9', $(10), 8, 7)).toMatchObject({ net: $(10), ret: $(20), carry: {} });
    expect(one('dontCome9', $(10), 8, 9)).toMatchObject({ net: -$(10), carry: {} });
    expect(one('dontCome9', $(10), null, 7)).toMatchObject({ net: $(10) });
  });

  it('a new Come bet replaces the one paid on the same number ("off and on")', () => {
    const st = settleBoard({ come: $(5), come6: $(10), 'odds:come6': $(20) }, ctx(8, 6));
    expect(st.carry).toEqual({ come6: $(5) });
    expect(st.returnCents).toBe($(10) + $(10) + $(20) + $(24)); // come6 + win, odds + 6:5
    expect(st.netCents).toBe($(10) + $(24));
  });
});

describe('odds', () => {
  it('free odds pay true odds: 2:1 on 4/10, 3:2 on 5/9, 6:5 on 6/8, and come back', () => {
    const won: Record<number, number> = { 4: $(20), 5: $(15), 6: $(12), 8: $(12), 9: $(15), 10: $(20) };
    for (const p of [4, 5, 6, 8, 9, 10] as const) {
      expect(one('odds:pass', $(10), p, p)).toMatchObject({ net: won[p], ret: $(10) + won[p], carry: {}, outcome: 'win' });
      expect(one('odds:pass', $(10), p, 7)).toMatchObject({ net: -$(10), carry: {} });
      expect(one('odds:come' + p, $(10), 4 === p ? 5 : 4, p)).toMatchObject({ net: won[p], carry: {} });
    }
    expect(one('odds:pass', $(1), 5, 5).net).toBe(150); // $1 at 3:2 = $1.50
    expect(one('odds:pass', $(1), 6, 6).net).toBe(120); // $1 at 6:5 = $1.20
  });

  it('lay odds pay 1:2 on 4/10, 2:3 on 5/9, 5:6 on 6/8', () => {
    expect(one('odds:dontPass', $(10), 4, 7).net).toBe($(5));
    expect(one('odds:dontPass', $(1), 10, 7).net).toBe(50);
    expect(one('odds:dontPass', $(9), 5, 7).net).toBe($(6));
    expect(one('odds:dontPass', $(3), 9, 7).net).toBe($(2));
    expect(one('odds:dontPass', $(12), 6, 7).net).toBe($(10));
    expect(one('odds:dontPass', $(3), 8, 7).net).toBe(250); // $3 at 5:6 = $2.50
    expect(one('odds:dontPass', $(6), 8, 8)).toMatchObject({ net: -$(6), carry: {} });
    expect(one('odds:dontCome6', $(6), 9, 7)).toMatchObject({ net: $(5), ret: $(11) });
    expect(one('odds:dontCome6', $(6), null, 7).net).toBe($(5)); // lay odds always work
    expect(one('odds:dontCome6', $(6), 9, 6).net).toBe(-$(6));
  });

  it('come odds are OFF on the come-out: returned when their come bet is decided', () => {
    const win = settleBoard({ come6: $(10), 'odds:come6': $(20) }, ctx(null, 6));
    expect(win.outcomes.map((o) => [o.spot, o.outcome])).toEqual([['come6', 'win'], ['odds:come6', 'push']]);
    expect(win).toMatchObject({ netCents: $(10), returnCents: $(40), carry: {} });
    const lose = settleBoard({ come6: $(10), 'odds:come6': $(20) }, ctx(null, 7));
    expect(lose).toMatchObject({ netCents: -$(10), returnCents: $(20), carry: {} });
  });
});

describe('place, hardways, field, propositions', () => {
  it('place bets pay 9:5, 7:5, 7:6 and stay up; 7 loses; OFF on the come-out', () => {
    const cases: Array<[string, number, number]> = [['place4', $(5), $(9)], ['place5', $(5), $(7)], ['place6', $(6), $(7)], ['place8', $(12), $(14)], ['place9', $(10), $(14)], ['place10', $(5), $(9)]];
    for (const [spot, stake, won] of cases) {
      const n = Number(spot.slice(5));
      expect(one(spot, stake, n === 9 ? 5 : 9, n), spot).toMatchObject({ net: won, ret: won, carry: { [spot]: stake }, outcome: 'win' });
      expect(one(spot, stake, 9 === n ? 5 : 9, 7), spot).toMatchObject({ net: -stake, carry: {} });
      expect(one(spot, stake, null, n), spot).toMatchObject({ net: 0, carry: { [spot]: stake }, outcome: 'none' });
      expect(one(spot, stake, null, 7), spot).toMatchObject({ net: 0, carry: { [spot]: stake }, outcome: 'none' });
    }
    expect(one('place4', $(1), 9, 4).net).toBe(180); // $1 at 9:5 = $1.80
    expect(one('place5', $(1), 9, 5).net).toBe(140);
    expect(one('place6', $(3), 9, 6).net).toBe(350); // $3 at 7:6 = $3.50
  });

  it('hardways: 7:1 on 4/10, 9:1 on 6/8 (stay up); the easy way or 7 loses; OFF on the come-out', () => {
    expect(one('hard4', $(5), 9, [2, 2])).toMatchObject({ net: $(35), carry: { hard4: $(5) }, outcome: 'win' });
    expect(one('hard10', $(5), 9, [5, 5]).net).toBe($(35));
    expect(one('hard6', $(5), 9, [3, 3]).net).toBe($(45));
    expect(one('hard8', $(5), 9, [4, 4])).toMatchObject({ net: $(45), carry: { hard8: $(5) } });
    expect(one('hard4', $(5), 9, [1, 3])).toMatchObject({ net: -$(5), carry: {} });
    expect(one('hard6', $(5), 9, [2, 4]).net).toBe(-$(5));
    expect(one('hard8', $(5), 9, [2, 6]).net).toBe(-$(5));
    expect(one('hard10', $(5), 9, [6, 4]).net).toBe(-$(5));
    expect(one('hard8', $(5), 9, 7).net).toBe(-$(5));
    expect(one('hard8', $(5), 9, 9)).toMatchObject({ net: 0, carry: { hard8: $(5) } });
    expect(one('hard8', $(5), null, [4, 4])).toMatchObject({ net: 0, carry: { hard8: $(5) }, outcome: 'none' });
    expect(one('hard8', $(5), null, 7)).toMatchObject({ net: 0, carry: { hard8: $(5) } });
  });

  it('field: 2 pays 2:1, 12 pays 3:1, 3/4/9/10/11 pay 1:1, 5/6/7/8 lose — one roll', () => {
    const net: Record<number, number> = { 2: $(20), 3: $(10), 4: $(10), 5: -$(10), 6: -$(10), 7: -$(10), 8: -$(10), 9: $(10), 10: $(10), 11: $(10), 12: $(30) };
    for (const t of ALL_TOTALS) {
      for (const p of [null, 6] as const) expect(one('field', $(10), p, t), `${p}/${t}`).toMatchObject({ net: net[t], carry: {} });
    }
  });

  it('propositions (one roll): Any 7 4:1, Any Craps 7:1, Yo 15:1, 2 and 12 30:1, 3 15:1', () => {
    const table: Array<[string, number[], number]> = [
      ['any7', [7], 4], ['anyCraps', [2, 3, 12], 7], ['yo', [11], 15], ['two', [2], 30], ['twelve', [12], 30], ['three', [3], 15],
    ];
    for (const [spot, hits, ratio] of table) {
      for (const t of ALL_TOTALS) {
        const r = one(spot, $(5), t % 2 ? null : 8, t);
        if (hits.includes(t)) expect(r, `${spot}/${t}`).toMatchObject({ net: $(5) * ratio, ret: $(5) * (ratio + 1), carry: {}, outcome: 'win' });
        else expect(r, `${spot}/${t}`).toMatchObject({ net: -$(5), carry: {}, outcome: 'lose' });
      }
    }
  });

  it('counters: hardway wins, long shots (2, 3, 11, 12), the stake decided', () => {
    const st = settleBoard({ two: $(1), three: $(1), yo: $(1), twelve: $(1), anyCraps: $(1), hard6: $(5), place8: $(6), pass: $(10) }, ctx(6, [1, 1]));
    expect(st).toMatchObject({ longShots: 1, hardways: 0 });
    expect(st.actionCents).toBe($(5)); // the five one-roll bets; place, hard and pass undecided
    expect(st.netCents).toBe($(30) + $(7) - $(3));
    const hard = settleBoard({ hard6: $(5), place6: $(6), pass: $(10) }, ctx(6, [3, 3]));
    expect(hard).toMatchObject({ hardways: 1, actionCents: $(21), netCents: $(45) + $(7) + $(10), stakedCents: 0 });
  });
});

describe('safety net and leaving seats', () => {
  it('safety net: the Pass Line comes back on a seven-out (odds lost), and is spent', () => {
    const st = settleBoard({ pass: $(10), 'odds:pass': $(20), place6: $(6) }, ctx(6, 7, { safetyNet: true }));
    expect(st).toMatchObject({ safetyNetRefund: $(10), safetyNetSpent: true, returnCents: $(10), carry: {} });
    expect(st.netCents).toBe(-$(26));
    expect(st.outcomes.find((o) => o.spot === 'pass')!.outcome).toBe('refund');
    // not spent while the point goes on; spent when the pass is decided otherwise
    expect(settleBoard({ pass: $(10) }, ctx(6, 8, { safetyNet: true })).safetyNetSpent).toBe(false);
    expect(settleBoard({ pass: $(10) }, ctx(null, 4, { safetyNet: true })).safetyNetSpent).toBe(false);
    expect(settleBoard({ pass: $(10) }, ctx(6, 6, { safetyNet: true })).safetyNetSpent).toBe(true);
    expect(settleBoard({ pass: $(10) }, ctx(null, 3, { safetyNet: true }))).toMatchObject({ safetyNetSpent: true, netCents: -$(10) });
    expect(settleBoard({ pass: $(10) }, ctx(null, 7, { safetyNet: true }))).toMatchObject({ safetyNetSpent: true, netCents: $(10) });
  });

  it('a leaving seat keeps only pending contract bets; the rest comes back (winnings paid)', () => {
    const st = settleBoard({ pass: $(10), come8: $(5), dontCome4: $(5), place6: $(6), 'odds:pass': $(10), hard8: $(5) }, ctx(6, 9, { leaving: true }));
    expect(st.carry).toEqual({ pass: $(10), come8: $(5) });
    expect(st.returnCents).toBe($(5) + $(6) + $(10) + $(5));
    expect(st.netCents).toBe(0);
    const win = settleBoard({ pass: $(10), place6: $(6) }, ctx(6, 6, { leaving: true }));
    expect(win).toMatchObject({ carry: {}, returnCents: $(20) + $(13), netCents: $(17) });
    const comeOut = settleBoard({ pass: $(10), dontPass: $(5) }, ctx(null, 12, { leaving: true }));
    expect(comeOut).toMatchObject({ carry: {}, returnCents: $(5), netCents: -$(10) }); // the bar-12 push comes back
    const travel = settleBoard({ come: $(5) }, ctx(6, 5, { leaving: true }));
    expect(travel.carry).toEqual({ come5: $(5) }); // a come bet that just moved is a contract bet
  });

  it('contract bets of a board: pass with a point, come numbers', () => {
    const b = { pass: $(10), dontPass: $(5), come5: $(5), dontCome6: $(5), 'odds:come5': $(5), place8: $(6) };
    expect(contractBets(b, 9)).toEqual({ pass: $(10), come5: $(5) });
    expect(contractBets(b, null)).toEqual({ come5: $(5) });
  });

  it('every resolution conserves money for a full board (staked = board − carry, net = return − staked)', () => {
    const board = {
      pass: $(10), 'odds:pass': $(30), dontPass: $(10), 'odds:dontPass': $(60), come: $(5), dontCome: $(5), come4: $(5),
      'odds:come4': $(15), dontCome10: $(5), 'odds:dontCome10': $(30), place4: $(5), place5: $(5), place6: $(6), place8: $(6),
      place9: $(5), place10: $(5), hard4: $(1), hard6: $(1), hard8: $(1), hard10: $(1), field: $(2), any7: $(1), anyCraps: $(1),
      two: $(1), three: $(1), yo: $(1), twelve: $(1),
    };
    const total = Object.values(board).reduce((a, v) => a + v, 0);
    for (const p of [null, 4, 5, 6, 8, 9, 10] as const) {
      for (let d1 = 1; d1 <= 6; d1++) {
        for (let d2 = 1; d2 <= 6; d2++) {
          for (const safetyNet of [false, true]) {
            for (const leaving of [false, true]) {
              const st = settleBoard(board, { pointBefore: p, d1, d2, safetyNet, leaving });
              const carry = Object.values(st.carry).reduce((a, v) => a + v, 0);
              expect(st.stakedCents).toBe(total - carry);
              expect(st.netCents).toBe(st.returnCents - st.stakedCents);
              for (const v of [...Object.values(st.carry), st.returnCents]) expect(Number.isSafeInteger(v) && v >= 0).toBe(true);
              for (const v of Object.values(st.carry)) expect(v % 100).toBe(0);
            }
          }
        }
      }
    }
  });
});

describe('validation (checkBoard)', () => {
  const rules = (point: CrapsPoint | null, shooter = false): BoardRules => ({ point, minBetCents: $(5), maxBetCents: $(500), shooter });
  const check = (next: Record<string, number>, current: Record<string, number>, r: BoardRules) => reasonOf(() => checkBoard(next, current, r));

  it('unknown spots', () => {
    expect(check({ place7: $(5) }, {}, rules(null))).toBe('BAD_BET_SPOT');
    expect(check({ red: $(5) }, {}, rules(6))).toBe('BAD_BET_SPOT');
  });

  it('what is open when: line bets on the come-out, Come and line odds with a point', () => {
    expect(check({ pass: $(10) }, {}, rules(null))).toBe('NO_ERROR');
    expect(check({ pass: $(10) }, {}, rules(6))).toBe('BET_NOT_OPEN'); // no put bets
    expect(check({ dontPass: $(10) }, {}, rules(6))).toBe('BET_NOT_OPEN');
    expect(check({ come: $(10) }, {}, rules(null))).toBe('BET_NOT_OPEN');
    expect(check({ dontCome: $(10) }, {}, rules(null))).toBe('BET_NOT_OPEN');
    expect(check({ come: $(10), dontCome: $(5) }, {}, rules(6))).toBe('NO_ERROR');
    expect(check({ come5: $(10) }, {}, rules(6))).toBe('BET_NOT_OPEN'); // set by the server only
    expect(check({ dontCome5: $(10) }, {}, rules(6))).toBe('BET_NOT_OPEN');
    expect(check({ come5: $(15) }, { come5: $(10) }, rules(6))).toBe('BET_NOT_OPEN');
    expect(check({ 'odds:pass': $(10) }, {}, rules(6))).toBe('BET_NOT_OPEN');
    expect(check({ pass: $(10), 'odds:pass': $(10) }, { pass: $(10) }, rules(null))).toBe('BET_NOT_OPEN');
    expect(check({ dontPass: $(10), 'odds:dontPass': $(12) }, { dontPass: $(10) }, rules(6))).toBe('NO_ERROR');
    expect(check({ 'odds:come5': $(5) }, {}, rules(6))).toBe('BET_NOT_OPEN');
    expect(check({ come5: $(5), 'odds:come5': $(5) }, { come5: $(5) }, rules(null))).toBe('NO_ERROR'); // off, but may be set
    expect(check({ place6: $(6), hard8: $(5), field: $(5), any7: $(5) }, {}, rules(null))).toBe('NO_ERROR');
  });

  it('contract bets cannot be taken down (Pass with a point, Come numbers); the don\'t side can', () => {
    expect(check({}, { pass: $(10) }, rules(6))).toBe('BET_NOT_REMOVABLE');
    expect(check({ pass: $(5) }, { pass: $(10) }, rules(6))).toBe('BET_NOT_REMOVABLE');
    expect(check({}, { pass: $(10) }, rules(null))).toBe('NO_ERROR'); // not a contract on the come-out
    expect(check({}, { come8: $(10) }, rules(6))).toBe('BET_NOT_REMOVABLE');
    expect(check({}, { come8: $(10) }, rules(null))).toBe('BET_NOT_REMOVABLE');
    expect(check({}, { dontPass: $(10) }, rules(6))).toBe('NO_ERROR');
    expect(check({ dontCome8: $(5) }, { dontCome8: $(10) }, rules(6))).toBe('NO_ERROR');
    expect(check({ dontCome8: $(4) }, { dontCome8: $(10) }, rules(6))).toBe('BET_OUT_OF_RANGE'); // lowered under the minimum
    expect(check({}, { dontCome8: $(10), place6: $(6), 'odds:dontCome8': $(6) }, rules(6))).toBe('NO_ERROR');
    expect(check({ pass: $(10) }, { pass: $(10), 'odds:pass': $(20), place5: $(5) }, rules(6))).toBe('NO_ERROR');
  });

  it('odds up to 3-4-5× (lay: 6×), not capped by the table maximum', () => {
    for (const [p, m] of [[4, 3], [5, 4], [6, 5], [8, 5], [9, 4], [10, 3]] as const) {
      expect(check({ pass: $(10), 'odds:pass': $(10 * m) }, { pass: $(10) }, rules(p)), `${p}`).toBe('NO_ERROR');
      expect(check({ pass: $(10), 'odds:pass': $(10 * m + 1) }, { pass: $(10) }, rules(p)), `${p}`).toBe('BET_OUT_OF_RANGE');
      expect(maxOdds(parseSpot('odds:pass')!, $(10), p)).toBe($(10 * m));
    }
    expect(check({ pass: $(500), 'odds:pass': $(2500) }, { pass: $(500) }, rules(6))).toBe('NO_ERROR'); // $2,500 > max $500
    expect(check({ dontPass: $(10), 'odds:dontPass': $(60) }, { dontPass: $(10) }, rules(4))).toBe('NO_ERROR');
    expect(check({ dontPass: $(10), 'odds:dontPass': $(61) }, { dontPass: $(10) }, rules(4))).toBe('BET_OUT_OF_RANGE');
    expect(check({ come6: $(5), 'odds:come6': $(26) }, { come6: $(5) }, rules(9))).toBe('BET_OUT_OF_RANGE');
    expect(check({ dontCome4: $(5), 'odds:dontCome4': $(30) }, { dontCome4: $(5) }, rules(9))).toBe('NO_ERROR');
  });

  it('place 6/8 and lay odds on 5, 9, 6, 8 by multiples of $3 (BET_INCREMENT)', () => {
    expect(check({ place6: $(5) }, {}, rules(null))).toBe('BET_INCREMENT');
    expect(check({ place8: $(10) }, {}, rules(null))).toBe('BET_INCREMENT');
    expect(check({ place6: $(6), place8: $(9) }, {}, rules(null))).toBe('NO_ERROR');
    expect(check({ place5: $(7), place4: $(7) }, {}, rules(null))).toBe('NO_ERROR');
    for (const p of [5, 9, 6, 8] as const) {
      expect(check({ dontPass: $(10), 'odds:dontPass': $(10) }, { dontPass: $(10) }, rules(p)), `${p}`).toBe('BET_INCREMENT');
      expect(check({ dontPass: $(10), 'odds:dontPass': $(12) }, { dontPass: $(10) }, rules(p)), `${p}`).toBe('NO_ERROR');
    }
    expect(check({ dontPass: $(10), 'odds:dontPass': $(7) }, { dontPass: $(10) }, rules(4))).toBe('NO_ERROR');
    expect(check({ dontCome8: $(10), 'odds:dontCome8': $(10) }, { dontCome8: $(10) }, rules(4))).toBe('BET_INCREMENT');
    expect(check({ pass: $(10), 'odds:pass': $(7) }, { pass: $(10) }, rules(6))).toBe('NO_ERROR'); // $7 at 6:5 = $8.40
  });

  it('per-spot limits (every spot but odds)', () => {
    expect(check({ field: $(4) }, {}, rules(null))).toBe('BET_OUT_OF_RANGE');
    expect(check({ field: $(501) }, {}, rules(null))).toBe('BET_OUT_OF_RANGE');
    expect(check({ hard4: $(500) }, {}, rules(null))).toBe('NO_ERROR');
  });

  it('the shooter must bet the line', () => {
    expect(check({ field: $(5) }, {}, rules(null, true))).toBe('MUST_BET_LINE');
    expect(check({ place6: $(6) }, { place6: $(6) }, rules(null, true))).toBe('MUST_BET_LINE');
    expect(check({}, { place6: $(6) }, rules(null, true))).toBe('NO_ERROR'); // declines: the dice will pass
    expect(check({ dontPass: $(5), field: $(5) }, {}, rules(null, true))).toBe('NO_ERROR');
    expect(check({}, { dontPass: $(5) }, rules(6, true))).toBe('MUST_BET_LINE');
    expect(check({ field: $(5) }, {}, rules(6, true))).toBe('NO_ERROR'); // got the dice mid-point: no line possible
    expect(check({}, { dontPass: $(5) }, rules(6, false))).toBe('NO_ERROR');
  });
});
