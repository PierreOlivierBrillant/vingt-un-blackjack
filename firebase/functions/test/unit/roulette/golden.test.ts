/**
 * Golden transcript of the roulette at a fixed seed: a simulated table (bots + two humans with
 * fixed boards, one of them using the zero shield) played through the real kernel for 25 spins.
 * The seeds (provably-fair DRBG) fix the numbers, the table rng fixes the bots: the full JSON
 * transcript is versioned in test/golden/roulette-transcript.json, so any behavioural change of
 * the engine, the module or the bots shows up as a diff. Regenerate deliberately with
 * `npx vitest run --config vitest.unit.config.mts test/unit/roulette/golden.test.ts -u` and review it.
 */
import { describe, expect, it } from 'vitest';
import { seededRng, sha256Hex } from '../../../src/engine';
import { rouletteModule } from '../../../src/games/roulette/module';
import type { BetMap } from '../../../src/shared/games/common';
import type { RoulettePublic } from '../../../src/shared/games/roulette';
import { gameSimRoster } from '../../../src/sim/profiles';
import { human, World } from '../kernel/harness';

const HUMAN_BOARDS: Record<string, BetMap[]> = {
  h1: [{ red: 1_000, n17: 100, 'sp0-3': 100 }, { dozen3: 500, col1: 500, even: 300 }, { first4: 200, low: 800 }],
  h2: [{ black: 2_000, n0: 100 }, { 'tr0-2-3': 300, ln31: 400, odd: 700 }],
};

function transcript() {
  const tableId = 'rl-sim-01';
  const w = new World(rouletteModule, { tableId, simManaged: true, stakeTier: 'low', seed: 2026 });
  const roster = gameSimRoster(tableId)!;
  w.tx((m) => { for (const b of roster.slice(0, 3)) m.join({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true }); });
  for (const uid of ['h1', 'h2']) {
    w.fund(uid, 1_000_000);
    w.inventory.set(`${uid}:zeroShield`, 99);
    w.tx((m) => m.join(human(Number(uid.slice(1)))));
  }
  const out: unknown[] = [];
  for (let spin = 1; spin <= 25; spin++) {
    w.until((t) => t.phase === 'betting');
    const round = w.pub.round;
    for (const [uid, boards] of Object.entries(HUMAN_BOARDS)) {
      if (!w.seat(uid)) continue;
      w.setBets(uid, boards[round % boards.length], uid === 'h1' && round % 4 === 0 ? 'zeroShield' : undefined);
    }
    const seed = w.priv.seed!;
    const commit = w.pub.fairness.currentCommit;
    w.until((t) => t.phase === 'live');
    const g = w.pub.g as unknown as RoulettePublic;
    expect(g.number).toBe(seededRng(seed).nextInt(37));
    expect(sha256Hex(seed)).toBe(commit);
    const boards = Object.fromEntries([...w.boards.values()].filter((b) => b.totalCents > 0).map((b) => [`seat${b.seatIndex}`, b.bets]));
    const markets = w.ofKind('marketStatus', w.last).map((e) => `${e.marketId.split('__').at(-1)}:${e.status}${e.outcome ? `:${e.outcome}` : ''}`);
    w.until((t) => t.phase === 'settled');
    const settle = w.ofKind('settle', w.last)[0];
    out.push({
      round, commit, seed, number: g.number, boards, markets,
      rows: settle.rows.map((r) => [r.seatIndex, r.isBot ? 'bot' : r.uid, r.stakedCents, r.returnCents, r.netCents, r.outcome, r.highlight, r.counters]),
      events: w.pub.events.filter((e) => !['join', 'leave'].includes(e.type)).map((e) => [e.type, e.seatIndex, e.d]),
      last: g.last.slice(-5),
      series: g.series,
    });
  }
  return { tableId, wallets: Object.fromEntries([...w.wallets]), rounds: out };
}

describe('roulette golden transcript', () => {
  it('25 spins at a fixed seed match test/golden/roulette-transcript.json', async () => {
    const t = transcript();
    expect(t.rounds).toHaveLength(25);
    await expect(JSON.stringify(t, null, 1) + '\n').toMatchFileSnapshot('../../golden/roulette-transcript.json');
  });
});
