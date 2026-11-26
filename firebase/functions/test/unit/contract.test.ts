/**
 * Cross-language contract: every enum the Flutter client mirrors is dumped to
 * test/golden/contract.json (committed). The Dart test app/test/unit/contract_parity_test.dart reads
 * the same file, so a value added on one side without the other fails a test.
 * Regenerate after an intended change: npx vitest run --config vitest.unit.config.mts test/unit/contract.test.ts -u
 */
import { describe, expect, it } from 'vitest';
import {
  ALL_GAMES, GAME_EVENTS_CAP, GAME_MISSED_ROUNDS_LIMIT, GAME_PHASES, GAME_PREFIX, GAME_RANK_POINTS, GAME_SEATS, GAME_TIMING,
  RANK_POINTS_DAILY_CAP_PER_GAME,
} from '../../src/shared/games/common';
import { COSMETICS, EXCLUSIVE_CARD_BACKS, EXCLUSIVE_FELTS, TITLE_IDS } from '../../src/shared/cosmetics';
import { AFFINITY_TIER_THRESHOLDS, CHARACTER_IDS, DEALER_OF } from '../../src/shared/romance';
import {
  CALLABLE_NAMES, ERROR_REASONS, LEDGER_TYPES, MARKET_KINDS, MARKET_LIQUIDITY, POWER_GAME, POWER_IDS, POWER_PRICES_CENTS,
  SERIES_MARKET_KINDS, type CallableName, type Callables,
} from '../../src/shared/types';

describe('contract', () => {
  it('CALLABLE_NAMES lists every callable exactly once', () => {
    const all: Record<CallableName, true> = Object.fromEntries(CALLABLE_NAMES.map((n) => [n, true])) as Record<keyof Callables, true>;
    expect(new Set(CALLABLE_NAMES).size).toBe(CALLABLE_NAMES.length);
    expect(Object.keys(all).sort()).toEqual([...CALLABLE_NAMES].sort());
  });

  it('every cosmetic id is unique and catalogued', () => {
    const ids = [...EXCLUSIVE_CARD_BACKS, ...EXCLUSIVE_FELTS, ...TITLE_IDS];
    expect(new Set(ids).size).toBe(ids.length);
    for (const id of ids) expect(COSMETICS[id]?.free).toBe(false);
  });

  it('matches test/golden/contract.json (mirrored by the Dart client)', async () => {
    const contract = {
      errorReasons: ERROR_REASONS,
      powerIds: POWER_IDS,
      powerGame: POWER_GAME,
      powerPricesCents: POWER_PRICES_CENTS,
      marketKinds: MARKET_KINDS,
      seriesMarketKinds: SERIES_MARKET_KINDS,
      marketLiquidity: MARKET_LIQUIDITY,
      ledgerTypes: LEDGER_TYPES,
      games: ALL_GAMES,
      gamePrefix: GAME_PREFIX,
      gameSeats: GAME_SEATS,
      gamePhases: GAME_PHASES,
      gameTiming: GAME_TIMING,
      gameMissedRoundsLimit: GAME_MISSED_ROUNDS_LIMIT,
      gameEventsCap: GAME_EVENTS_CAP,
      gameRankPoints: GAME_RANK_POINTS,
      rankPointsDailyCapPerGame: RANK_POINTS_DAILY_CAP_PER_GAME,
      characters: CHARACTER_IDS,
      dealerOf: DEALER_OF,
      affinityTierThresholds: AFFINITY_TIER_THRESHOLDS,
      cosmetics: COSMETICS,
      callables: CALLABLE_NAMES,
    };
    await expect(JSON.stringify(contract, null, 1) + '\n').toMatchFileSnapshot('../golden/contract.json');
  });
});
