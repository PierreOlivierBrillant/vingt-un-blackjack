/**
 * Baccarat (Punto Banco, 8 decks) — shared contract. OWNER: baccarat implementer.
 * Values in the exported lists below are spread into the global unions of ../types.ts.
 * Append new values at the END of a list (never rename/remove: Dart mirrors them).
 *
 * TODO(baccarat implementer): document the public state `g` (cards, totals, roads, shoe info), the
 * seat state, the spot ids ("player", "banker", "tie", "playerPair", "bankerPair") and event types.
 */
export const BACCARAT_POWER_IDS = ['freeCommission'] as const;
export const BACCARAT_MARKET_KINDS = ['baccaratBanker', 'baccaratTie', 'baccaratPair', 'baccaratBankerShoe'] as const;
export const BACCARAT_REASONS = [] as const;

export type BaccaratPowerId = (typeof BACCARAT_POWER_IDS)[number];
