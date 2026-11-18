import type { CardCode } from '../../src/shared/types';
import { startRound, type BetEntry, type RoundRules, type RoundState } from '../../src/engine';

export const RULES: RoundRules = { minBetCents: 100, maxBetCents: 100_000 };

/**
 * Build a deck for a single-seat round: player gets p1,p2; dealer up/hole; then `rest` in order.
 * Deal order is p1, up, p2, hole.
 */
export function deck1(p1: CardCode, p2: CardCode, up: CardCode, hole: CardCode, rest: CardCode[] = []): CardCode[] {
  return [p1, up, p2, hole, ...rest];
}

/** Multi-seat: first[i]/second[i] are seat i's cards (seat order). */
export function deckN(first: CardCode[], up: CardCode, second: CardCode[], hole: CardCode, rest: CardCode[] = []): CardCode[] {
  return [...first, up, ...second, hole, ...rest];
}

export function start1(p1: CardCode, p2: CardCode, up: CardCode, hole: CardCode, rest: CardCode[] = [], bet = 1000): RoundState {
  return startRound(RULES, [{ seatIndex: 0, playerId: 'p0', betCents: bet }], deck1(p1, p2, up, hole, rest));
}

export function bets(...amounts: number[]): BetEntry[] {
  return amounts.map((a, i) => ({ seatIndex: i, playerId: `p${i}`, betCents: a }));
}
