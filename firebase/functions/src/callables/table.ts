/** Matchmaking and table actions. Each runs the table's overdue transitions first. */
import { randomInt } from 'node:crypto';
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { cryptoRng } from '../engine/rng';
import { fail } from '../shared/errors';
import { refs } from '../shared/paths';
import { gameOfTableId } from '../shared/games/common';
import type { InventoryDoc, ProfileDoc, StakeTier, TableDoc } from '../shared/types';
import { currentLocation } from '../games/location';
import { applyOverdueAny } from '../games/overdue';
import { pickFreeBots } from '../table/machine';
import type { PlayerInfo } from '../table/model';
import { TableTx } from '../table/service';
import { defineCallable, setOverdueHook } from './framework';
import { S } from './schemas';

// One hook for every callable and both collections (blackjack ids → tables, rl-/bc-/ho-/cr- → gameTables).
setOverdueHook(async (db, tableId, now) => {
  await applyOverdueAny(db, tableId, now);
});

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** 6-char private table code (shared by blackjack and the kernel games: one tableCodes collection). */
export function newTableCode(): string {
  let s = '';
  for (let i = 0; i < 6; i++) s += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return s;
}

export async function requireProfile(db: Firestore, tx: Transaction, uid: string): Promise<ProfileDoc> {
  const p = await tx.get(refs(db).profile(uid));
  if (!p.exists) throw fail.pre('PROFILE_REQUIRED');
  return p.data() as ProfileDoc;
}

export function playerInfo(p: ProfileDoc): PlayerInfo {
  return { uid: p.uid, username: p.username, avatar: p.avatar, rankTier: p.rankTier, isBot: false };
}

/** Matchmaking score: humans of the same rank tier > humans > bots only. Higher is better. */
function score(t: TableDoc, tier: ProfileDoc['rankTier']): number {
  const sameTier = t.seats.some((s) => s && !s.isBot && s.rankTier === tier);
  const free = t.seats.filter((s) => s === null).length;
  const base = t.humanCount > 0 ? (sameTier ? 300 : 200) : 100;
  return base + t.humanCount * 10 + (free > 0 ? 5 : 0) - t.queue.length;
}

function roomFor(t: TableDoc): boolean {
  if (t.status !== 'open') return false;
  const free = t.seats.some((s) => s === null);
  return free || (!t.isPrivate && t.botCount > t.queue.length);
}

export const joinMatchmaking = defineCallable({
  name: 'joinMatchmaking',
  schema: S.joinMatchmaking,
  handler: async (tx, data, { db, uid, now }) => {
    const r = refs(db);
    const profile = await requireProfile(db, tx, uid);
    const me = playerInfo(profile);

    // already somewhere (blackjack or any other game: one location per user)?
    const loc = await currentLocation(db, tx, profile);
    if (loc) {
      if (data.mode === 'quick' && loc.game === 'blackjack' && loc.stakeTier === data.stakeTier && !loc.isPrivate) {
        return { response: { tableId: loc.tableId, status: loc.status, seatIndex: loc.seatIndex, code: null } };
      }
      throw fail.pre('ALREADY_SEATED');
    }

    if (data.mode === 'joinCode') {
      if (!data.code) throw fail.invalid('INVALID_ARGUMENT', 'code required');
      const code = data.code.toUpperCase();
      const cs = await tx.get(r.tableCode(code));
      if (!cs.exists) throw fail.notFound('BAD_CODE');
      // Codes of the other games' tables are joined with gameJoin (hold'em needs a buy-in).
      if (gameOfTableId(cs.get('tableId') as string) !== 'blackjack') throw fail.invalid('WRONG_GAME');
      const tt = await TableTx.load(db, tx, cs.get('tableId') as string, now, { uids: [uid] });
      tt.machine.advance();
      if (tt.pub.status !== 'open') throw fail.pre('TABLE_CLOSED');
      const res = tt.machine.join(me);
      tt.commit(tx);
      return { response: { tableId: tt.pub.tableId, status: res.status, seatIndex: res.seatIndex, code }, after: () => tt.afterCommit() };
    }

    if (data.mode === 'createPrivate') {
      let code = newTableCode();
      for (let i = 0; i < 5 && (await tx.get(r.tableCode(code))).exists; i++) code = newTableCode();
      const tableId = db.collection('tables').doc().id;
      const tt = await TableTx.create(db, tx, {
        // The join code stays secret: table names are public (lobby, market questions).
        tableId, name: `Privée ${tableId.slice(0, 4).toUpperCase()}`, stakeTier: data.stakeTier, isPrivate: true, simManaged: false, rankTier: profile.rankTier,
      }, now, { uids: [uid] });
      const res = tt.machine.join(me);
      tt.commit(tx, () => tx.set(r.tableCode(code), { tableId, game: 'blackjack', createdAtMs: now }));
      return { response: { tableId, status: res.status, seatIndex: res.seatIndex, code } };
    }

    // quick: best public table of the stake tier (non-transactional scan, then transactional re-check)
    const scan = await db.collection('tables')
      .where('status', '==', 'open').where('isPrivate', '==', false).where('stakeTier', '==', data.stakeTier)
      .limit(50).get();
    const candidates = scan.docs.map((d) => d.data() as TableDoc).filter(roomFor)
      .sort((a, b) => score(b, profile.rankTier) - score(a, profile.rankTier));
    for (const c of candidates.slice(0, 3)) {
      const tt = await TableTx.load(db, tx, c.tableId, now, { uids: [uid] });
      tt.machine.advance();
      if (!tt.machine.hasRoomForHuman()) continue;
      const res = tt.machine.join(me);
      tt.commit(tx);
      return { response: { tableId: tt.pub.tableId, status: res.status, seatIndex: res.seatIndex, code: null }, after: () => tt.afterCommit() };
    }
    // nothing suitable: new public table, 2 bots to complete
    const tableId = db.collection('tables').doc().id;
    const tt = await TableTx.create(db, tx, {
      tableId, name: `Table ${tableId.slice(0, 4).toUpperCase()}`, stakeTier: data.stakeTier as StakeTier, isPrivate: false,
      simManaged: false, rankTier: profile.rankTier,
    }, now, { uids: [uid] });
    for (const b of pickFreeBots(cryptoRng(), 2)) tt.machine.join(b);
    const res = tt.machine.join(me);
    tt.commit(tx);
    return { response: { tableId, status: res.status, seatIndex: res.seatIndex, code: null } };
  },
});

export const leaveTable = defineCallable({
  name: 'leaveTable',
  schema: S.leaveTable,
  tableIdOf: (d) => d.tableId,
  handler: async (tx, data, { db, uid, now }) => {
    const tt = await TableTx.load(db, tx, data.tableId, now, { uids: [uid] });
    tt.machine.advance();
    const refundedCents = tt.machine.leave(uid);
    tt.commit(tx);
    return { response: { left: true as const, refundedCents }, after: () => tt.afterCommit() };
  },
});

export const placeBet = defineCallable({
  name: 'placeBet',
  schema: S.placeBet,
  tableIdOf: (d) => d.tableId,
  handler: async (tx, data, { db, uid, now }) => {
    const tt = await TableTx.load(db, tx, data.tableId, now, { uids: [uid] });
    tt.machine.advance();
    const hand = tt.pub.handNumber;
    // Validate phase/seat/range first; if the debit then fails the whole transaction aborts.
    tt.machine.placeBet(uid, data.handNumber, data.amountCents);
    const w = tt.wallet(uid);
    w.debit(data.amountCents, 'bet', { tableId: data.tableId, handNumber: hand });
    tt.commit(tx);
    return { response: { betCents: data.amountCents, balanceCents: w.balance, phase: tt.pub.phase }, after: () => tt.afterCommit() };
  },
});

export const act = defineCallable({
  name: 'act',
  schema: S.act,
  tableIdOf: (d) => d.tableId,
  handler: async (tx, data, { db, uid, now }) => {
    const tt = await TableTx.load(db, tx, data.tableId, now, {
      uids: [uid], inventory: data.power ? { uid, powerId: data.power } : null,
    });
    tt.machine.advance();
    if (data.power && tt.inventoryQty < 1) throw fail.pre('POWER_NOT_OWNED');
    const w = tt.wallet(uid);
    const hand = tt.pub.handNumber;
    const { costCents, ledgerType } = tt.machine.act(uid, data);
    if (costCents > 0) w.debit(costCents, ledgerType ?? 'bet', { tableId: data.tableId, handNumber: hand });
    tt.commit(tx, () => {
      if (data.power) {
        const inv: InventoryDoc = { powerId: data.power, quantity: tt.inventoryQty - 1, updatedAtMs: now };
        tx.set(refs(db).inventory(uid, data.power), inv);
      }
    });
    return { response: { phase: tt.pub.phase, balanceCents: w.balance }, after: () => tt.afterCommit() };
  },
});

export const pokeTable = defineCallable({
  name: 'pokeTable',
  schema: S.pokeTable,
  tableIdOf: () => null, // the handler itself advances the table and reports it
  handler: async (tx, data, { db, now }) => {
    const tt = await TableTx.load(db, tx, data.tableId, now);
    const advanced = tt.machine.advance();
    if (advanced) tt.commit(tx);
    return {
      response: { phase: tt.pub.phase, handNumber: tt.pub.handNumber, deadlineMs: tt.pub.deadlineMs, advanced },
      after: () => tt.afterCommit(),
    };
  },
});
