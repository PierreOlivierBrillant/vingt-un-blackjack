/**
 * Simulated tables of the kernel-driven games: `<prefix>-sim-NN` (rl-sim-01, bc-sim-02…), N per
 * available game (default 2; `SIM_GAME_TABLES` env var or the runner's `--game-tables=` argument,
 * 0..8, for the classroom capacity). Each has a fixed bot roster (sim/profiles gameSimRoster),
 * `simManaged: true` (never closes, bots come and go, long markets allowed) and a short history
 * played in fast-forward when created. Games whose module is a stub get no table.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { GameTableTx } from '../games/kernel/tx';
import { availableGames } from '../games/registry';
import { GAME_PREFIX, GAME_TIMING, type GameId, type GameTableDoc } from '../shared/games/common';
import { refs } from '../shared/paths';
import type { StakeTier } from '../shared/types';
import { gameSimRoster, gameSimTableId } from './profiles';

export const GAME_SIM_TABLES_DEFAULT = 2;
export const GAME_SIM_TABLES_MAX = 8;

/** Tables per game from SIM_GAME_TABLES (default 2, clamped to 0..8). */
export function gameSimTablesPerGame(raw = process.env.SIM_GAME_TABLES): number {
  const n = raw === undefined || raw === '' ? GAME_SIM_TABLES_DEFAULT : Number(raw);
  return Number.isInteger(n) ? Math.min(GAME_SIM_TABLES_MAX, Math.max(0, n)) : GAME_SIM_TABLES_DEFAULT;
}

const NAMES: Record<GameId, string[]> = {
  roulette: ['Monte-Carlo Rouge', 'Riviera Noire', 'Belle Époque', 'Zéro d’Or', 'Cylindre Bleu', 'Les Voisins', 'Tiers du Cylindre', 'Orphelins'],
  baccarat: ['Salon Punto', 'Macao Banco', 'Le Sabot d’Argent', 'Salle Privée', 'Grand Baccara', 'Dragon Rouge', 'Lotus', 'Jade Room'],
  holdem: ['River Club', 'Le Flop', 'All-In Lounge', 'Pocket Aces', 'Le Bouton', 'Turn & River', 'Big Blind', 'Royal Flush'],
  craps: ['Les Dés Fous', 'Seven Out', 'Hard Eight', 'Le Point', 'Snake Eyes', 'Boxcars', 'Come Out', 'Field Day'],
};
const TIERS: StakeTier[] = ['low', 'mid', 'low', 'mid', 'high', 'low', 'mid', 'high'];

export function gameSimTableIds(perGame: number, games: readonly GameId[] = availableGames()): string[] {
  const out: string[] = [];
  for (const g of games) for (let n = 0; n < perGame; n++) out.push(gameSimTableId(GAME_PREFIX[g], n));
  return out;
}

/** (Re)creates sim table `n` (0-based) of `game`, plays `historyRounds` rounds in fast-forward, seats 3–4 bots. */
export async function createGameSimTable(db: Firestore, game: GameId, n: number, historyRounds: number): Promise<void> {
  const r = refs(db);
  const now = Date.now();
  const tableId = gameSimTableId(GAME_PREFIX[game], n);
  const roster = gameSimRoster(tableId)!;
  let gt: GameTableTx | null = null;
  await db.runTransaction(async (tx) => {
    const start = now - historyRounds * 40_000;
    gt = await GameTableTx.create(db, tx, game, {
      tableId, name: NAMES[game][n % NAMES[game].length] + (n >= NAMES[game].length ? ` ${n + 1}` : ''),
      stakeTier: TIERS[n % TIERS.length], isPrivate: false, simManaged: true, rankTier: roster[0].rankTier,
    }, start, { uids: roster.map((b) => b.uid) });
    const m = gt.machine;
    for (const b of roster.slice(0, 3 + (n % 2))) m.join({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true });
    let settled = 0;
    for (let guard = 0; guard < 5_000 && settled < historyRounds; guard++) {
      const next = m.pub.deadlineMs;
      if (next === null || next > now) break;
      m.now = Math.max(m.now, next);
      const wasSettled = m.pub.phase === 'settled';
      m.advance();
      if (!wasSettled && m.pub.phase === 'settled') settled++;
    }
    m.now = now;
    if (m.pub.deadlineMs !== null && m.pub.deadlineMs < now) m.pub.deadlineMs = now + GAME_TIMING.botMaxMs;
    gt.commit(tx);
  });
  if (gt) await (gt as GameTableTx).afterCommit();
  const snap = await r.gameTable(tableId).get();
  const seated = (snap.get('seatedUids') as string[]) ?? [];
  const b2 = db.batch();
  for (const uid of seated) b2.set(r.profile(uid), { currentTableId: tableId, lastSeenAtMs: now }, { merge: true });
  await b2.commit();
}

/** Creates the missing (or closed) sim tables of every available game. Idempotent. Returns the ids created. */
export async function ensureGameSimTables(db: Firestore, perGame = gameSimTablesPerGame(), historyRounds = 3): Promise<string[]> {
  const ids = gameSimTableIds(perGame);
  if (ids.length === 0) return [];
  const snaps = await db.getAll(...ids.map((id) => refs(db).gameTable(id)));
  const created: string[] = [];
  for (const s of snaps) {
    const t = s.data() as GameTableDoc | undefined;
    if (t && t.status === 'open') continue;
    const prefix = s.id.slice(0, 2);
    const game = (Object.keys(GAME_PREFIX) as GameId[]).find((g) => GAME_PREFIX[g] === prefix)!;
    await createGameSimTable(db, game, Number(s.id.slice(-2)) - 1, historyRounds);
    created.push(s.id);
  }
  return created;
}
