/**
 * Callable framework: every callable goes through `execute`, which enforces in this order
 *   1. authentication,
 *   2. strict zod validation (unknown fields rejected),
 *   3. per-user fixed-window rate limit (its own small transaction, so failed calls count too),
 *      plus an optional per-operation limit (`rateKeyOf`, e.g. romance/dating `op`),
 *   4. overdue table timeouts (the user's current table, or the table named in the request),
 *   5. the handler inside ONE Firestore transaction that also reads/writes the idempotency record
 *      `idempotency/{uid}_{requestId}` — a replay returns the stored response, never re-executes,
 *   6. optional post-commit work (e.g. paying market positions), errors logged not thrown.
 * Logs never contain personal data (only callable name, reason codes, uids are pseudonymous).
 */
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { EngineError } from '../engine/round';
import { LmsrError } from '../market/lmsr';
import { firestore } from '../shared/admin';
import { AppError, fail, fromEngineCode } from '../shared/errors';
import { refs } from '../shared/paths';
import type { CallableName, Callables } from '../shared/types';
import { RATE_LIMITS } from '../shared/types';

export interface Ctx {
  uid: string;
  now: number;
  db: Firestore;
  requestId: string;
}

export interface TxResult<R> {
  response: R;
  /** Runs after the transaction committed (not on idempotent replays). */
  after?: () => Promise<void>;
}

export type Handler<N extends CallableName> = (
  tx: Transaction, data: Callables[N][0], ctx: Ctx,
) => Promise<TxResult<Callables[N][1]>>;

interface Def<N extends CallableName> {
  name: N;
  schema: z.ZodType<Callables[N][0]>;
  handler: Handler<N>;
  /** Table whose overdue deadlines are applied before the handler (default: user's current table). */
  tableIdOf?: (data: Callables[N][0]) => string | null;
  /**
   * Extra per-operation limit checked together with the callable's own (e.g. romance / dating
   * `op`, see ROMANCE_OP_RATE_LIMITS / DATING_OP_RATE_LIMITS). `key`: [A-Za-z0-9_]+, unique per op.
   */
  rateKeyOf?: (data: Callables[N][0]) => RateKey | null;
}

export interface RateKey { key: string; count: number; windowMs: number }

/** Hook installed by the table module (avoids an import cycle). */
type OverdueHook = (db: Firestore, tableId: string, now: number) => Promise<void>;
let overdueHook: OverdueHook | null = null;
export function setOverdueHook(h: OverdueHook): void {
  overdueHook = h;
}

export const requestIdSchema = z.string().regex(/^[A-Za-z0-9_-]{8,64}$/);

function toHttps(e: unknown, name: string): HttpsError {
  let app: AppError;
  if (e instanceof HttpsError) return e;
  if (e instanceof AppError) app = e;
  else if (e instanceof z.ZodError) {
    const issue = e.issues[0];
    app = fail.invalid('INVALID_ARGUMENT', `${issue?.path.join('.') || 'request'}: ${issue?.message ?? 'invalid'}`);
  } else if (e instanceof EngineError) app = fromEngineCode(e.code);
  else if (e instanceof LmsrError) {
    app = e.code === 'MARKET_LIMIT' ? fail.pre('MARKET_LIMIT') : fail.invalid('INVALID_ARGUMENT', e.code);
  } else {
    const err = e as Error;
    logger.error('callable internal error', { callable: name, error: err?.name, message: err?.message, stack: err?.stack });
    app = new AppError('internal', 'INTERNAL', 'internal error');
  }
  return new HttpsError(app.code, app.message, { reason: app.reason });
}

async function rateLimit(db: Firestore, uid: string, name: CallableName, now: number, extra: RateKey | null = null): Promise<void> {
  const limits: RateKey[] = [{ key: name, ...RATE_LIMITS[name] }];
  if (extra) {
    if (!/^[A-Za-z0-9_]+$/.test(extra.key) || extra.key === name) throw new Error(`bad rate key ${extra.key}`);
    limits.push(extra);
  }
  const ref = refs(db).rateLimit(uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const all = (snap.data() ?? {}) as Record<string, { windowStartMs: number; count: number }>;
    const out: Record<string, { windowStartMs: number; count: number }> = {};
    for (const { key, count, windowMs } of limits) {
      const cur = all[key];
      const fresh = !cur || now - cur.windowStartMs >= windowMs;
      const next = fresh ? { windowStartMs: now, count: 1 } : { windowStartMs: cur.windowStartMs, count: cur.count + 1 };
      if (next.count > count) throw new AppError('resource-exhausted', 'RATE_LIMITED', 'too many requests');
      out[key] = next;
    }
    tx.set(ref, out, { merge: true });
  });
}

const lastPresenceWrite = new Map<string, number>();
async function touchPresence(db: Firestore, uid: string, now: number): Promise<void> {
  const last = lastPresenceWrite.get(uid) ?? 0;
  if (now - last < 30_000) return;
  lastPresenceWrite.set(uid, now);
  try {
    await refs(db).profile(uid).update({ lastSeenAtMs: now });
  } catch {
    /* profile not created yet */
  }
}

/** Core executor (independent of the Functions runtime). */
export async function execute<N extends CallableName>(def: Def<N>, uid: string | undefined, raw: unknown): Promise<Callables[N][1]> {
  try {
    if (!uid) throw new AppError('unauthenticated', 'UNAUTHENTICATED', 'sign in required');
    const data = def.schema.parse(raw ?? {});
    const db = firestore();
    const now = Date.now();
    await rateLimit(db, uid, def.name, now, def.rateKeyOf ? def.rateKeyOf(data) : null);

    if (overdueHook) {
      let tableId = def.tableIdOf ? def.tableIdOf(data) : null;
      if (tableId === null && !def.tableIdOf) {
        const p = await refs(db).profile(uid).get();
        tableId = (p.get('currentTableId') as string | null | undefined) ?? null;
      }
      if (tableId) {
        try {
          await overdueHook(db, tableId, now);
        } catch (e) {
          logger.warn('overdue hook failed', { callable: def.name, error: (e as Error)?.message });
        }
      }
    }

    const requestId = (data as { requestId: string }).requestId;
    const idemRef = refs(db).idempotency(uid, requestId);
    let after: (() => Promise<void>) | undefined;
    const response = await db.runTransaction(async (tx) => {
      after = undefined;
      const idem = await tx.get(idemRef);
      if (idem.exists) {
        if (idem.get('fn') !== def.name || idem.get('uid') !== uid) throw fail.invalid('REQUEST_ID_REUSED');
        return idem.get('response') as Callables[N][1];
      }
      const res = await def.handler(tx, data, { uid, now: Date.now(), db, requestId });
      tx.set(idemRef, { fn: def.name, uid, response: res.response, createdAtMs: now });
      after = res.after;
      return res.response;
    });
    if (after) {
      try {
        await after();
      } catch (e) {
        logger.warn('post-commit step failed', { callable: def.name, error: (e as Error)?.message });
      }
    }
    void touchPresence(db, uid, now);
    return response;
  } catch (e) {
    const h = toHttps(e, def.name);
    if (h.code !== 'internal') logger.info('callable rejected', { callable: def.name, reason: (h.details as { reason?: string })?.reason });
    throw h;
  }
}

/** Define a deployed callable. */
export function defineCallable<N extends CallableName>(def: Def<N>) {
  const fn = onCall({ region: 'us-central1', cors: true, invoker: 'public' }, (req) => execute(def, req.auth?.uid, req.data));
  return Object.assign(fn, { def });
}
