/**
 * Emulator integration of the generic kernel through the real callable code, in-process (see
 * ./inproc.ts), with the test-only modules swapped in: roulette tables play "coin" (bet boards),
 * hold'em tables play "duel" (stacks). Covers: fast-path bets that never write the table, deadlines,
 * provably-fair rounds, payouts + ledger, double spend, replay, out of turn, forbidden bets,
 * powers, buy-in / cash-out, refunds on leave and close, one location across games, own-table
 * markets, Rendez-vous affinity, a withdrawn game closing with refunds.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { sha256Hex } from '../../src/engine';
import * as account from '../../src/callables/account';
import * as games from '../../src/callables/games';
import * as market from '../../src/callables/market';
import * as table from '../../src/callables/table';
import { overrideGameModuleForTests } from '../../src/games/registry';
import { coinModule, coinReturn } from '../../src/games/testing/coin';
import { duelModule, type DuelPublic } from '../../src/games/testing/duel';
import type { GameBetDoc, GameRoundDoc, GameTableDoc } from '../../src/shared/games/common';
import { dayId } from '../../src/shared/time';
import type { MarketDoc, PositionDoc, ProfileDoc } from '../../src/shared/types';
import { DECISION_GRACE_MS, WELCOME_BONUS_CENTS } from '../../src/shared/types';
import { admin, balance, ledgerSum } from './client';
import { inprocPlayer, reasonIn, run, runRaw } from './inproc';

type P = { uid: string; username: string };

async function gtable(id: string): Promise<GameTableDoc> {
  return (await admin().doc(`gameTables/${id}`).get()).data() as GameTableDoc;
}

/** Expires the current deadline (+ the human grace) and pokes, like a client would. */
async function expire(p: P, tableId: string) {
  await admin().doc(`gameTables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS - 1 });
  return run(games.gamePoke, p.uid, { tableId });
}

const bet = (p: P, tableId: string, round: number, bets: Record<string, number>, power?: 'zeroShield' | 'freeCommission') =>
  run(games.gameAction, p.uid, { tableId, round, action: { type: 'setBets', bets, ...(power ? { power } : {}) } });

async function privateCoin(): Promise<{ a: P; b: P; tableId: string; code: string }> {
  const a = await inprocPlayer();
  const b = await inprocPlayer();
  const c = await run(games.gameJoin, a.uid, { game: 'roulette', mode: 'createPrivate', stakeTier: 'low' });
  expect(c.tableId).toMatch(/^rl-/);
  expect(c.code).toMatch(/^[A-Z0-9]{6}$/);
  expect((await gtable(c.tableId)).name).not.toContain(c.code!);
  const j = await run(games.gameJoin, b.uid, { game: 'baccarat', mode: 'joinCode', stakeTier: 'high', code: c.code!.toLowerCase() });
  expect(j).toEqual({ tableId: c.tableId, game: 'roulette', status: 'seated', seatIndex: 1, code: c.code });
  return { a, b, tableId: c.tableId, code: c.code! };
}

beforeAll(() => {
  overrideGameModuleForTests('roulette', coinModule({ game: 'roulette' }));
  overrideGameModuleForTests('holdem', duelModule({ game: 'holdem' }));
});
afterAll(() => {
  overrideGameModuleForTests('roulette', null);
  overrideGameModuleForTests('holdem', null);
});

describe('a bet-board game (coin as roulette)', () => {
  it('fast-path bets never write the table; a full provably-fair round pays exactly, ledger and affinity follow', async () => {
    const { a, b, tableId } = await privateCoin();
    const t0 = await gtable(tableId);
    expect(t0.phase).toBe('betting');
    expect(t0.fairness.currentCommit).toMatch(/^[0-9a-f]{64}$/);
    const r1 = await bet(a, tableId, t0.round, { heads: 1_000, edge: 100 });
    expect(r1).toMatchObject({ phase: 'betting', round: 1, balanceCents: WELCOME_BONUS_CENTS - 1_100, stackCents: null });
    await bet(b, tableId, t0.round, { tails: 500 });
    await bet(b, tableId, t0.round, { tails: 300 }); // whole board: refunds the difference
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 300);
    const t1 = await gtable(tableId);
    expect(t1.updatedAtMs).toBe(t0.updatedAtMs); // the table document was not written by the bets
    expect(t1.eventSeq).toBe(t0.eventSeq);
    const boardA = (await admin().doc(`gameTables/${tableId}/bets/${a.uid}`).get()).data() as GameBetDoc;
    expect(boardA).toMatchObject({ uid: a.uid, seatIndex: 0, round: 1, bets: { heads: 1_000, edge: 100 }, totalCents: 1_100, power: null });

    const flip = await expire(a, tableId);
    expect(flip).toMatchObject({ phase: 'live', round: 1, advanced: true });
    const live = await gtable(tableId);
    const n = (live.g as { outcome: number }).outcome;
    expect(live.seats[0]!.stakeCents).toBe(1_100);
    const marketId = `${tableId}__r1__rouletteRed`;
    expect(((await admin().doc(`markets/${marketId}`).get()).data() as MarketDoc)).toMatchObject({ status: 'resolved', game: 'roulette', outcome: n >= 1 && n <= 18 ? 'yes' : 'no' });
    expect(await reasonIn(bet(b, tableId, 1, { tails: 400 }))).toBe('BAD_PHASE');

    expect((await expire(a, tableId)).phase).toBe('settled');
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 1_100 + coinReturn({ heads: 1_000, edge: 100 }, n, false));
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 300 + coinReturn({ tails: 300 }, n, false));
    for (const p of [a, b]) expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
    const round = (await admin().doc(`gameTables/${tableId}/rounds/00000001`).get()).data() as GameRoundDoc;
    expect(sha256Hex(round.fairness.seed)).toBe(t0.fairness.currentCommit);
    expect(round.seats.map((s) => s.uid).sort()).toEqual([a.uid, b.uid].sort());
    const settled = await gtable(tableId);
    expect(settled.fairness.lastSeed).toBe(round.fairness.seed);
    const day = dayId(Date.now());
    for (const p of [a, b]) {
      expect((await admin().doc(`users/${p.uid}/romance/camille`).get()).get('tablePlay')?.[day]).toBe(1);
      const prof = (await admin().doc(`profiles/${p.uid}`).get()).data() as ProfileDoc;
      expect(prof.gameStats?.roulette?.rounds).toBe(1);
      expect(prof.rankDaily?.day).toBe(day);
    }
    expect(((await admin().doc(`gameTables/${tableId}/bets/${a.uid}`).get()).data() as GameBetDoc)).toMatchObject({ bets: {}, totalCents: 0, previous: { heads: 1_000, edge: 100 } });
  });

  it('double spend: a bet and a purchase racing for the last $10 — exactly one wins', async () => {
    const { a, tableId } = await privateCoin();
    await run(account.submitKyc, a.uid, { docType: 'passport', birthDate: '1990-05-17' });
    await admin().doc(`users/${a.uid}/private/kyc`).update({ verifyAfterMs: Date.now() - 1 });
    await run(account.submitKyc, a.uid, { refresh: true });
    await run(account.withdraw, a.uid, { amountCents: WELCOME_BONUS_CENTS - 1_000, method: 'card' });
    const t = await gtable(tableId);
    const res = await Promise.all([
      reasonIn(bet(a, tableId, t.round, { heads: 1_000 })),
      reasonIn(run(account.buyPower, a.uid, { powerId: 'freeInsurance', quantity: 1 })),
    ]);
    expect(res.filter((r) => r === 'NO_ERROR')).toHaveLength(1);
    expect(res.filter((r) => r === 'INSUFFICIENT_FUNDS')).toHaveLength(1);
    expect(await balance(a.uid)).toBe(0);
    expect(await ledgerSum(a.uid)).toBe(0);
  });

  it('replay with the same requestId executes once; a requestId reused for another callable is refused', async () => {
    const { a, tableId } = await privateCoin();
    const t = await gtable(tableId);
    const requestId = randomUUID();
    const r1 = await run(games.gameAction, a.uid, { requestId, tableId, round: t.round, action: { type: 'setBets', bets: { heads: 500 } } });
    const r2 = await run(games.gameAction, a.uid, { requestId, tableId, round: t.round, action: { type: 'setBets', bets: { heads: 500 } } });
    expect(r2).toEqual(r1);
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 500);
    expect(await reasonIn(run(games.gamePoke, a.uid, { requestId, tableId }))).toBe('REQUEST_ID_REUSED');
  });

  it('forbidden bets and powers are refused and debit nothing; an owned power is consumed once', async () => {
    const { a, b, tableId } = await privateCoin();
    const r = (await gtable(tableId)).round;
    expect(await reasonIn(bet(a, tableId, r, { zero: 100 }))).toBe('BAD_BET_SPOT');
    expect(await reasonIn(bet(a, tableId, r, { heads: 150 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reasonIn(bet(a, tableId, r, { heads: 10_100 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reasonIn(bet(a, tableId, r + 1, { heads: 100 }))).toBe('STALE_HAND');
    expect(await reasonIn(bet(a, tableId, r, { heads: 100 }, 'freeCommission'))).toBe('WRONG_GAME');
    expect(await reasonIn(bet(a, tableId, r, { heads: 100 }, 'zeroShield'))).toBe('POWER_NOT_OWNED');
    expect(await reasonIn(runRaw(games.gameAction, a.uid, { requestId: randomUUID(), tableId, round: r, action: { type: 'cheer', loud: true } }))).toBe('INVALID_ARGUMENT');
    expect(await reasonIn(runRaw(games.gameAction, a.uid, { requestId: randomUUID(), tableId, round: r, action: { type: 'dance' } }))).toBe('INVALID_ARGUMENT');
    const stranger = await inprocPlayer();
    expect(await reasonIn(bet(stranger, tableId, r, { heads: 100 }))).toBe('NOT_SEATED');
    expect(await reasonIn(run(games.gameAction, stranger.uid, { tableId, round: r, action: { type: 'cheer' } }))).toBe('NOT_SEATED');
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
    await run(account.buyPower, a.uid, { powerId: 'zeroShield', quantity: 1 });
    expect(await reasonIn(bet(a, tableId, r, { edge: 100 }, 'zeroShield'))).toBe('POWER_NOT_APPLICABLE');
    const ok = await bet(a, tableId, r, { heads: 200 }, 'zeroShield');
    expect(ok.data).toMatchObject({ power: 'zeroShield', totalCents: 200 });
    expect((await admin().doc(`users/${a.uid}/inventory/zeroShield`).get()).get('quantity')).toBe(0);
    await bet(a, tableId, r, { heads: 300 }, 'zeroShield'); // already attached: not consumed again
    expect(await ledgerSum(a.uid)).toBe(await balance(a.uid));
    await bet(b, tableId, r, { tails: 100 });
    await expire(a, tableId);
    expect((await gtable(tableId)).seats[0]!.powerUsed).toBe('zeroShield');
  });

  it('leaving during betting refunds the board; the last human leaving closes the table', async () => {
    const { a, b, tableId } = await privateCoin();
    const r = (await gtable(tableId)).round;
    await bet(a, tableId, r, { heads: 700 });
    expect(await run(games.gameLeave, a.uid, { tableId })).toEqual({ left: true, refundedCents: 700, cashOutCents: 0, deferred: false });
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
    expect((await admin().doc(`gameTables/${tableId}/bets/${a.uid}`).get()).exists).toBe(false);
    expect((await admin().doc(`profiles/${a.uid}`).get()).get('currentTableId')).toBeNull();
    await run(games.gameLeave, b.uid, { tableId });
    expect((await gtable(tableId)).status).toBe('closed');
    expect(await reasonIn(run(games.gameLeave, b.uid, { tableId }))).toBe('NOT_SEATED');
  });
});

describe('quick matchmaking, one location for every game, own-table markets', () => {
  it('quick-join creates a public table with 2 bots; one location across blackjack and the other games', async () => {
    const a = await inprocPlayer();
    const q = await run(games.gameJoin, a.uid, { game: 'roulette', mode: 'quick', stakeTier: 'mid' });
    expect(q).toMatchObject({ game: 'roulette', status: 'seated' });
    const t = await gtable(q.tableId);
    expect([t.humanCount, t.botCount, t.isPrivate]).toEqual([1, 2, false]);
    expect((await run(games.gameJoin, a.uid, { game: 'roulette', mode: 'quick', stakeTier: 'mid' })).tableId).toBe(q.tableId); // idempotent
    expect(await reasonIn(run(games.gameJoin, a.uid, { game: 'roulette', mode: 'quick', stakeTier: 'low' }))).toBe('ALREADY_SEATED');
    expect(await reasonIn(run(table.joinMatchmaking, a.uid, { mode: 'quick', stakeTier: 'mid' }))).toBe('ALREADY_SEATED');
    expect(await reasonIn(run(table.joinMatchmaking, a.uid, { mode: 'createPrivate', stakeTier: 'low' }))).toBe('ALREADY_SEATED');
    // a second human quick-joining the same game and tier lands at the same table
    const b = await inprocPlayer();
    expect((await run(games.gameJoin, b.uid, { game: 'roulette', mode: 'quick', stakeTier: 'mid' })).tableId).toBe(q.tableId);
    await run(games.gameLeave, a.uid, { tableId: q.tableId });
    const bj = await run(table.joinMatchmaking, a.uid, { mode: 'createPrivate', stakeTier: 'low' });
    expect(await reasonIn(run(games.gameJoin, a.uid, { game: 'roulette', mode: 'quick', stakeTier: 'mid' }))).toBe('ALREADY_SEATED');
    await run(table.leaveTable, a.uid, { tableId: bj.tableId });
    await run(games.gameLeave, b.uid, { tableId: q.tableId });
    expect((await gtable(q.tableId)).status).toBe('closed');
  });

  it('no trading on a market of your own game table; a spectator trades (humanTradeCount) and is paid', async () => {
    const { a, b, tableId } = await privateCoin();
    const marketId = (await gtable(tableId)).markets.round.rouletteRed!;
    expect(await reasonIn(run(market.tradeShares, a.uid, { marketId, side: 'yes', direction: 'buy', shares: 5 }))).toBe('OWN_TABLE_MARKET');
    const spec = await inprocPlayer();
    const buy = await run(market.tradeShares, spec.uid, { marketId, side: 'yes', direction: 'buy', shares: 10 });
    expect(buy.amountCents).toBeGreaterThan(500);
    expect(((await admin().doc(`markets/${marketId}`).get()).data() as MarketDoc).humanTradeCount).toBe(1);
    await bet(a, tableId, 1, { heads: 100 });
    await bet(b, tableId, 1, { tails: 100 });
    await expire(a, tableId); // the coin is drawn: market closed and resolved in that transaction
    expect(await reasonIn(run(market.tradeShares, spec.uid, { marketId, side: 'yes', direction: 'buy', shares: 1 }))).toBe('MARKET_CLOSED');
    const m = (await admin().doc(`markets/${marketId}`).get()).data() as MarketDoc;
    let pos: PositionDoc | undefined;
    for (let i = 0; i < 20; i++) {
      pos = (await admin().doc(`users/${spec.uid}/positions/${marketId}`).get()).data() as PositionDoc;
      if (pos.status !== 'open') break;
      await new Promise((r) => setTimeout(r, 250));
    }
    expect(pos!.status).toBe(m.outcome === 'yes' ? 'won' : 'lost');
    expect(await ledgerSum(spec.uid)).toBe(await balance(spec.uid));
  });
});

describe('a stack game (duel as hold\'em)', () => {
  it('buy-in at join, turns enforced, rebuy only between hands, cash-out on leave', async () => {
    const a = await inprocPlayer();
    const b = await inprocPlayer();
    expect(await reasonIn(run(games.gameJoin, a.uid, { game: 'holdem', mode: 'createPrivate', stakeTier: 'low' }))).toBe('BUY_IN_REQUIRED');
    expect(await reasonIn(run(games.gameJoin, a.uid, { game: 'holdem', mode: 'createPrivate', stakeTier: 'low', buyInCents: 999_900 }))).toBe('BUY_IN_OUT_OF_RANGE');
    const c = await run(games.gameJoin, a.uid, { game: 'holdem', mode: 'createPrivate', stakeTier: 'low', buyInCents: 2_000 });
    const tableId = c.tableId;
    expect(tableId).toMatch(/^ho-/);
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 2_000);
    expect((await gtable(tableId)).phase).toBe('idle');
    await run(games.gameJoin, b.uid, { game: 'holdem', mode: 'joinCode', stakeTier: 'low', code: c.code!, buyInCents: 3_000 });
    let t = await gtable(tableId);
    expect(t.phase).toBe('live');
    const ids = (t.g as unknown as DuelPublic).order.map((i) => t.seats[i]!.uid);
    const [first, second] = ids.map((uid) => (uid === a.uid ? a : b));
    expect(await reasonIn(run(games.gameAction, second.uid, { tableId, round: t.round, action: { type: 'play' } }))).toBe('NOT_YOUR_TURN');
    expect(await reasonIn(run(games.gameAction, first.uid, { tableId, round: t.round - 1, action: { type: 'play' } }))).toBe('STALE_HAND');
    expect(await reasonIn(run(games.gameAction, first.uid, { tableId, round: t.round, action: { type: 'rebuy', cents: 100 } }))).toBe('REBUY_NOT_ALLOWED');
    expect(await reasonIn(run(games.gameAction, first.uid, { tableId, round: t.round, action: { type: 'setBets', bets: { x: 100 } } }))).toBe('ILLEGAL_ACTION');
    // hole cards: only in holes/{uid}
    expect((await admin().doc(`gameTables/${tableId}/holes/${first.uid}`).get()).get('cards')).toHaveLength(1);
    expect(JSON.stringify(t)).not.toMatch(/"cards"/);
    const played = await run(games.gameAction, first.uid, { tableId, round: t.round, action: { type: 'play' } });
    expect(played.stackCents).toBe((first === a ? 2_000 : 3_000) - 200);
    await run(games.gameAction, second.uid, { tableId, round: t.round, action: { type: 'fold' } });
    t = await gtable(tableId);
    expect(t.phase).toBe('settled');
    const stacks = t.seats.filter(Boolean).reduce((x, s) => x + s!.stackCents!, 0);
    expect(stacks).toBe(5_000); // zero-sum
    const rb = await run(games.gameAction, a.uid, { tableId, round: t.round, action: { type: 'rebuy', cents: 1_000 } });
    expect(rb.balanceCents).toBe(WELCOME_BONUS_CENTS - 3_000);
    const seatA = (await gtable(tableId)).seats.find((s) => s?.uid === a.uid)!;
    const left = await run(games.gameLeave, a.uid, { tableId });
    expect(left).toEqual({ left: true, refundedCents: 0, cashOutCents: seatA.stackCents, deferred: false });
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 3_000 + seatA.stackCents!);
    expect(await ledgerSum(a.uid)).toBe(await balance(a.uid));
    const ledger = await admin().collection(`users/${a.uid}/ledger`).get();
    expect(ledger.docs.map((d) => d.get('type')).sort()).toEqual(['buyIn', 'buyIn', 'cashOut', 'welcomeBonus']);
    await run(games.gameLeave, b.uid, { tableId });
    expect((await gtable(tableId)).status).toBe('closed');
    expect(await balance(a.uid) + await balance(b.uid)).toBe(2 * WELCOME_BONUS_CENTS); // nothing created, nothing lost
  });
});

describe('a withdrawn game', () => {
  it('its open tables close at the next poke and every locked bet is refunded', async () => {
    const { a, b, tableId } = await privateCoin();
    await bet(a, tableId, 1, { heads: 900 });
    await bet(b, tableId, 1, { edge: 200 });
    await expire(a, tableId); // locked: the coin is flipping
    expect((await gtable(tableId)).phase).toBe('live');
    overrideGameModuleForTests('roulette', null); // back to the phase-A stub
    try {
      const poke = await run(games.gamePoke, a.uid, { tableId });
      expect(poke).toMatchObject({ phase: 'closed', advanced: true });
      expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
      expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS);
      expect((await admin().collection(`gameTables/${tableId}/bets`).get()).size).toBe(0);
      expect(await reasonIn(run(games.gameJoin, a.uid, { game: 'roulette', mode: 'quick', stakeTier: 'low' }))).toBe('FEATURE_UNAVAILABLE');
    } finally {
      overrideGameModuleForTests('roulette', coinModule({ game: 'roulette' }));
    }
  });
});
