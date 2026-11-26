/**
 * The roulette module driven by the real kernel (GameTableMachine, in-memory World of the kernel
 * tests): round lifecycle, the draw in the "Rien ne va plus" transaction, markets, payouts,
 * the zero shield, leaving while the ball spins, bots, series market, fairEstimate, counters.
 */
import { describe, expect, it } from 'vitest';
import { seededRng, sha256Hex } from '../../../src/engine';
import { colorOf, rouletteLimits, settleBoard } from '../../../src/games/roulette/engine';
import { makeRouletteModule, rouletteFairEstimate, rouletteModule } from '../../../src/games/roulette/module';
import { gameModule } from '../../../src/games/registry';
import type { GameTableDoc } from '../../../src/shared/games/common';
import {
  ROULETTE_TIMING, ROULETTE_ZERO_SERIES_CLOSE_AFTER, ROULETTE_ZERO_SERIES_LENGTH, type RoulettePublic, type RouletteSeat,
} from '../../../src/shared/games/roulette';
import type { MarketDoc } from '../../../src/shared/types';
import { gameSimRoster } from '../../../src/sim/profiles';
import { bot, human, reasonOf, World } from '../kernel/harness';

const g = (w: World) => w.pub.g as unknown as RoulettePublic;

function seated(n = 2, opts: ConstructorParameters<typeof World>[1] = {}): World {
  const w = new World(rouletteModule, opts);
  for (let i = 1; i <= n; i++) {
    w.fund(`h${i}`, 100_000);
    w.tx((m) => m.join(human(i)));
  }
  return w;
}

describe('registry', () => {
  it('the production registry plays the real roulette (available, bet boards)', () => {
    expect(gameModule('roulette')).toBe(rouletteModule);
    expect(rouletteModule.available).toBe(true);
    expect(rouletteModule.money).toBe('board');
    expect(rouletteModule.limits('low')).toEqual(rouletteLimits('low'));
  });
});

describe('round lifecycle', () => {
  it('betting 20 s with 3 round markets → draw in the closing transaction → 8 s spin → settlement → next round', () => {
    const w = seated(2);
    expect(w.pub.phase).toBe('betting');
    expect(w.pub.step).toBe('betting');
    expect(w.pub.deadlineMs).toBe(w.now + ROULETTE_TIMING.bettingMs);
    expect(Object.keys(w.pub.markets.round).sort()).toEqual(['rouletteDozen3', 'rouletteRed', 'rouletteZero']);
    expect(w.pub.markets.series).toEqual({}); // not a simulated table
    expect(g(w).number).toBeNull();
    const created = w.ofKind('marketCreate').map((e) => e.market);
    expect(created.map((m) => m.question.fr)).toEqual(['Rouge ? (Test, tour n°1)', 'Zéro ? (Test, tour n°1)', '3e douzaine ? (Test, tour n°1)']);

    const b1 = { n17: 1_000, red: 2_000, 'sp0-3': 500 };
    const b2 = { dozen3: 3_000, odd: 1_000 };
    w.setBets('h1', b1);
    w.setBets('h2', b2);
    const seed = w.priv.seed!;
    expect(w.pub.fairness.currentCommit).toBe(sha256Hex(seed));
    w.expire();
    const n = seededRng(seed).nextInt(37);
    expect(w.pub.phase).toBe('live');
    expect(w.pub.step).toBe('spinning');
    expect(w.pub.deadlineMs).toBe(w.now + ROULETTE_TIMING.spinMs);
    expect(g(w).number).toBe(n);
    expect(g(w).last).toEqual([n]);
    expect(w.pub.events.filter((e) => e.type === 'spin')).toEqual([
      expect.objectContaining({ seatIndex: null, d: { number: n, color: colorOf(n), spinMs: ROULETTE_TIMING.spinMs } }),
    ]);
    // the 3 markets are closed AND resolved in this very transaction
    const st = w.ofKind('marketStatus', w.last).map((e) => [e.marketId.split('__')[2], e.status, e.outcome ?? null]);
    expect(st).toEqual([
      ['rouletteRed', 'closed', null], ['rouletteRed', 'resolved', colorOf(n) === 'red' ? 'yes' : 'no'],
      ['rouletteZero', 'closed', null], ['rouletteZero', 'resolved', n === 0 ? 'yes' : 'no'],
      ['rouletteDozen3', 'closed', null], ['rouletteDozen3', 'resolved', n >= 25 ? 'yes' : 'no'],
    ]);
    expect(w.ofKind('debit', w.last)).toEqual([]); // a deadline never debits

    w.expire();
    expect(w.pub.phase).toBe('settled');
    const r1 = settleBoard(b1, n), r2 = settleBoard(b2, n);
    expect(w.wallets.get('h1')).toBe(100_000 - 3_500 + r1.returnCents);
    expect(w.wallets.get('h2')).toBe(100_000 - 4_000 + r2.returnCents);
    const settle = w.ofKind('settle', w.last)[0];
    expect(settle.rows.map((r) => [r.uid, r.stakedCents, r.returnCents, r.netCents])).toEqual([
      ['h1', 3_500, r1.returnCents, r1.returnCents - 3_500], ['h2', 4_000, r2.returnCents, r2.returnCents - 4_000],
    ]);
    const types = w.pub.events.map((e) => e.type);
    expect(types.slice(-3)).toEqual(['result', 'payout', 'payout']);
    expect(w.pub.events.find((e) => e.type === 'payout' && e.seatIndex === 0)!.d).toEqual({
      stakedCents: 3_500, returnCents: r1.returnCents, netCents: r1.returnCents - 3_500, wins: r1.wins, shield: false,
    });
    const hist = w.ofKind('history', w.last)[0].doc;
    expect(hist.result).toEqual({ number: n, color: colorOf(n) });
    expect(hist.fairness).toMatchObject({ seed, commit: sha256Hex(seed), remainingBefore: null, dealt: null, decks: null });
    expect(w.boards.get('h1')).toMatchObject({ bets: {}, totalCents: 0, previous: b1 });

    w.expire(); // next round
    expect(w.pub.round).toBe(2);
    expect(w.pub.phase).toBe('betting');
    expect(g(w).number).toBeNull();
    expect(g(w).last).toEqual([n]);
  });

  it('an empty round restarts betting without drawing; bets are refused once betting closed', () => {
    const w = seated(1);
    const seed = w.priv.seed;
    w.expire();
    expect(w.pub.phase).toBe('betting');
    expect(w.pub.round).toBe(1);
    expect(w.priv.seed).toBe(seed);
    expect(g(w).last).toEqual([]);
    w.setBets('h1', { red: 100 });
    w.expire();
    expect(reasonOf(() => w.setBets('h1', { red: 200 }))).toBe('BAD_PHASE');
  });

  it('every seat gets its own chip colour, reused once freed', () => {
    const w = seated(3);
    const colors = () => w.pub.seats.filter(Boolean).map((s) => (s!.g as unknown as RouletteSeat).color);
    expect(colors()).toEqual([0, 1, 2]);
    w.tx((m) => m.leave('h2'));
    w.fund('h9', 1_000);
    w.tx((m) => m.join(human(9)));
    expect(new Set(colors()).size).toBe(3);
    expect(colors()).toContain(1);
  });
});

describe('validation through the kernel fast path', () => {
  it('spots, caps, round maximum, powers', () => {
    const w = seated(1);
    w.inventory.set('h1:zeroShield', 1);
    expect(reasonOf(() => w.setBets('h1', { n37: 100 }))).toBe('BAD_BET_SPOT');
    expect(reasonOf(() => w.setBets('h1', { heads: 100 }))).toBe('BAD_BET_SPOT');
    expect(reasonOf(() => w.setBets('h1', { n7: 2_600 }))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => w.setBets('h1', { n7: 150 }))).toBe('BET_OUT_OF_RANGE'); // whole dollars
    const big = Object.fromEntries(Array.from({ length: 6 }, (_, i) => [`ln${1 + 3 * i}`, 10_000]));
    expect(reasonOf(() => w.setBets('h1', big))).toBe('BET_OUT_OF_RANGE'); // $600 > $500 per round
    expect(reasonOf(() => w.setBets('h1', { n0: 100 }, 'zeroShield'))).toBe('POWER_NOT_APPLICABLE');
    expect(reasonOf(() => w.setBets('h1', { red: 100 }, 'freeCommission'))).toBe('WRONG_GAME');
    expect(w.wallets.get('h1')).toBe(100_000);
    const plan = w.setBets('h1', { red: 1_000, n0: 100 }, 'zeroShield');
    expect(plan.powerConsumed).toBe('zeroShield');
    expect(w.inventory.get('h1:zeroShield')).toBe(0);
  });

  it('a game action other than setBets is a schema error (INVALID_ARGUMENT)', () => {
    const w = seated(1);
    expect(reasonOf(() => w.tx((m) => m.action('h1', w.pub.round, { type: 'cheer' })))).toBe('INVALID_ARGUMENT');
    expect(rouletteModule.legalActions(undefined as never, undefined as never)).toEqual([]);
  });
});

describe('zero shield (la partage)', () => {
  it('on 0 the shielded even-money bets return half; the other seat loses them all; counters follow', () => {
    // find a table seed whose first round draws 0
    let w: World | null = null;
    for (let s = 1; s < 4_000 && !w; s++) {
      const c = seated(2, { seed: s });
      if (seededRng(c.priv.seed!).nextInt(37) === 0) w = c;
    }
    expect(w).not.toBeNull();
    w!.inventory.set('h1:zeroShield', 1);
    w!.setBets('h1', { red: 1_100, black: 300, n0: 100 }, 'zeroShield');
    w!.setBets('h2', { red: 1_100, black: 300, n0: 100 });
    w!.expire();
    expect(g(w!).number).toBe(0);
    expect(w!.pub.seats[0]!.powerUsed).toBe('zeroShield');
    w!.expire();
    const rows = w!.ofKind('settle', w!.last)[0].rows;
    expect(rows[0]).toMatchObject({ stakedCents: 1_500, returnCents: 550 + 150 + 3_600, counters: { straightUps: 1, zeroShieldSaves: 1 }, highlight: 'jackpot' });
    expect(rows[1]).toMatchObject({ stakedCents: 1_500, returnCents: 3_600, counters: { straightUps: 1 }, highlight: 'jackpot' });
    expect(w!.wallets.get('h1')).toBe(100_000 - 1_500 + 4_300);
    expect(w!.pub.events.find((e) => e.type === 'payout' && e.seatIndex === 0)!.d).toMatchObject({ shield: true, wins: ['n0'] });
    // the kernel feeds the jackpots
    expect(w!.ofKind('feed', w!.last).map((e) => e.entry.kind)).toEqual(['jackpot', 'jackpot']);
  });
});

describe('leaving', () => {
  it('while betting: the board is refunded at once; while the ball spins: settled normally, then removed', () => {
    const w = seated(3);
    w.setBets('h1', { red: 500 });
    w.setBets('h2', { black: 700 });
    w.setBets('h3', { n5: 100 });
    w.tx((m) => m.leave('h1'));
    expect(w.wallets.get('h1')).toBe(100_000);
    expect(w.seat('h1')).toBeNull();
    w.expire(); // locked, spinning
    const n = g(w).number!;
    w.tx((m) => m.leave('h2'));
    expect(w.seat('h2')!.status).toBe('leaving');
    expect(w.wallets.get('h2')).toBe(100_000 - 700);
    w.expire(); // settled: h2 is paid like everyone, then removed
    expect(w.wallets.get('h2')).toBe(100_000 - 700 + settleBoard({ black: 700 }, n).returnCents);
    w.expire();
    expect(w.seat('h2')).toBeNull();
  });
});

describe('bots', () => {
  it('a simulated table plays with bots only: valid boards within the caps, house money, never debited', () => {
    const id = 'rl-sim-01';
    const w = new World(rouletteModule, { tableId: id, simManaged: true, stakeTier: 'mid', seed: 3 });
    const roster = gameSimRoster(id)!;
    w.tx((m) => { for (const b of roster.slice(0, 5)) m.join({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true }); });
    let played = 0;
    for (let r = 0; r < 30; r++) {
      w.until((t) => t.phase === 'live');
      for (const b of w.boards.values()) {
        if (b.totalCents === 0) continue;
        played++;
        expect(b.isBot).toBe(true);
        expect(() => rouletteModule.validateBets({ game: 'roulette', now: w.now, table: w.pub, limits: w.pub.limits }, w.seat(b.uid)!, b.bets, {})).not.toThrow();
        expect(b.totalCents).toBeLessThanOrEqual(w.pub.limits.maxRoundCents);
      }
      w.until((t) => t.phase === 'settled');
    }
    expect(played).toBeGreaterThan(80);
    expect(w.ofKind('debit')).toEqual([]);
    expect(w.ofKind('credit')).toEqual([]);
    expect(g(w).last).toHaveLength(30);
  });

  it('bots only ever answer "bets"', () => {
    const w = new World(rouletteModule);
    w.tx((m) => m.join(bot(48)));
    expect(rouletteModule.bot({} as never, w.pub.seats[0]!, 'turn')).toBeNull();
  });
});

describe('series market (simulated tables) and fair estimates', () => {
  it('opens with the round, closes after 18 spins, resolves YES on the first zero or NO after 37 spins', () => {
    const fast = makeRouletteModule({ bettingMs: 1_000, spinMs: 1_000, settledMs: 1_000 });
    const checked = { yes: 0, no: 0 };
    for (let seed = 1; seed <= 40 && (checked.yes === 0 || checked.no === 0); seed++) {
      const id = 'rl-sim-02';
      const w = new World(fast, { tableId: id, simManaged: true, seed });
      w.tx((m) => m.join(bot(100)));
      const s0 = g(w).series!;
      expect(s0).toEqual({ n: 1, startRound: 1, closed: false });
      const marketId = w.pub.markets.series.rouletteZeroSeries!;
      expect(marketId).toBeTruthy();
      let zeroAt: number | null = null;
      for (let spin = 1; spin <= ROULETTE_ZERO_SERIES_LENGTH; spin++) {
        w.until((t) => t.phase === 'live' && t.round === spin);
        const st = w.ofKind('marketStatus', w.last).filter((e) => e.marketId === marketId);
        if (g(w).number === 0) {
          zeroAt = spin;
          expect(st.at(-1)).toMatchObject({ status: 'resolved', outcome: 'yes' });
          expect(g(w).series).toBeNull();
          break;
        }
        if (spin === ROULETTE_ZERO_SERIES_CLOSE_AFTER) expect(st.map((e) => e.status)).toEqual(['closed']);
        if (spin === ROULETTE_ZERO_SERIES_LENGTH) {
          expect(st.at(-1)).toMatchObject({ status: 'resolved', outcome: 'no' });
          expect(g(w).series).toBeNull();
        } else {
          // the fair estimate falls with every spin without a zero
          const t = w.pub as unknown as GameTableDoc<RoulettePublic>;
          expect(rouletteFairEstimate('rouletteZeroSeries', t)).toBeCloseTo(1 - (36 / 37) ** (ROULETTE_ZERO_SERIES_LENGTH - spin), 12);
        }
      }
      if (zeroAt) checked.yes++;
      else checked.no++;
      // a new series starts with the next round
      w.until((t) => t.phase === 'betting');
      expect(g(w).series).toMatchObject({ n: 2, startRound: w.pub.round });
    }
    expect(checked.yes).toBeGreaterThan(0);
    expect(checked.no).toBeGreaterThan(0);
  });

  it('round markets: 18/37, 1/37, 12/37; a closing table voids the series', () => {
    const m = (kind: MarketDoc['kind']) => ({ kind }) as MarketDoc;
    expect(rouletteModule.fairEstimate(m('rouletteRed'), null)).toBeCloseTo(18 / 37, 15);
    expect(rouletteModule.fairEstimate(m('rouletteZero'), null)).toBeCloseTo(1 / 37, 15);
    expect(rouletteModule.fairEstimate(m('rouletteDozen3'), null)).toBeCloseTo(12 / 37, 15);
    expect(rouletteModule.fairEstimate(m('rouletteZeroSeries'), null)).toBeCloseTo(1 - (36 / 37) ** 37, 15);
    const w = new World(rouletteModule, { tableId: 'rl-sim-01', simManaged: true });
    w.tx((m2) => m2.join(bot(100)));
    expect(g(w).series).not.toBeNull();
    w.tx((m2) => m2.closeTable());
    expect(g(w).series).toBeNull();
    expect(w.ofKind('marketStatus', w.last).map((e) => e.status)).toEqual(expect.arrayContaining(['void']));
  });
});
