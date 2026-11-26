/**
 * dating{op} — player-to-player "Rencontres" (shared/romance.ts). PHASE A STUB: the request
 * envelope is fully validated (strict per-op shapes, `datingSchema` in ./schemas.ts) and
 * rate-limited per op (DATING_OP_RATE_LIMITS through `rateKeyOf`); then, like the real feature,
 * the server switch `config/features.dating` is checked first (absent / false → DATING_DISABLED,
 * the classroom default), otherwise FEATURE_UNAVAILABLE. Nothing is written.
 *
 * TO THE RENDEZ-VOUS IMPLEMENTER (phase B): replace the handler (keep the export name `dating`,
 * already exported by src/index.ts). Firestore rules for datingMatches / messages are in place
 * (firebase/firestore.rules, tested in test/rules); the sim runner calls `datingBotTick`
 * (src/romance/bots.ts) every ~10 s for the bots' likes and replies.
 */
import { fail } from '../shared/errors';
import { refs } from '../shared/paths';
import { DATING_OP_RATE_LIMITS, type DatingRequest } from '../shared/romance';
import { defineCallable } from './framework';
import { datingSchema } from './schemas';

export const dating = defineCallable({
  name: 'dating',
  schema: datingSchema as unknown as import('zod').ZodType<DatingRequest>,
  tableIdOf: () => null,
  rateKeyOf: (d) => ({ key: `dating_op_${d.op}`, ...DATING_OP_RATE_LIMITS[d.op] }),
  handler: async (tx, _data, { db }) => {
    const features = await tx.get(refs(db).features());
    if (features.get('dating') !== true) throw fail.pre('DATING_DISABLED');
    throw fail.pre('FEATURE_UNAVAILABLE', 'Rencontres are not available yet');
  },
});
