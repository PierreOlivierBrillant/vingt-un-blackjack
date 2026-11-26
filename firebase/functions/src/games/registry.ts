/**
 * Registry of the kernel-driven games (complete since phase A: one module file per game,
 * src/games/<game>/module.ts — phase B replaces those files, never this one).
 * Test-only modules (src/games/testing/coin.ts, duel.ts) are NOT registered here; tests and the
 * load probe swap them in with `overrideGameModuleForTests` (in-process only, never in a callable).
 */
import { gameOfTableId, GAME_IDS, type GameId } from '../shared/games/common';
import { baccaratModule } from './baccarat/module';
import { crapsModule } from './craps/module';
import { holdemModule } from './holdem/module';
import type { AnyGameModule } from './kernel/module';
import { rouletteModule } from './roulette/module';

export const PRODUCTION_GAME_MODULES: Readonly<Record<GameId, AnyGameModule>> = Object.freeze({
  roulette: rouletteModule,
  baccarat: baccaratModule,
  holdem: holdemModule,
  craps: crapsModule,
});

const active: Record<GameId, AnyGameModule> = { ...PRODUCTION_GAME_MODULES };

export function gameModule(game: GameId): AnyGameModule {
  return active[game];
}

/** Module of a kernel-driven table id (`rl-…`, `bc-…`, `ho-…`, `cr-…`), null for blackjack ids. */
export function moduleOfTableId(tableId: string): AnyGameModule | null {
  const g = gameOfTableId(tableId);
  return g === 'blackjack' ? null : active[g];
}

/** Games whose module is available (implemented). */
export function availableGames(): GameId[] {
  return GAME_IDS.filter((g) => active[g].available);
}

/** Tests / load probe only: plays `game` tables with another module (null restores production). */
export function overrideGameModuleForTests(game: GameId, module: AnyGameModule | null): void {
  active[game] = module ? { ...module, game } as AnyGameModule : PRODUCTION_GAME_MODULES[game];
}
