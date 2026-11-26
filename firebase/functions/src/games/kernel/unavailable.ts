/**
 * Module of a game that is not implemented yet (phase A stubs, see src/games/<game>/module.ts).
 * Safe by construction: `available: false` makes gameJoin refuse with FEATURE_UNAVAILABLE, the
 * matchmaking scan skip the game, the sim runner create no table for it, and any table of that game
 * that is still open close at its next transaction with every cent refunded (boards, stacks, queue).
 */
import { z } from 'zod';
import { fail } from '../../shared/errors';
import type { GameId } from '../../shared/games/common';
import { STAKE_TIER_LIMITS } from '../../shared/types';
import { defineGameModule, type AnyGameModule } from './module';

export function unavailableModule(game: GameId): AnyGameModule {
  const unavailable = (): never => {
    throw fail.pre('FEATURE_UNAVAILABLE');
  };
  return defineGameModule({
    game,
    available: false,
    money: game === 'holdem' ? 'stack' : 'board',
    actionSchema: z.strictObject({ type: z.literal('unavailable') }),
    limits: (tier) => {
      const l = STAKE_TIER_LIMITS[tier];
      return { minBetCents: l.minBetCents, maxBetCents: l.maxBetCents, maxRoundCents: l.maxBetCents * 5, extra: {} };
    },
    init: () => ({ g: {}, priv: {} }),
    seatInit: () => ({}),
    canStart: () => false,
    openRound: (ctx) => ctx.idle(),
    validateBets: unavailable,
    power: unavailable,
    closeBetting: (ctx) => ctx.idle(),
    act: unavailable,
    legalActions: () => [],
    onDeadline: (ctx) => ctx.idle(),
    seatClear: () => true,
    onLeaving: () => ({}),
    bot: () => null,
    fairEstimate: () => 0.5,
  });
}
