/**
 * Load probe of the sim runner: N simulated tables per kernel game played by the test-only
 * modules (coin for roulette / baccarat / craps — bet boards —, duel for hold'em — stacks —, with
 * short timings, i.e. MORE transitions per minute than the real games), optionally with the 8
 * blackjack simulated tables, all driven by one SimRunner. Reports tick duration percentiles.
 * Target (PLAN_SPRINT2.md): tick p95 < 400 ms with 16 simulated tables.
 *
 *   node lib/sim/loadProbe.js [--duration=60000] [--game-tables=2] [--no-blackjack] [--tick=500]
 * Requires the emulators (FIRESTORE_EMULATOR_HOST). In-process only: the module swap never
 * reaches the deployed functions.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { overrideGameModuleForTests } from '../games/registry';
import { coinModule } from '../games/testing/coin';
import { duelModule } from '../games/testing/duel';
import { firestore } from '../shared/admin';
import { GAME_IDS, type GameTableDoc } from '../shared/games/common';
import { refs } from '../shared/paths';
import type { TableDoc } from '../shared/types';
import { gameSimTableIds } from './gameSims';
import { SIM_TABLE_COUNT, simTableId } from './profiles';
import { percentile, SimRunner } from './runner';
import { ensureSeedV2, seed } from './seed';

export interface ProbeResult {
  tables: { blackjack: number; games: number; total: number };
  durationMs: number;
  ticks: number;
  tickP50Ms: number;
  tickP95Ms: number;
  tickP99Ms: number;
  tickMaxMs: number;
  advanced: number;
  botTrades: number;
  errors: number;
  /** Rounds played by the game tables / hands by the blackjack tables during the probe. */
  gameRounds: number;
  blackjackHands: number;
}

export function useTestModules(): () => void {
  overrideGameModuleForTests('roulette', coinModule({ game: 'roulette', bettingMs: 6_000, flipMs: 2_000, settledMs: 2_000 }));
  overrideGameModuleForTests('baccarat', coinModule({ game: 'baccarat', bettingMs: 6_000, flipMs: 2_000, settledMs: 2_000 }));
  overrideGameModuleForTests('craps', coinModule({ game: 'craps', bettingMs: 4_000, flipMs: 1_500, settledMs: 1_500 }));
  overrideGameModuleForTests('holdem', duelModule({ game: 'holdem', settledMs: 2_000 }));
  return () => { for (const g of GAME_IDS) overrideGameModuleForTests(g, null); };
}

async function counters(db: Firestore, gameIds: string[], bjIds: string[]): Promise<{ rounds: number; hands: number }> {
  const r = refs(db);
  const gs = gameIds.length ? await db.getAll(...gameIds.map((id) => r.gameTable(id))) : [];
  const bs = bjIds.length ? await db.getAll(...bjIds.map((id) => r.table(id))) : [];
  return {
    rounds: gs.reduce((a, s) => a + ((s.data() as GameTableDoc | undefined)?.round ?? 0), 0),
    hands: bs.reduce((a, s) => a + ((s.data() as TableDoc | undefined)?.handNumber ?? 0), 0),
  };
}

export async function runLoadProbe(db: Firestore, opts: { durationMs: number; gameTablesPerGame: number; blackjack: boolean; tickMs?: number; warmupMs?: number }): Promise<ProbeResult> {
  const restore = useTestModules();
  try {
    await seed({ historyHands: 3 }); // skipped when already seeded
    await ensureSeedV2(db, { gameTablesPerGame: opts.gameTablesPerGame, historyRounds: 2 });
    const gameIds = gameSimTableIds(opts.gameTablesPerGame);
    const bjIds = opts.blackjack ? Array.from({ length: SIM_TABLE_COUNT }, (_, i) => simTableId(i)) : [];
    const runner = new SimRunner(db, opts.tickMs ?? 500, { gameTablesPerGame: opts.gameTablesPerGame, blackjackSims: opts.blackjack });
    const warmup = opts.warmupMs ?? 3_000;
    const before = await counters(db, gameIds, bjIds);
    const t0 = Date.now();
    const stats = await runner.run(opts.durationMs + warmup);
    const after = await counters(db, gameIds, bjIds);
    const skip = Math.min(runner.tickDurations.length, Math.round(warmup / (opts.tickMs ?? 500)));
    const d = runner.tickDurations.slice(skip);
    return {
      tables: { blackjack: bjIds.length, games: gameIds.length, total: bjIds.length + gameIds.length },
      durationMs: Date.now() - t0, ticks: d.length,
      tickP50Ms: percentile(d, 50), tickP95Ms: percentile(d, 95), tickP99Ms: percentile(d, 99), tickMaxMs: d.length ? Math.max(...d) : 0,
      advanced: stats.advanced, botTrades: stats.trades, errors: stats.errors,
      gameRounds: after.rounds - before.rounds, blackjackHands: after.hands - before.hands,
    };
  } finally {
    restore();
  }
}

if (require.main === module) {
  const arg = (k: string) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split('=')[1];
  runLoadProbe(firestore(), {
    durationMs: Number(arg('duration') ?? 60_000),
    gameTablesPerGame: Number(arg('game-tables') ?? 2),
    blackjack: !process.argv.includes('--no-blackjack'),
    tickMs: Number(arg('tick') ?? 500),
  }).then((r) => {
    console.log(JSON.stringify(r, null, 1));
    process.exit(r.errors === 0 ? 0 : 1);
  }).catch((e) => {
    console.error('load probe failed:', (e as Error).message);
    process.exit(1);
  });
}
