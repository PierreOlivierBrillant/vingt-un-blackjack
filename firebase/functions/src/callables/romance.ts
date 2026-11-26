/**
 * romance{op} — Rendez-vous meta (contract: shared/romance.ts, rules: src/romance/service.ts).
 * The request envelope is validated by `romanceSchema` (src/callables/schemas.ts, strict per op) and
 * rate-limited per op (ROMANCE_OP_RATE_LIMITS through `rateKeyOf`); everything else (affinity,
 * scene replay, gifts, dates, rewards) is decided by the server in ONE transaction.
 * Table affinity arrives as blind increments `users/{uid}/romance/{DEALER_OF[game]}.tablePlay[day]`
 * written by every table settlement; `sync` (and every other op, for its character) folds them.
 */
import { romanceOp } from '../romance/service';
import { ROMANCE_OP_RATE_LIMITS, type RomanceRequest } from '../shared/romance';
import { defineCallable } from './framework';
import { romanceSchema } from './schemas';

export const romance = defineCallable({
  name: 'romance',
  schema: romanceSchema as unknown as import('zod').ZodType<RomanceRequest>,
  tableIdOf: () => null,
  rateKeyOf: (d) => ({ key: `romance_op_${d.op}`, ...ROMANCE_OP_RATE_LIMITS[d.op] }),
  handler: async (tx, data, { db, uid, now }) => ({ response: await romanceOp(tx, data, { db, uid, now }) }),
});
