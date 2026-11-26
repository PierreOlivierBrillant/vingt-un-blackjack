/** 120 bots: the 60 Sprint 1 bots unchanged, disjoint rosters for the simulated tables, free pool. */
import { describe, expect, it } from 'vitest';
import { GAME_PREFIX, GAME_IDS } from '../../../src/shared/games/common';
import { gameSimTableIds, gameSimTablesPerGame } from '../../../src/sim/gameSims';
import {
  BOTS, BOTS_V1, FREE_BOTS, GAME_SIM_ROSTERS, gameSimRoster, gameSimTableId, SIM_TABLE_COUNT, simRoster,
} from '../../../src/sim/profiles';
import { friendshipsOf } from '../../../src/sim/seed';

describe('bots', () => {
  it('120 unique bots; the first 60 are exactly the Sprint 1 ones', () => {
    expect(BOTS).toHaveLength(120);
    expect(BOTS.slice(0, 60)).toEqual(BOTS_V1);
    // Sprint 1 identities pinned (uid, name, personality seed)
    expect([BOTS[0].uid, BOTS[0].username, BOTS[59].uid, BOTS[59].username]).toEqual(['bot_001', 'LuckyLuc', 'bot_060', 'OscarOnTilt']);
    expect(new Set(BOTS.map((b) => b.uid)).size).toBe(120);
    expect(new Set(BOTS.map((b) => b.username.toLowerCase())).size).toBe(120);
    for (const b of BOTS) expect(b.username).toMatch(/^[A-Za-z0-9_]{3,16}$/);
    expect(BOTS[119].uid).toBe('bot_120');
  });

  it('blackjack rosters, game rosters and the free pool never overlap', () => {
    const bj = Array.from({ length: SIM_TABLE_COUNT }, (_, i) => simRoster(i)).flat().map((b) => b.uid);
    const games = GAME_IDS.flatMap((g) => [0, 1].map((n) => gameSimRoster(gameSimTableId(GAME_PREFIX[g], n))!)).flat().map((b) => b.uid);
    const free = FREE_BOTS.map((b) => b.uid);
    expect(games).toHaveLength(GAME_SIM_ROSTERS * 6);
    expect(new Set([...bj, ...games, ...free]).size).toBe(120);
    expect(free).toHaveLength(24);
    expect(gameSimRoster('sim-01')).toBeNull();
    expect(gameSimRoster('rl-abcdef')).toBeNull();
    // a 3rd table of a game reuses a roster (configurable table count)
    expect(gameSimRoster('rl-sim-03')!.length).toBe(6);
  });

  it('sim table ids and count setting', () => {
    expect(gameSimTableIds(2, ['roulette', 'craps'])).toEqual(['rl-sim-01', 'rl-sim-02', 'cr-sim-01', 'cr-sim-02']);
    expect(gameSimTablesPerGame(undefined)).toBe(2);
    expect(gameSimTablesPerGame('0')).toBe(0);
    expect(gameSimTablesPerGame('99')).toBe(8);
    expect(gameSimTablesPerGame('x')).toBe(2);
  });

  it('Sprint 1 bots keep their friendships; new bots get a ring of their own', () => {
    const now = 1_000;
    const v1 = friendshipsOf(0, now).map((f) => f.uids.join('_'));
    expect(v1).toEqual([['bot_001', 'bot_008'], ['bot_001', 'bot_015'], ['bot_001', 'bot_022']].map((p) => p.join('_')));
    for (const f of friendshipsOf(70, now)) for (const u of f.uids) expect(Number(u.slice(4))).toBeGreaterThan(60);
  });
});
