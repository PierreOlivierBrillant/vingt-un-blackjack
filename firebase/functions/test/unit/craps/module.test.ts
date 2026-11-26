/**
 * Craps module on the real kernel (in-memory World, see ../kernel/harness.ts): the roll cycle,
 * the shooter (gesture, auto-roll, NOT_SHOOTER, MUST_BET_LINE, passing the dice), bets staying on
 * the board between rolls, the safety net, leaving with contract bets, closing with refunds,
 * markets, rank / stats rows, bots, provably-fair dice.
 */
import { describe, expect, it } from 'vitest';
import { seededRng, sha256Hex } from '../../../src/engine';
import { rollDice } from '../../../src/games/craps/engine';
import { CRAPS_POINT_AVERAGE, crapsModule } from '../../../src/games/craps/module';
import type { AnyGameModule } from '../../../src/games/kernel/module';
import { CRAPS_TIMING, type CrapsPublic } from '../../../src/shared/games/craps';
import type { GameTableDoc } from '../../../src/shared/games/common';
import { DECISION_GRACE_MS, type MarketDoc } from '../../../src/shared/types';
import { gameSimRoster } from '../../../src/sim/profiles';
import { reasonOf } from '../kernel/harness';
import { CrapsWorld } from './helpers';

const $ = (d: number) => d * 100;
const START = 100_000;

function events(w: CrapsWorld, type: string) {
  return w.pub.events.filter((e) => e.type === type);
}

describe('the roll cycle', () => {
  it('a full roll: shooter, gesture, provably-fair dice, payouts, winning line bet stays up', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([3, 4]).seatHumans(2);
    expect(w.pub).toMatchObject({ phase: 'betting', step: 'comeOut', round: 1, turn: { seatIndex: 0 } });
    expect(w.g).toMatchObject({ shooter: 0, shooterUid: 'h1', point: null });
    expect(events(w, 'shooter')[0]).toMatchObject({ seatIndex: 0, d: { uid: 'h1', reason: 'start' } });
    expect(w.pub.markets.round.crapsSeven).toBe('cr-t1__r1__crapsSeven');
    expect(w.pub.deadlineMs! - w.pub.phaseStartedAtMs).toBe(CRAPS_TIMING.shooterMs);
    const commit = w.pub.fairness.currentCommit;

    expect(reasonOf(() => w.roll('h2'))).toBe('NOT_SHOOTER');
    expect(reasonOf(() => w.roll('h1'))).toBe('MUST_BET_LINE');
    expect(reasonOf(() => w.setBets('h1', { field: $(5) }))).toBe('MUST_BET_LINE');
    w.setBets('h1', { pass: $(10) });
    w.setBets('h2', { dontPass: $(5), field: $(5) });
    expect(reasonOf(() => w.setBets('h2', { come: $(5) }))).toBe('BET_NOT_OPEN');
    expect(w.wallets.get('h1')).toBe(START - $(10));

    const r = w.roll('h1');
    const rollAt = w.pub.phaseStartedAtMs + CRAPS_TIMING.minWindowMs;
    expect(r.data).toEqual({ rollAt });
    expect(w.g.rollAt).toBe(rollAt);
    expect(w.pub.deadlineMs).toBe(rollAt - DECISION_GRACE_MS);
    expect(events(w, 'throw')[0]).toMatchObject({ seatIndex: 0, d: { at: rollAt } });
    expect(w.roll('h1').data).toEqual({ rollAt }); // idempotent
    expect(w.last.some((e) => e.kind === 'debit')).toBe(false);

    w.now = rollAt - 1;
    w.setBets('h2', { dontPass: $(5), field: $(10) }); // still open until the dice are out
    w.now = rollAt + 1;
    expect(reasonOf(() => w.setBets('h2', { dontPass: $(5) }))).toBe('BAD_PHASE');
    w.tx((m) => m.advance());
    expect(w.pub).toMatchObject({ phase: 'live', step: 'rolling', turn: null });
    expect(w.g.roll).toEqual({ d1: 3, d2: 4, total: 7, pointBefore: null, verdict: 'natural' });
    expect(w.g.dice).toEqual([3, 4]);
    expect(events(w, 'roll')[0].d).toMatchObject({ d1: 3, d2: 4, verdict: 'natural' });
    expect(w.ofKind('marketStatus', w.last)).toEqual([
      { kind: 'marketStatus', marketId: 'cr-t1__r1__crapsSeven', status: 'closed', outcome: null },
      { kind: 'marketStatus', marketId: 'cr-t1__r1__crapsSeven', status: 'resolved', outcome: 'yes' },
    ]);
    expect(w.pub.seats[0]!.stakeCents).toBe($(10));

    w.expire();
    expect(w.pub.phase).toBe('settled');
    expect(w.wallets.get('h1')).toBe(START - $(10) + $(10)); // winnings paid, the bet stays on the line
    expect(w.board('h1')).toEqual({ pass: $(10) });
    expect(w.wallets.get('h2')).toBe(START - $(15));
    expect(w.board('h2')).toEqual({});
    const settle = w.ofKind('settle', w.last)[0];
    expect(settle.rows.map((x) => [x.uid, x.stakedCents, x.returnCents, x.netCents, x.outcome, x.counters])).toEqual([
      ['h1', 0, $(10), $(10), 'win', { actionCents: $(10) }],
      ['h2', $(15), 0, -$(15), 'lose', { actionCents: $(15) }],
    ]);
    expect(settle.rows.every((x) => x.affinity)).toBe(true);
    expect(events(w, 'pay').map((e) => [e.seatIndex, e.d])).toEqual([
      [0, { wins: { pass: $(10) }, lost: [], pushed: [], returned: [], moved: {}, net: $(10), safetyNet: 0 }],
      [1, { wins: {}, lost: ['dontPass', 'field'], pushed: [], returned: [], moved: {}, net: -$(15), safetyNet: 0 }],
    ]);
    const hist = w.ofKind('history', w.last)[0].doc;
    expect(hist.result).toEqual({ dice: [3, 4], total: 7, pointBefore: null, pointAfter: null, verdict: 'natural', shooter: 0, noRoll: false });
    expect(sha256Hex(hist.fairness.seed)).toBe(commit);
    expect(rollDice(seededRng(hist.fairness.seed))).toEqual([3, 4]);
    expect(w.boards.get('h1')!.previous).toEqual({ pass: $(10) });

    w.nextWindow();
    expect(w.pub).toMatchObject({ round: 2, step: 'comeOut', turn: { seatIndex: 0 } });
    expect(w.g.shooter).toBe(0); // a natural keeps the dice
    expect(w.board('h1')).toEqual({ pass: $(10) }); // still working
  });

  it('without a gesture the dice roll automatically at the deadline (15 s + the human grace)', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([6, 5]).seatHumans(1);
    w.setBets('h1', { pass: $(10) });
    w.now = w.pub.deadlineMs! + DECISION_GRACE_MS - 1;
    w.tx((m) => m.advance());
    expect(w.pub.phase).toBe('betting');
    w.now += 1;
    w.tx((m) => m.advance());
    expect(w.pub.phase).toBe('live');
    expect(w.g.roll!.total).toBe(11);
  });

  it('a whole point: odds, come travel, place and hardway pay exactly; contract bets stay; come odds off on the come-out', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([2, 4], [4, 1], [3, 3], [5, 2]).seatHumans(1);
    w.setBets('h1', { pass: $(10) });
    w.playRoll();
    expect(w.g).toMatchObject({ point: 6 });
    expect(events(w, 'puck')[0].d).toEqual({ point: 6 });
    w.nextWindow();
    expect(w.pub.step).toBe('point');
    const cur = { pass: $(10) };
    expect(reasonOf(() => w.setBets('h1', {}))).toBe('MUST_BET_LINE');
    expect(reasonOf(() => w.setBets('h1', { pass: $(5) }))).toBe('BET_NOT_REMOVABLE');
    expect(reasonOf(() => w.setBets('h1', { ...cur, 'odds:pass': $(51) }))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => w.setBets('h1', { ...cur, place6: $(5) }))).toBe('BET_INCREMENT');
    expect(reasonOf(() => w.setBets('h1', { ...cur, dontPass: $(5) }))).toBe('BET_NOT_OPEN');
    w.setBets('h1', { ...cur, 'odds:pass': $(50), come: $(10), place5: $(5), hard6: $(5) });
    w.playRoll(); // 4 + 1
    expect(w.wallets.get('h1')).toBe(START - $(80) + $(7));
    expect(w.board('h1')).toEqual({ pass: $(10), 'odds:pass': $(50), come5: $(10), place5: $(5), hard6: $(5) });
    expect(events(w, 'pay')[0].d).toMatchObject({ wins: { place5: $(7) }, moved: { come: 'come5' } });
    w.nextWindow();
    expect(reasonOf(() => w.setBets('h1', { pass: $(10), 'odds:pass': $(50), place5: $(5), hard6: $(5) }))).toBe('BET_NOT_REMOVABLE');
    w.setBets('h1', { ...w.board('h1'), 'odds:come5': $(40) });
    w.playRoll(); // 3 + 3: point made the hard way
    expect(w.g.point).toBeNull();
    expect(w.g.shooterPoints).toBe(1);
    expect(w.board('h1')).toEqual({ pass: $(10), come5: $(10), 'odds:come5': $(40), place5: $(5), hard6: $(5) });
    const row = w.ofKind('settle', w.last)[0].rows[0];
    expect(row).toMatchObject({ stakedCents: $(50), returnCents: $(10) + $(110) + $(45), netCents: $(115), outcome: 'win' });
    expect(row.counters).toEqual({ actionCents: $(65), pointsMade: 1, hardways: 1 });
    expect(events(w, 'point')[0]).toMatchObject({ seatIndex: 0, d: { point: 6 } });
    w.nextWindow();
    expect(w.pub.step).toBe('comeOut');
    expect(w.g.shooter).toBe(0);
    w.playRoll(); // 5 + 2: natural; the come bet loses, its odds (off) come back; place / hard are off
    expect(w.board('h1')).toEqual({ pass: $(10), place5: $(5), hard6: $(5) });
    expect(w.ofKind('settle', w.last)[0].rows[0]).toMatchObject({ stakedCents: $(50), returnCents: $(50), netCents: 0 });
    expect(w.wallets.get('h1')).toBe(START - $(120) + $(7) + $(165) + $(50));
    expect(w.wallets.get('h1')! + w.boardTotal('h1')).toBe(START + w.nets.get('h1')!);
  });
});

describe('the shooter and the dice', () => {
  it('a seven-out passes the dice to the next player', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([4, 4], [6, 1]).seatHumans(3);
    w.setBets('h1', { pass: $(10) });
    w.setBets('h3', { dontPass: $(10) });
    w.playRoll();
    w.nextWindow();
    w.playRoll();
    expect(w.g).toMatchObject({ point: null, passDice: 'sevenOut' });
    expect(w.wallets.get('h3')).toBe(START - $(10) + $(10));
    expect(w.board('h3')).toEqual({ dontPass: $(10) });
    w.nextWindow();
    expect(w.g).toMatchObject({ shooter: 1, shooterUid: 'h2', passDice: null, shooterRolls: 0 });
    expect(w.pub.turn).toEqual({ seatIndex: 1 });
    expect(events(w, 'shooter')[0]).toMatchObject({ seatIndex: 1, d: { uid: 'h2', reason: 'sevenOut' } });
  });

  it('a shooter without a line bet on the come-out declines: no roll, the dice pass on', () => {
    const w = new CrapsWorld({ isPrivate: true }).seatHumans(2);
    w.setBets('h2', { pass: $(5), field: $(5) });
    const seed = w.priv.seed;
    w.expire();
    expect(w.pub.phase).toBe('settled');
    expect(events(w, 'noRoll')[0]).toMatchObject({ seatIndex: 0, d: { reason: 'noLineBet' } });
    expect(w.ofKind('history', w.last)[0].doc.result).toMatchObject({ noRoll: true, dice: null });
    expect(w.ofKind('settle', w.last)[0].rows).toEqual([]);
    expect(w.board('h2')).toEqual({ pass: $(5), field: $(5) });
    expect(w.wallets.get('h2')).toBe(START - $(10));
    expect(w.pub.fairness.lastSeed).toBe(seed);
    expect(w.pub.deadlineMs! - w.now).toBe(CRAPS_TIMING.noRollSettledMs);
    w.nextWindow();
    expect(w.g).toMatchObject({ shooter: 1, shooterUid: 'h2' });
    expect(events(w, 'shooter')[0].d).toMatchObject({ reason: 'declined' });
  });

  it('a shooter who leaves passes the dice at once; the point goes on with the next shooter', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([5, 5], [2, 1]).seatHumans(2);
    w.setBets('h1', { pass: $(10) });
    w.setBets('h2', { pass: $(5) });
    w.playRoll();
    w.nextWindow();
    expect(w.g.point).toBe(10);
    w.setBets('h1', { pass: $(10), 'odds:pass': $(30), place8: $(6) });
    const res = w.tx((m) => m.leave('h1'));
    expect(res).toEqual({ refundedCents: $(36), cashOutCents: 0, deferred: true });
    expect(w.seat('h1')!.status).toBe('leaving');
    expect(w.board('h1')).toEqual({ pass: $(10) });
    expect(w.g).toMatchObject({ shooter: 1, shooterUid: 'h2', point: 10 });
    expect(w.pub.turn).toEqual({ seatIndex: 1 });
    expect(reasonOf(() => w.roll('h1'))).toBe('NOT_SEATED');
    w.roll('h2'); // no line bet needed during the point: the roll goes on
    w.playRoll();
    expect(w.g.roll!.total).toBe(3);
  });

  it('the house rolls for the pending bets of players who left; their seat goes once clear, then the table closes', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([2, 2], [5, 6], [6, 6], [1, 3]).seatHumans(1);
    w.setBets('h1', { pass: $(10) });
    w.playRoll();
    w.nextWindow();
    w.setBets('h1', { pass: $(10), 'odds:pass': $(30), place6: $(6) });
    w.tx((m) => m.leave('h1'));
    expect(w.wallets.get('h1')).toBe(START - $(10));
    expect(w.g.shooter).toBeNull();
    expect(w.pub.status).toBe('open');
    expect(w.pub.deadlineMs! - w.pub.phaseStartedAtMs).toBe(CRAPS_TIMING.shooterMs); // this window keeps its length
    w.until((t) => t.status === 'closed', 40);
    expect(w.wallets.get('h1')).toBe(START - $(10) + $(20)); // point 4 made: the pass comes back with its win
    expect(w.pub.seats.every((s) => s === null)).toBe(true);
    expect(w.boards.size).toBe(0);
  });
});

describe('powers, closing, markets', () => {
  it('safety net: consumed when set, armed at the come-out, refunds the Pass Line on the seven-out', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([2, 2], [3, 4]).seatHumans(2);
    w.inventory.set('h1:safetyNet', 2);
    expect(reasonOf(() => w.setBets('h1', { dontPass: $(10) }, 'safetyNet'))).toBe('POWER_NOT_APPLICABLE');
    expect(reasonOf(() => w.setBets('h2', { pass: $(10) }, 'safetyNet'))).toBe('POWER_NOT_OWNED');
    expect(reasonOf(() => w.setBets('h1', { pass: $(10) }, 'zeroShield'))).toBe('WRONG_GAME');
    w.setBets('h1', { pass: $(10) }, 'safetyNet');
    expect(w.inventory.get('h1:safetyNet')).toBe(1);
    expect(w.boards.get('h1')!.power).toBe('safetyNet');
    w.playRoll();
    expect(w.seatG('h1').safetyNet).toBe(true);
    expect(events(w, 'power')[0]).toMatchObject({ seatIndex: 0, d: { power: 'safetyNet' } });
    expect(w.pub.seats[0]!.powerUsed).toBe('safetyNet');
    w.nextWindow();
    expect(reasonOf(() => w.setBets('h1', { pass: $(10), 'odds:pass': $(10) }, 'safetyNet'))).toBe('POWER_NOT_APPLICABLE');
    w.setBets('h1', { pass: $(10), 'odds:pass': $(20) });
    w.playRoll(); // seven-out
    expect(w.seatG('h1').safetyNet).toBe(false);
    expect(w.wallets.get('h1')).toBe(START - $(30) + $(10));
    expect(w.board('h1')).toEqual({});
    const row = w.ofKind('settle', w.last)[0].rows[0];
    expect(row).toMatchObject({ stakedCents: $(30), returnCents: $(10), netCents: -$(20) });
    expect(events(w, 'pay')[0].d).toMatchObject({ returned: ['pass'], lost: ['odds:pass'], safetyNet: $(10) });
  });

  it('a game withdrawn closes the table and refunds every board, carried contract bets included', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([3, 3]).seatHumans(2);
    w.setBets('h1', { pass: $(10) });
    w.setBets('h2', { dontPass: $(10), place8: $(12) });
    w.playRoll();
    w.nextWindow();
    w.setBets('h1', { pass: $(10), 'odds:pass': $(50), hard8: $(5) });
    (w as unknown as { module: AnyGameModule }).module = { ...crapsModule, available: false };
    w.tx((m) => m.advance());
    expect(w.pub.status).toBe('closed');
    expect(w.wallets.get('h1')).toBe(START);
    expect(w.wallets.get('h2')).toBe(START);
    expect(w.boards.size).toBe(0);
    const credits = w.ofKind('credit', w.last);
    expect(credits.map((c) => [c.uid, c.cents, c.ledger])).toEqual([['h1', $(65), 'refund'], ['h2', $(22), 'refund']]);
    expect(w.ofKind('marketStatus', w.last).every((m) => m.status === 'void')).toBe(true);
  });

  it('sim tables: the point market lasts the point and resolves with it; never on other tables', () => {
    const w = new CrapsWorld({ tableId: 'cr-sim-01', simManaged: true }).rolls([2, 2], [6, 6], [1, 3]);
    for (const b of gameSimRoster('cr-sim-01')!.slice(0, 3)) w.tx((m) => m.join({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true }));
    expect(w.pub.deadlineMs! - w.pub.phaseStartedAtMs).toBe(CRAPS_TIMING.botsOnlyMs);
    w.playRoll();
    const created = w.ofKind('marketCreate', w.last).map((e) => e.market as MarketDoc);
    expect(created.map((m) => [m.marketId, m.kind, m.question.fr])).toEqual([
      ['cr-sim-01__w1__crapsPoint', 'crapsPoint', `Le lanceur fait son point de 4 ? (${w.pub.name})`],
    ]);
    expect(w.pub.markets.series.crapsPoint).toBe('cr-sim-01__w1__crapsPoint');
    expect(crapsModule.fairEstimate(created[0], w.pub)).toBeCloseTo(1 / 3, 12);
    w.nextWindow();
    w.playRoll(); // 12: nothing
    expect(w.pub.markets.series.crapsPoint).toBe('cr-sim-01__w1__crapsPoint');
    w.nextWindow();
    w.expire(); // 1 + 3: point made
    expect(w.ofKind('marketStatus', w.last).filter((m) => m.marketId.includes('crapsPoint'))).toEqual([
      { kind: 'marketStatus', marketId: 'cr-sim-01__w1__crapsPoint', status: 'closed', outcome: null },
      { kind: 'marketStatus', marketId: 'cr-sim-01__w1__crapsPoint', status: 'resolved', outcome: 'yes' },
    ]);
    expect(w.g.pointSeries).toBe(1);

    const p = new CrapsWorld({ isPrivate: true }).rolls([2, 2]).seatHumans(1);
    p.setBets('h1', { pass: $(5) });
    p.playRoll();
    expect(p.ofKind('marketCreate').some((e) => e.market.kind === 'crapsPoint')).toBe(false);
  });

  it('fair estimates: seven 1/6, point by number, 67/165 without a point', () => {
    const m = { kind: 'crapsSeven' } as MarketDoc;
    expect(crapsModule.fairEstimate(m, null)).toBeCloseTo(1 / 6, 12);
    const pt = { kind: 'crapsPoint' } as MarketDoc;
    const t = (point: number | null) => ({ g: { point } }) as unknown as GameTableDoc<CrapsPublic>;
    expect(crapsModule.fairEstimate(pt, t(6) as never)).toBeCloseTo(5 / 11, 12);
    expect(crapsModule.fairEstimate(pt, t(9) as never)).toBeCloseTo(2 / 5, 12);
    expect(crapsModule.fairEstimate(pt, t(null) as never)).toBe(CRAPS_POINT_AVERAGE);
    expect(crapsModule.fairEstimate(pt, null)).toBeCloseTo(67 / 165, 12);
  });
});

describe('rank, bots, fairness', () => {
  it('rank compares the net with the stake decided by the roll (covering everything is not a win)', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([4, 4], [2, 4]).seatHumans(2);
    w.setBets('h1', { pass: $(10) });
    w.playRoll(); // point 8
    w.nextWindow();
    w.setBets('h1', { pass: $(10), place4: $(5), place5: $(5), place6: $(6), place9: $(5), place10: $(5), field: $(5) });
    w.setBets('h2', { any7: $(5), yo: $(5) });
    w.playRoll(); // 6: place6 +7, field −5
    const rows = w.ofKind('settle', w.last)[0].rows;
    expect(rows.map((r) => [r.uid, r.netCents, r.counters.actionCents, r.outcome])).toEqual([
      ['h1', $(2), $(11), 'none'],
      ['h2', -$(10), $(10), 'lose'],
    ]);
  });

  it('a long shot is a jackpot (feed), a hardway counts', () => {
    const w = new CrapsWorld({ isPrivate: true }).rolls([6, 6]).seatHumans(1);
    w.setBets('h1', { pass: $(5), twelve: $(5) });
    w.playRoll();
    const row = w.ofKind('settle', w.last)[0].rows[0];
    expect(row).toMatchObject({ netCents: $(150) - $(5), highlight: 'jackpot', counters: { longShots: 1, actionCents: $(10) }, outcome: 'bigWin' });
    expect(w.ofKind('feed', w.last)[0].entry).toMatchObject({ kind: 'jackpot', game: 'craps', amountCents: $(145) });
  });

  it('a bots-only sim table plays 300 rolls: shooters always bet the line, dice from the seed, contract bets kept', () => {
    const w = new CrapsWorld({ tableId: 'cr-sim-02', simManaged: true, seed: 9 });
    for (const b of gameSimRoster('cr-sim-02')!.slice(0, 4)) w.tx((m) => m.join({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true }));
    let rolls = 0;
    let noRolls = 0;
    const verdicts = new Set<string>();
    for (let i = 0; i < 2_000 && rolls < 300; i++) {
      const before = new Map([...w.boards].map(([k, v]) => [k, { ...v.bets }]));
      const point = w.g.point;
      w.expire();
      for (const e of w.ofKind('history', w.last)) {
        const r = e.doc.result as { dice: [number, number] | null; noRoll: boolean; verdict: string };
        if (r.noRoll) { noRolls++; continue; }
        rolls++;
        verdicts.add(r.verdict);
        expect(rollDice(seededRng(e.doc.fairness.seed))).toEqual(r.dice);
      }
      if (w.pub.phase === 'betting' && w.ofKind('settle', w.last).length === 0) {
        // bots' new boards: never fewer contract bets than before
        for (const [uid, b] of w.boards) {
          const prev = before.get(uid) ?? {};
          if (point !== null && (prev.pass ?? 0) > 0) expect(b.bets.pass, uid).toBe(prev.pass);
          for (const [k, v] of Object.entries(prev)) if (/^come\d+$/.test(k)) expect(b.bets[k], `${uid} ${k}`).toBe(v);
        }
      }
    }
    expect(rolls).toBe(300);
    expect(noRolls).toBe(0);
    expect([...verdicts].sort()).toEqual(['craps', 'natural', 'pointMade', 'pointOn', 'roll', 'sevenOut']);
  });
});
