/** Rank points of kernel-driven games: shared ladder, anti-farming outcome, daily cap per game. Pure. */
import { GAME_RANK_POINTS, RANK_POINTS_DAILY_CAP_PER_GAME, type GameId, type GameRankOutcome } from '../../shared/games/common';
import { dayId, weekId } from '../../shared/time';
import type { ProfileDoc } from '../../shared/types';
import { rankTierFor } from '../../sim/profiles';

export interface RankUpdate {
  rankPoints: number;
  rankTier: ProfileDoc['rankTier'];
  weekId: string;
  weeklyPoints: number;
  rankDaily: NonNullable<ProfileDoc['rankDaily']>;
  /** Points actually applied (after the daily cap). */
  granted: number;
}

/**
 * Applies one round outcome to a profile (mutates `p`). Gains count toward the daily cap of the
 * game (RANK_POINTS_DAILY_CAP_PER_GAME, UTC day); losses always apply. Points never go below 0.
 */
export function applyRankOutcome(p: ProfileDoc, game: GameId, outcome: GameRankOutcome, now: number): RankUpdate {
  const day = dayId(now);
  const daily = p.rankDaily && p.rankDaily.day === day ? { day, byGame: { ...p.rankDaily.byGame } } : { day, byGame: {} as Partial<Record<GameId, number>> };
  const pts = GAME_RANK_POINTS[outcome];
  let granted = pts;
  if (pts > 0) {
    const earned = daily.byGame[game] ?? 0;
    granted = Math.max(0, Math.min(pts, RANK_POINTS_DAILY_CAP_PER_GAME - earned));
    daily.byGame[game] = earned + granted;
  }
  const wk = weekId(now);
  if (p.weekId !== wk) { p.weekId = wk; p.weeklyPoints = 0; }
  p.rankPoints = Math.max(0, p.rankPoints + granted);
  p.weeklyPoints = Math.max(0, p.weeklyPoints + granted);
  p.rankTier = rankTierFor(p.rankPoints);
  p.rankDaily = daily;
  return { rankPoints: p.rankPoints, rankTier: p.rankTier, weekId: p.weekId, weeklyPoints: p.weeklyPoints, rankDaily: daily, granted };
}
