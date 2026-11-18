import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import {
  actInPlace, actionCost, buildShoe, EngineError, fastRng, legalActions, shuffleInPlace, startRound, summarize,
  timeoutInPlace, totalStaked, type RoundState,
} from '../../src/engine';
import type { PlayerAction, PowerId } from '../../src/shared/types';
import { RULES } from './helpers';

const RUNS = 400;

describe('shoe properties', () => {
  it('a shuffled 312-card shoe is a permutation (no duplicates beyond 6 decks)', () => {
    fc.assert(fc.property(fc.integer(), (seed) => {
      const shoe = shuffleInPlace(buildShoe(6), fastRng(seed));
      expect(shoe).toHaveLength(312);
      const counts = new Map<string, number>();
      for (const c of shoe) counts.set(c, (counts.get(c) ?? 0) + 1);
      expect(counts.size).toBe(52);
      expect([...counts.values()].every((n) => n === 6)).toBe(true);
      expect([...shoe].sort()).toEqual(buildShoe(6).sort());
    }), { numRuns: 100 });
  });
});

const POWERS: (PowerId | null)[] = [null, null, null, 'freeSplit', 'freeDouble', 'freeInsurance', 'peek', 'secondChance'];

/**
 * Random game driver: random seats/bets/deck, random legal decisions (powers included), with a
 * wallet per player that must pay every extra stake. Checks invariants at each step.
 */
function playRandomRound(seed: number) {
  const rng = fastRng(seed);
  const nSeats = 1 + rng.nextInt(5);
  const seatIdx = shuffleInPlace([0, 1, 2, 3, 4], rng).slice(0, nSeats).sort();
  const balances = new Map<number, number>();
  const betsArr = seatIdx.map((i) => {
    const bet = (1 + rng.nextInt(50)) * 100;
    balances.set(i, bet * rng.nextInt(4) + rng.nextInt(3) * 50); // may be too poor for doubles/splits
    return { seatIndex: i, playerId: `p${i}`, betCents: bet };
  });
  const initial = [...balances.values()].reduce((a, b) => a + b, 0) + betsArr.reduce((a, b) => a + b.betCents, 0);
  const deck = shuffleInPlace(buildShoe(6), rng);
  const s: RoundState = startRound(RULES, betsArr, deck);
  let attempts = 0;
  const progress = () => s.events.length;
  while (s.phase !== 'settled') {
    attempts++;
    expect(attempts).toBeLessThan(5000); // termination
    expect(progress()).toBeLessThan(400);
    // invariant: there is always someone with a legal action
    const actors = s.seats.filter((x) => legalActions(s, x.seatIndex).length > 0);
    expect(actors.length).toBeGreaterThan(0);
    if (s.phase === 'playerTurns') expect(actors.map((a) => a.seatIndex)).toEqual([s.turn!.seatIndex]);
    if (rng.nextInt(20) === 0) { timeoutInPlace(s); continue; }
    const seat = actors[rng.nextInt(actors.length)];
    const legal = legalActions(s, seat.seatIndex);
    const action = legal[rng.nextInt(legal.length)] as PlayerAction;
    const power = POWERS[rng.nextInt(POWERS.length)];
    const amountCents = action === 'insurance' ? rng.nextInt(Math.floor(seat.hands[0].betCents / 2) + 1) : undefined;
    let cost: number;
    try {
      cost = actionCost(s, seat.seatIndex, action, { power, amountCents });
    } catch (e) {
      expect(e).toBeInstanceOf(EngineError);
      continue; // illegal combination (e.g. power mismatch) — engine refused, state unchanged
    }
    const bal = balances.get(seat.seatIndex)!;
    if (cost > bal) continue; // cannot afford: the server would refuse (INSUFFICIENT_FUNDS)
    const before = totalStaked(s, seat.seatIndex);
    actInPlace(s, seat.seatIndex, action, { power, amountCents });
    expect(totalStaked(s, seat.seatIndex) - before).toBe(cost);
    balances.set(seat.seatIndex, bal - cost);
    expect(balances.get(seat.seatIndex)!).toBeGreaterThanOrEqual(0);
  }
  const sum = summarize(s);
  let houseNet = 0;
  for (const r of sum) {
    balances.set(r.seatIndex, balances.get(r.seatIndex)! + r.returnCents);
    houseNet += r.stakedCents - r.returnCents;
    expect(Number.isSafeInteger(r.returnCents)).toBe(true);
    expect(r.returnCents).toBeGreaterThanOrEqual(0);
  }
  const final = [...balances.values()].reduce((a, b) => a + b, 0);
  // conservation: players' money + house result = what players had (wallet + initial bets)
  expect(final + houseNet).toBe(initial);
  for (const b of balances.values()) expect(b).toBeGreaterThanOrEqual(0);
  // every hand settled with an integer return and a result
  for (const seat of s.seats) for (const h of seat.hands) {
    expect(h.result).not.toBeNull();
    expect(Number.isInteger(h.returnCents)).toBe(true);
    expect(h.cards.length).toBeGreaterThanOrEqual(2);
  }
  // no card dealt twice from the 312-card deck beyond its multiplicity
  const dealt = s.deck.slice(0, s.deckPos);
  const counts = new Map<string, number>();
  for (const c of dealt) counts.set(c, (counts.get(c) ?? 0) + 1);
  expect([...counts.values()].every((n) => n <= 6)).toBe(true);
  return s;
}

describe('round properties (random play)', () => {
  it('money is conserved, no negative balance, no stuck state, always terminates', () => {
    fc.assert(fc.property(fc.integer(), (seed) => { playRandomRound(seed); }), { numRuns: RUNS });
  });

  it('returns are bounded: 0 ≤ return ≤ staked + 1.5·bet (+2× insurance)', () => {
    fc.assert(fc.property(fc.integer(), (seed) => {
      const s = playRandomRound(seed);
      for (const seat of s.seats) {
        for (const h of seat.hands) expect(h.returnCents!).toBeLessThanOrEqual(h.stakedCents + 1.5 * h.betCents);
        expect(seat.insurance.returnCents!).toBeLessThanOrEqual(seat.insurance.stakedCents + 2 * seat.insurance.betCents);
      }
    }), { numRuns: RUNS });
  });
});
