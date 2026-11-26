/**
 * Roulette bots (house money): a board when betting opens, chosen with the NON-fair `ctx.rng`
 * (never the round seed) from the bot's personality. 'min' bots play the even chances and the
 * dozens, 'flat' bots mix outside bets with their lucky numbers, 'aggressive' bots play the call
 * bets (voisins, tiers, orphelins, jeu zéro, neighbours of their lucky number) and pleins.
 * Every board respects the table caps (validated again by the kernel like a human's).
 */
import type { Rng } from '../../engine/rng';
import type { BetMap, GameLimits } from '../../shared/games/common';
import { ROULETTE_EVEN_SPOTS } from '../../shared/games/roulette';
import type { BotProfile } from '../../sim/profiles';
import { ANNOUNCE_IDS, addBoards, announceBoard, spotCap, SPOTS } from './engine';

/** Probability (in %) that a bot sits a round out. */
export const BOT_SKIP_PERCENT = 8;

const pick = <T>(rng: Rng, list: readonly T[]): T => list[rng.nextInt(list.length)];

/** Caps every spot and drops spots until the round total fits. */
export function fitBoard(board: BetMap, limits: GameLimits): BetMap {
  const out: BetMap = {};
  for (const [id, v] of Object.entries(board)) {
    const spot = SPOTS.get(id);
    if (!spot || v <= 0) continue;
    const capped = Math.min(v, spotCap(spot.type, limits));
    const whole = Math.floor(capped / 100) * 100;
    if (whole >= limits.minBetCents) out[id] = whole;
  }
  let total = Object.values(out).reduce((a, b) => a + b, 0);
  for (const id of Object.keys(out).reverse()) {
    if (total <= limits.maxRoundCents) break;
    total -= out[id];
    delete out[id];
  }
  return out;
}

/** The bot's board for this round (null = sits this round out). */
export function botBoard(rng: Rng, profile: BotProfile | null, limits: GameLimits): BetMap | null {
  if (rng.nextInt(100) < BOT_SKIP_PERCENT) return null;
  const style = profile?.betStyle ?? 'flat';
  const seed = profile?.seed ?? 0;
  const min = limits.minBetCents;
  const unit = min * (1 + ((seed + rng.nextInt(3)) % 3));
  const lucky = seed % 37;
  let board: BetMap = {};
  const add = (id: string, cents: number) => {
    board[id] = (board[id] ?? 0) + cents;
  };
  switch (style) {
    case 'min': {
      add(pick(rng, ROULETTE_EVEN_SPOTS), unit);
      if (rng.nextInt(3) === 0) add(`dozen${1 + rng.nextInt(3)}`, min);
      break;
    }
    case 'flat': {
      add(pick(rng, ROULETTE_EVEN_SPOTS), unit);
      add(`n${lucky}`, min);
      const r = rng.nextInt(4);
      if (r === 0) add(`col${1 + rng.nextInt(3)}`, unit);
      else if (r === 1) add(`n${rng.nextInt(37)}`, min);
      else if (r === 2) add(`co${pick(rng, [1, 5, 8, 13, 17, 20, 25, 29])}`, min);
      else add(`dozen${1 + rng.nextInt(3)}`, unit);
      break;
    }
    default: {
      const r = rng.nextInt(5);
      board = r < 4 ? announceBoard(ANNOUNCE_IDS[r], min) : announceBoard('neighbours', min, lucky);
      if (rng.nextInt(2) === 0) board = addBoards(board, { [`n${lucky}`]: min });
      if (rng.nextInt(3) === 0) add(pick(rng, ROULETTE_EVEN_SPOTS), unit * 2);
    }
  }
  const fitted = fitBoard(board, limits);
  return Object.keys(fitted).length ? fitted : null;
}
