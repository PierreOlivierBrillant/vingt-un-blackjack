/**
 * Golden transcripts of the baccarat module at fixed seeds (round seeds = sha256("seed-<n>-<k>"),
 * bots driven by fastRng): coups, burn, totals, events, markets, nets. Versioned in
 * test/golden/baccarat-*.json — any behavioural change of the engine or the module shows up as a
 * diff. Regenerate deliberately with `npx vitest run --config vitest.unit.config.mts test/unit/baccarat/golden.test.ts -u`.
 */
import { describe, expect, it } from 'vitest';
import { verifyFairness } from '../../../src/engine';
import { baccaratModule } from '../../../src/games/baccarat/module';
import type { BaccaratPublic } from '../../../src/shared/games/baccarat';
import { BOTS, gameSimRoster, gameSimTableId } from '../../../src/sim/profiles';
import { bot, human, World } from '../kernel/harness';

const BOARDS = [
  { h1: { banker: 1_000 }, h2: { player: 500, tie: 100 } },
  { h1: { banker: 2_000, bankerPair: 100 }, h2: { player: 500, playerPair: 100 } },
  { h1: { player: 300 }, h2: { banker: 700, tie: 200 } },
];

function transcript(w: World, coups: number, boards: boolean) {
  const out: unknown[] = [];
  for (let n = 0; n < coups; n++) {
    while (w.pub.phase !== 'betting') w.expire();
    if (boards) for (const [uid, b] of Object.entries(BOARDS[n % BOARDS.length])) w.setBets(uid, b);
    const bets = [...w.boards.values()].filter((b) => b.round === w.pub.round && b.totalCents > 0).map((b) => [b.seatIndex, b.bets]);
    const commit = w.pub.fairness.currentCommit;
    w.expire();
    const deal = w.last;
    const g = w.pub.g as unknown as BaccaratPublic;
    const events = w.pub.events.filter((e) => !['join', 'leave'].includes(e.type)).map((e) => [e.type, ...Object.values(e.d ?? {})]);
    const markets = w.ofKind('marketStatus', deal).filter((e) => e.status !== 'closed').map((e) => [e.marketId.split('__').pop(), e.status, e.outcome]);
    w.expire();
    const doc = w.ofKind('history', w.last)[0].doc;
    expect(verifyFairness({ commit: doc.fairness.commit, seed: doc.fairness.seed, remainingBefore: doc.fairness.remainingBefore!, dealt: doc.fairness.dealt!, decks: 8 })).toBe(true);
    out.push({
      round: doc.round,
      commit,
      bets,
      coup: g.coup,
      shoe: { n: g.shoe.n, remaining: g.shoe.remaining, coups: g.shoe.coups },
      events,
      markets,
      nets: doc.seats.map((s) => [s.seatIndex, s.netCents]),
    });
  }
  return out;
}

describe('baccarat golden transcripts (fixed seeds)', () => {
  it('private table, two humans, fixed boards', async () => {
    const w = new World(baccaratModule, { tableId: 'bc-golden', isPrivate: true, seed: 21 });
    for (const i of [1, 2]) {
      w.fund(`h${i}`, 1_000_000);
      w.tx((m) => m.join(human(i)));
    }
    const t = transcript(w, 15, true);
    await expect(JSON.stringify(t, null, 1) + '\n').toMatchFileSnapshot('../../golden/baccarat-private.json');
  });

  it('simulated table, bots only (their boards, the series market)', async () => {
    const id = gameSimTableId('bc', 1);
    const w = new World(baccaratModule, { tableId: id, simManaged: true, seed: 22 });
    w.tx((m) => { for (const b of gameSimRoster(id)!.slice(0, 4)) m.join(bot(BOTS.indexOf(b))); });
    const t = transcript(w, 10, false);
    await expect(JSON.stringify(t, null, 1) + '\n').toMatchFileSnapshot('../../golden/baccarat-sim.json');
  });
});
