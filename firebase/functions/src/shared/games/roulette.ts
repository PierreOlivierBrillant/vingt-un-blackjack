/**
 * Roulette (European, single zero) — shared contract. OWNER: roulette implementer.
 * Values in the exported lists below are spread into the global unions of ../types.ts.
 * Append new values at the END of a list (never rename/remove: Dart mirrors them).
 *
 * TODO(roulette implementer): document here the public state `g` (RoulettePublic), the seat state,
 * the bet spot id grammar (e.g. "n17", "sp17-20", "red"…), event types and any game action.
 */
export const ROULETTE_POWER_IDS = ['zeroShield'] as const;
export const ROULETTE_MARKET_KINDS = ['rouletteRed', 'rouletteZero', 'rouletteDozen3', 'rouletteZeroSeries'] as const;
export const ROULETTE_REASONS = [] as const;

export type RoulettePowerId = (typeof ROULETTE_POWER_IDS)[number];
