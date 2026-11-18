/**
 * Integration-test helpers: real Firebase JS SDK clients (one app instance per simulated device)
 * talking to the Auth + Functions emulators, plus an Admin SDK handle to inspect server-only data.
 * Must run under `firebase emulators:exec` (env vars FIRESTORE_EMULATOR_HOST etc. are set).
 */
import { randomUUID } from 'node:crypto';
import { deleteApp, initializeApp, type FirebaseApp } from 'firebase/app';
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth } from 'firebase/auth';
import { connectFunctionsEmulator, getFunctions, httpsCallable, type FunctionsError } from 'firebase/functions';
import { connectFirestoreEmulator, getFirestore, type Firestore as ClientFirestore } from 'firebase/firestore';
import { firestore as adminDb } from '../../src/shared/admin';
import type { CallableName, Callables, ErrorReason } from '../../src/shared/types';

const HOST = process.env.BACKEND_HOST ?? '127.0.0.1';
const [FS_HOST, FS_PORT] = (process.env.FIRESTORE_EMULATOR_HOST ?? `${HOST}:8080`).split(':');

export const admin = () => adminDb();

type DistOmit<T, K extends PropertyKey> = T extends unknown ? Omit<T, K> : never;

export interface Client {
  uid: string;
  app: FirebaseApp;
  db: ClientFirestore;
  call<N extends CallableName>(name: N, data: DistOmit<Callables[N][0], 'requestId'> & { requestId?: string }): Promise<Callables[N][1]>;
  /** Raw call with arbitrary payload (to test validation). */
  raw(name: string, data: unknown): Promise<unknown>;
  close(): Promise<void>;
}

let counter = 0;

export async function newClient(opts: { signIn?: boolean } = {}): Promise<Client> {
  const app = initializeApp({ apiKey: 'demo-key', projectId: 'demo-blackjack', authDomain: 'demo-blackjack.firebaseapp.com' }, `client-${Date.now()}-${counter++}`);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${HOST}:9099`, { disableWarnings: true });
  const fns = getFunctions(app, 'us-central1');
  connectFunctionsEmulator(fns, HOST, 5001);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, FS_HOST, Number(FS_PORT));
  let uid = '';
  if (opts.signIn !== false) {
    const cred = await createUserWithEmailAndPassword(auth, `user${randomUUID().slice(0, 12)}@example.test`, `Pw-${randomUUID()}`);
    uid = cred.user.uid;
  }
  return {
    uid, app, db,
    async call(name, data) {
      const fn = httpsCallable(fns, name, { timeout: 60_000 });
      const res = await fn({ requestId: randomUUID(), ...data });
      return res.data as never;
    },
    async raw(name, data) {
      const fn = httpsCallable(fns, name, { timeout: 60_000 });
      return (await fn(data)).data;
    },
    async close() {
      await deleteApp(app);
    },
  };
}

/** Assert a promise rejects with the given `details.reason`. */
export async function reason(p: Promise<unknown>): Promise<ErrorReason | 'NO_ERROR'> {
  try {
    await p;
    return 'NO_ERROR';
  } catch (e) {
    const fe = e as FunctionsError;
    return ((fe.details as { reason?: ErrorReason } | undefined)?.reason ?? (fe.code as ErrorReason));
  }
}

let nameCounter = 0;
export function uniqueName(prefix = 'u'): string {
  return `${prefix}${Date.now().toString(36).slice(-6)}${(nameCounter++).toString(36)}`.slice(0, 16);
}

/** Signed-in client with a completed profile (welcome bonus $1,000). */
export async function playerClient(opts: { kyc?: boolean } = {}): Promise<Client & { username: string }> {
  const c = await newClient();
  const username = uniqueName('p');
  await c.call('completeProfile', { username, avatar: 'avatar01' });
  if (opts.kyc) await verifyKyc(c);
  return Object.assign(c, { username });
}

/** Submit KYC as an adult and fast-forward the fake review (admin backdates verifyAfterMs). */
export async function verifyKyc(c: Client): Promise<void> {
  await c.call('submitKyc', { docType: 'passport', birthDate: '1990-05-17' });
  await admin().doc(`users/${c.uid}/private/kyc`).update({ verifyAfterMs: Date.now() - 1 });
  const r = await c.call('submitKyc', { refresh: true });
  if (r.status !== 'verified') throw new Error(`kyc not verified: ${r.status}`);
}

export async function balance(uid: string): Promise<number> {
  return (await admin().doc(`users/${uid}/private/wallet`).get()).get('balanceCents') as number;
}

export async function ledgerSum(uid: string): Promise<number> {
  const s = await admin().collection(`users/${uid}/ledger`).get();
  return s.docs.reduce((a, d) => a + (d.get('amountCents') as number), 0);
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
