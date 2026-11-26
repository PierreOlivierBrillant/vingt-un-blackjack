import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { WELCOME_BONUS_CENTS } from '../../src/shared/types';
import { admin, balance, ledgerSum, newClient, playerClient, reason, uniqueName, verifyKyc } from './client';

describe('auth and validation', () => {
  it('rejects unauthenticated calls', async () => {
    const c = await newClient({ signIn: false });
    expect(await reason(c.call('deposit', { amountCents: 1000, method: 'card' }))).toBe('UNAUTHENTICATED');
    await c.close();
  });

  it('rejects unknown fields, decimals, negatives, huge numbers, wrong types, bad requestId', async () => {
    const c = await playerClient({ kyc: true });
    const base = { requestId: randomUUID(), method: 'card' };
    for (const amountCents of [-500, 10.5, 1e15, '1000', null, Number.MAX_SAFE_INTEGER + 2]) {
      expect(await reason(c.raw('deposit', { ...base, requestId: randomUUID(), amountCents }))).toBe('INVALID_ARGUMENT');
    }
    expect(await reason(c.raw('deposit', { ...base, amountCents: 1000, balanceCents: 1e9 }))).toBe('INVALID_ARGUMENT');
    expect(await reason(c.raw('deposit', { amountCents: 1000, method: 'card' }))).toBe('INVALID_ARGUMENT'); // no requestId
    expect(await reason(c.raw('deposit', { requestId: 'x', amountCents: 1000, method: 'card' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(c.raw('deposit', { ...base, amountCents: 1000, method: 'paypal' }))).toBe('INVALID_ARGUMENT');
    expect(await balance(c.uid)).toBe(WELCOME_BONUS_CENTS);
    await c.close();
  });
});

describe('completeProfile', () => {
  it('creates profile, settings, wallet with welcome bonus, ledger, suggestions, bot friend requests', async () => {
    const c = await newClient();
    const username = uniqueName('Neo');
    const r = await c.call('completeProfile', { username, avatar: 'avatar07', language: 'en' });
    expect(r).toEqual({ uid: c.uid, username, balanceCents: WELCOME_BONUS_CENTS });
    const db = admin();
    const p = (await db.doc(`profiles/${c.uid}`).get()).data()!;
    expect(p).toMatchObject({ username, usernameLower: username.toLowerCase(), isBot: false, rankTier: 'bronze', currentTableId: null });
    expect((await db.doc(`users/${c.uid}`).get()).data()).toMatchObject({ theme: 'dark', language: 'en' });
    expect(await ledgerSum(c.uid)).toBe(WELCOME_BONUS_CENTS);
    expect(((await db.doc(`users/${c.uid}/private/suggestions`).get()).get('uids') as string[]).length).toBeGreaterThan(0);
    const reqs = await db.collection('friendRequests').where('toUid', '==', c.uid).get();
    expect(reqs.size).toBe(2);
    await c.close();
  });

  it('username is unique case-insensitively; profile only once', async () => {
    const a = await newClient();
    const b = await newClient();
    const name = uniqueName('Dup');
    await a.call('completeProfile', { username: name, avatar: 'avatar01' });
    expect(await reason(b.call('completeProfile', { username: name.toUpperCase(), avatar: 'avatar01' }))).toBe('USERNAME_TAKEN');
    expect(await reason(a.call('completeProfile', { username: uniqueName('Other'), avatar: 'avatar01' }))).toBe('PROFILE_EXISTS');
    expect(await reason(a.call('completeProfile', { username: 'a b', avatar: 'avatar01' }))).toBe('INVALID_ARGUMENT');
    await a.close();
    await b.close();
  });

  it('concurrent claims of the same username: exactly one wins', async () => {
    const clients = await Promise.all([newClient(), newClient(), newClient()]);
    const name = uniqueName('Race');
    const res = await Promise.all(clients.map((c) => reason(c.call('completeProfile', { username: name, avatar: 'avatar02' }))));
    expect(res.filter((r) => r === 'NO_ERROR')).toHaveLength(1);
    expect(res.filter((r) => r === 'USERNAME_TAKEN')).toHaveLength(2);
    await Promise.all(clients.map((c) => c.close()));
  });

  it('calls requiring a profile fail before completeProfile', async () => {
    const c = await newClient();
    expect(await reason(c.call('buyPower', { powerId: 'peek', quantity: 1 }))).toBe('PROFILE_REQUIRED');
    await c.close();
  });
});

describe('simulated KYC', () => {
  it('deposit requires verified KYC; pending flips to verified after the review delay', async () => {
    const c = await playerClient();
    expect(await reason(c.call('deposit', { amountCents: 5000, method: 'card' }))).toBe('KYC_REQUIRED');
    const s = await c.call('submitKyc', { docType: 'idCard', birthDate: '2000-01-31' });
    expect(s.status).toBe('pending');
    expect(await reason(c.call('deposit', { amountCents: 5000, method: 'card' }))).toBe('KYC_REQUIRED');
    await admin().doc(`users/${c.uid}/private/kyc`).update({ verifyAfterMs: Date.now() - 1 });
    // deposit itself promotes the pending review
    const d = await c.call('deposit', { amountCents: 5000, method: 'crypto' });
    expect(d.balanceCents).toBe(WELCOME_BONUS_CENTS + 5000);
    const kyc = (await admin().doc(`users/${c.uid}/private/kyc`).get()).data()!;
    expect(kyc.status).toBe('verified');
    expect(JSON.stringify(kyc)).not.toContain('2000-01-31'); // birth date not stored
    expect((await admin().doc(`profiles/${c.uid}`).get()).get('kycVerified')).toBe(true);
    expect(await reason(c.call('submitKyc', { docType: 'idCard', birthDate: '2000-01-31' }))).toBe('KYC_ALREADY_VERIFIED');
    await c.close();
  });

  it('under 18 is rejected (final)', async () => {
    const c = await playerClient();
    const now = new Date();
    const minor = `${now.getUTCFullYear() - 17}-01-01`;
    const r = await c.call('submitKyc', { docType: 'passport', birthDate: minor });
    expect(r).toMatchObject({ status: 'rejected', rejectionReason: 'underage' });
    expect(await reason(c.call('deposit', { amountCents: 5000, method: 'card' }))).toBe('KYC_REJECTED');
    expect(await reason(c.call('submitKyc', { docType: 'passport', birthDate: '1980-01-01' }))).toBe('KYC_REJECTED');
    await c.close();
  });

  it('invalid birth dates are refused', async () => {
    const c = await playerClient();
    for (const birthDate of ['1990-02-30', '2999-01-01', '1850-01-01', '19900101']) {
      expect(await reason(c.call('submitKyc', { docType: 'passport', birthDate }))).toBe('INVALID_ARGUMENT');
    }
    await c.close();
  });
});

describe('wallet', () => {
  it('deposit limits: per deposit and daily cap', async () => {
    const c = await playerClient({ kyc: true });
    expect(await reason(c.call('deposit', { amountCents: 100, method: 'card' }))).toBe('DEPOSIT_LIMIT');
    expect(await reason(c.call('deposit', { amountCents: 100_001, method: 'card' }))).toBe('DEPOSIT_LIMIT');
    for (let i = 0; i < 5; i++) await c.call('deposit', { amountCents: 100_000, method: 'bankTransfer' });
    expect(await reason(c.call('deposit', { amountCents: 500, method: 'card' }))).toBe('DEPOSIT_LIMIT');
    expect(await balance(c.uid)).toBe(WELCOME_BONUS_CENTS + 500_000);
    expect(await ledgerSum(c.uid)).toBe(await balance(c.uid));
    await c.close();
  });

  it('withdraw cannot exceed the balance', async () => {
    const c = await playerClient({ kyc: true });
    expect(await reason(c.call('withdraw', { amountCents: WELCOME_BONUS_CENTS + 100, method: 'card' }))).toBe('INSUFFICIENT_FUNDS');
    const w = await c.call('withdraw', { amountCents: 40_000, method: 'card' });
    expect(w.balanceCents).toBe(WELCOME_BONUS_CENTS - 40_000);
    await c.close();
  });

  it('concurrent double spend: 5 parallel withdrawals of $400 from $1,000 → exactly 2 succeed', async () => {
    const c = await playerClient({ kyc: true });
    const res = await Promise.all(Array.from({ length: 5 }, () => reason(c.call('withdraw', { amountCents: 40_000, method: 'card' }))));
    expect(res.filter((r) => r === 'NO_ERROR')).toHaveLength(2);
    expect(res.filter((r) => r === 'INSUFFICIENT_FUNDS')).toHaveLength(3);
    expect(await balance(c.uid)).toBe(20_000);
    expect(await ledgerSum(c.uid)).toBe(20_000);
    await c.close();
  });

  it('concurrent double spend across callables (withdraw + buyPower) never goes negative', async () => {
    const c = await playerClient({ kyc: true });
    await c.call('withdraw', { amountCents: 95_000, method: 'card' }); // $50 left
    const res = await Promise.all([
      reason(c.call('buyPower', { powerId: 'peek', quantity: 1 })), // $30
      reason(c.call('buyPower', { powerId: 'peek', quantity: 1 })),
      reason(c.call('withdraw', { amountCents: 3_000, method: 'card' })),
    ]);
    expect(res.filter((r) => r === 'NO_ERROR')).toHaveLength(1);
    const b = await balance(c.uid);
    expect(b).toBe(2_000);
    expect(await ledgerSum(c.uid)).toBe(b);
    await c.close();
  });
});

describe('idempotency', () => {
  it('replaying a request returns the original response and executes once', async () => {
    const c = await playerClient({ kyc: true });
    const requestId = randomUUID();
    const r1 = await c.call('deposit', { requestId, amountCents: 2_500, method: 'card' });
    const r2 = await c.call('deposit', { requestId, amountCents: 2_500, method: 'card' });
    expect(r2).toEqual(r1);
    expect(await balance(c.uid)).toBe(WELCOME_BONUS_CENTS + 2_500);
    await c.close();
  });

  it('concurrent replays execute once', async () => {
    const c = await playerClient({ kyc: true });
    const requestId = randomUUID();
    const rs = await Promise.all([1, 2, 3].map(() => c.call('deposit', { requestId, amountCents: 1_000, method: 'card' })));
    expect(new Set(rs.map((r) => r.ledgerEntryId)).size).toBe(1);
    expect(await balance(c.uid)).toBe(WELCOME_BONUS_CENTS + 1_000);
    await c.close();
  });

  it('a requestId cannot be reused for another callable', async () => {
    const c = await playerClient({ kyc: true });
    const requestId = randomUUID();
    await c.call('deposit', { requestId, amountCents: 1_000, method: 'card' });
    expect(await reason(c.call('withdraw', { requestId, amountCents: 1_000, method: 'card' }))).toBe('REQUEST_ID_REUSED');
    await c.close();
  });

  it('requestIds are per user (another user with the same id executes normally)', async () => {
    const a = await playerClient({ kyc: true });
    const b = await playerClient({ kyc: true });
    const requestId = randomUUID();
    await a.call('deposit', { requestId, amountCents: 1_000, method: 'card' });
    const rb = await b.call('deposit', { requestId, amountCents: 2_000, method: 'card' });
    expect(rb.balanceCents).toBe(WELCOME_BONUS_CENTS + 2_000);
    await a.close();
    await b.close();
  });

  it('a stored response is only replayed to the user who made the request', async () => {
    const c = await playerClient({ kyc: true });
    const requestId = randomUUID();
    // A record under this key whose owner differs (possible only through an ambiguous `uid_requestId` key).
    await admin().doc(`idempotency/${c.uid}_${requestId}`).set({ fn: 'deposit', uid: 'someone-else', response: { leaked: true }, createdAtMs: Date.now() });
    expect(await reason(c.call('deposit', { requestId, amountCents: 1_000, method: 'card' }))).toBe('REQUEST_ID_REUSED');
    await c.close();
  });
});

describe('rate limiting', () => {
  it('claimAdReward: 6th call within a minute is RATE_LIMITED', async () => {
    const c = await playerClient();
    const res: string[] = [];
    for (let i = 0; i < 6; i++) res.push(await reason(c.call('claimAdReward', { adId: 'banner_1' })));
    expect(res[0]).toBe('NO_ERROR');
    expect(res.slice(1, 5).every((r) => r === 'AD_COOLDOWN')).toBe(true);
    expect(res[5]).toBe('RATE_LIMITED');
    expect(await balance(c.uid)).toBe(WELCOME_BONUS_CENTS + 500);
    await c.close();
  });

  it('a burst of parallel calls is cut at the limit', async () => {
    const c = await playerClient();
    const res = await Promise.all(Array.from({ length: 15 }, () => reason(c.call('buyPower', { powerId: 'freeInsurance', quantity: 1 }))));
    expect(res.filter((r) => r === 'RATE_LIMITED').length).toBe(5);
    expect(res.filter((r) => r === 'NO_ERROR').length).toBe(10);
    await c.close();
  });
});

describe('shop, ads, styles', () => {
  it('buyPower debits price × quantity and fills inventory', async () => {
    const c = await playerClient();
    const r = await c.call('buyPower', { powerId: 'freeSplit', quantity: 3 });
    expect(r).toEqual({ quantity: 3, balanceCents: WELCOME_BONUS_CENTS - 6_000 });
    expect(await reason(c.call('buyPower', { powerId: 'freeSplit', quantity: 11 }))).toBe('INVALID_ARGUMENT');
    expect(await reason(c.call('buyPower', { powerId: 'secondChance', quantity: 10 }))).toBe('NO_ERROR');
    expect(await reason(c.call('buyPower', { powerId: 'secondChance', quantity: 10 }))).toBe('NO_ERROR');
    expect(await reason(c.call('buyPower', { powerId: 'secondChance', quantity: 10 }))).toBe('INSUFFICIENT_FUNDS');
    await c.close();
  });

  it('equipCardStyle validates enums', async () => {
    const c = await playerClient();
    expect(await c.call('equipCardStyle', { cardBack: 'goldFiligree', felt: 'purple' })).toEqual({ cardBack: 'goldFiligree', cardFace: 'classic', felt: 'purple', title: null });
    expect(await reason(c.raw('equipCardStyle', { requestId: randomUUID(), cardBack: 'pirate' }))).toBe('INVALID_ARGUMENT');
    expect(await reason(c.raw('equipCardStyle', { requestId: randomUUID() }))).toBe('INVALID_ARGUMENT');
    await c.close();
  });

  it('verifyKyc helper sanity', async () => {
    const c = await playerClient();
    await verifyKyc(c);
    await c.close();
  });
});
