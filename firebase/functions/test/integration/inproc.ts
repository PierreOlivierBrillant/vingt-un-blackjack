/**
 * In-process callables: runs the real callable code (`execute`: auth, strict schema, rate limit,
 * idempotency, ONE Firestore transaction on the emulator) without the Functions emulator, so a
 * test can swap a game module in (overrideGameModuleForTests) — impossible through HTTP, where the
 * emulator runs the production registry (phase-A stubs).
 */
import { randomUUID } from 'node:crypto';
import { HttpsError } from 'firebase-functions/v2/https';
import { execute } from '../../src/callables/framework';
import { completeProfile } from '../../src/callables/account';
import type { CallableName, Callables, ErrorReason } from '../../src/shared/types';
import { uniqueName } from './client';

type DistOmit<T, K extends PropertyKey> = T extends unknown ? Omit<T, K> : never;

/** Calls a callable in-process as `uid` (a fresh requestId unless given). */
export function run<N extends CallableName>(
  callable: { def: { name: N } },
  uid: string,
  data: DistOmit<Callables[N][0], 'requestId'> & { requestId?: string },
): Promise<Callables[N][1]> {
  return execute(callable.def as never, uid, { requestId: randomUUID(), ...data }) as Promise<Callables[N][1]>;
}

/** Raw payload (to test validation). */
export function runRaw(callable: { def: unknown }, uid: string, data: unknown): Promise<unknown> {
  return execute(callable.def as never, uid, data);
}

export async function reasonIn(p: Promise<unknown>): Promise<ErrorReason | 'NO_ERROR'> {
  try {
    await p;
    return 'NO_ERROR';
  } catch (e) {
    if (e instanceof HttpsError) return (e.details as { reason: ErrorReason }).reason;
    throw e;
  }
}

/** A user with a completed profile ($1,000), no Firebase Auth account needed in-process. */
export async function inprocPlayer(): Promise<{ uid: string; username: string }> {
  const uid = `ip${randomUUID().replace(/-/g, '').slice(0, 24)}`;
  const username = uniqueName('k');
  await run(completeProfile, uid, { username, avatar: 'avatar02' });
  return { uid, username };
}
