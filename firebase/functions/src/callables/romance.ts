/**
 * romance{op} — Rendez-vous meta (shared/romance.ts). PHASE A STUB: the request envelope is fully
 * validated (strict per-op shapes, src/callables/schemas.ts `romanceSchema`) and rate-limited per op
 * (ROMANCE_OP_RATE_LIMITS through `rateKeyOf`), then the call is refused with FEATURE_UNAVAILABLE
 * (failed-precondition) — nothing is written.
 *
 * TO THE RENDEZ-VOUS IMPLEMENTER (phase B): replace the handler (keep the export name `romance`,
 * already exported by src/index.ts). Table affinity already arrives as blind increments
 * `users/{uid}/romance/{DEALER_OF[game]}.tablePlay[day]` written by every table settlement
 * (blackjack and kernel games, humans who staked ≥ the table minimum / were dealt in): such a
 * document may hold ONLY `tablePlay` until your first write — fill the other RomanceDoc fields
 * with defaults when you read it.
 */
import { fail } from '../shared/errors';
import { ROMANCE_OP_RATE_LIMITS, type RomanceRequest } from '../shared/romance';
import { defineCallable } from './framework';
import { romanceSchema } from './schemas';

export const romance = defineCallable({
  name: 'romance',
  schema: romanceSchema as unknown as import('zod').ZodType<RomanceRequest>,
  tableIdOf: () => null,
  rateKeyOf: (d) => ({ key: `romance_op_${d.op}`, ...ROMANCE_OP_RATE_LIMITS[d.op] }),
  handler: async () => {
    throw fail.pre('FEATURE_UNAVAILABLE', 'Rendez-vous is not available yet');
  },
});
