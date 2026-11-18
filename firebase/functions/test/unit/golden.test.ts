/**
 * Golden transcripts: a fixed seed fully determines the deal order (provably-fair DRBG) and the
 * bots' noisy decisions, so the complete JSON transcript of each scenario is versioned in
 * test/golden/*.json. Any behavioural change of the engine shows up as a diff.
 * Regenerate deliberately with `npm run golden:update` and review the diff.
 */
import { describe, expect, it } from 'vitest';
import {
  actInPlace, buildShoe, commitForSeed, fairDealOrder, fastRng, noisyStrategy, sha256Hex, situationFor,
  startRound, summarize, verifyFairness,
} from '../../src/engine';
import { RULES } from './helpers';

interface Scenario { name: string; seats: number; bet: number; noise: number; insuranceEvery?: boolean }

const SCENARIOS: Scenario[] = [
  { name: 'solo-basic', seats: 1, bet: 1000, noise: 0 },
  { name: 'full-table-noisy', seats: 5, bet: 2500, noise: 0.15 },
  { name: 'three-seats-insurance', seats: 3, bet: 500, noise: 0.05, insuranceEvery: true },
];

function transcript(sc: Scenario, hands: number) {
  const out: unknown[] = [];
  let remaining = buildShoe(6);
  const rng = fastRng(7);
  for (let n = 1; n <= hands; n++) {
    const seed = sha256Hex(`${sc.name}:${n}`);
    if (remaining.length < 78) remaining = buildShoe(6);
    const deck = fairDealOrder(remaining, seed);
    const s = startRound(RULES, Array.from({ length: sc.seats }, (_, i) => ({ seatIndex: i, playerId: `bot${i}`, betCents: sc.bet })), deck);
    while (s.phase === 'insurance') {
      const seat = s.seats.find((x) => !x.insurance.decided)!;
      actInPlace(s, seat.seatIndex, 'insurance', { amountCents: sc.insuranceEvery ? Math.floor(seat.hands[0].betCents / 2) : 0 });
    }
    while (s.phase === 'playerTurns') actInPlace(s, s.turn!.seatIndex, noisyStrategy(situationFor(s)!, rng, sc.noise));
    const dealt = s.deck.slice(0, s.deckPos);
    expect(verifyFairness({ commit: commitForSeed(seed), seed, remainingBefore: remaining, dealt })).toBe(true);
    remaining = deck.slice(s.deckPos, remaining.length);
    out.push({
      hand: n,
      commit: commitForSeed(seed),
      dealer: s.dealer.cards,
      seats: s.seats.map((x) => ({ seat: x.seatIndex, hands: x.hands.map((h) => ({ cards: h.cards, result: h.result, ret: h.returnCents })), ins: x.insurance.betCents })),
      net: summarize(s).map((r) => r.netCents),
      events: s.events.map((e) => [e.type, e.seatIndex, e.handIndex, e.card, e.amountCents, e.result].filter((v) => v !== null)),
    });
  }
  return out;
}

describe('golden transcripts (fixed seeds)', () => {
  for (const sc of SCENARIOS) {
    it(sc.name, async () => {
      const t = transcript(sc, sc.seats === 1 ? 25 : 12);
      await expect(JSON.stringify(t, null, 1) + '\n').toMatchFileSnapshot(`../golden/${sc.name}.json`);
    });
  }
});
