/**
 * Baccarat (Punto Banco) engine — pure: no Firebase, no clock, no randomness of its own.
 * Rules: shared/games/baccarat.ts (header). A coup is dealt from a deal order (the provably-fair
 * `fairDealOrder(remainingBefore, seed, 8)`), burn included; payouts are integer cents.
 */
import { cardPoints, RANKS } from '../../engine/cards';
import type { Rng } from '../../engine/rng';
import type { BetMap } from '../../shared/games/common';
import {
  BACCARAT_CUT_CARDS, BACCARAT_SHOE_THRESHOLD_PCT, BACCARAT_TIMING,
  type BaccaratCoupPublic, type BaccaratWinner,
} from '../../shared/games/baccarat';
import type { CardCode } from '../../shared/types';

/** Baccarat value of a card: ace 1, 2–9 face value, ten / J / Q / K 0. */
export function baccaratValue(card: CardCode): number {
  const p = cardPoints(card);
  return p === 10 ? 0 : p;
}

/** Total of a hand (sum of values mod 10). */
export function handTotal(cards: readonly CardCode[]): number {
  let t = 0;
  for (const c of cards) t += baccaratValue(c);
  return t % 10;
}

/** Number of cards burned after the burn card (ace 1, 2–9 face value, ten / faces 10). */
export function burnCount(card: CardCode): number {
  return cardPoints(card);
}

export const isPair = (cards: readonly CardCode[]): boolean => cards.length >= 2 && cards[0][0] === cards[1][0];

/** Player draws a third card on 0–5 (no natural). */
export const playerDraws = (playerTotal: number): boolean => playerTotal <= 5;

/**
 * Banker's drawing rule (no natural). `playerThird` = baccarat value of Player's third card, or null
 * when Player stood on two cards.
 */
export function bankerDraws(bankerTotal: number, playerThird: number | null): boolean {
  if (playerThird === null) return bankerTotal <= 5;
  switch (bankerTotal) {
    case 0: case 1: case 2: return true;
    case 3: return playerThird !== 8;
    case 4: return playerThird >= 2 && playerThird <= 7;
    case 5: return playerThird >= 4 && playerThird <= 7;
    case 6: return playerThird === 6 || playerThird === 7;
    default: return false;
  }
}

export interface DealtCoup extends Omit<BaccaratCoupPublic, 'burn'> {
  burn: { card: CardCode; count: number; cards: CardCode[] } | null;
  /** Every card taken from the order, in order (burn card, burned cards, then the coup). */
  dealt: CardCode[];
}

/** The outcome of a coup, as needed by the payouts. */
export type CoupOutcome = Pick<BaccaratCoupPublic, 'winner' | 'playerPair' | 'bankerPair'>;

/**
 * Deals one coup from `order` (index 0 upward). `burn`: first coup of a shoe (burn card + burned
 * cards come first). Throws if `order` is too short (never with fairDealOrder: it refills).
 */
export function dealCoup(order: readonly CardCode[], opts: { burn: boolean }): DealtCoup {
  let i = 0;
  const take = (): CardCode => {
    if (i >= order.length) throw new Error('baccarat: deal order exhausted');
    return order[i++];
  };
  let burn: DealtCoup['burn'] = null;
  if (opts.burn) {
    const card = take();
    const count = burnCount(card);
    const cards: CardCode[] = [];
    for (let k = 0; k < count; k++) cards.push(take());
    burn = { card, count, cards };
  }
  const player: CardCode[] = [];
  const banker: CardCode[] = [];
  player.push(take());
  banker.push(take());
  player.push(take());
  banker.push(take());
  const p2 = handTotal(player);
  const b2 = handTotal(banker);
  const natural = p2 >= 8 || b2 >= 8;
  if (!natural) {
    let third: number | null = null;
    if (playerDraws(p2)) {
      const c = take();
      player.push(c);
      third = baccaratValue(c);
    }
    if (bankerDraws(b2, third)) banker.push(take());
  }
  const playerTotal = handTotal(player);
  const bankerTotal = handTotal(banker);
  const winner: BaccaratWinner = playerTotal > bankerTotal ? 'player' : bankerTotal > playerTotal ? 'banker' : 'tie';
  return {
    player, banker, playerTotal, bankerTotal, winner, natural,
    playerPair: isPair(player), bankerPair: isPair(banker), burn, dealt: order.slice(0, i),
  };
}

/** Commission on a winning Banker bet of `cents` (5 %; exact for whole-dollar bets). */
export function bankerCommission(cents: number): number {
  return (cents * 5) / 100;
}

/**
 * What one spot returns (stake included; 0 = lost). `freeCommission`: a winning Banker bet pays 1:1.
 * Bets are whole dollars (kernel), so every amount is an integer number of cents.
 */
export function spotReturn(spot: string, cents: number, o: CoupOutcome, freeCommission = false): number {
  switch (spot) {
    case 'player':
      return o.winner === 'player' ? 2 * cents : o.winner === 'tie' ? cents : 0;
    case 'banker':
      return o.winner === 'banker' ? 2 * cents - (freeCommission ? 0 : bankerCommission(cents)) : o.winner === 'tie' ? cents : 0;
    case 'tie':
      return o.winner === 'tie' ? 9 * cents : 0;
    case 'playerPair':
      return o.playerPair ? 12 * cents : 0;
    case 'bankerPair':
      return o.bankerPair ? 12 * cents : 0;
    default:
      return 0;
  }
}

export interface BoardSettlement {
  stakedCents: number;
  returnCents: number;
  netCents: number;
  counters: Record<string, number>;
  /** A winning tie or pair bet. */
  jackpot: boolean;
}

/** Settles a whole board against a coup (see the counters in shared/games/baccarat.ts). */
export function settleBoard(bets: BetMap, coup: CoupOutcome & { natural: boolean }, freeCommission = false): BoardSettlement {
  let staked = 0;
  let ret = 0;
  const counters: Record<string, number> = {};
  const add = (k: string, v: number) => {
    if (v > 0) counters[k] = (counters[k] ?? 0) + v;
  };
  for (const [spot, v] of Object.entries(bets)) {
    if (!(v > 0)) continue;
    staked += v;
    const r = spotReturn(spot, v, coup, freeCommission);
    ret += r;
    if (spot === 'banker' && coup.winner === 'banker') {
      add('bankerWins', 1);
      if (freeCommission) add('commissionSaved', bankerCommission(v));
    }
    if (spot === 'player' && coup.winner === 'player') add('playerWins', 1);
    if (spot === 'tie' && r > 0) add('tieWins', 1);
    if ((spot === 'playerPair' || spot === 'bankerPair') && r > 0) add('pairWins', 1);
  }
  if (staked > 0 && coup.natural) add('naturals', 1);
  const jackpot = (counters.tieWins ?? 0) > 0 || (counters.pairWins ?? 0) > 0;
  return { stakedCents: staked, returnCents: ret, netCents: ret - staked, counters, jackpot };
}

/** Duration of the 'dealing' step (client animation of the coup). */
export function dealingMs(coup: Pick<DealtCoup, 'player' | 'banker' | 'burn'>): number {
  const t = BACCARAT_TIMING;
  const thirds = (coup.player.length > 2 ? 1 : 0) + (coup.banker.length > 2 ? 1 : 0);
  return (coup.burn ? t.burnMs : 0) + 4 * t.cardMs + thirds * t.thirdCardMs + t.revealMs;
}

/** The cut card came out: at most BACCARAT_CUT_CARDS cards are left. */
export const cutCardOut = (remaining: number): boolean => remaining <= BACCARAT_CUT_CARDS;

// ============================================================================================
// Long market "Banker wins ≥ 46 % of the shoe"
// ============================================================================================

/** Most coups that can still be dealt from a shoe with `remaining` cards (each coup takes ≥ 4 cards). */
export function maxCoupsLeft(remaining: number): number {
  if (cutCardOut(remaining)) return 0;
  return Math.floor((remaining - BACCARAT_CUT_CARDS - 1) / 4) + 1;
}

/** 'yes' / 'no' once certain, else null (`bankerWins` of `coups` so far, `remaining` cards left). */
export function shoeOutcome(bankerWins: number, coups: number, remaining: number): 'yes' | 'no' | null {
  const k = maxCoupsLeft(remaining);
  const th = BACCARAT_SHOE_THRESHOLD_PCT;
  // Lowest final share: no more Banker win over the most coups; highest: Banker wins all of them.
  if (100 * bankerWins >= th * (coups + k) && coups + k > 0) return 'yes';
  if (100 * (bankerWins + k) < th * (coups + k)) return 'no';
  return null;
}

/** Average number of cards per coup (8 decks): ≈ 4.94. */
export const AVG_CARDS_PER_COUP = 4.94;

/** Standard normal CDF (Abramowitz–Stegun 7.1.26, |error| < 1.5e-7). */
export function normalCdf(z: number): number {
  const x = Math.abs(z) / Math.SQRT2;
  const t = 1 / (1 + 0.3275911 * x);
  const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x);
  return z >= 0 ? (1 + y) / 2 : (1 - y) / 2;
}

/** Fair probability that the shoe ends with Banker ≥ 46 % (normal approximation of the coups left). */
export function shoeYesProbability(bankerWins: number, coups: number, remaining: number, pBanker = BANKER_WIN_P): number {
  const certain = shoeOutcome(bankerWins, coups, remaining);
  if (certain) return certain === 'yes' ? 1 : 0;
  const m = Math.max(1, (remaining - BACCARAT_CUT_CARDS) / AVG_CARDS_PER_COUP);
  const need = (BACCARAT_SHOE_THRESHOLD_PCT / 100) * (coups + m) - bankerWins;
  const mean = m * pBanker;
  const sd = Math.sqrt(m * pBanker * (1 - pBanker));
  return 1 - normalCdf((Math.ceil(need) - 0.5 - mean) / sd);
}

// ============================================================================================
// Exact probabilities (combinatorial, without replacement) — fair estimates and tests
// ============================================================================================

/** Cards per baccarat value 0..9 in `decks` decks (value 0: ten, J, Q, K). */
export function valueCounts(decks: number): number[] {
  return [16 * decks, 4 * decks, 4 * decks, 4 * decks, 4 * decks, 4 * decks, 4 * decks, 4 * decks, 4 * decks, 4 * decks];
}

export interface CoupOdds { banker: number; player: number; tie: number }

/**
 * Exact P(Banker), P(Player), P(Tie) of the next coup dealt from a shoe with `counts[v]` cards of
 * each value v (no replacement), by enumeration of the up to 6 cards.
 */
export function coupOdds(counts: readonly number[]): CoupOdds {
  const c = [...counts];
  let n = c.reduce((a, b) => a + b, 0);
  const out = { banker: 0, player: 0, tie: 0 };
  const draw = (v: number) => {
    const p = c[v] / n;
    c[v]--;
    n--;
    return p;
  };
  const back = (v: number) => {
    c[v]++;
    n++;
  };
  const score = (pt: number, bt: number, w: number) => {
    if (pt > bt) out.player += w;
    else if (bt > pt) out.banker += w;
    else out.tie += w;
  };
  for (let p1 = 0; p1 < 10; p1++) {
    if (!c[p1]) continue;
    const w1 = draw(p1);
    for (let b1 = 0; b1 < 10; b1++) {
      if (!c[b1]) continue;
      const w2 = w1 * draw(b1);
      for (let p2 = 0; p2 < 10; p2++) {
        if (!c[p2]) continue;
        const w3 = w2 * draw(p2);
        for (let b2 = 0; b2 < 10; b2++) {
          if (!c[b2]) continue;
          const w4 = w3 * draw(b2);
          const pt = (p1 + p2) % 10;
          const bt = (b1 + b2) % 10;
          if (pt >= 8 || bt >= 8) {
            score(pt, bt, w4);
          } else if (playerDraws(pt)) {
            for (let p3 = 0; p3 < 10; p3++) {
              if (!c[p3]) continue;
              const w5 = w4 * draw(p3);
              const pf = (pt + p3) % 10;
              if (bankerDraws(bt, p3)) {
                for (let b3 = 0; b3 < 10; b3++) {
                  if (!c[b3]) continue;
                  const w6 = w5 * (c[b3] / n);
                  score(pf, (bt + b3) % 10, w6);
                }
              } else {
                score(pf, bt, w5);
              }
              back(p3);
            }
          } else if (bankerDraws(bt, null)) {
            for (let b3 = 0; b3 < 10; b3++) {
              if (!c[b3]) continue;
              score(pt, (bt + b3) % 10, w4 * (c[b3] / n));
            }
          } else {
            score(pt, bt, w4);
          }
          back(b2);
        }
        back(p2);
      }
      back(b1);
    }
    back(p1);
  }
  return out;
}

/** Cards per rank (A..K, 13 entries) of `decks` decks. */
export const rankCounts = (decks: number): number[] => Array.from({ length: RANKS.length }, () => 4 * decks);

/** Exact P(Player pair or Banker pair) of the next coup (first two cards of each side). */
export function pairOdds(ranks: readonly number[]): number {
  const n = ranks.reduce((a, b) => a + b, 0);
  if (n < 4) return 0;
  let one = 0;
  for (const r of ranks) one += r * (r - 1);
  one /= n * (n - 1);
  let both = 0;
  for (let i = 0; i < ranks.length; i++) {
    for (let j = 0; j < ranks.length; j++) {
      const a = ranks[i];
      const b = ranks[j];
      both += i === j ? a * (a - 1) * (a - 2) * (a - 3) : a * (a - 1) * b * (b - 1);
    }
  }
  both /= n * (n - 1) * (n - 2) * (n - 3);
  return 2 * one - both;
}

/**
 * Fresh 8-deck shoe: `coupOdds(valueCounts(8))` and `pairOdds(rankCounts(8))` (checked by the
 * tests). House edges: Banker 1.0579 %, Player 1.2351 %, Tie 14.36 %, each pair 10.36 %.
 */
export const BANKER_WIN_P = 0.4585974226322891;
export const PLAYER_WIN_P = 0.44624660934317073;
export const TIE_P = 0.09515596802363396;
export const PAIR_P = 0.14381687186687586;

/** Uniform pick (bots). */
export function pick<T>(rng: Rng, list: readonly T[]): T {
  return list[rng.nextInt(list.length)];
}
