/**
 * Emulator integration (real HTTP callables, production registry = phase-A stubs): the new
 * Sprint 2 callables refuse cleanly, validate strictly, rate-limit per op; one location across
 * games; cosmetics lock; blackjack retouches (affinity at settlement, codes of other games).
 */
import { randomUUID } from 'node:crypto';
import { doc, setDoc, updateDoc } from 'firebase/firestore';
import { describe, expect, it } from 'vitest';
import { dayId } from '../../src/shared/time';
import type { TableDoc } from '../../src/shared/types';
import { DECISION_GRACE_MS } from '../../src/shared/types';
import { admin, playerClient, reason, type Client } from './client';

async function bjTable(id: string): Promise<TableDoc> {
  return (await admin().doc(`tables/${id}`).get()).data() as TableDoc;
}

async function expireBj(c: Client, tableId: string): Promise<void> {
  await admin().doc(`tables/${tableId}`).update({ deadlineMs: Date.now() - DECISION_GRACE_MS - 1 });
  await c.call('pokeTable', { tableId });
}

describe('game callables with the phase-A stubs', () => {
  it('every kernel game is "not available yet"; nothing is created', async () => {
    const a = await playerClient();
    for (const game of ['roulette', 'baccarat', 'holdem', 'craps'] as const) {
      expect(await reason(a.call('gameJoin', { game, mode: 'quick', stakeTier: 'low' }))).toBe('FEATURE_UNAVAILABLE');
      expect(await reason(a.call('gameJoin', { game, mode: 'createPrivate', stakeTier: 'low', buyInCents: 4_000 }))).toBe('FEATURE_UNAVAILABLE');
    }
    expect((await admin().doc(`profiles/${a.uid}`).get()).get('currentTableId')).toBeNull();
    await a.close();
  });

  it('strict envelopes: unknown fields, bad types, bad actions are INVALID_ARGUMENT; unknown tables TABLE_NOT_FOUND', async () => {
    const a = await playerClient();
    const rid = () => randomUUID();
    expect(await reason(a.raw('gameJoin', { requestId: rid(), game: 'poker', mode: 'quick', stakeTier: 'low' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('gameJoin', { requestId: rid(), game: 'roulette', mode: 'quick', stakeTier: 'low', seat: 2 }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('gameAction', { requestId: rid(), tableId: 'rl-x', round: 1, action: 'setBets' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('gameAction', { requestId: rid(), tableId: 'rl-x', round: 1, action: { type: 'setBets' }, uid: a.uid }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('gameAction', { requestId: rid(), tableId: 'rl-x', round: 1.5, action: { type: 'sitOut' } }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('gameAction', { requestId: rid(), tableId: 'rl-x', round: 1, action: { type: 'setBets', bets: { 'red;drop': 100 } } }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('gameAction', { requestId: rid(), tableId: 'rl-x', round: 1, action: { type: 'setBets', bets: { red: -100 } } }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('gameAction', { requestId: rid(), tableId: 'rl-x', round: 1, action: { type: 'setBets', bets: { red: 100 }, extra: 1 } }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.call('gameAction', { tableId: 'rl-nope', round: 1, action: { type: 'setBets', bets: { red: 100 } } }))).toBe('TABLE_NOT_FOUND');
    expect(await reason(a.call('gameAction', { tableId: 'rl-nope', round: 1, action: { type: 'sitOut' } }))).toBe('TABLE_NOT_FOUND');
    expect(await reason(a.call('gamePoke', { tableId: 'rl-nope' }))).toBe('TABLE_NOT_FOUND');
    expect(await reason(a.call('gamePoke', { tableId: 'sim-01' }))).toBe('TABLE_NOT_FOUND');
    expect(await reason(a.call('gameLeave', { tableId: 'cr-nope' }))).toBe('TABLE_NOT_FOUND');
    await a.close();
  });
});

describe('one location across games, private codes of any game', () => {
  it('gameJoin joinCode joins a blackjack private table; ALREADY_SEATED for any other game; gameLeave works for blackjack', async () => {
    const a = await playerClient();
    const b = await playerClient();
    const created = await a.call('joinMatchmaking', { mode: 'createPrivate', stakeTier: 'low' });
    const joined = await b.call('gameJoin', { game: 'roulette', mode: 'joinCode', stakeTier: 'low', code: created.code!.toLowerCase() });
    expect(joined).toMatchObject({ tableId: created.tableId, game: 'blackjack', status: 'seated', seatIndex: 1, code: created.code });
    expect(await reason(b.call('gameJoin', { game: 'roulette', mode: 'quick', stakeTier: 'low' }))).toBe('ALREADY_SEATED');
    expect(await reason(b.call('gameJoin', { game: 'holdem', mode: 'createPrivate', stakeTier: 'low', buyInCents: 4_000 }))).toBe('ALREADY_SEATED');
    const left = await b.call('gameLeave', { tableId: created.tableId });
    expect(left).toEqual({ left: true, refundedCents: 0, cashOutCents: 0, deferred: false });
    expect((await admin().doc(`profiles/${b.uid}`).get()).get('currentTableId')).toBeNull();
    await Promise.all([a.close(), b.close()]);
  });

  it('joinMatchmaking with the code of another game\'s table is WRONG_GAME', async () => {
    const a = await playerClient();
    await admin().doc('tableCodes/ZQZQZQ').set({ tableId: 'rl-someTable', game: 'roulette', createdAtMs: Date.now() });
    expect(await reason(a.call('joinMatchmaking', { mode: 'joinCode', stakeTier: 'low', code: 'zqzqzq' }))).toBe('WRONG_GAME');
    await a.close();
  });
});

describe('blackjack settlement feeds the Rendez-vous table affinity (blind increment)', () => {
  it('each human who staked at least the minimum gets romance/lucas.tablePlay[day] += 1', async () => {
    const a = await playerClient();
    const b = await playerClient();
    const created = await a.call('joinMatchmaking', { mode: 'createPrivate', stakeTier: 'low' });
    const tableId = created.tableId;
    await b.call('joinMatchmaking', { mode: 'joinCode', stakeTier: 'low', code: created.code! });
    let t = await bjTable(tableId);
    await a.call('placeBet', { tableId, handNumber: t.handNumber, amountCents: 100 });
    await b.call('placeBet', { tableId, handNumber: t.handNumber, amountCents: 200 });
    for (let i = 0; i < 40 && t.phase !== 'settled'; i++) {
      t = await bjTable(tableId);
      if (t.phase === 'settled') break;
      await expireBj(a, tableId); // insurance declined / stand by timeout
      t = await bjTable(tableId);
    }
    expect(t.phase).toBe('settled');
    const day = dayId(Date.now());
    for (const p of [a, b]) {
      const rd = await admin().doc(`users/${p.uid}/romance/lucas`).get();
      expect(rd.get('tablePlay')?.[day]).toBe(1);
    }
    // client cannot touch it
    expect(await reason(setDoc(doc(a.db, `users/${a.uid}/romance/lucas`), { tablePlay: { [day]: 99 } }))).toBe('permission-denied');
    await Promise.all([a.close(), b.close()]);
  });
});

describe('romance / dating stubs', () => {
  it('romance: validated per op, rate-limited per op, then FEATURE_UNAVAILABLE', async () => {
    const a = await playerClient();
    expect(await reason(a.call('romance', { op: 'sync' }))).toBe('FEATURE_UNAVAILABLE');
    expect(await reason(a.raw('romance', { requestId: randomUUID(), op: 'flirt' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('romance', { requestId: randomUUID(), op: 'gift', characterId: 'zorro', giftId: 'rose' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('romance', { requestId: randomUUID(), op: 'sync', characterId: 'lucas' }))).toBe('INVALID_ARGUMENT');
    const out: string[] = [];
    for (let i = 0; i < 21; i++) out.push(await reason(a.call('romance', { op: 'gift', characterId: 'camille', giftId: 'rose' })));
    expect(out.slice(0, 20).every((r) => r === 'FEATURE_UNAVAILABLE')).toBe(true);
    expect(out[20]).toBe('RATE_LIMITED'); // ROMANCE_OP_RATE_LIMITS.gift = 20 / min
    expect(await reason(a.call('romance', { op: 'playScene', characterId: 'lucas', sceneId: 's1', choices: ['c1'] }))).toBe('FEATURE_UNAVAILABLE'); // another op
    await a.close();
  });

  it('dating: DATING_DISABLED by default (server switch), FEATURE_UNAVAILABLE once enabled; strict shapes', async () => {
    const a = await playerClient({ kyc: true });
    await admin().doc('config/features').delete();
    expect(await reason(a.call('dating', { op: 'discover' }))).toBe('DATING_DISABLED');
    expect(await reason(a.raw('dating', { requestId: randomUUID(), op: 'optIn', favoriteGame: 'roulette', interests: ['music', 'art'], lookingFor: 'flirt' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('dating', { requestId: randomUUID(), op: 'optIn', favoriteGame: 'roulette', interests: ['music', 'art', 'art'], lookingFor: 'flirt' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('dating', { requestId: randomUUID(), op: 'send', pairId: 'a_b', lineId: 'hi', reaction: 'heart' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(a.raw('dating', { requestId: randomUUID(), op: 'send', pairId: 'a_b', text: 'free text' }))).toBe('INVALID_ARGUMENT');
    await admin().doc('config/features').set({ dating: true });
    expect(await reason(a.call('dating', { op: 'optIn', favoriteGame: 'roulette', interests: ['music', 'art', 'cinema'], lookingFor: 'flirt' }))).toBe('FEATURE_UNAVAILABLE');
    await admin().doc('config/features').delete();
    await a.close();
  });
});

describe('cosmetics lock (equipCardStyle + rules)', () => {
  it('exclusive styles need an unlock; the client writes only theme / language', async () => {
    const a = await playerClient();
    expect(await reason(a.call('equipCardStyle', { cardBack: 'rv_lucas_back' }))).toBe('COSMETIC_LOCKED');
    expect(await reason(a.call('equipCardStyle', { title: 'rv_alex_title' }))).toBe('COSMETIC_LOCKED');
    await admin().doc(`users/${a.uid}/unlocks/rv_lucas_back`).set({ cosmeticId: 'rv_lucas_back', slot: 'cardBack', source: 'romance', characterId: 'lucas', tier: 1, pairId: null, grantedAtMs: Date.now() });
    expect((await a.call('equipCardStyle', { cardBack: 'rv_lucas_back', felt: 'blue' })).cardBack).toBe('rv_lucas_back');
    expect(await reason(updateDoc(doc(a.db, `users/${a.uid}`), { felt: 'red' }))).toBe('permission-denied');
    expect(await reason(updateDoc(doc(a.db, `users/${a.uid}`), { cardBack: 'rv_camille_back' }))).toBe('permission-denied');
    expect(await reason(updateDoc(doc(a.db, `users/${a.uid}`), { theme: 'light', language: 'en', updatedAtMs: Date.now() }))).toBe('NO_ERROR');
    expect((await admin().doc(`users/${a.uid}`).get()).data()).toMatchObject({ theme: 'light', language: 'en', cardBack: 'rv_lucas_back', felt: 'blue' });
    await a.close();
  });
});
