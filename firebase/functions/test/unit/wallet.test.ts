/**
 * Regression test for the wallet signature (mitigation of direct emulator "owner" writes).
 * A balance changed in the database without going through a callable has no valid signature, so
 * WalletSession.load rejects it (WALLET_INTEGRITY): the forged money can never be spent.
 */
process.env.WALLET_SIGNING_KEY ||= 'unit-test-wallet-signing-key-0123456789';

import { beforeEach, describe, expect, it } from 'vitest';
import { AppError } from '../../src/shared/errors';
import type { WalletDoc } from '../../src/shared/types';
import { walletSignature, WalletSession } from '../../src/shared/wallet';

/** Minimal in-memory stand-in for the parts of Firestore WalletSession uses. */
function fakeBackend() {
  const store = new Map<string, Record<string, unknown>>();
  let counter = 0;
  const docRef = (path: string) => ({
    path,
    id: path.split('/').pop(),
    doc: (id?: string) => docRef(`${path}/${id ?? `auto${++counter}`}`),
  });
  const db = {
    doc: (p: string) => docRef(p),
    collection: (p: string) => ({ doc: (id?: string) => docRef(`${p}/${id ?? `auto${++counter}`}`) }),
  } as never;
  const tx = {
    get: async (ref: { path: string }) => ({ exists: store.has(ref.path), data: () => store.get(ref.path) }),
    set: (ref: { path: string }, data: Record<string, unknown>, opts?: { merge?: boolean }) =>
      store.set(ref.path, opts?.merge ? { ...(store.get(ref.path) ?? {}), ...data } : data),
  } as never;
  return { db, tx, store };
}

const UID = 'alice';
const WALLET_PATH = `users/${UID}/private/wallet`;

describe('wallet signature', () => {
  let be: ReturnType<typeof fakeBackend>;

  beforeEach(() => {
    be = fakeBackend();
    // Create a wallet the legitimate way: credit the welcome bonus, then write (signs it).
    const w = WalletSession.create(be.db, UID, 1_000);
    w.credit(100_000, 'welcomeBonus');
    w.write(be.tx);
  });

  it('signs the wallet on write and loads it back', async () => {
    const stored = be.store.get(WALLET_PATH) as unknown as WalletDoc;
    expect(stored.balanceCents).toBe(100_000);
    expect(stored.sig).toBe(walletSignature(UID, stored));
    const w = await WalletSession.load(be.db, be.tx, UID, 2_000);
    expect(w.balance).toBe(100_000);
  });

  it('rejects a balance changed in the database (forged money is not playable)', async () => {
    const stored = be.store.get(WALLET_PATH) as unknown as WalletDoc;
    stored.balanceCents = 999_999_999; // the PoC write: owner access, signature left untouched
    await expect(WalletSession.load(be.db, be.tx, UID, 2_000)).rejects.toMatchObject(
      { reason: 'WALLET_INTEGRITY' } satisfies Partial<AppError>,
    );
  });

  it('rejects a wallet whose signature was stripped', async () => {
    const stored = be.store.get(WALLET_PATH) as unknown as WalletDoc;
    delete stored.sig;
    await expect(WalletSession.load(be.db, be.tx, UID, 2_000)).rejects.toMatchObject({ reason: 'WALLET_INTEGRITY' });
  });

  it('rejects another account’s valid signature copied onto this wallet', async () => {
    const stored = be.store.get(WALLET_PATH) as unknown as WalletDoc;
    // A signature that is valid for a DIFFERENT uid but the same amounts must not validate here.
    stored.sig = walletSignature('mallory', stored);
    await expect(WalletSession.load(be.db, be.tx, UID, 2_000)).rejects.toMatchObject({ reason: 'WALLET_INTEGRITY' });
  });

  it('accepts a balance that was changed and re-signed through a session', async () => {
    const w = await WalletSession.load(be.db, be.tx, UID, 2_000);
    w.credit(5_000, 'adReward');
    w.write(be.tx);
    const reloaded = await WalletSession.load(be.db, be.tx, UID, 3_000);
    expect(reloaded.balance).toBe(105_000);
  });
});
