import { describe, expect, it } from 'vitest';
import { fastRng, sha256Hex, verifyFairness } from '../../src/engine';
import { AppError } from '../../src/shared/errors';
import { CUT_CARD_REMAINING, DECISION_GRACE_MS, MISSED_ROUNDS_LIMIT, TIMING, type TableDoc } from '../../src/shared/types';
import { BOTS, simRoster, simTableId } from '../../src/sim/profiles';
import { newTableState, TableMachine, type MachineDeps } from '../../src/table/machine';
import type { Effect, PlayerInfo, TablePrivateDoc } from '../../src/table/model';

function deps(seed = 1): MachineDeps {
  let n = 0;
  return { rng: fastRng(seed), shuffleRng: fastRng(seed + 1000), newSeed: () => sha256Hex(`seed-${seed}-${n++}`) };
}

const human = (i: number): PlayerInfo => ({ uid: `h${i}`, username: `Human${i}`, avatar: 'avatar01', rankTier: 'bronze', isBot: false });
const botInfo = (i: number): PlayerInfo => ({ uid: BOTS[i].uid, username: BOTS[i].username, avatar: BOTS[i].avatar, rankTier: BOTS[i].rankTier, isBot: true });

class Harness {
  now = 1_000_000;
  pub: TableDoc;
  priv: TablePrivateDoc;
  effects: Effect[] = [];
  private d: MachineDeps;
  constructor(opts: { isPrivate?: boolean; simManaged?: boolean; tableId?: string; seed?: number } = {}) {
    this.d = deps(opts.seed ?? 1);
    const s = newTableState({
      tableId: opts.tableId ?? 't1', name: 'Test', stakeTier: 'low', isPrivate: opts.isPrivate ?? false,
      simManaged: opts.simManaged ?? false, rankTier: 'bronze',
    }, this.now, this.d);
    this.pub = s.pub;
    this.priv = s.priv;
  }
  /** Run `fn` on a machine at the current time, like one transaction. */
  run<T>(fn: (m: TableMachine) => T): T {
    const m = new TableMachine(structuredClone(this.pub), structuredClone(this.priv), this.d, this.now);
    const out = fn(m);
    this.pub = m.pub;
    this.priv = m.priv;
    this.effects.push(...m.effects);
    return out;
  }
  tick(ms: number): boolean {
    this.now += ms;
    return this.run((m) => m.advance());
  }
  /** Advance time until phase matches (bounded). */
  until(pred: (t: TableDoc) => boolean, maxSteps = 200): void {
    for (let i = 0; i < maxSteps && !pred(this.pub); i++) {
      const dl = this.pub.deadlineMs;
      // Human decisions get DECISION_GRACE_MS after the displayed deadline.
      const due = dl === null ? null : dl + this.run((m) => m.graceMs());
      this.tick(due === null ? 1000 : Math.max(1, due - this.now));
    }
    expect(pred(this.pub)).toBe(true);
  }
  ofKind<K extends Effect['kind']>(k: K): Extract<Effect, { kind: K }>[] {
    return this.effects.filter((e): e is Extract<Effect, { kind: K }> => e.kind === k);
  }
}

function reasonOf(fn: () => unknown): string {
  try { fn(); } catch (e) {
    if (e instanceof AppError) return e.reason;
    return (e as { code?: string }).code ?? String(e);
  }
  return 'NO_ERROR';
}

describe('table lifecycle', () => {
  it('joining an idle table opens betting with a provably-fair commitment and markets', () => {
    const h = new Harness();
    const r = h.run((m) => m.join(human(1)));
    expect(r).toEqual({ status: 'seated', seatIndex: 0 });
    expect(h.pub.phase).toBe('betting');
    expect(h.pub.handNumber).toBe(1);
    expect(h.pub.deadlineMs).toBe(h.now + TIMING.bettingMs);
    expect(h.pub.fairness.currentCommit).toBe(sha256Hex(h.priv.seed!));
    const kinds = h.ofKind('marketCreate').map((e) => e.market.kind).sort();
    expect(kinds).toEqual(['dealerBust', 'natural', 'shoeDealerBustRate']);
    expect(h.ofKind('location')).toEqual([{ kind: 'location', uid: 'h1', tableId: 't1' }]);
  });

  it('a lone human betting deals immediately; timeout stands; settlement reveals the seed and a valid proof', () => {
    const h = new Harness();
    h.run((m) => m.join(human(1)));
    h.run((m) => m.placeBet('h1', 1, 500));
    expect(['playerTurns', 'settled', 'insurance']).toContain(h.pub.phase);
    // hole card never public while hidden
    if (h.pub.dealer.holeHidden) {
      expect(h.pub.dealer.cards).toHaveLength(1);
      expect(h.pub.events.find((e) => e.type === 'dealerHole')?.card).toBeNull();
      expect(JSON.stringify(h.pub)).not.toContain(h.priv.seed!);
    }
    h.until((t) => t.phase === 'settled');
    const settle = h.ofKind('settle');
    expect(settle).toHaveLength(1);
    expect(settle[0].seats[0].uid).toBe('h1');
    const hist = h.ofKind('history')[0].doc;
    expect(verifyFairness(hist.fairness)).toBe(true);
    expect(h.pub.fairness.lastSeed).toBe(hist.fairness.seed);
    expect(h.pub.fairness.lastCommit).toBe(sha256Hex(hist.fairness.seed));
    // markets of the hand resolved
    const resolved = h.ofKind('marketStatus').filter((e) => e.status === 'resolved').map((e) => e.marketId);
    expect(resolved).toEqual(expect.arrayContaining(['t1__h1__dealerBust', 't1__h1__natural', 't1__h1__p0']));
    h.tick(TIMING.settledMs);
    expect(h.pub.phase).toBe('betting');
    expect(h.pub.handNumber).toBe(2);
    expect(h.pub.seats[0]!.hands).toEqual([]);
  });

  it('a decision arriving just after the displayed deadline (slow callable, clock drift) still counts', () => {
    const h = new Harness({ seed: 3 });
    h.run((m) => m.join(human(1)));
    h.run((m) => m.placeBet('h1', 1, 500));
    if (h.pub.phase === 'insurance') h.tick(TIMING.insuranceMs + DECISION_GRACE_MS);
    expect(h.pub.phase).toBe('playerTurns');
    h.now += TIMING.decisionMs + DECISION_GRACE_MS - 500; // the poke has not run yet
    h.run((m) => { m.advance(); m.act('h1', { handNumber: 1, action: 'stand' }); });
    expect(h.pub.events.some((e) => e.type === 'timeout')).toBe(false);
    expect(h.pub.events.some((e) => e.type === 'stand')).toBe(true);
  });

  it('a human who never acts times out to stand within the decision window', () => {
    const h = new Harness({ seed: 3 });
    h.run((m) => m.join(human(1)));
    h.run((m) => m.placeBet('h1', 1, 500));
    if (h.pub.phase === 'insurance') h.tick(TIMING.insuranceMs + DECISION_GRACE_MS);
    expect(h.pub.phase).toBe('playerTurns');
    {
      expect(h.pub.deadlineMs).toBe(h.now + TIMING.decisionMs);
      // The displayed deadline passes; the human still has the grace period.
      expect(h.tick(TIMING.decisionMs + DECISION_GRACE_MS - 1)).toBe(false);
      h.tick(1);
      expect(h.pub.events.some((e) => e.type === 'timeout')).toBe(true);
    }
  });

  it('bots bet when betting opens and play their turns on short deadlines', () => {
    const h = new Harness();
    h.run((m) => { m.join(botInfo(50)); m.join(botInfo(51)); m.join(human(1)); });
    expect(h.pub.phase).toBe('betting');
    h.run((m) => m.placeBet('h1', 1, 1000));
    h.until((t) => t.phase === 'settled', 400);
    const s = h.ofKind('settle')[0];
    expect(s.seats.length).toBeGreaterThanOrEqual(1);
    expect(h.pub.events.filter((e) => e.type === 'settle').length).toBeGreaterThan(0);
  });

  it('only bots: deals when the betting deadline passes', () => {
    const h = new Harness({ simManaged: true, tableId: simTableId(0) });
    h.run((m) => { for (const b of simRoster(0).slice(0, 3)) m.join({ ...botInfo(BOTS.indexOf(b)) }); });
    expect(h.pub.phase).toBe('betting');
    h.tick(TIMING.bettingMs);
    expect(h.pub.phase === 'settled' || h.pub.phase === 'playerTurns' || h.pub.phase === 'insurance' || h.pub.phase === 'betting').toBe(true);
    h.until((t) => t.phase === 'settled', 400);
  });
});

describe('regressions', () => {
  it('BUG#1: bots seated first on a fresh matchmaking table must not open-then-close it', () => {
    const h = new Harness();
    h.run((m) => { m.join(botInfo(50)); m.join(botInfo(51)); });
    expect(h.pub.status).toBe('open');
    expect(h.pub.phase).toBe('idle');
    h.run((m) => m.join(human(1)));
    expect(h.pub.status).toBe('open');
    expect(h.pub.phase).toBe('betting');
  });
});

describe('regressions (2)', () => {
  it('BUG#2: re-joining while the seat is "leaving" must not create a second seat for the same uid', () => {
    const h = new Harness({ seed: 5 });
    h.run((m) => { m.join(human(1)); m.join(human(2)); });
    h.run((m) => { m.placeBet('h1', 1, 500); m.placeBet('h2', 1, 500); });
    expect(h.pub.phase).not.toBe('settled');
    h.run((m) => m.leave('h1'));
    const r = h.run((m) => m.join(human(1)));
    expect(r).toEqual({ status: 'seated', seatIndex: 0 });
    expect(h.pub.seats.filter((s) => s?.uid === 'h1')).toHaveLength(1);
    expect(h.pub.seats[0]!.status).toBe('active');
  });
});

describe('seating priority and leaving', () => {
  it('bots yield their seat to a human between hands', () => {
    const h = new Harness();
    h.run((m) => { for (let i = 0; i < 5; i++) m.join(botInfo(48 + i)); });
    expect(h.pub.botCount).toBe(5);
    const r = h.run((m) => m.join(human(1)));
    expect(r.status).toBe('seated');
    expect(h.pub.humanCount).toBe(1);
    expect(h.pub.botCount).toBe(4);
  });

  it('mid-hand: human is queued, then seated at the next betting round (a bot yields)', () => {
    const h = new Harness();
    h.run((m) => { for (let i = 0; i < 4; i++) m.join(botInfo(48 + i)); m.join(human(1)); });
    h.run((m) => m.placeBet('h1', 1, 100));
    expect(h.pub.phase).not.toBe('settled'); // fixed seed: the hand is in progress
    const r = h.run((m) => m.join(human(2)));
    expect(r.status).toBe('queued');
    expect(h.pub.queue.map((q) => q.uid)).toEqual(['h2']);
    h.until((t) => t.phase === 'betting');
    expect(h.pub.queue).toEqual([]);
    expect(h.pub.seatedUids).toContain('h2');
    expect(h.pub.humanCount).toBe(2);
  });

  it(`a human who skips ${MISSED_ROUNDS_LIMIT} betting rounds in a row loses the seat (not before)`, () => {
    expect(MISSED_ROUNDS_LIMIT).toBe(5);
    expect(TIMING.bettingMs).toBe(20_000);
    const h = new Harness({ isPrivate: true });
    h.run((m) => { m.join(human(1)); m.join(human(2)); });
    const seated = (uid: string) => h.pub.seats.some((s) => s?.uid === uid);
    for (let round = 1; round <= MISSED_ROUNDS_LIMIT; round++) {
      expect(seated('h2')).toBe(true);
      const hand = h.pub.handNumber;
      h.run((m) => m.placeBet('h1', hand, 100));
      // h2 never bets: the hand is dealt at the deadline, then settles.
      h.until((t) => t.phase === 'betting' && t.handNumber === hand + 1, 400);
      expect(h.pub.seats.find((s) => s?.uid === 'h2')?.missedRounds ?? MISSED_ROUNDS_LIMIT).toBe(round === MISSED_ROUNDS_LIMIT ? MISSED_ROUNDS_LIMIT : round);
    }
    expect(seated('h1')).toBe(true);
    expect(seated('h2')).toBe(false);
  });
  it('private table: a host waiting alone for friends is never removed (idle rounds do not count)', () => {
    const h = new Harness({ isPrivate: true });
    h.run((m) => m.join(human(1)));
    for (let i = 0; i < MISSED_ROUNDS_LIMIT * 2; i++) {
      h.until((t) => t.phase === 'betting' && t.deadlineMs !== null);
      h.tick(TIMING.bettingMs);
    }
    expect(h.pub.status).toBe('open');
    expect(h.pub.seatedUids).toContain('h1');
    // A friend arrives and plays: the host can still bet.
    h.run((m) => m.join(human(2)));
    expect(h.pub.seats.filter((s) => s !== null).length).toBe(2);
  });
  it('private table: no bots, full → TABLE_FULL', () => {
    const h = new Harness({ isPrivate: true });
    h.run((m) => { for (let i = 0; i < 5; i++) m.join(human(i)); });
    expect(reasonOf(() => h.run((m) => m.join(human(9))))).toBe('TABLE_FULL');
  });

  it('leaving during betting refunds the bet', () => {
    const h = new Harness();
    h.run((m) => { m.join(human(1)); m.join(human(2)); });
    h.run((m) => m.placeBet('h1', 1, 700));
    const refund = h.run((m) => m.leave('h1'));
    expect(refund).toBe(700);
    expect(h.ofKind('refund')).toEqual([{ kind: 'refund', uid: 'h1', cents: 700, handNumber: 1 }]);
    expect(h.pub.seatedUids).toEqual(['h2']);
  });

  it('leaving mid-hand auto-stands, settles normally, seat removed next round', () => {
    const h = new Harness({ seed: 5 });
    h.run((m) => { m.join(human(1)); m.join(human(2)); });
    h.run((m) => { m.placeBet('h1', 1, 500); m.placeBet('h2', 1, 500); });
    expect(h.pub.phase).not.toBe('settled');
    h.run((m) => m.leave('h1'));
    expect(h.pub.seats[0]?.status).toBe('leaving');
    h.until((t) => t.phase === 'settled');
    expect(h.ofKind('settle')[0].seats.map((s) => s.uid)).toContain('h1');
    h.tick(TIMING.settledMs);
    expect(h.pub.seatedUids).toEqual(['h2']);
  });

  it('a non-simulated table closes when the last human leaves; its markets are voided', () => {
    const h = new Harness();
    h.run((m) => { m.join(botInfo(50)); m.join(human(1)); });
    h.run((m) => m.leave('h1'));
    expect(h.pub.status).toBe('closed');
    expect(h.pub.phase).toBe('closed');
    expect(h.pub.seatedUids).toEqual([]);
    expect(h.ofKind('marketStatus').filter((e) => e.status === 'void').length).toBe(3);
  });

  it('closing a table after its shoe market stopped trading resolves it instead of refunding (regression: free option)', () => {
    const h = new Harness({ seed: 7 });
    h.run((m) => { m.join(botInfo(50)); m.join(human(1)); });
    for (let i = 0; i < 80 && !h.priv.shoeMarketClosed; i++) {
      h.until((t) => t.phase === 'betting' && t.deadlineMs !== null);
      h.run((m) => m.placeBet('h1', h.pub.handNumber, 500));
      h.until((t) => t.phase === 'settled');
    }
    expect(h.priv.shoeMarketClosed).toBe(true);
    const shoeId = h.pub.markets.shoe!;
    h.until((t) => t.phase === 'betting');
    h.run((m) => m.leave('h1'));
    if (h.pub.status !== 'closed') h.tick(TIMING.settledMs);
    expect(h.pub.status).toBe('closed');
    const final = h.ofKind('marketStatus').filter((e) => e.marketId === shoeId && e.status !== 'closed');
    expect(final).toHaveLength(1);
    expect(final[0]!.status).toBe('resolved');
    expect(['yes', 'no']).toContain(final[0]!.outcome);
  });

  it(`humans missing ${MISSED_ROUNDS_LIMIT} betting rounds are removed`, () => {
    const h = new Harness();
    h.run((m) => { m.join(botInfo(50)); m.join(human(1)); });
    for (let i = 0; i < MISSED_ROUNDS_LIMIT + 1 && h.pub.seatedUids.includes('h1'); i++) {
      h.until((t) => t.phase === 'betting' && t.deadlineMs !== null);
      h.tick(TIMING.bettingMs + DECISION_GRACE_MS);
      h.until((t) => t.phase === 'betting' || t.status === 'closed', 400);
    }
    expect(h.pub.seatedUids).not.toContain('h1');
  });
});

describe('action validation', () => {
  it('stale hand, bad phase, not seated, not your turn', () => {
    const h = new Harness({ seed: 9 });
    h.run((m) => { m.join(human(1)); m.join(human(2)); });
    expect(reasonOf(() => h.run((m) => m.act('h1', { handNumber: 1, action: 'hit' })))).toBe('BAD_PHASE');
    expect(reasonOf(() => h.run((m) => m.placeBet('h1', 2, 500)))).toBe('STALE_HAND');
    expect(reasonOf(() => h.run((m) => m.placeBet('zz', 1, 500)))).toBe('NOT_SEATED');
    expect(reasonOf(() => h.run((m) => m.placeBet('h1', 1, 150)))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => h.run((m) => m.placeBet('h1', 1, 100_00_00)))).toBe('BET_OUT_OF_RANGE');
    h.run((m) => m.placeBet('h1', 1, 500));
    expect(reasonOf(() => h.run((m) => m.placeBet('h1', 1, 500)))).toBe('ALREADY_BET');
    h.run((m) => m.placeBet('h2', 1, 500));
    if (h.pub.phase === 'insurance') h.tick(TIMING.insuranceMs);
    expect(h.pub.phase).toBe('playerTurns');
    const turnUid = h.pub.seats[h.pub.turn!.seatIndex]!.uid;
    const other = turnUid === 'h1' ? 'h2' : 'h1';
    expect(reasonOf(() => h.run((m) => m.act(other, { handNumber: 1, action: 'hit' })))).toBe('NOT_YOUR_TURN');
    expect(reasonOf(() => h.run((m) => m.act(turnUid, { handNumber: 0, action: 'hit' })))).toBe('STALE_HAND');
    expect(reasonOf(() => h.run((m) => m.act(turnUid, { handNumber: 1, action: 'hit', handIndex: 2 })))).toBe('NOT_YOUR_TURN');
    expect(reasonOf(() => h.run((m) => m.act(turnUid, { handNumber: 1, action: 'insurance', amountCents: 0 })))).toBe('BAD_PHASE');
    expect(reasonOf(() => h.run((m) => m.act(turnUid, { handNumber: 1, action: 'stand' })))).toBe('NO_ERROR');
  });

  it('peek power writes the hole card only to a private effect', () => {
    for (let seed = 1; seed < 40; seed++) {
      const h = new Harness({ seed });
      h.run((m) => m.join(human(1)));
      h.run((m) => m.placeBet('h1', 1, 500));
      if (h.pub.phase !== 'playerTurns') continue;
      h.run((m) => m.act('h1', { handNumber: 1, action: 'peek', power: 'peek' }));
      const peek = h.ofKind('peek')[0];
      expect(peek.holeCard).toBe(h.priv.round!.dealer.cards[1]);
      expect(h.pub.dealer.cards).toHaveLength(1);
      expect(h.pub.events.filter((e) => e.type === 'power').every((e) => e.card === null)).toBe(true);
      return;
    }
    throw new Error('no seed reached playerTurns');
  });

  it('peek closes the dealerBust market (regression: hole-card knowledge sold to a second account)', () => {
    for (let seed = 1; seed < 40; seed++) {
      const h = new Harness({ seed });
      h.run((m) => m.join(human(1)));
      h.run((m) => m.placeBet('h1', 1, 500));
      if (h.pub.phase !== 'playerTurns') continue;
      const id = h.pub.markets.dealerBust!;
      expect(h.ofKind('marketStatus').some((e) => e.marketId === id && e.status === 'closed')).toBe(false);
      h.run((m) => m.act('h1', { handNumber: 1, action: 'peek', power: 'peek' }));
      expect(h.ofKind('marketStatus').some((e) => e.marketId === id && e.status === 'closed')).toBe(true);
      return;
    }
    throw new Error('no seed reached playerTurns');
  });

  it('a human seat\'s "player wins" market stops trading once their turn is reached (regression: bet NO then bust on purpose)', () => {
    for (let seed = 1; seed < 40; seed++) {
      const h = new Harness({ seed });
      h.run((m) => m.join(human(1)));
      h.run((m) => m.placeBet('h1', 1, 500));
      if (h.pub.phase !== 'playerTurns') continue;
      const id = h.pub.markets.players['0']!;
      expect(h.ofKind('marketStatus').some((e) => e.marketId === id && e.status === 'closed')).toBe(true);
      return;
    }
    throw new Error('no seed reached playerTurns');
  });

  it('markets open at the true prior, not 50 % (regression: buying NO on dealerBust every hand was +EV)', () => {
    const h = new Harness();
    h.run((m) => m.join(human(1)));
    const by = (k: string) => h.ofKind('marketCreate').find((e) => e.market.kind === k)!.market;
    expect(by('dealerBust').priceYes).toBeCloseTo(0.28, 5);
    expect(by('natural').priceYes).toBeLessThan(0.15);
    expect(by('shoeDealerBustRate').priceYes).toBe(0.5);
    const d = by('dealerBust');
    expect(1 / (1 + Math.exp((d.qNo - d.qYes) / d.b))).toBeCloseTo(0.28, 5);
  });

  it('"player wins" market closes as soon as a natural makes YES certain (regression: risk-free spectator bet)', () => {
    for (let seed = 1; seed < 400; seed++) {
      const h = new Harness({ seed });
      h.run((m) => { m.join(human(1)); m.join(human(2)); });
      h.run((m) => m.placeBet('h1', 1, 500));
      h.run((m) => m.placeBet('h2', 1, 500));
      if (h.pub.phase === 'insurance') h.tick(TIMING.insuranceMs);
      if (h.pub.phase !== 'playerTurns') continue;
      const nat = h.priv.round!.seats.find((s) => s.hands.length === 1 && s.hands[0]!.blackjack);
      if (!nat) continue;
      const id = h.pub.markets.players[String(nat.seatIndex)]!;
      expect(id).toBeTruthy();
      // Still playing (another seat has to act), yet the natural's market no longer trades.
      expect(h.pub.phase).toBe('playerTurns');
      expect(h.ofKind('marketStatus').some((e) => e.marketId === id && e.status === 'closed')).toBe(true);
      h.until((t) => t.phase === 'settled' || t.phase === 'betting');
      expect(h.ofKind('marketStatus').find((e) => e.marketId === id && e.status === 'resolved')?.outcome).toBe('yes');
      return;
    }
    throw new Error('no seed dealt a natural with another seat still to play');
  });

  it('double reports its extra stake for the wallet debit', () => {
    for (let seed = 1; seed < 60; seed++) {
      const h = new Harness({ seed });
      h.run((m) => m.join(human(1)));
      h.run((m) => m.placeBet('h1', 1, 500));
      if (h.pub.phase !== 'playerTurns') continue;
      const r = h.run((m) => m.act('h1', { handNumber: 1, action: 'double' }));
      expect(r).toEqual({ costCents: 500, ledgerType: 'double' });
      return;
    }
    throw new Error('no seed reached playerTurns');
  });
});

describe('long simulation (sim table, bots only)', () => {
  it('300 hands: never stuck, shoe changes at the cut card, markets resolve, money conserved per hand', () => {
    const h = new Harness({ simManaged: true, tableId: simTableId(1), seed: 42 });
    h.run((m) => { for (const b of simRoster(1).slice(0, 4)) m.join(botInfo(BOTS.indexOf(b))); });
    let hands = 0;
    let lastShoe = h.pub.shoe.shoeNumber;
    let shoeChanges = 0;
    for (let step = 0; step < 20_000 && hands < 300; step++) {
      expect(h.pub.status).toBe('open');
      expect(h.pub.deadlineMs).not.toBeNull(); // never stuck
      const before = h.ofKind('settle').length;
      h.tick(Math.max(1, h.pub.deadlineMs! - h.now));
      if (h.ofKind('settle').length > before) hands++;
      if (h.pub.shoe.shoeNumber !== lastShoe) {
        shoeChanges++;
        lastShoe = h.pub.shoe.shoeNumber;
        expect(h.pub.events[0]?.type).toBe('shuffle');
      }
      expect(h.priv.shoe.length).toBeGreaterThanOrEqual(0);
    }
    expect(hands).toBe(300);
    expect(shoeChanges).toBeGreaterThan(5);
    for (const s of h.ofKind('settle')) for (const x of s.seats) {
      expect(x.returnCents).toBeGreaterThanOrEqual(0);
      expect(x.netCents).toBe(x.returnCents - x.stakedCents);
    }
    for (const hist of h.ofKind('history')) expect(verifyFairness(hist.doc.fairness)).toBe(true);
    // every created per-hand market got a final status
    const created = new Set(h.ofKind('marketCreate').filter((e) => e.market.kind !== 'shoeDealerBustRate').map((e) => e.market.marketId));
    const finals = new Set(h.ofKind('marketStatus').filter((e) => e.status !== 'closed').map((e) => e.marketId));
    const pending = [...created].filter((id) => !finals.has(id));
    expect(pending.length).toBeLessThanOrEqual(3); // only the current hand's markets
    expect(h.ofKind('marketStatus').filter((e) => e.marketId.endsWith('__shoe') && e.status === 'resolved').length).toBeGreaterThan(3);
    expect(CUT_CARD_REMAINING).toBe(78);
  });
});
