/**
 * Emulator integration of the REAL roulette module (production registry) through the real callable
 * code, in-process (./inproc.ts: `execute()` on the Firestore emulator, one transaction per call).
 * Covers: a provably-fair round paid to the cent (ledger, history, profile counters), double
 * spend, replay, forbidden bets and powers, own-table markets, quick play with bots, leaving while
 * betting / while the ball spins, and a closing table refunding every locked board.
 */
import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { seededRng, sha256Hex } from '../../src/engine';
import * as account from '../../src/callables/account';
import * as games from '../../src/callables/games';
import * as market from '../../src/callables/market';
import { unavailableModule } from '../../src/games/kernel/unavailable';
import { overrideGameModuleForTests } from '../../src/games/registry';
import { colorOf, settleBoard } from '../../src/games/roulette/engine';
import type { GameBetDoc, GameRoundDoc, GameTableDoc } from '../../src/shared/games/common';
import type { RoulettePublic } from '../../src/shared/games/roulette';
import type { MarketDoc, PositionDoc, ProfileDoc } from '../../src/shared/types';
import { DECISION_GRACE_MS, WELCOME_BONUS_CENTS } from '../../src/shared/types';
import { admin, balance, ledgerSum } from './client';
import { inprocPlayer, reasonIn, run, runRaw } from './inproc';

type P = { uid: string; username: string };

async function gtable(id: string): Promise<GameTableDoc<RoulettePublic>> {
  return (await admin().doc(`gameTables/${id}`).get()).data() as GameTableDoc<RoulettePublic>;
}

/** Expires the current deadline (+ the human grace) and pokes, like a client would. */
async function expire(p: P, tableId: string) {
  await admin().doc(`gameTables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS - 1 });
  return run(games.gamePoke, p.uid, { tableId });
}

const bet = (p: P, tableId: string, round: number, bets: Record<string, number>, power?: 'zeroShield' | 'freeCommission') =>
  run(games.gameAction, p.uid, { tableId, round, action: { type: 'setBets', bets, ...(power ? { power } : {}) } });

async function privateRoulette(): Promise<{ a: P; b: P; tableId: string }> {
  const a = await inprocPlayer();
  const b = await inprocPlayer();
  const c = await run(games.gameJoin, a.uid, { game: 'roulette', mode: 'createPrivate', stakeTier: 'low' });
  expect(c.tableId).toMatch(/^rl-/);
  const j = await run(games.gameJoin, b.uid, { game: 'roulette', mode: 'joinCode', stakeTier: 'low', code: c.code! });
  expect(j).toMatchObject({ tableId: c.tableId, game: 'roulette', status: 'seated', seatIndex: 1 });
  return { a, b, tableId: c.tableId };
}

describe('roulette on the emulators (real module)', () => {
  it('a full provably-fair round: fast-path bets, draw at "Rien ne va plus", markets resolved, exact payouts, ledger, history, counters', async () => {
    const { a, b, tableId } = await privateRoulette();
    const t0 = await gtable(tableId);
    expect(t0).toMatchObject({ phase: 'betting', step: 'betting', round: 1, limits: { minBetCents: 100, maxBetCents: 10_000, maxRoundCents: 50_000 } });
    expect(t0.g).toEqual({ number: null, last: [], series: null, seriesCount: 0 });
    expect(t0.seats.filter(Boolean).map((s) => (s!.g as { color: number }).color)).toEqual([0, 1]);
    expect(Object.keys(t0.markets.round).sort()).toEqual(['rouletteDozen3', 'rouletteRed', 'rouletteZero']);
    const boardA = { n17: 2_500, 'sp0-3': 500, red: 3_000, dozen3: 1_000 };
    // voisins du zéro at $1 a chip, as the client computes it
    const boardB = { 'tr0-2-3': 200, 'sp4-7': 100, 'sp12-15': 100, 'sp18-21': 100, 'sp19-22': 100, 'sp32-35': 100, co25: 200 };
    const r1 = await bet(a, tableId, 1, boardA);
    expect(r1).toMatchObject({ phase: 'betting', round: 1, balanceCents: WELCOME_BONUS_CENTS - 7_000 });
    await bet(b, tableId, 1, { ...boardB, black: 5_000 });
    await bet(b, tableId, 1, boardB); // the whole board again: the black bet is refunded
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 900);
    const t1 = await gtable(tableId);
    expect(t1.updatedAtMs).toBe(t0.updatedAtMs); // bets never write the table document
    expect(((await admin().doc(`gameTables/${tableId}/bets/${a.uid}`).get()).data() as GameBetDoc)).toMatchObject({ bets: boardA, totalCents: 7_000 });

    expect(await expire(a, tableId)).toMatchObject({ phase: 'live', advanced: true });
    const live = await gtable(tableId);
    const n = live.g.number!;
    expect(live.step).toBe('spinning');
    expect(live.events.find((e) => e.type === 'spin')!.d).toEqual({ number: n, color: colorOf(n), spinMs: 8_000 });
    for (const [kind, yes] of [['rouletteRed', colorOf(n) === 'red'], ['rouletteZero', n === 0], ['rouletteDozen3', n >= 25]] as const) {
      const m = (await admin().doc(`markets/${tableId}__r1__${kind}`).get()).data() as MarketDoc;
      expect(m).toMatchObject({ status: 'resolved', game: 'roulette', outcome: yes ? 'yes' : 'no' });
    }
    expect(await reasonIn(bet(b, tableId, 1, boardB))).toBe('BAD_PHASE');

    expect((await expire(a, tableId)).phase).toBe('settled');
    const retA = settleBoard(boardA, n).returnCents;
    const retB = settleBoard(boardB, n).returnCents;
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 7_000 + retA);
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 900 + retB);
    for (const p of [a, b]) expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
    const round = (await admin().doc(`gameTables/${tableId}/rounds/00000001`).get()).data() as GameRoundDoc;
    expect(sha256Hex(round.fairness.seed)).toBe(t0.fairness.currentCommit);
    expect(seededRng(round.fairness.seed).nextInt(37)).toBe(n);
    expect(round.result).toEqual({ number: n, color: colorOf(n) });
    const settled = await gtable(tableId);
    expect(settled.events.filter((e) => e.type === 'payout').map((e) => [e.seatIndex, (e.d as { returnCents: number }).returnCents])).toEqual([[0, retA], [1, retB]]);
    const prof = (await admin().doc(`profiles/${a.uid}`).get()).data() as ProfileDoc;
    expect(prof.gameStats?.roulette).toMatchObject({ rounds: 1, netCents: retA - 7_000 });
    if (n === 17) expect(prof.gameStats?.roulette?.counters.straightUps).toBe(1);
    expect(((await admin().doc(`gameTables/${tableId}/bets/${a.uid}`).get()).data() as GameBetDoc)).toMatchObject({ bets: {}, totalCents: 0, previous: boardA });
  });

  it('double spend: a bet and a purchase racing for the last $10 — exactly one wins', async () => {
    const { a, tableId } = await privateRoulette();
    await run(account.submitKyc, a.uid, { docType: 'passport', birthDate: '1990-05-17' });
    await admin().doc(`users/${a.uid}/private/kyc`).update({ verifyAfterMs: Date.now() - 1 });
    await run(account.submitKyc, a.uid, { refresh: true });
    await run(account.withdraw, a.uid, { amountCents: WELCOME_BONUS_CENTS - 1_000, method: 'card' });
    const res = await Promise.all([
      reasonIn(bet(a, tableId, 1, { red: 1_000 })),
      reasonIn(run(account.buyPower, a.uid, { powerId: 'freeInsurance', quantity: 1 })),
    ]);
    expect(res.filter((r) => r === 'NO_ERROR')).toHaveLength(1);
    expect(res.filter((r) => r === 'INSUFFICIENT_FUNDS')).toHaveLength(1);
    expect(await balance(a.uid)).toBe(0);
    expect(await ledgerSum(a.uid)).toBe(0);
  });

  it('replay with the same requestId executes once', async () => {
    const { a, tableId } = await privateRoulette();
    const requestId = randomUUID();
    const once = () => run(games.gameAction, a.uid, { requestId, tableId, round: 1, action: { type: 'setBets', bets: { n0: 500 } } });
    const [r1, r2] = [await once(), await once()];
    expect(r2).toEqual(r1);
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 500);
    expect(await reasonIn(run(games.gamePoke, a.uid, { requestId, tableId }))).toBe('REQUEST_ID_REUSED');
  });

  it('forbidden bets and powers are refused and debit nothing; an owned zero shield is consumed once and pays la partage', async () => {
    const { a, b, tableId } = await privateRoulette();
    expect(await reasonIn(bet(a, tableId, 1, { n37: 100 }))).toBe('BAD_BET_SPOT');
    expect(await reasonIn(bet(a, tableId, 1, { 'sp3-4': 100 }))).toBe('BAD_BET_SPOT');
    expect(await reasonIn(bet(a, tableId, 1, { heads: 100 }))).toBe('BAD_BET_SPOT');
    expect(await reasonIn(bet(a, tableId, 1, { n5: 2_600 }))).toBe('BET_OUT_OF_RANGE'); // plein cap $25
    expect(await reasonIn(bet(a, tableId, 1, { red: 10_100 }))).toBe('BET_OUT_OF_RANGE'); // $100 per spot
    expect(await reasonIn(bet(a, tableId, 1, { red: 150 }))).toBe('BET_OUT_OF_RANGE'); // whole dollars
    expect(await reasonIn(bet(a, tableId, 1, { red: -100 }))).toBe('INVALID_ARGUMENT');
    const six = Object.fromEntries([1, 4, 7, 10, 13, 16].map((x) => [`ln${x}`, 10_000]));
    expect(await reasonIn(bet(a, tableId, 1, six))).toBe('BET_OUT_OF_RANGE'); // $600 > $500 per spin
    expect(await reasonIn(bet(a, tableId, 2, { red: 100 }))).toBe('STALE_HAND');
    expect(await reasonIn(bet(a, tableId, 1, { red: 100 }, 'freeCommission'))).toBe('WRONG_GAME');
    expect(await reasonIn(bet(a, tableId, 1, { red: 100 }, 'zeroShield'))).toBe('POWER_NOT_OWNED');
    expect(await reasonIn(runRaw(games.gameAction, a.uid, { requestId: randomUUID(), tableId, round: 1, action: { type: 'spin' } }))).toBe('INVALID_ARGUMENT');
    const stranger = await inprocPlayer();
    expect(await reasonIn(bet(stranger, tableId, 1, { red: 100 }))).toBe('NOT_SEATED');
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);

    await run(account.buyPower, a.uid, { powerId: 'zeroShield', quantity: 1 });
    const afterBuy = await balance(a.uid);
    expect(await reasonIn(bet(a, tableId, 1, { n0: 100, dozen1: 100 }, 'zeroShield'))).toBe('POWER_NOT_APPLICABLE');
    expect((await admin().doc(`users/${a.uid}/inventory/zeroShield`).get()).get('quantity')).toBe(1);
    const ok = await bet(a, tableId, 1, { red: 1_000, black: 1_000 }, 'zeroShield');
    expect(ok.data).toMatchObject({ power: 'zeroShield', totalCents: 2_000 });
    expect((await admin().doc(`users/${a.uid}/inventory/zeroShield`).get()).get('quantity')).toBe(0);
    await bet(a, tableId, 1, { red: 1_000, black: 1_000, n0: 100 }, 'zeroShield'); // already attached: not consumed again
    await bet(b, tableId, 1, { red: 1_000, black: 1_000 });
    await expire(a, tableId);
    const n = (await gtable(tableId)).g.number!;
    expect((await gtable(tableId)).seats[0]!.powerUsed).toBe('zeroShield');
    await expire(a, tableId);
    // red + black: 0 → the shielded player gets half back, the other loses everything
    const expectedA = settleBoard({ red: 1_000, black: 1_000, n0: 100 }, n, true).returnCents;
    expect(await balance(a.uid)).toBe(afterBuy - 2_100 + expectedA);
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 2_000 + (n === 0 ? 0 : 2_000));
    for (const p of [a, b]) expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
  });

  it('no trading on a market of your own roulette table; a spectator trades, the draw closes and resolves it', async () => {
    const { a, b, tableId } = await privateRoulette();
    const marketId = (await gtable(tableId)).markets.round.rouletteRed!;
    expect(await reasonIn(run(market.tradeShares, a.uid, { marketId, side: 'yes', direction: 'buy', shares: 5 }))).toBe('OWN_TABLE_MARKET');
    expect(await reasonIn(run(market.tradeShares, b.uid, { marketId, side: 'no', direction: 'buy', shares: 5 }))).toBe('OWN_TABLE_MARKET');
    const spec = await inprocPlayer();
    await run(market.tradeShares, spec.uid, { marketId, side: 'yes', direction: 'buy', shares: 10 });
    await bet(a, tableId, 1, { red: 100 });
    await expire(a, tableId);
    expect(await reasonIn(run(market.tradeShares, spec.uid, { marketId, side: 'yes', direction: 'buy', shares: 1 }))).toBe('MARKET_CLOSED');
    const m = (await admin().doc(`markets/${marketId}`).get()).data() as MarketDoc;
    expect(m.outcome).toBe(colorOf((await gtable(tableId)).g.number!) === 'red' ? 'yes' : 'no');
    let pos: PositionDoc | undefined;
    for (let i = 0; i < 20; i++) {
      pos = (await admin().doc(`users/${spec.uid}/positions/${marketId}`).get()).data() as PositionDoc;
      if (pos.status !== 'open') break;
      await new Promise((r) => setTimeout(r, 250));
    }
    expect(pos!.status).toBe(m.outcome === 'yes' ? 'won' : 'lost');
    expect(await ledgerSum(spec.uid)).toBe(await balance(spec.uid));
  });

  it('quick play: a public table with 2 bots whose boards are placed by the kernel', async () => {
    const a = await inprocPlayer();
    const q = await run(games.gameJoin, a.uid, { game: 'roulette', mode: 'quick', stakeTier: 'mid' });
    const t = await gtable(q.tableId);
    expect([t.humanCount, t.botCount, t.isPrivate, t.limits.minBetCents]).toEqual([1, 2, false, 500]);
    let botBoards = 0;
    for (let i = 0; i < 4 && botBoards === 0; i++) {
      const bets = await admin().collection(`gameTables/${q.tableId}/bets`).get();
      botBoards = bets.docs.filter((d) => d.get('isBot') && d.get('totalCents') > 0).length;
      if (botBoards === 0) {
        await bet(a, q.tableId, (await gtable(q.tableId)).round, { red: 500 });
        await expire(a, q.tableId);
        await expire(a, q.tableId);
        await expire(a, q.tableId);
      }
    }
    expect(botBoards).toBeGreaterThan(0);
    await run(games.gameLeave, a.uid, { tableId: q.tableId });
    expect((await gtable(q.tableId)).status).toBe('closed');
    expect(await ledgerSum(a.uid)).toBe(await balance(a.uid));
  });

  it('leaving while betting refunds the board; leaving while the ball spins settles it normally', async () => {
    const { a, b, tableId } = await privateRoulette();
    await bet(a, tableId, 1, { red: 700 });
    expect(await run(games.gameLeave, a.uid, { tableId })).toEqual({ left: true, refundedCents: 700, cashOutCents: 0, deferred: false });
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
    const c = await inprocPlayer();
    await run(games.gameJoin, c.uid, { game: 'roulette', mode: 'joinCode', stakeTier: 'low', code: (await admin().doc(`gameTables/${tableId}/private/state`).get()).get('code') });
    await bet(b, tableId, 1, { n7: 1_000 });
    await bet(c, tableId, 1, { even: 500 });
    await expire(b, tableId); // spinning: boards locked
    expect(await run(games.gameLeave, b.uid, { tableId })).toEqual({ left: true, refundedCents: 0, cashOutCents: 0, deferred: true });
    const n = (await gtable(tableId)).g.number!;
    await expire(c, tableId);
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 1_000 + settleBoard({ n7: 1_000 }, n).returnCents);
    expect((await admin().doc(`profiles/${b.uid}`).get()).get('currentTableId')).toBeNull();
    await run(games.gameLeave, c.uid, { tableId });
    expect((await gtable(tableId)).status).toBe('closed');
    for (const p of [a, b, c]) expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
  });

  it('a closing table (roulette withdrawn) refunds every locked board at the next poke', async () => {
    const { a, b, tableId } = await privateRoulette();
    await bet(a, tableId, 1, { n36: 900 });
    await bet(b, tableId, 1, { 'sp0-1': 200, col2: 300 });
    await expire(a, tableId); // the ball spins: locked boards
    expect((await gtable(tableId)).phase).toBe('live');
    overrideGameModuleForTests('roulette', unavailableModule('roulette'));
    try {
      expect(await run(games.gamePoke, a.uid, { tableId })).toMatchObject({ phase: 'closed', advanced: true });
      expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
      expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS);
      expect((await admin().collection(`gameTables/${tableId}/bets`).get()).size).toBe(0);
      const voided = await admin().collection('markets').where('tableId', '==', tableId).get();
      expect(voided.docs.every((d) => d.get('status') !== 'open')).toBe(true);
      for (const p of [a, b]) expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
    } finally {
      overrideGameModuleForTests('roulette', null);
    }
  });
});
