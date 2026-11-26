/**
 * Emulator integration of the BACCARAT through the real callable code, in-process (./inproc.ts),
 * with the production module (no override): a whole provably-fair coup paid to the cent, double
 * spend, replay, forbidden bets / actions, an unowned power, a power consumed once, betting on your
 * own table's market, a spectator paid, closing refunds (last human leaving, game withdrawn mid-coup),
 * quick matchmaking with bots.
 */
import { randomUUID } from 'node:crypto';
import { afterAll, describe, expect, it } from 'vitest';
import * as account from '../../src/callables/account';
import * as games from '../../src/callables/games';
import * as market from '../../src/callables/market';
import { sha256Hex, verifyFairness } from '../../src/engine';
import { settleBoard } from '../../src/games/baccarat/engine';
import { unavailableModule } from '../../src/games/kernel/unavailable';
import { overrideGameModuleForTests } from '../../src/games/registry';
import type { BaccaratPublic, BaccaratResult } from '../../src/shared/games/baccarat';
import type { GameBetDoc, GameRoundDoc, GameTableDoc } from '../../src/shared/games/common';
import type { MarketDoc, PositionDoc, ProfileDoc } from '../../src/shared/types';
import { DECISION_GRACE_MS, WELCOME_BONUS_CENTS } from '../../src/shared/types';
import { admin, balance, ledgerSum } from './client';
import { inprocPlayer, reasonIn, run, runRaw } from './inproc';

type P = { uid: string; username: string };

afterAll(() => overrideGameModuleForTests('baccarat', null));

async function gtable(id: string): Promise<GameTableDoc<BaccaratPublic>> {
  return (await admin().doc(`gameTables/${id}`).get()).data() as GameTableDoc<BaccaratPublic>;
}

/** Expires the current deadline (+ the human grace) and pokes, like a client would. */
async function expire(p: P, tableId: string) {
  await admin().doc(`gameTables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS - 1 });
  return run(games.gamePoke, p.uid, { tableId });
}

const bet = (p: P, tableId: string, round: number, bets: Record<string, number>, power?: 'zeroShield' | 'freeCommission') =>
  run(games.gameAction, p.uid, { tableId, round, action: { type: 'setBets', bets, ...(power ? { power } : {}) } });

async function privateBaccarat(): Promise<{ a: P; b: P; tableId: string }> {
  const a = await inprocPlayer();
  const b = await inprocPlayer();
  const c = await run(games.gameJoin, a.uid, { game: 'baccarat', mode: 'createPrivate', stakeTier: 'low' });
  expect(c.tableId).toMatch(/^bc-/);
  const j = await run(games.gameJoin, b.uid, { game: 'roulette', mode: 'joinCode', stakeTier: 'high', code: c.code! });
  expect(j).toMatchObject({ tableId: c.tableId, game: 'baccarat', status: 'seated', seatIndex: 1 });
  return { a, b, tableId: c.tableId };
}

describe('a baccarat coup on the emulator', () => {
  it('bets never write the table; the coup is dealt and public in one transaction, paid exactly, provably fair', async () => {
    const { a, b, tableId } = await privateBaccarat();
    const t0 = await gtable(tableId);
    expect(t0).toMatchObject({ game: 'baccarat', phase: 'betting', step: 'betting', round: 1 });
    expect(t0.g.shoe).toMatchObject({ n: 1, remaining: 416, cutAt: 16 });
    expect(Object.keys(t0.markets.round).sort()).toEqual(['baccaratBanker', 'baccaratPair', 'baccaratTie']);
    const boardA = { banker: 1_000, tie: 100 };
    const boardB = { player: 700, playerPair: 100, bankerPair: 100 };
    const r = await bet(a, tableId, 1, boardA);
    expect(r).toMatchObject({ phase: 'betting', round: 1, balanceCents: WELCOME_BONUS_CENTS - 1_100 });
    await bet(b, tableId, 1, { player: 500 });
    await bet(b, tableId, 1, boardB); // whole board: debits the difference
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 900);
    const t1 = await gtable(tableId);
    expect(t1.updatedAtMs).toBe(t0.updatedAtMs);
    expect(t1.g.coup).toBeNull();

    expect(await expire(a, tableId)).toMatchObject({ phase: 'live', round: 1, advanced: true });
    const live = await gtable(tableId);
    const coup = live.g.coup!;
    expect(live.step).toBe('dealing');
    expect(coup.burn).not.toBeNull();
    expect(live.events.filter((e) => e.type === 'card')).toHaveLength(coup.player.length + coup.banker.length);
    // markets closed AND resolved in the transaction that showed the cards
    const yes = { baccaratBanker: coup.winner === 'banker', baccaratTie: coup.winner === 'tie', baccaratPair: coup.playerPair || coup.bankerPair };
    for (const [kind, y] of Object.entries(yes)) {
      const m = (await admin().doc(`markets/${tableId}__r1__${kind}`).get()).data() as MarketDoc;
      expect(m).toMatchObject({ status: 'resolved', game: 'baccarat', outcome: y ? 'yes' : 'no' });
    }
    expect(await reasonIn(bet(b, tableId, 1, { player: 800 }))).toBe('BAD_PHASE');
    // the private shoe is never readable from the table document
    expect(JSON.stringify(live)).not.toMatch(/remainingBefore|needsBurn/);

    expect((await expire(a, tableId)).phase).toBe('settled');
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 1_100 + settleBoard(boardA, coup).returnCents);
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS - 900 + settleBoard(boardB, coup).returnCents);
    for (const p of [a, b]) expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
    const round = (await admin().doc(`gameTables/${tableId}/rounds/00000001`).get()).data() as GameRoundDoc;
    expect(sha256Hex(round.fairness.seed)).toBe(t0.fairness.currentCommit);
    expect(round.fairness.decks).toBe(8);
    expect(round.fairness.remainingBefore).toHaveLength(416);
    expect(verifyFairness({ commit: round.fairness.commit, seed: round.fairness.seed, remainingBefore: round.fairness.remainingBefore!, dealt: round.fairness.dealt!, decks: 8 })).toBe(true);
    const result = round.result as unknown as BaccaratResult;
    expect(result).toMatchObject({ player: coup.player, banker: coup.banker, winner: coup.winner, shoe: 1, coupInShoe: 1 });
    expect(result.burn!.cards).toEqual(round.fairness.dealt!.slice(1, 1 + result.burn!.count));
    const prof = (await admin().doc(`profiles/${a.uid}`).get()).data() as ProfileDoc;
    expect(prof.gameStats?.baccarat?.rounds).toBe(1);
    expect(((await admin().doc(`gameTables/${tableId}/bets/${a.uid}`).get()).data() as GameBetDoc)).toMatchObject({ bets: {}, previous: boardA });
    // the next coup: no burn, its proof chains on the remaining cards
    expect((await expire(a, tableId)).phase).toBe('betting');
    await bet(a, tableId, 2, { banker: 100 });
    await expire(a, tableId);
    await expire(a, tableId);
    const r2 = (await admin().doc(`gameTables/${tableId}/rounds/00000002`).get()).data() as GameRoundDoc;
    expect(r2.fairness.remainingBefore).toHaveLength(416 - round.fairness.dealt!.length);
    expect((r2.result as unknown as BaccaratResult).burn).toBeNull();
    expect(verifyFairness({ commit: r2.fairness.commit, seed: r2.fairness.seed, remainingBefore: r2.fairness.remainingBefore!, dealt: r2.fairness.dealt!, decks: 8 })).toBe(true);
  });

  it('double spend: a bet and a purchase racing for the last $10 — exactly one wins', async () => {
    const { a, tableId } = await privateBaccarat();
    await run(account.submitKyc, a.uid, { docType: 'passport', birthDate: '1990-05-17' });
    await admin().doc(`users/${a.uid}/private/kyc`).update({ verifyAfterMs: Date.now() - 1 });
    await run(account.submitKyc, a.uid, { refresh: true });
    await run(account.withdraw, a.uid, { amountCents: WELCOME_BONUS_CENTS - 1_000, method: 'card' });
    const res = await Promise.all([
      reasonIn(bet(a, tableId, 1, { banker: 1_000 })),
      reasonIn(run(account.buyPower, a.uid, { powerId: 'freeInsurance', quantity: 1 })),
    ]);
    expect(res.filter((x) => x === 'NO_ERROR')).toHaveLength(1);
    expect(res.filter((x) => x === 'INSUFFICIENT_FUNDS')).toHaveLength(1);
    expect(await balance(a.uid)).toBe(0);
    expect(await ledgerSum(a.uid)).toBe(0);
    // two concurrent boards of the same player: the wallet is never overdrawn
    const { a: c, tableId: t2 } = await privateBaccarat();
    const both = await Promise.all([bet(c, t2, 1, { banker: 6_000 }), bet(c, t2, 1, { player: 9_000 })].map(reasonIn));
    expect(both.filter((x) => x === 'NO_ERROR').length).toBeGreaterThanOrEqual(1);
    const board = ((await admin().doc(`gameTables/${t2}/bets/${c.uid}`).get()).data() as GameBetDoc).totalCents;
    expect(await balance(c.uid)).toBe(WELCOME_BONUS_CENTS - board);
    expect(await ledgerSum(c.uid)).toBe(await balance(c.uid));
  });

  it('replay with the same requestId executes once', async () => {
    const { a, tableId } = await privateBaccarat();
    const requestId = randomUUID();
    const r1 = await run(games.gameAction, a.uid, { requestId, tableId, round: 1, action: { type: 'setBets', bets: { banker: 500 } } });
    const r2 = await run(games.gameAction, a.uid, { requestId, tableId, round: 1, action: { type: 'setBets', bets: { banker: 500 } } });
    expect(r2).toEqual(r1);
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 500);
    expect(await reasonIn(run(games.gamePoke, a.uid, { requestId, tableId }))).toBe('REQUEST_ID_REUSED');
  });

  it('forbidden bets, actions and powers are refused and debit nothing; an owned power is consumed once', async () => {
    const { a, b, tableId } = await privateBaccarat();
    expect(await reasonIn(bet(a, tableId, 1, { dragon: 100 }))).toBe('BAD_BET_SPOT');
    expect(await reasonIn(bet(a, tableId, 1, { banker: 150 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reasonIn(bet(a, tableId, 1, { banker: 10_100 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reasonIn(bet(a, tableId, 1, { tie: 2_100 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reasonIn(bet(a, tableId, 2, { banker: 100 }))).toBe('STALE_HAND');
    expect(await reasonIn(bet(a, tableId, 1, { banker: 100 }, 'zeroShield'))).toBe('WRONG_GAME');
    expect(await reasonIn(bet(a, tableId, 1, { banker: 100 }, 'freeCommission'))).toBe('POWER_NOT_OWNED');
    expect(await reasonIn(run(games.gameAction, a.uid, { tableId, round: 1, action: { type: 'none' } }))).toBe('ILLEGAL_ACTION');
    expect(await reasonIn(runRaw(games.gameAction, a.uid, { requestId: randomUUID(), tableId, round: 1, action: { type: 'squeeze' } }))).toBe('INVALID_ARGUMENT');
    const stranger = await inprocPlayer();
    expect(await reasonIn(bet(stranger, tableId, 1, { banker: 100 }))).toBe('NOT_SEATED');
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
    await run(account.buyPower, a.uid, { powerId: 'freeCommission', quantity: 1 });
    const afterBuy = await balance(a.uid);
    expect(await reasonIn(bet(a, tableId, 1, { player: 200 }, 'freeCommission'))).toBe('POWER_NOT_APPLICABLE');
    const ok = await bet(a, tableId, 1, { banker: 2_000 }, 'freeCommission');
    expect(ok.data).toMatchObject({ power: 'freeCommission', totalCents: 2_000 });
    expect((await admin().doc(`users/${a.uid}/inventory/freeCommission`).get()).get('quantity')).toBe(0);
    await bet(a, tableId, 1, { banker: 3_000 }, 'freeCommission'); // already attached: not consumed again
    await bet(b, tableId, 1, { player: 100 });
    await expire(a, tableId);
    const coup = (await gtable(tableId)).g.coup!;
    expect((await gtable(tableId)).seats[0]!.powerUsed).toBe('freeCommission');
    await expire(a, tableId);
    expect(await balance(a.uid)).toBe(afterBuy - 3_000 + settleBoard({ banker: 3_000 }, coup, true).returnCents);
    expect(await ledgerSum(a.uid)).toBe(await balance(a.uid));
  });
});

describe('markets, closing and matchmaking', () => {
  it('no trading on your own table; a spectator trades before the deal and is paid at the deal', async () => {
    const { a, b, tableId } = await privateBaccarat();
    const marketId = (await gtable(tableId)).markets.round.baccaratBanker!;
    expect(await reasonIn(run(market.tradeShares, a.uid, { marketId, side: 'yes', direction: 'buy', shares: 5 }))).toBe('OWN_TABLE_MARKET');
    const spec = await inprocPlayer();
    await run(market.tradeShares, spec.uid, { marketId, side: 'yes', direction: 'buy', shares: 10 });
    await bet(a, tableId, 1, { banker: 100 });
    await bet(b, tableId, 1, { player: 100 });
    await expire(a, tableId);
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

  it('closing refunds: leaving during betting refunds the board, the last human leaving closes the table', async () => {
    const { a, b, tableId } = await privateBaccarat();
    await bet(a, tableId, 1, { banker: 700, tie: 100 });
    expect(await run(games.gameLeave, a.uid, { tableId })).toEqual({ left: true, refundedCents: 800, cashOutCents: 0, deferred: false });
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
    await bet(b, tableId, 1, { player: 300 });
    await run(games.gameLeave, b.uid, { tableId });
    expect((await gtable(tableId)).status).toBe('closed');
    expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS);
    expect((await admin().collection(`gameTables/${tableId}/bets`).get()).size).toBe(0);
  });

  it('closing refunds: a table closed mid-coup (game withdrawn) refunds every locked board', async () => {
    const { a, b, tableId } = await privateBaccarat();
    await bet(a, tableId, 1, { banker: 900 });
    await bet(b, tableId, 1, { player: 400, bankerPair: 200 });
    await expire(a, tableId); // dealt: boards locked
    expect((await gtable(tableId)).phase).toBe('live');
    overrideGameModuleForTests('baccarat', unavailableModule('baccarat'));
    try {
      expect(await run(games.gamePoke, a.uid, { tableId })).toMatchObject({ phase: 'closed', advanced: true });
      expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
      expect(await balance(b.uid)).toBe(WELCOME_BONUS_CENTS);
      for (const p of [a, b]) expect(await ledgerSum(p.uid)).toBe(WELCOME_BONUS_CENTS);
      expect((await admin().collection(`gameTables/${tableId}/bets`).get()).size).toBe(0);
    } finally {
      overrideGameModuleForTests('baccarat', null);
    }
  });

  it('quick join: a public table with 2 bots that bet; one location across games', async () => {
    const a = await inprocPlayer();
    const q = await run(games.gameJoin, a.uid, { game: 'baccarat', mode: 'quick', stakeTier: 'mid' });
    expect(q).toMatchObject({ game: 'baccarat', status: 'seated' });
    const t = await gtable(q.tableId);
    expect([t.humanCount, t.botCount, t.isPrivate, t.limits.minBetCents]).toEqual([1, 2, false, 500]);
    expect((await run(games.gameJoin, a.uid, { game: 'baccarat', mode: 'quick', stakeTier: 'mid' })).tableId).toBe(q.tableId); // idempotent
    expect(await reasonIn(run(games.gameJoin, a.uid, { game: 'baccarat', mode: 'quick', stakeTier: 'low' }))).toBe('ALREADY_SEATED');
    const boards = await admin().collection(`gameTables/${q.tableId}/bets`).get();
    expect(boards.docs.every((d) => (d.data() as GameBetDoc).isBot)).toBe(true);
    await run(games.gameLeave, a.uid, { tableId: q.tableId });
    expect((await gtable(q.tableId)).status).toBe('closed');
  });
});
