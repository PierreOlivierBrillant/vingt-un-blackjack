/**
 * Basic strategy for the fixed rules (6 decks, S17, DAS, late surrender, no re-split of aces),
 * a "noisy" bot policy built on it, and a Monte-Carlo simulator used by the regression tests.
 */
import type { CardCode, PlayerAction } from '../shared/types';
import { CUT_CARD_REMAINING, DECKS_PER_SHOE } from '../shared/types';
import { buildShoe, cardPoints, handValue } from './cards';
import { nextFloat, shuffleInPlace, type Rng } from './rng';
import {
  actInPlace, canDouble, canSplit, canSurrender, startRoundInPlace, summarize, type RoundRules, type RoundState,
} from './round';

export type StrategyAction = 'hit' | 'stand' | 'double' | 'split' | 'surrender';

export interface Situation {
  cards: readonly CardCode[];
  dealerUp: CardCode;
  canDouble: boolean;
  canSplit: boolean;
  canSurrender: boolean;
}

/** Dealer up card as 2..11 (ace = 11). */
function upValue(c: CardCode): number {
  const p = cardPoints(c);
  return p === 1 ? 11 : p;
}

export function basicStrategy(x: Situation): StrategyAction {
  const d = upValue(x.dealerUp);
  const { total, soft } = handValue(x.cards);

  // Late surrender (S17): hard 16 vs 9/10/A, hard 15 vs 10. Never surrender a pair of 8s.
  if (x.canSurrender && !soft) {
    const isEights = x.cards.length === 2 && cardPoints(x.cards[0]) === 8 && cardPoints(x.cards[1]) === 8;
    if (!isEights && ((total === 16 && d >= 9) || (total === 15 && d === 10))) return 'surrender';
  }

  if (x.canSplit && x.cards.length === 2) {
    const p = cardPoints(x.cards[0]);
    const split =
      p === 1 ? true :
      p === 10 ? false :
      p === 9 ? (d >= 2 && d <= 9 && d !== 7) :
      p === 8 ? true :
      p === 7 ? d <= 7 :
      p === 6 ? d <= 6 :
      p === 5 ? false :
      p === 4 ? (d === 5 || d === 6) :
      /* 2,3 */ d <= 7;
    if (split) return 'split';
  }

  const dbl = (cond: boolean, otherwise: StrategyAction): StrategyAction => (cond && x.canDouble ? 'double' : otherwise);

  if (soft) {
    if (total >= 20) return 'stand';
    if (total === 19) return 'stand';
    if (total === 18) {
      if (d >= 3 && d <= 6) return dbl(true, 'stand');
      if (d === 2 || d === 7 || d === 8) return 'stand';
      return 'hit';
    }
    if (total === 17) return dbl(d >= 3 && d <= 6, 'hit');
    if (total === 16 || total === 15) return dbl(d >= 4 && d <= 6, 'hit');
    if (total === 14 || total === 13) return dbl(d >= 5 && d <= 6, 'hit');
    return 'hit';
  }

  if (total >= 17) return 'stand';
  if (total >= 13) return d <= 6 ? 'stand' : 'hit';
  if (total === 12) return d >= 4 && d <= 6 ? 'stand' : 'hit';
  if (total === 11) return dbl(d <= 10, 'hit');
  if (total === 10) return dbl(d <= 9, 'hit');
  if (total === 9) return dbl(d >= 3 && d <= 6, 'hit');
  return 'hit';
}

/** Situation for the current turn of a round. */
export function situationFor(s: RoundState): Situation | null {
  if (s.phase !== 'playerTurns' || !s.turn) return null;
  const seat = s.seats.find((x) => x.seatIndex === s.turn!.seatIndex)!;
  const h = seat.hands[s.turn.handIndex];
  return {
    cards: h.cards,
    dealerUp: s.dealer.cards[0],
    canDouble: canDouble(h),
    canSplit: canSplit(s, seat, h),
    canSurrender: canSurrender(seat, h),
  };
}

/**
 * Bot policy: basic strategy, but with probability `noise` a plausible human mistake
 * (hit/stand flip on 12–16, skipping a double/split/surrender).
 */
export function noisyStrategy(x: Situation, rng: Rng, noise = 0.08): StrategyAction {
  const best = basicStrategy(x);
  if (nextFloat(rng) >= noise) return best;
  const { total } = handValue(x.cards);
  if (best === 'double' || best === 'split' || best === 'surrender') return total >= 17 ? 'stand' : 'hit';
  if (total >= 12 && total <= 16) return best === 'hit' ? 'stand' : 'hit';
  if (total >= 19) return 'stand'; // even noisy bots do not hit 19+
  return best;
}

/** Map a strategy action onto an engine action (all StrategyActions are PlayerActions). */
export function toPlayerAction(a: StrategyAction): PlayerAction {
  return a;
}

// ---------------------------------------------------------------------------------------------
// Monte-Carlo

export interface SimulationResult {
  hands: number;
  totalStakedInitialCents: number;
  netCents: number;
  /** House edge = −net / Σ initial bets. */
  houseEdge: number;
}

/**
 * Plays `hands` rounds of one seat with flat `betCents` and perfect basic strategy (never takes
 * insurance), using a real 6-deck shoe with the cut card, shuffled with `rng`.
 */
export function simulateBasicStrategy(rng: Rng, hands: number, betCents = 100): SimulationResult {
  const rules: RoundRules = { minBetCents: 100, maxBetCents: 1_000_000 };
  let shoe: CardCode[] = shuffleInPlace(buildShoe(DECKS_PER_SHOE), rng);
  let pos = 0;
  let net = 0;
  for (let n = 0; n < hands; n++) {
    if (shoe.length - pos < CUT_CARD_REMAINING) {
      shoe = shuffleInPlace(buildShoe(DECKS_PER_SHOE), rng);
      pos = 0;
    }
    const deck = shoe.slice(pos);
    const s = startRoundInPlace(rules, [{ seatIndex: 0, playerId: 'p', betCents }], deck);
    if (s.phase === 'insurance') actInPlace(s, 0, 'insurance', { amountCents: 0 });
    while (s.phase === 'playerTurns') {
      const sit = situationFor(s)!;
      actInPlace(s, 0, basicStrategy(sit));
    }
    pos += s.deckPos;
    net += summarize(s)[0].netCents;
  }
  const staked = hands * betCents;
  return { hands, totalStakedInitialCents: staked, netCents: net, houseEdge: -net / staked };
}
