/**
 * Craps — shared contract. OWNER: craps implementer.
 * Values in the exported lists below are spread into the global unions of ../types.ts.
 * Append new values at the END of a list (never rename/remove: Dart mirrors them).
 * Every roll is a round (own seed, own rounds/{n} doc). Bets stay on the board between rolls.
 *
 * TODO(craps implementer): document `g` (point, shooter, dice, puck, roll history…), the seat
 * state, the spot ids ("pass", "dontPass", "come", "odds:pass", "place6", "field", "hard8"…), the
 * action {type:'roll'} and event types.
 */
export const CRAPS_POWER_IDS = ['safetyNet'] as const;
export const CRAPS_MARKET_KINDS = ['crapsSeven', 'crapsPoint'] as const;
export const CRAPS_REASONS = ['NOT_SHOOTER', 'MUST_BET_LINE'] as const;

export type CrapsPowerId = (typeof CRAPS_POWER_IDS)[number];
