/**
 * Baccarat engine: card values, burn, the COMPLETE official drawing chart (every two-card total
 * pair × every Player third card), naturals, pairs, and every payout exact to the cent.
 */
import { describe, expect, it } from 'vitest';
import {
  baccaratValue, bankerCommission, bankerDraws, burnCount, dealCoup, dealingMs, handTotal, isPair, maxCoupsLeft,
  playerDraws, settleBoard, shoeOutcome, shoeYesProbability, spotReturn, type CoupOutcome,
} from '../../../src/games/baccarat/engine';
import { BACCARAT_TIMING } from '../../../src/shared/games/baccarat';

/** One card of each baccarat value (0 = king). Suits vary so that only ranks make pairs. */
const OF_VALUE = ['K', 'A', '2', '3', '4', '5', '6', '7', '8', '9'];
const card = (value: number, suit = 'S') => `${OF_VALUE[value]}${suit}`;

/**
 * The official Punto Banco tableau, written out independently of the engine:
 * row = Banker's two-card total 0..7, column = value of Player's third card 0..9 (D draw, S stand),
 * last column = Player stood on two cards.
 */
const BANKER_CHART: Record<number, string> = {
  0: 'DDDDDDDDDD|D',
  1: 'DDDDDDDDDD|D',
  2: 'DDDDDDDDDD|D',
  3: 'DDDDDDDDSD|D',
  4: 'SSDDDDDDSS|D',
  5: 'SSSSDDDDSS|D',
  6: 'SSSSSSDDSS|S',
  7: 'SSSSSSSSSS|S',
};
const chartDraws = (bt: number, p3: number | null) => BANKER_CHART[bt][p3 === null ? 11 : p3] === 'D';

describe('card values, totals, burn', () => {
  it('ace 1, 2–9 face value, ten and faces 0; totals mod 10', () => {
    expect(['AS', '2H', '5D', '9C', 'TS', 'JH', 'QD', 'KC'].map(baccaratValue)).toEqual([1, 2, 5, 9, 0, 0, 0, 0]);
    expect(handTotal(['9S', '8H'])).toBe(7);
    expect(handTotal(['KS', 'QH'])).toBe(0);
    expect(handTotal(['AS', '9H', 'TD'])).toBe(0);
    expect(handTotal(['5S', '5H', '9D'])).toBe(9);
  });

  it('burn: ace 1, 2–9 face value, ten / faces 10', () => {
    expect(['AS', '2H', '7D', '9C', 'TS', 'JH', 'QD', 'KC'].map(burnCount)).toEqual([1, 2, 7, 9, 10, 10, 10, 10]);
  });

  it('pairs are the same rank (K Q is not a pair)', () => {
    expect(isPair(['7H', '7S'])).toBe(true);
    expect(isPair(['KC', 'KD', '3S'])).toBe(true);
    expect(isPair(['KC', 'QD'])).toBe(false);
    expect(isPair(['TC', 'JD'])).toBe(false);
  });
});

describe('the official drawing chart', () => {
  it('Player draws on 0–5 and stands on 6–7', () => {
    expect([0, 1, 2, 3, 4, 5, 6, 7].map(playerDraws)).toEqual([true, true, true, true, true, true, false, false]);
  });

  it('bankerDraws matches the tableau for Banker 0–7 × Player third card 0–9 / Player standing', () => {
    for (let bt = 0; bt <= 7; bt++) {
      for (const p3 of [null, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) {
        expect(bankerDraws(bt, p3), `banker ${bt}, player third ${p3}`).toBe(chartDraws(bt, p3));
      }
    }
  });

  it('dealCoup applies the chart to every combination of the first five cards (and naturals stand)', () => {
    let n = 0;
    for (let p1 = 0; p1 < 10; p1++) for (let b1 = 0; b1 < 10; b1++) for (let p2 = 0; p2 < 10; p2++) for (let b2 = 0; b2 < 10; b2++) {
      for (let p3 = 0; p3 < 10; p3++) {
        for (const b3 of [0, 7]) {
          const order = [card(p1, 'S'), card(b1, 'H'), card(p2, 'D'), card(b2, 'C'), card(p3, 'H'), card(b3, 'S'), '2D'];
          const c = dealCoup(order, { burn: false });
          const pt = (p1 + p2) % 10;
          const bt = (b1 + b2) % 10;
          const natural = pt >= 8 || bt >= 8;
          const pDraw = !natural && pt <= 5;
          const bDraw = !natural && chartDraws(bt, pDraw ? p3 : null);
          const ctx = `P ${p1}+${p2} B ${b1}+${b2} p3 ${p3}`;
          expect(c.natural, ctx).toBe(natural);
          expect(c.player.length, ctx).toBe(pDraw ? 3 : 2);
          expect(c.banker.length, ctx).toBe(bDraw ? 3 : 2);
          // the Banker's third card is the next card after Player's (or the 5th card when Player stood)
          if (bDraw) expect(c.banker[2], ctx).toBe(order[pDraw ? 5 : 4]);
          const fp = (pt + (pDraw ? p3 : 0)) % 10;
          const fb = (bt + (bDraw ? (pDraw ? b3 : p3) : 0)) % 10;
          expect([c.playerTotal, c.bankerTotal], ctx).toEqual([fp, fb]);
          expect(c.winner, ctx).toBe(fp > fb ? 'player' : fb > fp ? 'banker' : 'tie');
          expect(c.dealt, ctx).toEqual(order.slice(0, 4 + (pDraw ? 1 : 0) + (bDraw ? 1 : 0)));
          n++;
        }
      }
    }
    expect(n).toBe(200_000);
  });

  it('deal order is P1 B1 P2 B2, then Player third, then Banker third', () => {
    const c = dealCoup(['2S', '3H', 'KD', 'KC', '4S', '9H'], { burn: false });
    expect(c.player).toEqual(['2S', 'KD', '4S']);
    expect(c.banker).toEqual(['3H', 'KC', '9H']); // banker 3, player third 4 → draws
    expect([c.playerTotal, c.bankerTotal, c.winner]).toEqual([6, 2, 'player']);
  });

  it('a natural 8/9 stops the coup even against a low hand; 9 beats 8', () => {
    const c = dealCoup(['4S', 'AH', '5D', 'KC', '9S', '9H'], { burn: false });
    expect([c.player, c.banker, c.natural, c.winner]).toEqual([['4S', '5D'], ['AH', 'KC'], true, 'player']);
    const d = dealCoup(['4S', '5H', '4D', '4C'], { burn: false });
    expect([d.playerTotal, d.bankerTotal, d.winner]).toEqual([8, 9, 'banker']);
  });

  it('burn: the first card decides how many cards are burned, all from the same order', () => {
    const order = ['3S', 'KH', 'QH', 'JH', '9S', '8H', 'KC', 'KD', '5S', '6H'];
    const c = dealCoup(order, { burn: true });
    expect(c.burn).toEqual({ card: '3S', count: 3, cards: ['KH', 'QH', 'JH'] });
    expect(c.player).toEqual(['9S', 'KC']);
    expect(c.banker).toEqual(['8H', 'KD']);
    expect(c.dealt).toEqual(order.slice(0, 8));
    const t = dealCoup(['TS', ...Array.from({ length: 10 }, () => 'AC'), '8S', '8H', 'KS', 'KH'], { burn: true });
    expect(t.burn!.count).toBe(10);
    expect(t.player).toEqual(['8S', 'KS']);
  });

  it('an order that runs out throws (fairDealOrder always refills)', () => {
    expect(() => dealCoup(['2S', '3H', 'KD'], { burn: false })).toThrow(/exhausted/);
  });
});

describe('payouts (exact to the cent)', () => {
  const B: CoupOutcome = { winner: 'banker', playerPair: false, bankerPair: false };
  const P: CoupOutcome = { winner: 'player', playerPair: false, bankerPair: false };
  const T: CoupOutcome = { winner: 'tie', playerPair: false, bankerPair: false };

  it('Player 1:1, push on a tie', () => {
    expect([spotReturn('player', 1_000, P), spotReturn('player', 1_000, B), spotReturn('player', 1_000, T)]).toEqual([2_000, 0, 1_000]);
  });

  it('Banker 0.95:1 exact for every whole-dollar bet, 1:1 with freeCommission, push on a tie', () => {
    for (let dollars = 1; dollars <= 2_500; dollars++) {
      const v = dollars * 100;
      const r = spotReturn('banker', v, B);
      expect(Number.isInteger(r)).toBe(true);
      expect(r).toBe(v + dollars * 95); // 95 cents per dollar won
      expect(spotReturn('banker', v, B, true)).toBe(2 * v);
    }
    expect(spotReturn('banker', 100, B)).toBe(195);
    expect(spotReturn('banker', 700, B)).toBe(1_365);
    expect(bankerCommission(2_500)).toBe(125);
    expect([spotReturn('banker', 1_000, P), spotReturn('banker', 1_000, T)]).toEqual([0, 1_000]);
  });

  it('Tie 8:1; pairs 11:1 whatever the winner', () => {
    expect([spotReturn('tie', 500, T), spotReturn('tie', 500, B), spotReturn('tie', 500, P)]).toEqual([4_500, 0, 0]);
    const pp: CoupOutcome = { winner: 'banker', playerPair: true, bankerPair: false };
    const bp: CoupOutcome = { winner: 'player', playerPair: false, bankerPair: true };
    expect([spotReturn('playerPair', 200, pp), spotReturn('bankerPair', 200, pp)]).toEqual([2_400, 0]);
    expect([spotReturn('playerPair', 200, bp), spotReturn('bankerPair', 200, bp)]).toEqual([0, 2_400]);
    expect(spotReturn('nope', 200, bp)).toBe(0);
  });

  it('a whole board: stake, return, net, counters and jackpot', () => {
    const coup = { winner: 'tie' as const, playerPair: true, bankerPair: false, natural: true };
    const s = settleBoard({ banker: 1_000, player: 500, tie: 100, playerPair: 100, bankerPair: 100 }, coup);
    expect(s).toEqual({
      stakedCents: 1_800, returnCents: 1_000 + 500 + 900 + 1_200, netCents: 1_800, jackpot: true,
      counters: { tieWins: 1, pairWins: 1, naturals: 1 },
    });
    const b = settleBoard({ banker: 2_000 }, { winner: 'banker', playerPair: false, bankerPair: false, natural: false }, true);
    expect(b).toEqual({ stakedCents: 2_000, returnCents: 4_000, netCents: 2_000, jackpot: false, counters: { bankerWins: 1, commissionSaved: 100 } });
    const l = settleBoard({ player: 300 }, { winner: 'banker', playerPair: false, bankerPair: false, natural: false });
    expect(l).toEqual({ stakedCents: 300, returnCents: 0, netCents: -300, jackpot: false, counters: {} });
  });
});

describe('timing and the shoe market', () => {
  it('dealing lasts burn + 4 cards + third cards + reveal', () => {
    const t = BACCARAT_TIMING;
    expect(dealingMs({ player: ['a', 'b'], banker: ['c', 'd'], burn: null })).toBe(4 * t.cardMs + t.revealMs);
    expect(dealingMs({ player: ['a', 'b', 'e'], banker: ['c', 'd', 'f'], burn: { card: 'AS', count: 1, cards: [] } }))
      .toBe(t.burnMs + 4 * t.cardMs + 2 * t.thirdCardMs + t.revealMs);
  });

  it('coups still possible after the cut card is reached', () => {
    expect(maxCoupsLeft(16)).toBe(0);
    expect(maxCoupsLeft(17)).toBe(1);
    expect(maxCoupsLeft(20)).toBe(1);
    expect(maxCoupsLeft(21)).toBe(2);
    expect(maxCoupsLeft(416)).toBe(100);
  });

  it('the series outcome is only decided when no future coup can change it', () => {
    expect(shoeOutcome(40, 70, 16)).toBe('yes'); // shoe over: 57 %
    expect(shoeOutcome(30, 70, 16)).toBe('no'); // shoe over: 43 %
    expect(shoeOutcome(40, 70, 40)).toBe('yes'); // ≤ 6 coups left: at worst 40/76 = 52.6 %
    expect(shoeOutcome(30, 70, 40)).toBeNull(); // between 39.5 % and 47.4 %
    expect(shoeOutcome(20, 60, 40)).toBe('no'); // at best 26/66 = 39.4 %
    expect(shoeOutcome(0, 0, 416)).toBeNull();
  });

  it('fair probability of the series market: ≈ ½ on a fresh shoe, 0 / 1 once certain, monotonic', () => {
    const fresh = shoeYesProbability(0, 0, 416);
    expect(fresh).toBeGreaterThan(0.4);
    expect(fresh).toBeLessThan(0.55);
    expect(shoeYesProbability(40, 70, 40)).toBe(1);
    expect(shoeYesProbability(20, 60, 40)).toBe(0);
    expect(shoeYesProbability(30, 50, 200)).toBeGreaterThan(shoeYesProbability(20, 50, 200));
  });
});
