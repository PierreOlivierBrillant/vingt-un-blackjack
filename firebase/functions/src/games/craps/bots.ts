/**
 * Craps bots (pure): the WHOLE board a bot wants when a betting window opens. A bot plays by the
 * same rules as a human (its board goes through `validateBets`): it keeps its contract bets, the
 * shooter always has a line bet on the come-out, odds within 3-4-5× / 6×, place 6/8 by $3.
 * Personality from the bot profile: betStyle (min / flat / aggressive) sets the unit and the
 * appetite for odds and place bets; one bot in six plays the "dark side" (Don't Pass).
 */
import type { Rng } from '../../engine/rng';
import { nextFloat } from '../../engine/rng';
import type { BetMap, GameLimits } from '../../shared/games/common';
import { CRAPS_INCREMENT_CENTS, CRAPS_LAY_MULTIPLE, CRAPS_ODDS_MULTIPLE, CRAPS_POINTS, type CrapsPoint } from '../../shared/games/craps';
import type { BotProfile } from '../../sim/profiles';
import { checkBoard, hasLineBet } from './engine';

export interface BotBoardInput {
  current: BetMap;
  point: CrapsPoint | null;
  shooter: boolean;
  limits: GameLimits;
  profile: BotProfile | null;
  rng: Rng;
}

const roundUp = (v: number, step: number) => Math.ceil(v / step) * step;

/** Board of a bot for this window, or null to leave its board as it is. */
export function botBoard(p: BotBoardInput): BetMap | null {
  const { current, point, limits, rng } = p;
  const style = p.profile?.betStyle ?? 'flat';
  const dark = ((p.profile?.seed ?? 0) % 6) === 0;
  const chance = (x: number) => nextFloat(rng) < x;
  const mult = style === 'min' ? 1 : style === 'flat' ? 2 : 3;
  const unit = Math.min(limits.maxBetCents, limits.minBetCents * mult);
  const placeUnit = Math.min(roundUp(Math.max(unit, limits.minBetCents), CRAPS_INCREMENT_CENTS), Math.floor(limits.maxBetCents / CRAPS_INCREMENT_CENTS) * CRAPS_INCREMENT_CENTS);
  const board: BetMap = { ...current };
  const mustBet = p.shooter && point === null && !hasLineBet(current);
  if (!mustBet && chance(0.07)) return null; // a quiet roll

  if (point === null) {
    if (!hasLineBet(board) && (p.shooter || chance(0.72))) board[dark ? 'dontPass' : 'pass'] = unit;
    if (chance(0.05)) board[chance(0.5) ? 'yo' : 'any7'] = limits.minBetCents;
  } else {
    const appetite = style === 'aggressive' ? 0.8 : style === 'flat' ? 0.5 : 0.2;
    const pass = board.pass ?? 0;
    if (pass > 0 && !board['odds:pass'] && chance(appetite)) {
      const max = pass * CRAPS_ODDS_MULTIPLE[point];
      board['odds:pass'] = style === 'aggressive' ? max : Math.min(max, pass * (1 + rng.nextInt(2)));
    }
    const dp = board.dontPass ?? 0;
    if (dp > 0 && !board['odds:dontPass'] && chance(appetite * 0.7)) {
      const lay = Math.min(dp * CRAPS_LAY_MULTIPLE, dp * (style === 'aggressive' ? 3 : 1));
      const step = point === 4 || point === 10 ? 100 : CRAPS_INCREMENT_CENTS;
      const v = Math.floor(lay / step) * step;
      if (v >= 100) board['odds:dontPass'] = v;
    }
    const comeNumbers = CRAPS_POINTS.filter((n) => (board[`come${n}`] ?? 0) > 0).length;
    if (comeNumbers < 2 && chance(style === 'aggressive' ? 0.35 : 0.15)) board[dark ? 'dontCome' : 'come'] = unit;
    for (const n of CRAPS_POINTS) {
      const c = board[`come${n}`] ?? 0;
      if (c > 0 && !board[`odds:come${n}`] && chance(appetite * 0.6)) board[`odds:come${n}`] = c;
    }
    if (!dark && chance(style === 'aggressive' ? 0.5 : style === 'flat' ? 0.25 : 0.08)) {
      for (const n of [6, 8] as const) if (!board[`place${n}`] && point !== n) board[`place${n}`] = placeUnit;
    }
    if (chance(0.08)) board.field = limits.minBetCents;
    if (chance(0.04)) board[chance(0.5) ? 'hard6' : 'hard8'] = limits.minBetCents;
    if (chance(0.03)) board[(['any7', 'anyCraps', 'yo', 'two', 'twelve'] as const)[rng.nextInt(5)]] = limits.minBetCents;
  }
  const total = Object.values(board).reduce((a, v) => a + v, 0);
  try {
    if (total > limits.maxRoundCents) throw new Error('over the round maximum');
    checkBoard(board, current, { point, minBetCents: limits.minBetCents, maxBetCents: limits.maxBetCents, shooter: p.shooter });
    return board;
  } catch {
    if (!mustBet) return null;
    const fallback: BetMap = { ...current, [dark ? 'dontPass' : 'pass']: limits.minBetCents };
    return fallback;
  }
}
