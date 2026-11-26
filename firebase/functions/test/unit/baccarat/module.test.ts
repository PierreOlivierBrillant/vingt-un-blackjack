/**
 * The baccarat module on the real kernel (in-memory World of the kernel tests): a coup dealt in ONE
 * transaction with its markets closed and resolved, exact settlement, the fairness proof (burn
 * included), the shoe chain from coup to coup, the cut card and the new shoe, the series market,
 * the power, refused bets, bots, leaving, fair estimates.
 */
import { describe, expect, it } from 'vitest';
import { sha256Hex, verifyFairness } from '../../../src/engine';
import { canonicalSort } from '../../../src/engine/cards';
import { settleBoard, shoeYesProbability } from '../../../src/games/baccarat/engine';
import { baccaratLimits, baccaratModule } from '../../../src/games/baccarat/module';
import type { GameEffect } from '../../../src/games/kernel/effects';
import { gameModule, PRODUCTION_GAME_MODULES } from '../../../src/games/registry';
import {
  BACCARAT_SHOE_SIZE, BACCARAT_TIMING, type BaccaratPrivate, type BaccaratPublic, type BaccaratResult,
} from '../../../src/shared/games/baccarat';
import type { GameRoundDoc } from '../../../src/shared/games/common';
import type { MarketDoc } from '../../../src/shared/types';
import { BOTS, gameSimRoster, gameSimTableId } from '../../../src/sim/profiles';
import { bot, human, reasonOf, World } from '../kernel/harness';

const g = (w: World) => w.pub.g as unknown as BaccaratPublic;
const v = (w: World) => w.priv.g as unknown as BaccaratPrivate;
const history = (w: World, list: GameEffect[] = w.effects): GameRoundDoc[] => w.ofKind('history', list).map((e) => e.doc);

function privateTable(n = 2, opts: { seed?: number; tier?: 'low' | 'mid' | 'high' } = {}): World {
  const w = new World(baccaratModule, { tableId: 'bc-t1', isPrivate: true, seed: opts.seed ?? 3, stakeTier: opts.tier ?? 'low' });
  for (let i = 1; i <= n; i++) {
    w.fund(`h${i}`, 1_000_000);
    w.tx((m) => m.join(human(i)));
  }
  return w;
}

/** Plays one whole coup (betting → dealing → settled) with these boards. */
function playCoup(w: World, boards: Record<string, Record<string, number>>) {
  if (w.pub.phase === 'settled') w.expire();
  for (const [uid, b] of Object.entries(boards)) w.setBets(uid, b);
  w.expire(); // deal
  const dealt = w.last;
  w.expire(); // settle
  return { dealt, settled: w.last };
}

describe('registry and limits', () => {
  it('baccarat is the production module, available, bet boards', () => {
    expect(PRODUCTION_GAME_MODULES.baccarat).toBe(baccaratModule);
    expect(gameModule('baccarat').available).toBe(true);
    expect(baccaratModule.money).toBe('board');
  });

  it('limits follow the stake tiers; side bets up to a fifth of the maximum', () => {
    expect(baccaratLimits('low')).toEqual({ minBetCents: 100, maxBetCents: 10_000, maxRoundCents: 20_000, extra: { sideMaxCents: 2_000 } });
    expect(baccaratLimits('mid').extra.sideMaxCents).toBe(10_000);
    expect(baccaratLimits('high').extra.sideMaxCents).toBe(50_000);
  });
});

describe('a coup', () => {
  it('opens with a commitment, three per-coup markets, a fresh shoe; no series market off simulated tables', () => {
    const w = privateTable();
    expect(w.pub.phase).toBe('betting');
    expect(w.pub.step).toBe('betting');
    expect(w.pub.deadlineMs).toBe(w.now + BACCARAT_TIMING.bettingMs);
    expect(w.pub.fairness.currentCommit).toBe(sha256Hex(w.priv.seed!));
    expect(w.ofKind('marketCreate').map((e) => e.market.marketId)).toEqual([
      'bc-t1__r1__baccaratBanker', 'bc-t1__r1__baccaratTie', 'bc-t1__r1__baccaratPair',
    ]);
    expect(w.ofKind('marketCreate')[0].market.question.fr).toBe('Le Banquier gagne ? (Test, coup n°1)');
    expect(g(w).shoe).toMatchObject({ n: 1, total: 416, remaining: 416, cutAt: 16, coups: 0, cutOut: false });
    expect(g(w).series).toBeNull();
    expect(v(w).remaining).toHaveLength(BACCARAT_SHOE_SIZE);
    expect(v(w).needsBurn).toBe(true);
    expect(g(w).coup).toBeNull();
  });

  it('closing the bets deals the whole coup in one transaction: public cards, events, markets closed and resolved', () => {
    const w = privateTable();
    w.setBets('h1', { banker: 1_000, tie: 100 });
    w.setBets('h2', { player: 500, playerPair: 100, bankerPair: 200 });
    const seed = w.priv.seed!;
    w.expire();
    expect(w.pub.phase).toBe('live');
    expect(w.pub.step).toBe('dealing');
    const coup = g(w).coup!;
    expect(coup.burn).not.toBeNull(); // first coup of the shoe
    expect(coup.player.length).toBeGreaterThanOrEqual(2);
    // events, in deal order
    const ev = w.pub.events.filter((e) => ['burn', 'card', 'result'].includes(e.type));
    expect(ev[0]).toMatchObject({ type: 'burn', d: coup.burn });
    const cards = ev.filter((e) => e.type === 'card').map((e) => e.d as { hand: string; i: number; card: string; total: number });
    expect(cards.slice(0, 4).map((c) => c.hand)).toEqual(['player', 'banker', 'player', 'banker']);
    expect(cards.filter((c) => c.hand === 'player').map((c) => c.card)).toEqual(coup.player);
    expect(cards.filter((c) => c.hand === 'banker').map((c) => c.card)).toEqual(coup.banker);
    expect(cards.at(-1)!.total).toBe(cards.at(-1)!.hand === 'player' ? coup.playerTotal : coup.bankerTotal);
    expect(ev.at(-1)).toMatchObject({ type: 'result', d: { winner: coup.winner, playerTotal: coup.playerTotal, bankerTotal: coup.bankerTotal } });
    // markets: closed then resolved, in THIS transaction
    const st = w.ofKind('marketStatus', w.last);
    const yes = { baccaratBanker: coup.winner === 'banker', baccaratTie: coup.winner === 'tie', baccaratPair: coup.playerPair || coup.bankerPair };
    for (const [kind, y] of Object.entries(yes)) {
      const id = `bc-t1__r1__${kind}`;
      expect(st.filter((e) => e.marketId === id).map((e) => [e.status, e.outcome])).toEqual([['closed', null], ['resolved', y ? 'yes' : 'no']]);
    }
    expect(w.pub.markets.round).toEqual({});
    // the deadline covers the animation; no money moved yet; no secret of the next coups is public
    expect(w.pub.deadlineMs! - w.now).toBeGreaterThanOrEqual(BACCARAT_TIMING.burnMs + 4 * BACCARAT_TIMING.cardMs + BACCARAT_TIMING.revealMs);
    expect(w.ofKind('credit', w.last)).toEqual([]);
    expect(JSON.stringify(w.pub)).not.toContain(seed);
    expect(reasonOf(() => w.setBets('h1', { banker: 2_000 }))).toBe('BAD_PHASE');
  });

  it('settlement pays every board exactly; the round document proves the deal (burn included)', () => {
    const w = privateTable();
    const commit = w.pub.fairness.currentCommit!;
    const boards = { h1: { banker: 1_000, tie: 100 }, h2: { player: 500, playerPair: 100, bankerPair: 200 } };
    const { settled } = playCoup(w, boards);
    const coup = g(w).coup!;
    expect(w.pub.phase).toBe('settled');
    for (const [uid, b] of Object.entries(boards)) {
      const s = settleBoard(b, coup);
      expect(w.wallets.get(uid)).toBe(1_000_000 + s.netCents);
      expect(w.seat(uid)!.roundNetCents).toBe(s.netCents);
    }
    const [doc] = history(w, settled);
    const result = doc.result as unknown as BaccaratResult;
    expect(result).toMatchObject({ player: coup.player, banker: coup.banker, winner: coup.winner, shoe: 1, coupInShoe: 1 });
    expect(result.burn!.cards).toHaveLength(result.burn!.count);
    expect(doc.fairness.commit).toBe(commit);
    expect(sha256Hex(doc.fairness.seed)).toBe(commit);
    expect(doc.fairness.decks).toBe(8);
    expect(doc.fairness.remainingBefore).toHaveLength(416);
    expect(doc.fairness.dealt).toEqual([result.burn!.card, ...result.burn!.cards, ...interleave(coup.player, coup.banker)]);
    expect(verifyFairness({ ...doc.fairness, remainingBefore: doc.fairness.remainingBefore!, dealt: doc.fairness.dealt!, decks: 8 })).toBe(true);
    // a tampered deal fails
    const bad = [...doc.fairness.dealt!];
    [bad[bad.length - 1], bad[bad.length - 2]] = [bad[bad.length - 2], bad[bad.length - 1]];
    if (bad.join() !== doc.fairness.dealt!.join()) expect(verifyFairness({ ...doc.fairness, remainingBefore: doc.fairness.remainingBefore!, dealt: bad, decks: 8 })).toBe(false);
    expect(w.pub.fairness.lastSeed).toBe(doc.fairness.seed);
    // boards emptied, previous kept for "Rejouer"
    expect(w.boards.get('h1')).toMatchObject({ bets: {}, totalCents: 0, previous: boards.h1 });
  });

  it('coup after coup: no burn, each remainingBefore is the previous one minus what was dealt', () => {
    const w = privateTable(1, { seed: 11 });
    const docs: GameRoundDoc[] = [];
    for (let i = 0; i < 6; i++) docs.push(...history(w, playCoup(w, { h1: { banker: 100 } }).settled));
    expect(docs.map((d) => d.round)).toEqual([1, 2, 3, 4, 5, 6]);
    for (let i = 1; i < docs.length; i++) {
      const prev = docs[i - 1].fairness;
      const left = [...prev.remainingBefore!];
      for (const c of prev.dealt!) left.splice(left.indexOf(c), 1);
      expect(canonicalSort(docs[i].fairness.remainingBefore!)).toEqual(canonicalSort(left));
      expect((docs[i].result as unknown as BaccaratResult).burn).toBeNull();
      expect(verifyFairness({ ...docs[i].fairness, remainingBefore: docs[i].fairness.remainingBefore!, dealt: docs[i].fairness.dealt!, decks: 8 })).toBe(true);
    }
    expect(g(w).shoe.coups).toBe(6);
    expect(g(w).beads.map((b) => b.round)).toEqual([1, 2, 3, 4, 5, 6]);
    expect(g(w).shoe.remaining).toBe(v(w).remaining.length);
    expect(g(w).shoe.banker + g(w).shoe.player + g(w).shoe.tie).toBe(6);
  });

  it('nobody bets: betting restarts, no card is dealt', () => {
    const w = privateTable(1);
    w.expire();
    expect(w.pub.phase).toBe('betting');
    expect(w.pub.round).toBe(1);
    expect(g(w).coup).toBeNull();
    expect(v(w).remaining).toHaveLength(416);
  });
});

describe('bets and the power', () => {
  it('refuses unknown spots, amounts out of range (side bets capped), the wrong power, an unowned power', () => {
    const w = privateTable(1);
    expect(reasonOf(() => w.setBets('h1', { dragon: 100 }))).toBe('BAD_BET_SPOT');
    expect(reasonOf(() => w.setBets('h1', { banker: 10_100 }))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => w.setBets('h1', { tie: 2_100 }))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => w.setBets('h1', { playerPair: 2_100 }))).toBe('BET_OUT_OF_RANGE');
    expect(reasonOf(() => w.setBets('h1', { banker: 150 }))).toBe('BET_OUT_OF_RANGE'); // whole dollars
    expect(reasonOf(() => w.setBets('h1', { banker: 10_000, player: 10_000, tie: 2_000, playerPair: 2_000, bankerPair: 2_000 }))).toBe('BET_OUT_OF_RANGE'); // > maxRound
    expect(reasonOf(() => w.setBets('h1', { banker: 100 }, 'zeroShield'))).toBe('WRONG_GAME');
    expect(reasonOf(() => w.setBets('h1', { banker: 100 }, 'freeCommission'))).toBe('POWER_NOT_OWNED');
    w.inventory.set('h1:freeCommission', 1);
    expect(reasonOf(() => w.setBets('h1', { player: 100 }, 'freeCommission'))).toBe('POWER_NOT_APPLICABLE');
    expect(w.wallets.get('h1')).toBe(1_000_000);
    expect(reasonOf(() => w.setBets('h1', { banker: 10_000, tie: 2_000, playerPair: 2_000, bankerPair: 2_000 }))).toBe('NO_ERROR');
    expect(reasonOf(() => w.tx((m) => m.action('h1', w.pub.round, { type: 'none' })))).toBe('ILLEGAL_ACTION');
    expect(reasonOf(() => w.tx((m) => m.action('h1', w.pub.round, { type: 'squeeze' })))).toBe('INVALID_ARGUMENT');
  });

  it('freeCommission: consumed once, a winning Banker bet is paid 1:1 that coup only', () => {
    let saved = 0;
    for (let seed = 1; seed < 40 && saved === 0; seed++) {
      const w = privateTable(1, { seed });
      w.inventory.set('h1:freeCommission', 1);
      w.setBets('h1', { banker: 2_000 }, 'freeCommission');
      expect(w.inventory.get('h1:freeCommission')).toBe(0);
      w.expire();
      w.expire();
      const coup = g(w).coup!;
      expect(w.seat('h1')!.powerUsed).toBe('freeCommission');
      const row = w.ofKind('settle', w.last)[0].rows[0];
      expect(row.returnCents).toBe(coup.winner === 'banker' ? 4_000 : coup.winner === 'tie' ? 2_000 : 0);
      if (coup.winner === 'banker') {
        expect(row.counters).toMatchObject({ bankerWins: 1, commissionSaved: 100 });
        saved = 1;
        // next coup: the commission is back
        w.expire();
        expect(w.boards.get('h1')?.power ?? null).toBeNull();
      }
    }
    expect(saved).toBe(1);
  });
});

describe('leaving, bots, history counters', () => {
  it('leaving during betting refunds the board; during the deal the coup still settles to the wallet', () => {
    const w = privateTable(2);
    w.setBets('h1', { banker: 700 });
    expect(w.tx((m) => m.leave('h1'))).toEqual({ refundedCents: 700, cashOutCents: 0, deferred: false });
    expect(w.wallets.get('h1')).toBe(1_000_000);
    w.setBets('h2', { player: 900 });
    w.expire();
    expect(w.tx((m) => m.leave('h2')).deferred).toBe(true); // locked: stays until the coup settles
    w.expire();
    const s = settleBoard({ player: 900 }, g(w).coup!);
    expect(w.wallets.get('h2')).toBe(1_000_000 + s.netCents);
    w.expire(); // next opening: the last human is gone, the table closes
    expect(w.pub.status).toBe('closed');
  });

  it('bots bet valid boards on a public table and are settled with everyone', () => {
    const w = new World(baccaratModule, { tableId: 'bc-q1', seed: 5 });
    w.fund('h1', 100_000);
    w.tx((m) => { m.join(bot(108)); m.join(bot(109)); m.join(bot(110)); m.join(human(1)); });
    let botRows = 0;
    for (let i = 0; i < 20; i++) {
      const { settled } = playCoup(w, { h1: { banker: 100 } });
      for (const e of w.ofKind('settle', settled)) botRows += e.rows.filter((r) => r.isBot).length;
    }
    expect(botRows).toBeGreaterThan(30);
    for (const b of w.boards.values()) for (const [spot, c] of Object.entries(b.previous)) {
      expect(['player', 'banker', 'tie', 'playerPair', 'bankerPair']).toContain(spot);
      expect(c % 100).toBe(0);
    }
  });
});

describe('the shoe: cut card, new shoe, series market (simulated table)', () => {
  it('plays a whole shoe: cut event, then shuffle + burn on the next coup; the series market lives one shoe', () => {
    const id = gameSimTableId('bc', 0);
    const w = new World(baccaratModule, { tableId: id, simManaged: true, seed: 9 });
    w.tx((m) => { for (const b of gameSimRoster(id)!.slice(0, 4)) m.join(bot(BOTS.indexOf(b))); });
    expect(g(w).series).toEqual({ shoe: 1, closed: false });
    const created = w.ofKind('marketCreate').find((e) => e.market.kind === 'baccaratBankerShoe')!.market;
    expect(created.marketId).toBe(`${id}__w1__baccaratBankerShoe`);
    expect(created.handNumber).toBeNull();
    expect(created.question.fr).toContain('46 %');
    let guard = 0;
    while (!g(w).shoe.cutOut && guard++ < 2_000) w.expire();
    expect(g(w).shoe.cutOut).toBe(true);
    const sh = g(w).shoe;
    expect(sh.remaining).toBeLessThanOrEqual(16);
    expect(sh.coups).toBeGreaterThan(60);
    expect(g(w).beads).toHaveLength(sh.coups);
    expect(w.pub.events.some((e) => e.type === 'cut')).toBe(true);
    // the series market of shoe 1 was closed at half the shoe and resolved by now
    const s1 = w.ofKind('marketStatus').filter((e) => e.marketId === created.marketId);
    expect(s1.map((e) => e.status)).toEqual(['closed', 'resolved']);
    expect(s1[1].outcome).toBe(100 * sh.banker >= 46 * sh.coups ? 'yes' : 'no');
    expect(g(w).series).toBeNull();
    // next coup: new shoe
    w.until((t) => t.phase === 'betting');
    expect(w.pub.events.map((e) => e.type)).toContain('shuffle');
    expect(g(w).shoe).toMatchObject({ n: 2, remaining: 416, coups: 0, cutOut: false });
    expect(g(w).beads).toEqual([]);
    expect(g(w).series).toEqual({ shoe: 2, closed: false });
    expect(v(w).needsBurn).toBe(true);
    w.until((t) => t.phase === 'live');
    expect(g(w).coup!.burn).not.toBeNull();
  });

  it('fair estimates: exact coup odds, the series from the public shoe counters', () => {
    const m = (kind: MarketDoc['kind'], shoeNumber = 1) => ({ kind, shoeNumber }) as MarketDoc;
    expect(baccaratModule.fairEstimate(m('baccaratBanker'), null)).toBeCloseTo(0.4586, 4);
    expect(baccaratModule.fairEstimate(m('baccaratTie'), null)).toBeCloseTo(0.0952, 4);
    expect(baccaratModule.fairEstimate(m('baccaratPair'), null)).toBeCloseTo(0.1438, 4);
    const w = privateTable(1);
    const t = w.pub as never;
    expect(baccaratModule.fairEstimate(m('baccaratBankerShoe'), t)).toBeCloseTo(shoeYesProbability(0, 0, 416), 9);
    g(w).shoe = { ...g(w).shoe, coups: 70, banker: 40, remaining: 40 };
    expect(baccaratModule.fairEstimate(m('baccaratBankerShoe'), t)).toBe(1);
  });

  it('closing a simulated table resolves a series market whose outcome is certain, voids it otherwise', () => {
    const id = gameSimTableId('bc', 1);
    const w = new World(baccaratModule, { tableId: id, simManaged: true, seed: 2 });
    w.tx((m) => { for (const b of gameSimRoster(id)!.slice(0, 2)) m.join(bot(BOTS.indexOf(b))); });
    w.tx((m) => m.closeTable());
    const st = w.ofKind('marketStatus', w.last).filter((e) => e.marketId.includes('__w'));
    expect(st.map((e) => e.status)).toEqual(['void']);
    expect(w.pub.status).toBe('closed');
  });
});

function interleave(p: string[], b: string[]): string[] {
  const out = [p[0], b[0], p[1], b[1]];
  if (p[2]) out.push(p[2]);
  if (b[2]) out.push(b[2]);
  return out;
}
