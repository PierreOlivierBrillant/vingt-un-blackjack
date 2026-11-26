/**
 * Texas hold'em No-Limit (player vs player) — shared contract. OWNER: hold'em implementer.
 * Values in the exported lists below are spread into the global unions of ../types.ts.
 * Append new values at the END of a list (never rename/remove: Dart mirrors them).
 * No powers in hold'em (PvP fairness).
 *
 * Deck: fairDealOrder(buildShoe(1), seed, 1); fixed positions: hole cards 0..2n-1 (two passes from
 * the small blind), then burn, flop×3, burn, turn, burn, river — the board is fixed at the deal
 * (board markets settle on it even if everyone folds).
 *
 * TODO(hold'em implementer): document `g` (button, blinds, board, pots, current bet, min raise…),
 * the seat state, the actions ({type:'fold'|'check'|'call'|'allIn'}, {type:'bet'|'raise', toCents},
 * {type:'rebuy', cents}) and event types.
 */
export const HOLDEM_POWER_IDS = [] as const;
export const HOLDEM_MARKET_KINDS = ['holdemBoardAce', 'holdemBoardFlush'] as const;
export const HOLDEM_REASONS = [
  'BUY_IN_OUT_OF_RANGE', 'REBUY_NOT_ALLOWED', 'SITTING_OUT',
  // gameJoin of a hold'em table without buyInCents (e.g. a private code typed with another game selected)
  'BUY_IN_REQUIRED',
] as const;
