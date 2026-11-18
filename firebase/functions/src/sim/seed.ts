/**
 * Seed script: ~60 bot profiles with realistic stats, leaderboard (global + weekly), bot
 * friendships, usernames, and the 8 permanent simulated tables with a short played history
 * (hand histories with fairness proofs, resolved markets, "recent wins" feed).
 *
 *   node lib/sim/seed.js [--force]
 * Requires FIRESTORE_EMULATOR_HOST (tools/seed.ps1 sets it). Skips if already seeded unless --force.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { fastRng, nextFloat } from '../engine/rng';
import { firestore } from '../shared/admin';
import { refs } from '../shared/paths';
import { weekId } from '../shared/time';
import type { FriendshipDoc, ProfileDoc } from '../shared/types';
import { TIMING } from '../shared/types';
import { TableTx } from '../table/service';
import { BOTS, SIM_TABLE_COUNT, SIM_TABLE_NAMES, SIM_TABLE_TIERS, simRoster, simTableId } from './profiles';

function botProfile(i: number, now: number): ProfileDoc {
  const b = BOTS[i];
  const rng = fastRng(b.seed);
  const handsPlayed = 150 + Math.round(b.rankPoints / 2.5) + rng.nextInt(400);
  const winRate = 0.40 + nextFloat(rng) * 0.06;
  const handsWon = Math.round(handsPlayed * winRate);
  const handsPushed = Math.round(handsPlayed * (0.07 + nextFloat(rng) * 0.03));
  const blackjacks = Math.round(handsPlayed * (0.042 + nextFloat(rng) * 0.01));
  const unit = b.stakeTier === 'low' ? 500 : b.stakeTier === 'mid' ? 2_500 : 10_000;
  const netCents = Math.round((nextFloat(rng) - 0.55) * unit * Math.sqrt(handsPlayed) * 3 / 100) * 100;
  return {
    uid: b.uid, username: b.username, usernameLower: b.username.toLowerCase(), avatar: b.avatar, isBot: true,
    rankPoints: b.rankPoints, rankTier: b.rankTier,
    weeklyPoints: Math.round(b.rankPoints * (0.02 + nextFloat(rng) * 0.08)), weekId: weekId(now),
    stats: {
      handsPlayed, handsWon, handsLost: handsPlayed - handsWon - handsPushed, handsPushed, blackjacks, netCents,
      biggestWinCents: unit * (2 + rng.nextInt(8)),
    },
    currentTableId: null, lastSeenAtMs: now - rng.nextInt(3 * 86_400_000), kycVerified: true,
    createdAtMs: now - (30 + rng.nextInt(300)) * 86_400_000,
  };
}

export async function seed(opts: { force?: boolean; historyHands?: number } = {}): Promise<{ skipped: boolean; bots: number; tables: number }> {
  const db = firestore();
  const r = refs(db);
  const now = Date.now();
  if (!opts.force && (await r.profile(BOTS[0].uid).get()).exists) {
    return { skipped: true, bots: 0, tables: 0 };
  }

  // 1. bot profiles + usernames
  let batch = db.batch();
  let n = 0;
  const flush = async () => { if (n > 0) { await batch.commit(); batch = db.batch(); n = 0; } };
  for (let i = 0; i < BOTS.length; i++) {
    const p = botProfile(i, now);
    batch.set(r.profile(p.uid), p);
    batch.set(r.username(p.usernameLower), { uid: p.uid });
    n += 2;
    if (n >= 400) await flush();
  }
  // 2. bot friendships (each bot with the next 3 bots, ring)
  for (let i = 0; i < BOTS.length; i++) {
    for (let k = 1; k <= 3; k++) {
      const a = BOTS[i];
      const b = BOTS[(i + k * 7) % BOTS.length];
      if (a.uid === b.uid) continue;
      const f: FriendshipDoc = { uids: [a.uid, b.uid].sort() as [string, string], usernames: { [a.uid]: a.username, [b.uid]: b.username }, sinceMs: now - (k + i) * 3_600_000 };
      batch.set(r.friendship(a.uid, b.uid), f);
      n++;
      if (n >= 400) await flush();
    }
  }
  await flush();

  // 3. simulated tables with a short history played in fast-forward
  for (let t = 0; t < SIM_TABLE_COUNT; t++) await createSimTable(db, t, opts.historyHands ?? 10);
  return { skipped: false, bots: BOTS.length, tables: SIM_TABLE_COUNT };
}

/** (Re)creates simulated table `t` (0-based), plays `historyHands` hands in fast-forward, seats 3–4 bots. */
export async function createSimTable(db: Firestore, t: number, historyHands: number): Promise<void> {
  const r = refs(db);
  const now = Date.now();
  const tableId = simTableId(t);
  await db.runTransaction(async (tx) => {
    const start = now - historyHands * 40_000;
    const roster = simRoster(t);
    const tt = await TableTx.create(db, tx, {
      tableId, name: SIM_TABLE_NAMES[t], stakeTier: SIM_TABLE_TIERS[t], isPrivate: false, simManaged: true, rankTier: roster[0].rankTier,
    }, start, { uids: roster.map((b) => b.uid) });
    const m = tt.machine;
    for (const b of roster.slice(0, 3 + (t % 2))) m.join({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true });
    let settled = 0;
    for (let guard = 0; guard < 5_000 && settled < historyHands; guard++) {
      if (m.pub.deadlineMs === null) break;
      const next = m.pub.deadlineMs;
      if (next > now) break;
      m.now = next;
      const wasSettled = m.pub.phase === 'settled';
      m.advance();
      if (!wasSettled && m.pub.phase === 'settled') settled++;
    }
    m.now = now;
    if (m.pub.deadlineMs !== null && m.pub.deadlineMs < now) m.pub.deadlineMs = now + TIMING.botMaxMs;
    tt.commit(tx);
  });
  const snap = await r.table(tableId).get();
  const seated = (snap.get('seatedUids') as string[]) ?? [];
  const b2 = db.batch();
  for (const uid of seated) b2.set(r.profile(uid), { currentTableId: tableId, lastSeenAtMs: now }, { merge: true });
  await b2.commit();
}

if (require.main === module) {
  const force = process.argv.includes('--force');
  seed({ force })
    .then((res) => {
      console.log(res.skipped ? 'seed: already seeded (use --force to overwrite)' : `seed: ${res.bots} bots, ${res.tables} simulated tables`);
      process.exit(0);
    })
    .catch((e) => {
      console.error('seed failed:', (e as Error).message);
      process.exit(1);
    });
}
