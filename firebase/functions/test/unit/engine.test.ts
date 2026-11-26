import { describe, expect, it } from 'vitest';
import {
  act, buildShoe, canonicalSort, commitForSeed, EngineError, fairDealOrder, forfeitTurnsInPlace, handValue,
  legalActions, seededRng, startRound, summarize, timeout, totalStaked, verifyFairness, actionCost,
  type RoundState,
} from '../../src/engine';
import { RULES, bets, deckN, start1 } from './helpers';

function code(fn: () => unknown): string {
  try {
    fn();
  } catch (e) {
    if (e instanceof EngineError) return e.code;
    throw e;
  }
  return 'NO_ERROR';
}

const seat0 = (s: RoundState) => s.seats[0];
const net0 = (s: RoundState) => summarize(s)[0].netCents;

describe('hand values', () => {
  it.each([
    [['AS', '6H'], 17, true],
    [['AS', '6H', 'KD'], 17, false],
    [['AS', 'AH'], 12, true],
    [['AS', 'AH', '9C'], 21, true],
    [['AS', 'KH'], 21, true],
    [['5S', 'KH', 'QD'], 25, false],
    [['AS', 'AH', 'AD', 'AC', '7S'], 21, true],
    [['AS', 'AH', 'AD', 'AC', '7S', 'KD'], 21, false],
    [['TS', '9H', '2D'], 21, false],
    [['2S', '3H'], 5, false],
  ] as const)('%j = %i (soft=%s)', (cards, total, soft) => {
    expect(handValue([...cards])).toEqual({ total, soft });
  });

  it('shoe has 312 cards, 6 of each code', () => {
    const shoe = buildShoe(6);
    expect(shoe).toHaveLength(312);
    const counts = new Map<string, number>();
    for (const c of shoe) counts.set(c, (counts.get(c) ?? 0) + 1);
    expect(counts.size).toBe(52);
    for (const n of counts.values()) expect(n).toBe(6);
  });
});

describe('naturals and dealer peek', () => {
  it('natural pays 3:2', () => {
    const s = start1('AS', 'KD', '9H', '7C');
    expect(s.phase).toBe('settled');
    expect(seat0(s).hands[0].result).toBe('blackjack');
    expect(seat0(s).hands[0].returnCents).toBe(2500);
    expect(net0(s)).toBe(1500);
  });

  it('natural vs dealer natural (ten up) is a push', () => {
    const s = start1('AS', 'KD', 'TH', 'AC');
    expect(s.phase).toBe('settled');
    expect(seat0(s).hands[0].result).toBe('push');
    expect(net0(s)).toBe(0);
  });

  it('dealer natural with ten up: peek ends the hand before any action', () => {
    const s = start1('TS', '9D', 'KH', 'AC');
    expect(s.phase).toBe('settled');
    expect(s.dealer.peeked).toBe(true);
    expect(s.dealer.blackjack).toBe(true);
    expect(s.events.find((e) => e.type === 'peek')?.dealerBlackjack).toBe(true);
    expect(seat0(s).hands[0].result).toBe('lose');
    expect(net0(s)).toBe(-1000);
  });

  it('peek without blackjack continues to player turns', () => {
    const s = start1('TS', '9D', 'KH', '7C');
    expect(s.phase).toBe('playerTurns');
    expect(s.dealer.peeked).toBe(true);
    expect(s.events.find((e) => e.type === 'peek')?.dealerBlackjack).toBe(false);
  });

  it('no peek with a low up card', () => {
    const s = start1('TS', '9D', '5H', '7C');
    expect(s.dealer.peeked).toBe(false);
  });

  it('blackjack beats a 3-card 21 of the dealer', () => {
    // seat0 natural, seat1 hits to 21 so the dealer must play: up 5, hole 6, draws T = 21.
    const s0 = startRound(RULES, bets(1000, 1000), deckN(['AS', '9C'], '5H', ['KD', '2C'], '6D', ['TC', 'TH']));
    expect(s0.turn).toEqual({ seatIndex: 1, handIndex: 0 });
    const s1 = act(s0, 1, 'hit'); // 9+2+T = 21 → auto done → dealer plays: 5+6+T = 21
    expect(s1.phase).toBe('settled');
    expect(handValue(s1.dealer.cards).total).toBe(21);
    expect(s1.seats[0].hands[0].result).toBe('blackjack');
    expect(s1.seats[1].hands[0].result).toBe('push');
  });

  it('the hole card stays hidden in events until reveal', () => {
    const s = start1('TS', '9D', '5H', '7C', ['9C']);
    expect(s.events.find((e) => e.type === 'dealerHole')?.card).toBeNull();
    const s2 = act(s, 0, 'stand');
    expect(s2.events.find((e) => e.type === 'reveal')?.card).toBe('7C');
  });
});

describe('dealer drawing (S17)', () => {
  it('stands on soft 17', () => {
    const s = act(start1('TS', '8D', '6H', 'AC', ['5C']), 0, 'stand');
    expect(s.dealer.cards).toEqual(['6H', 'AC']);
    expect(seat0(s).hands[0].result).toBe('win');
  });
  it('stands on hard 17', () => {
    const s = act(start1('TS', '7D', 'TH', '7C', ['5C']), 0, 'stand');
    expect(s.dealer.cards).toHaveLength(2);
    expect(seat0(s).hands[0].result).toBe('push');
  });
  it('hits 16 and busts', () => {
    const s = act(start1('TS', '2D', 'TH', '6C', ['KC']), 0, 'stand');
    expect(s.dealer.busted).toBe(true);
    expect(seat0(s).hands[0].result).toBe('win');
    expect(net0(s)).toBe(1000);
  });
  it('hits soft 16 → A,5,+2 = soft 18', () => {
    const s = act(start1('TS', '9D', 'AH', '5C', ['2C']), 0, 'insurance', { amountCents: 0 });
    const s2 = act(s, 0, 'stand');
    expect(handValue(s2.dealer.cards)).toEqual({ total: 18, soft: true });
    expect(seat0(s2).hands[0].result).toBe('win');
  });
  it('does not draw when every player hand is busted', () => {
    const s = act(start1('TS', '6D', 'TH', '6C', ['KC', '5S']), 0, 'hit');
    expect(seat0(s).hands[0].result).toBe('bust');
    expect(s.dealer.cards).toEqual(['TH', '6C']);
    expect(s.dealer.holeRevealed).toBe(true);
  });
  it('player bust loses even if the dealer would bust', () => {
    const s = startRound(RULES, bets(1000, 1000), deckN(['TS', 'TC'], '6H', ['6D', '7C'], 'TD', ['KC', 'KD']));
    const s1 = act(s, 0, 'hit'); // 16 + K bust
    const s2 = act(s1, 1, 'stand'); // dealer 16 + K bust
    expect(s2.dealer.busted).toBe(true);
    expect(s2.seats[0].hands[0].result).toBe('bust');
    expect(s2.seats[1].hands[0].result).toBe('win');
  });
});

describe('insurance', () => {
  it('is offered on an Ace and pays 2:1 when the dealer has blackjack', () => {
    const s = start1('TS', '9D', 'AH', 'KC');
    expect(s.phase).toBe('insurance');
    expect(legalActions(s, 0)).toEqual(['insurance']);
    const s2 = act(s, 0, 'insurance', { amountCents: 500 });
    expect(s2.phase).toBe('settled');
    expect(seat0(s2).insurance.result).toBe('win');
    expect(seat0(s2).insurance.returnCents).toBe(1500);
    expect(net0(s2)).toBe(0); // insurance covers the main bet exactly
  });
  it('is lost when the dealer has no blackjack, play continues', () => {
    const s = act(start1('TS', '9D', 'AH', '7C'), 0, 'insurance', { amountCents: 500 });
    expect(s.phase).toBe('playerTurns');
    expect(seat0(s).insurance.result).toBe('lose');
    const s2 = act(s, 0, 'stand'); // 19 vs soft 18
    expect(seat0(s2).hands[0].result).toBe('win');
    expect(net0(s2)).toBe(1000 - 500);
  });
  it('max is half the bet; negative/decimal rejected', () => {
    const s = start1('TS', '9D', 'AH', '7C');
    expect(code(() => act(s, 0, 'insurance', { amountCents: 501 }))).toBe('BAD_AMOUNT');
    expect(code(() => act(s, 0, 'insurance', { amountCents: -1 }))).toBe('BAD_AMOUNT');
    expect(code(() => act(s, 0, 'insurance', { amountCents: 1.5 }))).toBe('BAD_AMOUNT');
    expect(code(() => act(s, 0, 'hit'))).toBe('BAD_PHASE');
  });
  it('waits for every seat; timeout declines the undecided', () => {
    const s = startRound(RULES, bets(1000, 1000), deckN(['TS', 'TC'], 'AH', ['9D', '8C'], '7D'));
    const s1 = act(s, 0, 'insurance', { amountCents: 500 });
    expect(s1.phase).toBe('insurance');
    expect(code(() => act(s1, 0, 'insurance', { amountCents: 0 }))).toBe('ILLEGAL_ACTION');
    const s2 = timeout(s1);
    expect(s2.phase).toBe('playerTurns');
    expect(s2.seats[1].insurance.betCents).toBe(0);
    expect(s2.seats[0].insurance.result).toBe('lose');
  });
  it('even money: natural + insurance vs dealer blackjack', () => {
    const s = act(start1('AS', 'KD', 'AH', 'KC'), 0, 'insurance', { amountCents: 500 });
    expect(seat0(s).hands[0].result).toBe('push');
    expect(net0(s)).toBe(1000); // insurance won 2:1, main pushed
  });
});

describe('double', () => {
  it('doubles the bet, draws exactly one card and ends the hand', () => {
    const s = start1('5S', '6D', '9H', '7C', ['9C', '2S']);
    expect(actionCost(s, 0, 'double')).toBe(1000);
    const s2 = act(s, 0, 'double');
    expect(seat0(s2).hands[0].cards).toEqual(['5S', '6D', '9C']);
    expect(seat0(s2).hands[0].betCents).toBe(2000);
    expect(seat0(s2).hands[0].doubled).toBe(true);
    expect(s2.phase).toBe('settled'); // dealer 16 draws 2 = 18; player 20 wins
    expect(net0(s2)).toBe(2000);
  });
  it('is not allowed on three cards', () => {
    const s = act(start1('2S', '3D', '9H', '7C', ['4C', '5S']), 0, 'hit');
    expect(code(() => act(s, 0, 'double'))).toBe('ILLEGAL_ACTION');
    expect(legalActions(s, 0)).not.toContain('double');
  });
  it('a doubled hand that loses costs twice the bet', () => {
    const s = act(start1('5S', '6D', 'TH', '9C', ['2S']), 0, 'double'); // 13 vs 19
    expect(net0(s)).toBe(-2000);
  });
});

describe('split', () => {
  it('splits a pair into two hands, each receives a card, both play', () => {
    const s = start1('8S', '8D', '6H', 'TC', ['3C', 'TS', 'TD', '9S']);
    expect(legalActions(s, 0)).toContain('split');
    const s1 = act(s, 0, 'split');
    expect(seat0(s1).hands.map((h) => h.cards)).toEqual([['8S', '3C'], ['8D', 'TS']]);
    expect(totalStaked(s1, 0)).toBe(2000);
    expect(s1.turn).toEqual({ seatIndex: 0, handIndex: 0 });
    const s2 = act(s1, 0, 'double'); // double after split: 8+3+T = 21
    expect(seat0(s2).hands[0].doubled).toBe(true);
    expect(s2.turn).toEqual({ seatIndex: 0, handIndex: 1 });
    const s3 = act(s2, 0, 'stand'); // 18; dealer 16 draws 9 → bust
    expect(s3.phase).toBe('settled');
    expect(seat0(s3).hands.map((h) => h.result)).toEqual(['win', 'win']);
    expect(net0(s3)).toBe(3000);
  });
  it('ten-value cards of different ranks can be split (same value)', () => {
    const s = start1('TS', 'KD', '6H', 'TC', ['2C', '3C']);
    expect(legalActions(s, 0)).toContain('split');
  });
  it('different values cannot be split', () => {
    const s = start1('9S', 'KD', '6H', 'TC');
    expect(code(() => act(s, 0, 'split'))).toBe('ILLEGAL_ACTION');
  });
  it('re-split up to 4 hands, never 5', () => {
    // Each split deals [first hand, new hand]; first hands keep receiving 8s.
    let s = start1('8S', '8D', '6H', 'TC', ['8C', 'TS', '8H', 'TD', '8S', 'TH']);
    s = act(s, 0, 'split');
    s = act(s, 0, 'split');
    s = act(s, 0, 'split');
    expect(seat0(s).hands).toHaveLength(4);
    expect(s.turn).toEqual({ seatIndex: 0, handIndex: 0 });
    expect(seat0(s).hands[0].cards).toEqual(['8S', '8S']); // still a pair...
    expect(legalActions(s, 0)).not.toContain('split');
    expect(code(() => act(s, 0, 'split'))).toBe('ILLEGAL_ACTION'); // ...but a 5th hand is refused
  });
  it('split aces: one card each, hands done, A+T is 21 not blackjack, no re-split', () => {
    const s = start1('AS', 'AD', '6H', 'TC', ['KC', 'AH', '9S']);
    const s1 = act(s, 0, 'split');
    const hands = seat0(s1).hands;
    expect(hands.map((h) => h.cards)).toEqual([['AS', 'KC'], ['AD', 'AH']]);
    expect(hands.every((h) => h.splitAces && h.done)).toBe(true);
    expect(s1.phase).toBe('settled'); // no more decisions → dealer 16 draws 9 = bust
    expect(seat0(s1).hands[0].blackjack).toBe(false);
    expect(seat0(s1).hands[0].result).toBe('win'); // paid 1:1, not 3:2
    expect(seat0(s1).hands[0].returnCents).toBe(2000);
  });
  it('split aces vs dealer 21 (3 cards): 21 after split pushes', () => {
    const s = act(start1('AS', 'AD', '6H', '5C', ['KC', 'QC', 'TS']), 0, 'split');
    expect(handValue(s.dealer.cards).total).toBe(21);
    expect(seat0(s).hands.map((h) => h.result)).toEqual(['push', 'push']);
  });
});

describe('surrender', () => {
  it('returns half the bet on the first two cards', () => {
    const s = act(start1('TS', '6D', 'TH', '7C'), 0, 'surrender');
    expect(seat0(s).hands[0].result).toBe('surrender');
    expect(seat0(s).hands[0].returnCents).toBe(500);
    expect(net0(s)).toBe(-500);
  });
  it('not after a hit', () => {
    const s = act(start1('2S', '3D', 'TH', '7C', ['4C']), 0, 'hit');
    expect(code(() => act(s, 0, 'surrender'))).toBe('ILLEGAL_ACTION');
  });
  it('not after a split', () => {
    const s = act(start1('8S', '8D', 'TH', '7C', ['3C', '4C']), 0, 'split');
    expect(legalActions(s, 0)).not.toContain('surrender');
    expect(code(() => act(s, 0, 'surrender'))).toBe('ILLEGAL_ACTION');
  });
});

describe('turns and validation', () => {
  it('acting out of turn / unknown seat / settled', () => {
    const s = startRound(RULES, bets(1000, 1000), deckN(['TS', 'TC'], '6H', ['6D', '7C'], 'TD', ['KC', 'KD']));
    expect(code(() => act(s, 1, 'hit'))).toBe('NOT_YOUR_TURN');
    expect(code(() => act(s, 3, 'hit'))).toBe('NOT_SEATED');
    const done = act(act(s, 0, 'stand'), 1, 'stand');
    expect(code(() => act(done, 0, 'hit'))).toBe('BAD_PHASE');
  });
  it('rejects bets outside limits, decimals and non-dollar amounts', () => {
    const d = buildShoe(1);
    for (const b of [0, -100, 50, 150, 1.5, 200_000, Number.NaN, 1e20]) {
      expect(code(() => startRound(RULES, bets(b), d))).toBe('BET_OUT_OF_RANGE');
    }
    expect(code(() => startRound(RULES, [], d))).toBe('ILLEGAL_ACTION');
    expect(code(() => startRound(RULES, [{ seatIndex: 0, playerId: 'a', betCents: 100 }, { seatIndex: 0, playerId: 'b', betCents: 100 }], d))).toBe('NOT_SEATED');
  });
  it('reaching 21 ends the hand automatically', () => {
    const s = act(start1('5S', '6D', '9H', '7C', ['TC', '2S']), 0, 'hit');
    expect(seat0(s).hands[0].done).toBe(true);
    expect(s.phase).toBe('settled');
  });
  it('timeout stands the current hand', () => {
    const s = timeout(start1('TS', '9D', '9H', '7C', ['2C']));
    expect(s.events.some((e) => e.type === 'timeout')).toBe(true);
    expect(seat0(s).hands[0].result).toBe('win');
  });
  it('forfeit (player left) stands every remaining hand', () => {
    const s = start1('8S', '8D', '6H', 'TC', ['3C', 'TS', '9S']);
    const s1 = act(s, 0, 'split');
    const c = structuredClone(s1);
    forfeitTurnsInPlace(c, 0);
    expect(c.phase).toBe('settled');
  });
  it('dealer DECK_EXHAUSTED is reported, never a silent wrong deal', () => {
    expect(code(() => startRound(RULES, bets(100), ['AS', 'KD', '9C']))).toBe('DECK_EXHAUSTED');
  });
  it('input state is never mutated', () => {
    const s = start1('TS', '6D', 'TH', '7C', ['KC']);
    const snap = JSON.stringify(s);
    act(s, 0, 'hit');
    expect(JSON.stringify(s)).toBe(snap);
  });
});

describe('powers', () => {
  it('freeSplit: the second hand is house-staked', () => {
    const s = start1('8S', '8D', '6H', 'TC', ['3C', 'TS', '9S']);
    expect(actionCost(s, 0, 'split', { power: 'freeSplit' })).toBe(0);
    const s1 = act(s, 0, 'split', { power: 'freeSplit' });
    expect(seat0(s1).hands[1].stakedCents).toBe(0);
    expect(seat0(s1).powerUsed).toBe('freeSplit');
    const s2 = act(act(s1, 0, 'stand'), 0, 'stand'); // 11 and 18 vs 16+9 bust → both win
    expect(seat0(s2).hands[1].returnCents).toBe(1000); // 0 staked + 1000 profit
    expect(net0(s2)).toBe(2000);
  });
  it('freeSplit losing hand costs nothing extra', () => {
    const s1 = act(start1('8S', '8D', 'TH', '9C', ['3C', 'TS']), 0, 'split', { power: 'freeSplit' });
    const s2 = act(act(s1, 0, 'stand'), 0, 'stand'); // 11 and 18 vs 19 → both lose
    expect(net0(s2)).toBe(-1000);
  });
  it('freeDouble: only the original stake is at risk', () => {
    const s = act(start1('5S', '6D', 'TH', '9C', ['2S']), 0, 'double', { power: 'freeDouble' });
    expect(seat0(s).hands[0].betCents).toBe(2000);
    expect(seat0(s).hands[0].stakedCents).toBe(1000);
    expect(net0(s)).toBe(-1000);
    const w = act(start1('5S', '6D', 'TH', '7C', ['TS']), 0, 'double', { power: 'freeDouble' });
    expect(net0(w)).toBe(2000);
  });
  it('freeInsurance: costs nothing, pays 2:1', () => {
    const s = act(start1('TS', '9D', 'AH', 'KC'), 0, 'insurance', { amountCents: 500, power: 'freeInsurance' });
    expect(seat0(s).insurance.stakedCents).toBe(0);
    expect(net0(s)).toBe(-1000 + 1000);
    const s2 = act(start1('TS', '9D', 'AH', '7C'), 0, 'insurance', { amountCents: 500, power: 'freeInsurance' });
    expect(totalStaked(s2, 0)).toBe(1000);
    expect(code(() => act(start1('TS', '9D', 'AH', '7C'), 0, 'insurance', { amountCents: 0, power: 'freeInsurance' }))).toBe('POWER_NOT_APPLICABLE');
  });
  it('free powers are capped so one use is worth less than its price (regression: free-roll insurance on big bets)', () => {
    expect(code(() => act(start1('TS', '9D', 'AH', 'KC', [], 100_000), 0, 'insurance', { amountCents: 50_000, power: 'freeInsurance' }))).toBe('BAD_AMOUNT');
    expect(code(() => act(start1('5S', '6D', 'TH', '9C', ['2S'], 5_000), 0, 'double', { power: 'freeDouble' }))).toBe('POWER_NOT_APPLICABLE');
    expect(code(() => act(start1('8S', '8D', 'TH', '9C', ['3C', 'TS'], 5_000), 0, 'split', { power: 'freeSplit' }))).toBe('POWER_NOT_APPLICABLE');
  });
  it('secondChance: a busting card is replaced once', () => {
    const s = act(start1('TS', '6D', 'TH', '7C', ['KC', '4S']), 0, 'hit', { power: 'secondChance' });
    expect(seat0(s).hands[0].cards).toEqual(['TS', '6D', '4S']);
    expect(s.events.find((e) => e.type === 'secondChance')?.card).toBe('KC');
    // non-busting card is kept
    const s2 = act(start1('TS', '2D', 'TH', '7C', ['5C', '4S']), 0, 'hit', { power: 'secondChance' });
    expect(seat0(s2).hands[0].cards).toEqual(['TS', '2D', '5C']);
  });
  it('peek does not end the turn and is one power per hand', () => {
    const s = start1('TS', '6D', '9H', '7C', ['KC']);
    const s1 = act(s, 0, 'peek', { power: 'peek' });
    expect(s1.turn).toEqual({ seatIndex: 0, handIndex: 0 });
    expect(seat0(s1).powerUsed).toBe('peek');
    expect(s1.events.find((e) => e.type === 'power')?.card).toBeNull();
    expect(code(() => act(s1, 0, 'hit', { power: 'secondChance' }))).toBe('POWER_ALREADY_USED');
    expect(code(() => act(s, 0, 'peek'))).toBe('ILLEGAL_ACTION');
  });
  it('power must match the action', () => {
    const s = start1('8S', '8D', '6H', 'TC', ['3C', 'TS']);
    expect(code(() => act(s, 0, 'hit', { power: 'freeSplit' }))).toBe('POWER_NOT_APPLICABLE');
    expect(code(() => act(s, 0, 'stand', { power: 'peek' }))).toBe('POWER_NOT_APPLICABLE');
    expect(code(() => act(s, 0, 'double', { power: 'freeSplit' }))).toBe('POWER_NOT_APPLICABLE');
  });
});

describe('provably fair', () => {
  const seed = 'a'.repeat(64);
  it('commit is sha256 of the seed; order is deterministic; verification detects tampering', () => {
    expect(commitForSeed(seed)).toMatch(/^[0-9a-f]{64}$/);
    const remaining = buildShoe(6).slice(0, 200);
    const o1 = fairDealOrder(remaining, seed);
    const o2 = fairDealOrder([...remaining].reverse(), seed); // input order does not matter
    expect(o1).toEqual(o2);
    expect(canonicalSort(o1.slice(0, 200))).toEqual(canonicalSort(remaining));
    const dealt = o1.slice(0, 12);
    expect(verifyFairness({ commit: commitForSeed(seed), seed, remainingBefore: remaining, dealt })).toBe(true);
    expect(verifyFairness({ commit: commitForSeed(seed), seed: 'b'.repeat(64), remainingBefore: remaining, dealt })).toBe(false);
    const forged = [...dealt];
    [forged[0], forged[1]] = [forged[1], forged[0]];
    expect(verifyFairness({ commit: commitForSeed(seed), seed, remainingBefore: remaining, dealt: forged })).toBe(forged[0] === forged[1]);
  });
  it('seededRng is reproducible and roughly uniform', () => {
    const a = seededRng('x');
    const b = seededRng('x');
    const xs = Array.from({ length: 50 }, () => a.nextInt(1000));
    expect(Array.from({ length: 50 }, () => b.nextInt(1000))).toEqual(xs);
    const r = seededRng('uniform');
    const counts = new Array(6).fill(0);
    for (let i = 0; i < 60_000; i++) counts[r.nextInt(6)]++;
    for (const c of counts) expect(Math.abs(c - 10_000)).toBeLessThan(500);
  });
  it('known-answer: first values of seededRng("golden") are stable', () => {
    const r = seededRng('golden');
    expect(Array.from({ length: 8 }, () => r.nextInt(52))).toMatchInlineSnapshot(`
      [
        46,
        14,
        23,
        8,
        36,
        37,
        0,
        22,
      ]
    `);
  });
});
