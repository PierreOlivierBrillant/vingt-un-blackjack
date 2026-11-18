/**
 * Application errors. Thrown anywhere on the server, converted to an HttpsError with
 * `details = { reason }` by the callable framework.
 */
import type { ErrorReason } from './types';

export type HttpCode =
  | 'invalid-argument' | 'failed-precondition' | 'not-found' | 'already-exists' | 'permission-denied'
  | 'resource-exhausted' | 'unauthenticated' | 'internal' | 'aborted';

export class AppError extends Error {
  constructor(public readonly code: HttpCode, public readonly reason: ErrorReason, message?: string) {
    super(message ?? reason);
    this.name = 'AppError';
  }
}

export const fail = {
  invalid: (reason: ErrorReason = 'INVALID_ARGUMENT', msg?: string) => new AppError('invalid-argument', reason, msg),
  pre: (reason: ErrorReason, msg?: string) => new AppError('failed-precondition', reason, msg),
  notFound: (reason: ErrorReason, msg?: string) => new AppError('not-found', reason, msg),
  exists: (reason: ErrorReason, msg?: string) => new AppError('already-exists', reason, msg),
  denied: (reason: ErrorReason, msg?: string) => new AppError('permission-denied', reason, msg),
};

/** Engine error code → (http code, reason). */
export function fromEngineCode(code: string): AppError {
  switch (code) {
    case 'BAD_PHASE': return fail.pre('BAD_PHASE');
    case 'NOT_YOUR_TURN': return fail.pre('NOT_YOUR_TURN');
    case 'NOT_SEATED': return fail.pre('NOT_SEATED');
    case 'ILLEGAL_ACTION': return fail.pre('ILLEGAL_ACTION');
    case 'BAD_AMOUNT': return fail.invalid('INVALID_ARGUMENT', 'bad amount');
    case 'BET_OUT_OF_RANGE': return fail.invalid('BET_OUT_OF_RANGE');
    case 'POWER_NOT_APPLICABLE': return fail.invalid('POWER_NOT_APPLICABLE');
    case 'POWER_ALREADY_USED': return fail.pre('POWER_ALREADY_USED');
    default: return new AppError('internal', 'INTERNAL', code);
  }
}
