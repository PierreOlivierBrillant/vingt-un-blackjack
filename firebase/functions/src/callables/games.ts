/**
 * Callables of the kernel-driven games (roulette, baccarat, hold'em, craps — shared/games/common.ts):
 * gameJoin, gameLeave, gameAction, gamePoke. The game itself is the table's GameModule
 * (src/games/registry.ts); this file never depends on a particular game.
 *
 *  - gameAction `setBets` is the FAST PATH: it reads the table, the caller's board, wallet (and
 *    inventory when a power is sent) and writes only `bets/{uid}` + the wallet (+ inventory), never
 *    the table document, so several players betting at once do not contend (see kernel/bets.ts).
 *  - every other gameAction runs the full table transaction (overdue deadlines applied first, in
 *    the same transaction: `tableIdOf: () => null`, no separate pre-pass).
 */
import type { Firestore } from 'firebase-admin/firestore';
import { cryptoRng } from '../engine/rng';
import { planSetBets } from '../games/kernel/bets';
import type { GameAction } from '../games/kernel/module';
import { GameTableTx } from '../games/kernel/tx';
import { currentLocation } from '../games/location';
import { applyOverdueAny } from '../games/overdue';
import { gameModule } from '../games/registry';
import { fail } from '../shared/errors';
import { GAME_PREFIX, gameOfTableId, type GameBetDoc, type GameId, type GameTableDoc } from '../shared/games/common';
import { refs } from '../shared/paths';
import type { InventoryDoc, ProfileDoc, StakeTier } from '../shared/types';
import { WalletSession } from '../shared/wallet';
import { pickFreeBots } from '../table/machine';
import { TableTx } from '../table/service';
import { defineCallable, setOverdueHook } from './framework';
import { actionTypeSchema, kernelActionSchemas, S } from './schemas';
import { newTableCode, playerInfo, requireProfile } from './table';

setOverdueHook(async (db, tableId, now) => {
  await applyOverdueAny(db, tableId, now);
});

/** Display name of a new public table of a game (language-neutral). */
const GAME_TABLE_LABEL: Record<GameId, string> = { roulette: 'Roulette', baccarat: 'Baccarat', holdem: "Hold'em", craps: 'Craps' };

function newGameTableId(db: Firestore, game: GameId): string {
  return `${GAME_PREFIX[game]}-${db.collection('gameTables').doc().id}`;
}

/** Matchmaking score: humans of the same rank tier > humans > bots only. Higher is better. */
function score(t: GameTableDoc, tier: ProfileDoc['rankTier']): number {
  const sameTier = t.seats.some((s) => s && !s.isBot && s.rankTier === tier);
  const free = t.seats.filter((s) => s === null).length;
  const base = t.humanCount > 0 ? (sameTier ? 300 : 200) : 100;
  return base + t.humanCount * 10 + (free > 0 ? 5 : 0) - t.queue.length;
}

function roomFor(t: GameTableDoc): boolean {
  if (t.status !== 'open') return false;
  return t.seats.some((s) => s === null) || (!t.isPrivate && t.botCount > t.queue.length);
}

export const gameJoin = defineCallable({
  name: 'gameJoin',
  schema: S.gameJoin,
  handler: async (tx, data, { db, uid, now }) => {
    const r = refs(db);
    const profile = await requireProfile(db, tx, uid);
    const me = playerInfo(profile);

    // One location per user across all games.
    const loc = await currentLocation(db, tx, profile);
    if (loc) {
      if (data.mode === 'quick' && loc.game === data.game && loc.stakeTier === data.stakeTier && !loc.isPrivate) {
        return { response: { tableId: loc.tableId, game: loc.game, status: loc.status, seatIndex: loc.seatIndex, code: null } };
      }
      throw fail.pre('ALREADY_SEATED');
    }

    if (data.mode === 'joinCode') {
      if (!data.code) throw fail.invalid('INVALID_ARGUMENT', 'code required');
      const code = data.code.toUpperCase();
      const cs = await tx.get(r.tableCode(code));
      if (!cs.exists) throw fail.notFound('BAD_CODE');
      const tableId = cs.get('tableId') as string;
      const game = gameOfTableId(tableId);
      if (game === 'blackjack') {
        const tt = await TableTx.load(db, tx, tableId, now, { uids: [uid] });
        tt.machine.advance();
        if (tt.pub.status !== 'open') throw fail.pre('TABLE_CLOSED');
        const res = tt.machine.join(me);
        tt.commit(tx);
        return { response: { tableId, game, status: res.status, seatIndex: res.seatIndex, code }, after: () => tt.afterCommit() };
      }
      const gt = await GameTableTx.load(db, tx, tableId, now, { uids: [uid] });
      gt.machine.advance();
      if (gt.pub.status !== 'open') throw fail.pre('TABLE_CLOSED');
      const res = gt.machine.join(me, data.buyInCents ?? null);
      gt.commit(tx);
      return { response: { tableId, game, status: res.status, seatIndex: res.seatIndex, code }, after: () => gt.afterCommit() };
    }

    const module = gameModule(data.game);
    if (!module.available) throw fail.pre('FEATURE_UNAVAILABLE', `${data.game} is not available yet`);
    const buyIn = data.buyInCents ?? null;

    if (data.mode === 'createPrivate') {
      let code = newTableCode();
      for (let i = 0; i < 5 && (await tx.get(r.tableCode(code))).exists; i++) code = newTableCode();
      const tableId = newGameTableId(db, data.game);
      const gt = await GameTableTx.create(db, tx, data.game, {
        // The join code stays secret: table names are public (lobby, market questions).
        tableId, name: `Privée ${tableId.slice(3, 7).toUpperCase()}`, stakeTier: data.stakeTier, isPrivate: true, simManaged: false,
        rankTier: profile.rankTier, code,
      }, now, { uids: [uid] });
      const res = gt.machine.join(me, buyIn);
      gt.commit(tx, () => tx.set(r.tableCode(code), { tableId, game: data.game, createdAtMs: now }));
      return { response: { tableId, game: data.game, status: res.status, seatIndex: res.seatIndex, code } };
    }

    // quick: best public table of the game and stake tier (non-transactional scan, transactional re-check)
    const scan = await db.collection('gameTables')
      .where('game', '==', data.game).where('status', '==', 'open').where('isPrivate', '==', false).where('stakeTier', '==', data.stakeTier)
      .limit(50).get();
    const candidates = scan.docs.map((d) => d.data() as GameTableDoc).filter(roomFor)
      .sort((a, b) => score(b, profile.rankTier) - score(a, profile.rankTier));
    for (const c of candidates.slice(0, 3)) {
      const gt = await GameTableTx.load(db, tx, c.tableId, now, { uids: [uid] });
      gt.machine.advance();
      if (!gt.machine.hasRoomForHuman()) continue;
      const res = gt.machine.join(me, buyIn);
      gt.commit(tx);
      return { response: { tableId: gt.pub.tableId, game: data.game, status: res.status, seatIndex: res.seatIndex, code: null }, after: () => gt.afterCommit() };
    }
    // nothing suitable: new public table, 2 bots to complete
    const tableId = newGameTableId(db, data.game);
    const gt = await GameTableTx.create(db, tx, data.game, {
      tableId, name: `${GAME_TABLE_LABEL[data.game]} ${tableId.slice(3, 7).toUpperCase()}`, stakeTier: data.stakeTier as StakeTier,
      isPrivate: false, simManaged: false, rankTier: profile.rankTier,
    }, now, { uids: [uid] });
    for (const b of pickFreeBots(cryptoRng(), 2)) gt.machine.join(b);
    const res = gt.machine.join(me, buyIn);
    gt.commit(tx);
    return { response: { tableId, game: data.game, status: res.status, seatIndex: res.seatIndex, code: null } };
  },
});

export const gameLeave = defineCallable({
  name: 'gameLeave',
  schema: S.gameLeave,
  tableIdOf: (d) => d.tableId,
  handler: async (tx, data, { db, uid, now }) => {
    if (gameOfTableId(data.tableId) === 'blackjack') {
      // Convenience: the same "leave" for every game (blackjack keeps its own leaveTable).
      const tt = await TableTx.load(db, tx, data.tableId, now, { uids: [uid] });
      tt.machine.advance();
      const refundedCents = tt.machine.leave(uid);
      const deferred = tt.machine.seatOf(uid) !== null;
      tt.commit(tx);
      return { response: { left: true as const, refundedCents, cashOutCents: 0, deferred }, after: () => tt.afterCommit() };
    }
    const gt = await GameTableTx.load(db, tx, data.tableId, now, { uids: [uid] });
    gt.machine.advance();
    const res = gt.machine.leave(uid);
    gt.commit(tx);
    return { response: { left: true as const, ...res }, after: () => gt.afterCommit() };
  },
});

export const gameAction = defineCallable({
  name: 'gameAction',
  schema: S.gameAction,
  tableIdOf: () => null, // the handler applies overdue deadlines in its own transaction
  handler: async (tx, data, { db, uid, now }) => {
    const head = actionTypeSchema.parse(data.action);
    const r = refs(db);
    if (head.type === 'setBets') {
      const a = kernelActionSchemas.setBets.parse(data.action);
      const reads = [r.gameTable(data.tableId), r.gameBet(data.tableId, uid), r.wallet(uid), ...(a.power ? [r.inventory(uid, a.power)] : [])];
      const [ts, bs, ws, inv] = await tx.getAll(...reads);
      if (gameOfTableId(data.tableId) === 'blackjack' || !ts.exists) throw fail.notFound('TABLE_NOT_FOUND');
      const table = ts.data() as GameTableDoc;
      const w = WalletSession.fromSnapshot(db, uid, ws, now);
      const plan = planSetBets({
        table, module: gameModule(table.game), uid, round: data.round, bets: a.bets, power: a.power,
        board: bs.exists ? (bs.data() as GameBetDoc) : null,
        inventoryQty: inv?.exists ? (inv.data() as InventoryDoc).quantity : 0, now,
      });
      const ref = { tableId: table.tableId, handNumber: table.round };
      if (plan.debitCents > 0) w.debit(plan.debitCents, 'bet', ref); // INSUFFICIENT_FUNDS aborts everything
      if (plan.refundCents > 0) w.credit(plan.refundCents, 'refund', ref);
      tx.set(r.gameBet(data.tableId, uid), plan.doc);
      if (plan.powerConsumed) {
        const qty = (inv.data() as InventoryDoc).quantity;
        const doc: InventoryDoc = { powerId: plan.powerConsumed, quantity: qty - 1, updatedAtMs: now };
        tx.set(r.inventory(uid, plan.powerConsumed), doc);
      }
      w.write(tx);
      return {
        response: {
          phase: table.phase, round: table.round, balanceCents: w.balance, stackCents: null,
          data: { bets: plan.doc.bets, totalCents: plan.doc.totalCents, power: plan.doc.power },
        },
      };
    }
    const action = (head.type === 'sitOut' || head.type === 'sitIn' ? kernelActionSchemas[head.type].parse(data.action) : data.action) as GameAction;
    const gt = await GameTableTx.load(db, tx, data.tableId, now, { uids: [uid] });
    gt.machine.advance();
    const out = gt.machine.action(uid, data.round, action);
    gt.commit(tx);
    const seat = gt.machine.seatOf(uid);
    return {
      response: {
        phase: gt.pub.phase, round: gt.pub.round, balanceCents: gt.wallets.get(uid)?.balance ?? 0,
        stackCents: seat?.stackCents ?? null, data: out.data,
      },
      after: () => gt.afterCommit(),
    };
  },
});

export const gamePoke = defineCallable({
  name: 'gamePoke',
  schema: S.gamePoke,
  tableIdOf: () => null, // the handler itself advances the table and reports it
  handler: async (tx, data, { db, now }) => {
    if (gameOfTableId(data.tableId) === 'blackjack') throw fail.notFound('TABLE_NOT_FOUND');
    const ts = await tx.get(refs(db).gameTable(data.tableId));
    if (!ts.exists) throw fail.notFound('TABLE_NOT_FOUND');
    const t = ts.data() as GameTableDoc;
    const withdrawn = t.status === 'open' && !gameModule(t.game).available;
    if (!withdrawn && (t.status !== 'open' || t.deadlineMs === null || t.deadlineMs > now)) {
      return { response: { phase: t.phase, round: t.round, deadlineMs: t.deadlineMs, advanced: false } };
    }
    const gt = await GameTableTx.load(db, tx, data.tableId, now);
    const advanced = gt.machine.advance();
    if (advanced) gt.commit(tx);
    return {
      response: { phase: gt.pub.phase, round: gt.pub.round, deadlineMs: gt.pub.deadlineMs, advanced },
      after: () => gt.afterCommit(),
    };
  },
});
