/**
 * Emulator integration: matchmaking, full hands with two real clients, turn/seat enforcement,
 * bets validation, powers, own-table markets, timeouts via pokeTable, double spend, replay.
 */
import { randomUUID } from 'node:crypto';
import { doc, getDoc } from 'firebase/firestore';
import { describe, expect, it } from 'vitest';
import { verifyFairness } from '../../src/engine';
import type { HandHistoryDoc, MarketDoc, PositionDoc, TableDoc } from '../../src/shared/types';
import { DECISION_GRACE_MS, WELCOME_BONUS_CENTS } from '../../src/shared/types';
import { admin, balance, ledgerSum, newClient, playerClient, reason, verifyKyc, type Client } from './client';

type Player = Client & { username: string };

async function table(id: string): Promise<TableDoc> {
  return (await admin().doc(`tables/${id}`).get()).data() as TableDoc;
}

/** Expire the current deadline (+ the human grace) and let the server apply it (what a client's pokeTable does). */
async function expire(c: Client, tableId: string): Promise<void> {
  await admin().doc(`tables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS - 1 });
  await c.call('pokeTable', { tableId });
}

async function privateTable(stakeTier: 'low' | 'mid' | 'high' = 'low'): Promise<{ a: Player; b: Player; tableId: string }> {
  const a = await playerClient();
  const b = await playerClient();
  const created = await a.call('joinMatchmaking', { mode: 'createPrivate', stakeTier });
  expect(created.code).toMatch(/^[A-Z0-9]{6}$/);
  // The join code is only given to its creator: never in the public table name (lobby, markets).
  expect((await table(created.tableId)).name).not.toContain(created.code!);
  const joined = await b.call('joinMatchmaking', { mode: 'joinCode', stakeTier, code: created.code!.toLowerCase() });
  expect(joined).toMatchObject({ tableId: created.tableId, status: 'seated', seatIndex: 1 });
  return { a, b, tableId: created.tableId };
}

/** Drive the current hand to settlement: everybody declines insurance, the player on turn stands. */
async function playToSettle(players: Client[], tableId: string): Promise<TableDoc> {
  for (let i = 0; i < 40; i++) {
    const t = await table(tableId);
    if (t.phase === 'settled' || t.phase === 'betting' && i > 0) return t;
    if (t.phase === 'insurance') {
      for (const p of players) {
        const seat = t.seats.find((s) => s?.uid === p.uid);
        if (seat?.insurance && !seat.insurance.decided) await p.call('act', { tableId, handNumber: t.handNumber, action: 'insurance', amountCents: 0 });
      }
    } else if (t.phase === 'playerTurns') {
      const uid = t.seats[t.turn!.seatIndex]!.uid;
      const p = players.find((x) => x.uid === uid);
      if (p) await p.call('act', { tableId, handNumber: t.handNumber, action: 'stand', handIndex: t.turn!.handIndex });
      else await expire(players[0], tableId);
    } else {
      await expire(players[0], tableId);
    }
  }
  throw new Error('hand did not settle');
}

/** Both bet `bet`, then returns the table once dealt. */
async function betBoth(a: Client, b: Client, tableId: string, bet = 1_000): Promise<TableDoc> {
  const t = await table(tableId);
  expect(t.phase).toBe('betting');
  await a.call('placeBet', { tableId, handNumber: t.handNumber, amountCents: bet });
  await b.call('placeBet', { tableId, handNumber: t.handNumber, amountCents: bet });
  return table(tableId);
}

/** Find a dealt hand that reaches 'playerTurns' (re-deals a few times if a dealer natural ends it at once). */
async function dealToTurns(a: Player, b: Player, tableId: string): Promise<TableDoc> {
  for (let k = 0; k < 8; k++) {
    let t = await betBoth(a, b, tableId);
    if (t.phase === 'insurance') {
      await a.call('act', { tableId, handNumber: t.handNumber, action: 'insurance', amountCents: 0 });
      await b.call('act', { tableId, handNumber: t.handNumber, action: 'insurance', amountCents: 0 });
      t = await table(tableId);
    }
    if (t.phase === 'playerTurns') return t;
    await playToSettle([a, b], tableId);
    await expire(a, tableId); // settled → betting
  }
  throw new Error('no playable hand');
}

describe('matchmaking', () => {
  it('two human clients quick-joining the same tier land at the same table; bots complete it', async () => {
    const a = await playerClient();
    const b = await playerClient();
    const ra = await a.call('joinMatchmaking', { mode: 'quick', stakeTier: 'high' });
    const rb = await b.call('joinMatchmaking', { mode: 'quick', stakeTier: 'high' });
    expect(rb.tableId).toBe(ra.tableId);
    expect(ra.status).toBe('seated');
    expect(rb.status).toBe('seated');
    const t = await table(ra.tableId);
    expect(t.humanCount).toBe(2);
    expect(t.botCount).toBe(2);
    expect((await admin().doc(`profiles/${a.uid}`).get()).get('currentTableId')).toBe(ra.tableId);
    // re-joining returns the same seat, joining another mode is refused
    expect((await a.call('joinMatchmaking', { mode: 'quick', stakeTier: 'high' })).seatIndex).toBe(ra.seatIndex);
    expect(await reason(a.call('joinMatchmaking', { mode: 'createPrivate', stakeTier: 'low' }))).toBe('ALREADY_SEATED');
    // the table progresses with bots + humans, both humans read it in real time
    const snap = await getDoc(doc(b.db, `tables/${ra.tableId}`));
    expect(snap.exists()).toBe(true);
    await a.call('leaveTable', { tableId: ra.tableId });
    await b.call('leaveTable', { tableId: ra.tableId });
    const after = await table(ra.tableId);
    expect(after.status).toBe('closed'); // humans gone → bots leave, table closes
    await a.close();
    await b.close();
  });

  it('bad private code', async () => {
    const a = await playerClient();
    expect(await reason(a.call('joinMatchmaking', { mode: 'joinCode', stakeTier: 'low', code: 'ZZZZZ9' }))).toBe('BAD_CODE');
    expect(await reason(a.call('joinMatchmaking', { mode: 'joinCode', stakeTier: 'low', code: 'bad' }))).toBe('INVALID_ARGUMENT');
    await a.close();
  });
});

describe('a full hand between two human clients', () => {
  it('bets, deal, decisions, dealer, settlement, ledger and fairness proof are consistent', async () => {
    const { a, b, tableId } = await privateTable();
    const t0 = await table(tableId);
    expect(t0.phase).toBe('betting');
    expect(t0.fairness.currentCommit).toMatch(/^[0-9a-f]{64}$/);
    const commit = t0.fairness.currentCommit;
    await betBoth(a, b, tableId, 2_000);
    const end = await playToSettle([a, b], tableId);
    expect(end.phase).toBe('settled');
    expect(end.dealer.holeHidden).toBe(false);
    for (const p of [a, b]) {
      const seat = end.seats.find((s) => s?.uid === p.uid)!;
      const ret = seat.hands.reduce((x, h) => x + (h.returnCents ?? 0), 0);
      expect(await balance(p.uid)).toBe(WELCOME_BONUS_CENTS - 2_000 + ret);
      expect(await ledgerSum(p.uid)).toBe(await balance(p.uid));
      expect(seat.roundNetCents).toBe(ret - 2_000);
    }
    const hist = (await admin().doc(`tables/${tableId}/hands/${String(end.handNumber).padStart(8, '0')}`).get()).data() as HandHistoryDoc;
    expect(hist.fairness.commit).toBe(commit);
    expect(verifyFairness(hist.fairness)).toBe(true);
    expect(end.fairness.lastSeed).toBe(hist.fairness.seed);
    // stats updated
    const p = (await admin().doc(`profiles/${a.uid}`).get()).data()!;
    expect(p.stats.handsPlayed).toBe(1);
    // the shoe and seed are never readable by players
    expect(await reason(getDoc(doc(a.db, `tables/${tableId}/private/state`)))).toBe('permission-denied');
    await a.close();
    await b.close();
  });
});

describe('turn and seat enforcement', () => {
  it('acting out of turn, on someone else\'s seat, when not seated, with a stale hand, or with extra fields', async () => {
    const { a, b, tableId } = await privateTable();
    const t = await dealToTurns(a, b, tableId);
    const turnUid = t.seats[t.turn!.seatIndex]!.uid;
    const [onTurn, other] = turnUid === a.uid ? [a, b] : [b, a];
    expect(await reason(other.call('act', { tableId, handNumber: t.handNumber, action: 'hit' }))).toBe('NOT_YOUR_TURN');
    expect(await reason(onTurn.call('act', { tableId, handNumber: t.handNumber - 1, action: 'hit' }))).toBe('STALE_HAND');
    expect(await reason(onTurn.call('act', { tableId, handNumber: t.handNumber, action: 'hit', handIndex: 3 }))).toBe('NOT_YOUR_TURN');
    // there is no way to name a seat: the seat is derived from the auth uid
    expect(await reason(other.raw('act', { requestId: randomUUID(), tableId, handNumber: t.handNumber, action: 'hit', seatIndex: t.turn!.seatIndex }))).toBe('INVALID_ARGUMENT');
    expect(await reason(other.raw('act', { requestId: randomUUID(), tableId, handNumber: t.handNumber, action: 'hit', uid: turnUid }))).toBe('INVALID_ARGUMENT');
    const stranger = await playerClient();
    expect(await reason(stranger.call('act', { tableId, handNumber: t.handNumber, action: 'stand' }))).toBe('NOT_SEATED');
    expect(await reason(stranger.call('placeBet', { tableId, handNumber: t.handNumber, amountCents: 100 }))).toBe('BAD_PHASE');
    expect(await reason(onTurn.call('act', { tableId, handNumber: t.handNumber, action: 'stand' }))).toBe('NO_ERROR');
    await Promise.all([a.close(), b.close(), stranger.close()]);
  });

  it('every callable applies overdue timeouts first: the waiting player can act once the other times out', async () => {
    const { a, b, tableId } = await privateTable();
    let t = await dealToTurns(a, b, tableId);
    for (let k = 0; k < 6 && t.turn!.seatIndex !== 0; k++) { // need a's turn first (a natural skips it)
      await playToSettle([a, b], tableId);
      await expire(a, tableId);
      t = await dealToTurns(a, b, tableId);
    }
    expect(t.turn!.seatIndex).toBe(0);
    expect(await reason(b.call('act', { tableId, handNumber: t.handNumber, action: 'stand' }))).toBe('NOT_YOUR_TURN');
    await admin().doc(`tables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS - 1 }); // a's 20 s (+ grace) are over
    const t2 = await table(tableId);
    expect(t2.turn!.seatIndex).toBe(0); // nothing happens by itself (no scheduler)...
    expect(await reason(b.call('act', { tableId, handNumber: t.handNumber, action: 'stand' }))).toBe('NO_ERROR'); // ...but b's call applies it
    const t3 = await table(tableId);
    expect(t3.events.some((e) => e.type === 'timeout' && e.seatIndex === 0)).toBe(true);
    await a.close();
    await b.close();
  });

  it('pokeTable advances only when the server clock says the deadline passed', async () => {
    const { a, b, tableId } = await privateTable();
    const r1 = await a.call('pokeTable', { tableId });
    expect(r1.advanced).toBe(false);
    expect(r1.phase).toBe('betting');
    // Humans get DECISION_GRACE_MS after the displayed deadline: just before its end, nothing yet...
    await admin().doc(`tables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS + 1500 });
    expect((await a.call('pokeTable', { tableId })).advanced).toBe(false);
    await admin().doc(`tables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS - 1 });
    const r2 = await b.call('pokeTable', { tableId });
    expect(r2.advanced).toBe(true); // nobody bet: betting restarts with a fresh deadline
    expect(r2.deadlineMs!).toBeGreaterThan(Date.now());
    await a.close();
    await b.close();
  });
});

describe('bet validation and money', () => {
  it('negative, decimal, huge, off-step and out-of-range bets are refused; nothing is debited', async () => {
    const { a, b, tableId } = await privateTable();
    const t = await table(tableId);
    const hn = t.handNumber;
    for (const amountCents of [-100, 0, 150.5, 1e12, Number.MAX_SAFE_INTEGER]) {
      expect(await reason(a.raw('placeBet', { requestId: randomUUID(), tableId, handNumber: hn, amountCents }))).toBe('INVALID_ARGUMENT');
    }
    expect(await reason(a.call('placeBet', { tableId, handNumber: hn, amountCents: 150 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reason(a.call('placeBet', { tableId, handNumber: hn, amountCents: 50 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reason(a.call('placeBet', { tableId, handNumber: hn, amountCents: 10_100 }))).toBe('BET_OUT_OF_RANGE');
    expect(await reason(a.call('placeBet', { tableId, handNumber: hn + 1, amountCents: 100 }))).toBe('STALE_HAND');
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
    await a.call('placeBet', { tableId, handNumber: hn, amountCents: 100 });
    expect(await reason(a.call('placeBet', { tableId, handNumber: hn, amountCents: 100 }))).toBe('ALREADY_BET');
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 100);
    await a.close();
    await b.close();
  });

  it('a bet above the balance is INSUFFICIENT_FUNDS (high tier, $2,000 with $1,000)', async () => {
    const { a, b, tableId } = await privateTable('high');
    const t = await table(tableId);
    expect(await reason(a.call('placeBet', { tableId, handNumber: t.handNumber, amountCents: 200_000 }))).toBe('INSUFFICIENT_FUNDS');
    await a.close();
    await b.close();
  });

  it('concurrent double spend: a bet and a purchase racing for the last $10', async () => {
    const { a, b, tableId } = await privateTable();
    await verifyKyc(a);
    await a.call('withdraw', { amountCents: WELCOME_BONUS_CENTS - 1_000, method: 'card' });
    const t = await table(tableId);
    const res = await Promise.all([
      reason(a.call('placeBet', { tableId, handNumber: t.handNumber, amountCents: 1_000 })),
      reason(a.call('buyPower', { powerId: 'freeInsurance', quantity: 1 })),
    ]);
    expect(res.filter((r) => r === 'NO_ERROR')).toHaveLength(1);
    expect(res.filter((r) => r === 'INSUFFICIENT_FUNDS')).toHaveLength(1);
    expect(await balance(a.uid)).toBe(0);
    expect(await ledgerSum(a.uid)).toBe(0);
    await a.close();
    await b.close();
  });

  it('replaying placeBet/act with the same requestId executes once', async () => {
    const { a, b, tableId } = await privateTable();
    const t = await table(tableId);
    const requestId = randomUUID();
    const r1 = await a.call('placeBet', { requestId, tableId, handNumber: t.handNumber, amountCents: 500 });
    const r2 = await a.call('placeBet', { requestId, tableId, handNumber: t.handNumber, amountCents: 500 });
    expect(r2).toEqual(r1);
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS - 500);
    await a.close();
    await b.close();
  });

  it('leaving during betting refunds the bet', async () => {
    const { a, b, tableId } = await privateTable();
    const t = await table(tableId);
    await a.call('placeBet', { tableId, handNumber: t.handNumber, amountCents: 700 });
    const r = await a.call('leaveTable', { tableId });
    expect(r.refundedCents).toBe(700);
    expect(await balance(a.uid)).toBe(WELCOME_BONUS_CENTS);
    expect((await admin().doc(`profiles/${a.uid}`).get()).get('currentTableId')).toBeNull();
    await a.close();
    await b.close();
  });
});

describe('powers', () => {
  it('using a power you do not own is refused; an owned peek is consumed and visible only to you', async () => {
    const { a, b, tableId } = await privateTable();
    const t = await dealToTurns(a, b, tableId);
    const onTurn = t.seats[t.turn!.seatIndex]!.uid === a.uid ? a : b;
    const other = onTurn === a ? b : a;
    expect(await reason(onTurn.call('act', { tableId, handNumber: t.handNumber, action: 'double', power: 'freeDouble' }))).toBe('POWER_NOT_OWNED');
    expect(await reason(onTurn.call('act', { tableId, handNumber: t.handNumber, action: 'peek', power: 'peek' }))).toBe('POWER_NOT_OWNED');
    await onTurn.call('buyPower', { powerId: 'peek', quantity: 1 });
    expect(await reason(onTurn.call('act', { tableId, handNumber: t.handNumber, action: 'hit', power: 'peek' }))).toBe('POWER_NOT_APPLICABLE');
    await onTurn.call('act', { tableId, handNumber: t.handNumber, action: 'peek', power: 'peek' });
    const mine = await getDoc(doc(onTurn.db, `tables/${tableId}/peeks/${onTurn.uid}`));
    expect(mine.get('holeCard')).toMatch(/^[A2-9TJQK][SHDC]$/);
    expect(await reason(getDoc(doc(other.db, `tables/${tableId}/peeks/${onTurn.uid}`)))).toBe('permission-denied');
    expect((await admin().doc(`users/${onTurn.uid}/inventory/peek`).get()).get('quantity')).toBe(0);
    const pub = await table(tableId);
    expect(pub.dealer.cards).toHaveLength(1); // still hidden publicly
    await onTurn.call('buyPower', { powerId: 'secondChance', quantity: 1 });
    expect(await reason(onTurn.call('act', { tableId, handNumber: t.handNumber, action: 'hit', power: 'secondChance' }))).toBe('POWER_ALREADY_USED');
    await a.close();
    await b.close();
  });
});

describe('spectator markets', () => {
  it('cannot bet on your own table; a spectator can, and is paid at resolution', async () => {
    const { a, b, tableId } = await privateTable();
    const t = await table(tableId);
    const marketId = t.markets.dealerBust!;
    expect(await reason(a.call('tradeShares', { marketId, side: 'yes', direction: 'buy', shares: 5 }))).toBe('OWN_TABLE_MARKET');
    const spec = await playerClient();
    const buy = await spec.call('tradeShares', { marketId, side: 'yes', direction: 'buy', shares: 10 });
    expect(buy.amountCents).toBeGreaterThan(500);
    expect(buy.priceYes).toBeGreaterThan(0.5);
    expect(await reason(spec.call('tradeShares', { marketId, side: 'no', direction: 'sell', shares: 1 }))).toBe('INSUFFICIENT_SHARES');
    expect(await reason(spec.call('tradeShares', { marketId, side: 'yes', direction: 'buy', shares: 1, maxCostCents: 1 }))).toBe('SLIPPAGE');
    const sell = await spec.call('tradeShares', { marketId, side: 'yes', direction: 'sell', shares: 4 });
    expect(sell.position).toEqual({ yesShares: 6, noShares: 0 });
    // natural market closes at the deal
    await betBoth(a, b, tableId, 100);
    expect(await reason(spec.call('tradeShares', { marketId: t.markets.natural!, side: 'yes', direction: 'buy', shares: 1 }))).toBe('MARKET_CLOSED');
    await playToSettle([a, b], tableId);
    const m = (await admin().doc(`markets/${marketId}`).get()).data() as MarketDoc;
    expect(m.status).toBe('resolved');
    expect(await reason(spec.call('tradeShares', { marketId, side: 'yes', direction: 'buy', shares: 1 }))).toBe('MARKET_CLOSED');
    // payout runs right after the settling transaction
    let pos: PositionDoc | undefined;
    for (let i = 0; i < 20; i++) {
      pos = (await admin().doc(`users/${spec.uid}/positions/${marketId}`).get()).data() as PositionDoc;
      if (pos.status !== 'open') break;
      await new Promise((r) => setTimeout(r, 250));
    }
    expect(pos!.status).toBe(m.outcome === 'yes' ? 'won' : 'lost');
    expect(pos!.payoutCents).toBe(m.outcome === 'yes' ? 600 : 0);
    expect(await ledgerSum(spec.uid)).toBe(await balance(spec.uid));
    await Promise.all([a.close(), b.close(), spec.close()]);
  });
});

describe('rate limiting on table calls', () => {
  it('pokeTable beyond 30 calls / 10 s is RATE_LIMITED', async () => {
    const { a, b, tableId } = await privateTable();
    const out: string[] = [];
    const t0 = Date.now();
    for (let i = 0; i < 8; i++) out.push(...(await Promise.all([1, 2, 3, 4].map(() => reason(a.call('pokeTable', { tableId }))))));
    if (Date.now() - t0 < 10_000) {
      expect(out.filter((r) => r === 'NO_ERROR')).toHaveLength(30);
      expect(out.filter((r) => r === 'RATE_LIMITED')).toHaveLength(2);
    } else {
      // slow machine: the 10 s window rolled over mid-burst; still only OK/RATE_LIMITED outcomes
      console.warn(`rate-limit burst took ${Date.now() - t0} ms; exact count not asserted`);
      expect(out.every((r) => r === 'NO_ERROR' || r === 'RATE_LIMITED')).toBe(true);
    }
    await a.close();
    await b.close();
  });

  it('unauthenticated table calls are refused', async () => {
    const c = await newClient({ signIn: false });
    expect(await reason(c.call('pokeTable', { tableId: 'sim-01' }))).toBe('UNAUTHENTICATED');
    await c.close();
  });
});
