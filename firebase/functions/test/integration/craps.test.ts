/**
 * Craps on the emulators through the real callable code, in-process (./inproc.ts: auth, strict
 * schema, rate limit, idempotency, ONE Firestore transaction), with the PRODUCTION craps module.
 * Covers: a full provably-fair roll (fast-path bets, the shooter's gesture, payouts, the board
 * carried to the next roll, ledger), double spend, replay, out of turn (NOT_SHOOTER), forbidden
 * bets (increments, contract bets, odds, what is not open), powers (not owned, not applicable,
 * consumed once), own-table markets, leaving with a contract bet (resolved by deadlines alone) and
 * a closing table refunding the carried boards.
 */
import { randomUUID } from 'node:crypto';
import { afterAll, describe, expect, it } from 'vitest';
import { seededRng, sha256Hex } from '../../src/engine';
import * as account from '../../src/callables/account';
import * as games from '../../src/callables/games';
import * as market from '../../src/callables/market';
import { rollDice, settleBoard } from '../../src/games/craps/engine';
import { crapsModule } from '../../src/games/craps/module';
import { overrideGameModuleForTests } from '../../src/games/registry';
import type { CrapsPublic } from '../../src/shared/games/craps';
import type { GameBetDoc, GameRoundDoc, GameTableDoc } from '../../src/shared/games/common';
import { DECISION_GRACE_MS, WELCOME_BONUS_CENTS, type MarketDoc, type ProfileDoc } from '../../src/shared/types';
import { admin, balance, ledgerSum } from './client';
import { inprocPlayer, reasonIn, run, runRaw } from './inproc';

type P = { uid: string; username: string };

async function gtable(id: string): Promise<GameTableDoc<CrapsPublic>> {
  return (await admin().doc(`gameTables/${id}`).get()).data() as GameTableDoc<CrapsPublic>;
}
async function board(id: string, uid: string): Promise<GameBetDoc | undefined> {
  return (await admin().doc(`gameTables/${id}/bets/${uid}`).get()).data() as GameBetDoc | undefined;
}
async function roundDoc(id: string, round: number): Promise<GameRoundDoc> {
  return (await admin().doc(`gameTables/${id}/rounds/${String(round).padStart(8, '0')}`).get()).data() as GameRoundDoc;
}

/** Expires the current deadline (+ the human grace) and pokes, like a client would. */
async function expire(p: P, tableId: string) {
  await admin().doc(`gameTables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS - 1 });
  return run(games.gamePoke, p.uid, { tableId });
}

async function bet(p: P, tableId: string, bets: Record<string, number>, power?: 'safetyNet' | 'zeroShield') {
  const round = (await gtable(tableId)).round;
  return run(games.gameAction, p.uid, { tableId, round, action: { type: 'setBets', bets, ...(power ? { power } : {}) } });
}
async function roll(p: P, tableId: string, requestId?: string) {
  const round = (await gtable(tableId)).round;
  return run(games.gameAction, p.uid, { tableId, round, action: { type: 'roll' }, ...(requestId ? { requestId } : {}) });
}

/** A private craps table: a (seat 0, the shooter) and b (seat 1, joined by code). */
async function privateCraps(): Promise<{ a: P; b: P; tableId: string }> {
  const a = await inprocPlayer();
  const b = await inprocPlayer();
  const c = await run(games.gameJoin, a.uid, { game: 'craps', mode: 'createPrivate', stakeTier: 'low' });
  expect(c.tableId).toMatch(/^cr-/);
  const j = await run(games.gameJoin, b.uid, { game: 'roulette', mode: 'joinCode', stakeTier: 'high', code: c.code! });
  expect(j).toMatchObject({ tableId: c.tableId, game: 'craps', status: 'seated', seatIndex: 1 });
  return { a, b, tableId: c.tableId };
}

/** Sum of the settled nets of `uid` over the rounds of a table. */
async function settledNet(tableId: string, uid: string): Promise<number> {
  const rounds = await admin().collection(`gameTables/${tableId}/rounds`).get();
  return rounds.docs.reduce((a, d) => a + ((d.data() as GameRoundDoc).seats.find((s) => s.uid === uid)?.netCents ?? 0), 0);
}

afterAll(() => overrideGameModuleForTests('craps', null));

describe('craps on the emulators', () => {
  it('a full roll: fast-path bets, the shooter throws, provably-fair dice, exact payouts, the board stays', async () => {
    const { a, b, tableId } = await privateCraps();
    const t0 = await gtable(tableId);
    expect(t0).toMatchObject({ phase: 'betting', step: 'comeOut', round: 1, turn: { seatIndex: 0 }, game: 'craps' });
    expect(t0.g).toMatchObject({ shooter: 0, shooterUid: a.uid, point: null });
    expect(t0.limits).toMatchObject({ minBetCents: 100, maxBetCents: 10_000, maxRoundCents: 200_000 });
    expect(t0.fairness.currentCommit).toMatch(/^[0-9a-f]{64}$/);
    expect(await reasonIn(roll(b, tableId))).toBe('NOT_SHOOTER');
    expect(await reasonIn(roll(a, tableId))).toBe('MUST_BET_LINE');
    const r1 = await bet(a, tableId, { pass: 1_000, place6: 600 });
    expect(r1).toMatchObject({ phase: 'betting', round: 1, balanceCents: WELCOME_BONUS_CENTS - 1_600, data: { bets: { pass: 1_000, place6: 600 }, totalCents: 1_600 } });
    await bet(b, tableId, { dontPass: 500, field: 500 });
    const t1 = await gtable(tableId);
    expect(t1.updatedAtMs).toBe(t0.updatedAtMs); // the bets never write the table document

    const thrown = await roll(a, tableId);
    expect(thrown.phase).toBe('betting');
    expect(typeof thrown.data?.rollAt).toBe('number');
    const t2 = await gtable(tableId);
    expect(t2.g.rollAt).toBe(thrown.data!.rollAt);
    expect(t2.events.some((e) => e.type === 'throw' && e.seatIndex === 0)).toBe(true);

    expect((await expire(a, tableId)).phase).toBe('live');
    const live = await gtable(tableId);
    const [d1, d2] = live.g.dice!;
    expect(live.g.roll).toMatchObject({ d1, d2, total: d1 + d2, pointBefore: null });
    const seven = (await admin().doc(`markets/${tableId}__r1__crapsSeven`).get()).data() as MarketDoc;
    expect(seven).toMatchObject({ status: 'resolved', game: 'craps', outcome: d1 + d2 === 7 ? 'yes' : 'no' });
    expect(await reasonIn(bet(b, tableId, { dontPass: 500 }))).toBe('BAD_PHASE');
    expect(await reasonIn(roll(a, tableId))).toBe('BAD_PHASE');

    expect((await expire(a, tableId)).phase).toBe('settled');
    const ctx = { pointBefore: null, d1, d2, safetyNet: false, leaving: false };
    const sa = settleBoard({ pass: 1_000, place6: 600 }, ctx);
    const sb = settleBoard({ dontPass: 500, field: 500 }, ctx);
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 1_600 + sa.returnCents);
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 1_000 + sb.returnCents);
    expect((await board(tableId, a.uid))!.bets).toEqual(sa.carry);
    expect((await board(tableId, b.uid))!.bets).toEqual(sb.carry);
    expect((await board(tableId, a.uid))!.previous).toEqual({ pass: 1_000, place6: 600 });
    for (const p of [a, b]) expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
    const round = await roundDoc(tableId, 1);
    expect(sha256Hex(round.fairness.seed)).toBe(t0.fairness.currentCommit);
    expect(rollDice(seededRng(round.fairness.seed))).toEqual([d1, d2]);
    expect(round.result).toMatchObject({ dice: [d1, d2], total: d1 + d2, noRoll: false, shooter: 0 });
    const rowA = round.seats.find((s) => s.uid === a.uid);
    const profA = (await admin().doc(`profiles/${a.uid}`).get()).data() as ProfileDoc;
    expect(profA.gameStats?.craps?.rounds ?? 0).toBe(rowA ? 1 : 0);
    if (rowA) expect(rowA.netCents).toBe(sa.netCents);
  });

  it('double spend: a bet and a purchase racing for the last $10 — exactly one wins', async () => {
    const { a, tableId } = await privateCraps();
    await run(account.submitKyc, a.uid, { docType: 'passport', birthDate: '1990-05-17' });
    await admin().doc(`users/${a.uid}/private/kyc`).update({ verifyAfterMs: Date.now() - 1 });
    await run(account.submitKyc, a.uid, { refresh: true });
    await run(account.withdraw, a.uid, { amountCents: WELCOME_BONUS_CENTS - 1_000, method: 'card' });
    const res = await Promise.all([
      reasonIn(bet(a, tableId, { pass: 1_000 })),
      reasonIn(run(account.buyPower, a.uid, { powerId: 'freeInsurance', quantity: 1 })),
    ]);
    expect(res.filter((r) => r === 'NO_ERROR')).toHaveLength(1);
    expect(res.filter((r) => r === 'INSUFFICIENT_FUNDS')).toHaveLength(1);
    expect(await balance(a.uid)).toBe(0);
    expect(await ledgerSum(a.uid)).toBe(0);
  });

  it('replay: the same requestId executes once (bets and the throw); reused for another callable it is refused', async () => {
    const { a, tableId } = await privateCraps();
    const t = await gtable(tableId);
    const requestId = randomUUID();
    const action = { type: 'setBets', bets: { pass: 500 } };
    const r1 = await run(games.gameAction, a.uid, { requestId, tableId, round: t.round, action });
    const r2 = await run(games.gameAction, a.uid, { requestId, tableId, round: t.round, action });
    expect(r2).toEqual(r1);
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 500);
    const rid = randomUUID();
    const x1 = await roll(a, tableId, rid);
    const x2 = await roll(a, tableId, rid);
    expect(x2).toEqual(x1);
    expect((await gtable(tableId)).events.filter((e) => e.type === 'throw')).toHaveLength(1);
    expect(await reasonIn(run(games.gamePoke, a.uid, { requestId, tableId }))).toBe('REQUEST_ID_REUSED');
  });

  it('forbidden bets, contract bets, odds and powers are refused and debit nothing; a power is consumed once', async () => {
    const { a, b, tableId } = await privateCraps();
    const r = (await gtable(tableId)).round;
    expect(await reasonIn(bet(b, tableId, { place7: 500 }))).toBe('BAD_BET_SPOT');
    expect(await reasonIn(bet(b, tableId, { place6: 500 }))).toBe('BET_INCREMENT');
    expect(await reasonIn(bet(b, tableId, { come: 500 }))).toBe('BET_NOT_OPEN');
    expect(await reasonIn(bet(b, tableId, { 'odds:pass': 500 }))).toBe('BET_NOT_OPEN');
    expect(await reasonIn(bet(b, tableId, { field: 10_100 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reasonIn(bet(b, tableId, { field: 150 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reasonIn(bet(a, tableId, { field: 500 }))).toBe('MUST_BET_LINE');
    expect(await reasonIn(run(games.gameAction, b.uid, { tableId, round: r + 1, action: { type: 'setBets', bets: { pass: 500 } } }))).toBe('STALE_HAND');
    expect(await reasonIn(runRaw(games.gameAction, a.uid, { requestId: randomUUID(), tableId, round: r, action: { type: 'roll', hard: true } }))).toBe('INVALID_ARGUMENT');
    expect(await reasonIn(bet(b, tableId, { pass: 500 }, 'zeroShield'))).toBe('WRONG_GAME');
    expect(await reasonIn(bet(b, tableId, { pass: 500 }, 'safetyNet'))).toBe('POWER_NOT_OWNED');
    const stranger = await inprocPlayer();
    expect(await reasonIn(bet(stranger, tableId, { pass: 500 }))).toBe('NOT_SEATED');
    expect(await reasonIn(roll(stranger, tableId))).toBe('NOT_SEATED');
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS);

    await run(account.buyPower, b.uid, { powerId: 'safetyNet', quantity: 1 });
    expect(await reasonIn(bet(b, tableId, { dontPass: 500 }, 'safetyNet'))).toBe('POWER_NOT_APPLICABLE');
    const ok = await bet(b, tableId, { pass: 500 }, 'safetyNet');
    expect(ok.data).toMatchObject({ power: 'safetyNet', totalCents: 500 });
    expect((await admin().doc(`users/${b.uid}/inventory/safetyNet`).get()).get('quantity')).toBe(0);
    await bet(b, tableId, { pass: 500, field: 100 }, 'safetyNet'); // already attached: not consumed again
    await bet(b, tableId, { pass: 500 });
    expect(await ledgerSum(b.uid)).toBe(await balance(b.uid));

    // a point is ON (set directly): the Pass Line becomes a contract bet
    await admin().doc(`gameTables/${tableId}`).update({ 'g.point': 6, step: 'point' });
    const before = await balance(b.uid);
    expect(await reasonIn(bet(b, tableId, {}))).toBe('BET_NOT_REMOVABLE');
    expect(await reasonIn(bet(b, tableId, { pass: 1_000 }))).toBe('BET_NOT_OPEN');
    expect(await reasonIn(bet(b, tableId, { pass: 500, 'odds:pass': 2_600 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reasonIn(bet(b, tableId, { pass: 500, dontPass: 500 }))).toBe('BET_NOT_OPEN');
    expect(await balance(b.uid)).toBe(before);
    const odds = await bet(b, tableId, { pass: 500, 'odds:pass': 2_500, come: 100 });
    expect(odds.balanceCents).toBe(before - 2_600);
  });

  it('no trading on a market of your own craps table; a spectator can', async () => {
    const { a, tableId } = await privateCraps();
    const marketId = (await gtable(tableId)).markets.round.crapsSeven!;
    expect(marketId).toBe(`${tableId}__r1__crapsSeven`);
    expect(await reasonIn(run(market.tradeShares, a.uid, { marketId, side: 'yes', direction: 'buy', shares: 5 }))).toBe('OWN_TABLE_MARKET');
    const spec = await inprocPlayer();
    const buy = await run(market.tradeShares, spec.uid, { marketId, side: 'no', direction: 'buy', shares: 10 });
    expect(buy.amountCents).toBeGreaterThan(400);
  });

  it('leaving keeps only the contract bet; it is decided by deadlines alone, then the table closes', async () => {
    const { a, b, tableId } = await privateCraps();
    await bet(a, tableId, { pass: 1_000 });
    await admin().doc(`gameTables/${tableId}`).update({ 'g.point': 8, step: 'point' });
    await bet(a, tableId, { pass: 1_000, 'odds:pass': 2_000, place6: 600 });
    expect(await run(games.gameLeave, a.uid, { tableId })).toEqual({ left: true, refundedCents: 2_600, cashOutCents: 0, deferred: true });
    expect((await board(tableId, a.uid))!.bets).toEqual({ pass: 1_000 });
    expect((await admin().doc(`profiles/${a.uid}`).get()).get('currentTableId')).toBeNull();
    let t = await gtable(tableId);
    expect(t.g).toMatchObject({ shooter: 1, shooterUid: b.uid }); // the dice passed on
    expect(await run(games.gameLeave, b.uid, { tableId })).toMatchObject({ left: true, deferred: false });
    t = await gtable(tableId);
    expect(t.status).toBe('open'); // a's Pass Line is still working
    for (let i = 0; i < 80 && t.status === 'open'; i++) {
      await expire(b, tableId);
      t = await gtable(tableId);
    }
    expect(t.status).toBe('closed');
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS + (await settledNet(tableId, a.uid)));
    expect(await ledgerSum(a.uid)).toBe(await balance(a.uid));
    expect((await admin().collection(`gameTables/${tableId}/bets`).get()).size).toBe(0);
  });

  it('a closing table (game withdrawn) refunds every board carried from roll to roll', async () => {
    const { a, b, tableId } = await privateCraps();
    await bet(a, tableId, { pass: 1_000, place6: 600, hard8: 100 }); // place / hard are off on the come-out: they stay
    await bet(b, tableId, { dontPass: 500, place8: 900 });
    await expire(a, tableId);
    await expire(a, tableId);
    const carriedA = (await board(tableId, a.uid))!;
    expect(carriedA.bets).toMatchObject({ place6: 600, hard8: 100 });
    expect(carriedA.round).toBe(1);
    expect((await gtable(tableId)).phase).toBe('settled');
    overrideGameModuleForTests('craps', { ...crapsModule, available: false });
    try {
      const poke = await run(games.gamePoke, a.uid, { tableId });
      expect(poke).toMatchObject({ phase: 'closed', advanced: true });
      for (const p of [a, b]) {
        expect(await balance(p.uid)).toBe(WELCOME_BONUS_CENTS + (await settledNet(tableId, p.uid)));
        expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
        expect((await admin().doc(`profiles/${p.uid}`).get()).get('currentTableId')).toBeNull();
      }
      expect((await admin().collection(`gameTables/${tableId}/bets`).get()).size).toBe(0);
      const refunds = await admin().collection(`users/${a.uid}/ledger`).where('type', '==', 'refund').get();
      expect(refunds.docs.map((d) => d.get('amountCents'))).toContain(Object.values(carriedA.bets).reduce((x, v) => x + v, 0));
      expect(await reasonIn(run(games.gameJoin, a.uid, { game: 'craps', mode: 'quick', stakeTier: 'low' }))).toBe('FEATURE_UNAVAILABLE');
    } finally {
      overrideGameModuleForTests('craps', null);
    }
  });
});
