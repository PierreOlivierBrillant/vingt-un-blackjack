/**
 * Firestore glue of the GameTableMachine (modelled on table/service.ts TableTx): loads every
 * document a table transaction may need BEFORE any write (table, private state, every seated
 * seat's bet board, profiles of seated / queued / extra users, wallets of the humans, optional
 * inventory), runs the machine, then applies its effects and writes everything in the SAME
 * transaction. A credit to an absent wallet is logged, never thrown (a deleted account must not
 * freeze a table).
 */
import { FieldValue, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { gameModule } from '../registry';
import { fail } from '../../shared/errors';
import { gameOfTableId, type GameBetDoc, type GameId, type GamePrivateDoc, type GameTableDoc } from '../../shared/games/common';
import { refs } from '../../shared/paths';
import { DEALER_OF } from '../../shared/romance';
import { dayId } from '../../shared/time';
import type { InventoryDoc, PowerId, PricePointDoc, ProfileDoc } from '../../shared/types';
import { WalletSession } from '../../shared/wallet';
import { settleMarketPayouts } from '../../table/markets';
import { GameTableMachine, newGameTableState, prodGameDeps, type GameDeps, type NewGameTableParams } from './machine';
import { defaultFoldStats, type AnyGameModule } from './module';
import { applyRankOutcome } from './rank';

export interface GameLoadOptions {
  /** Extra users whose profile (and wallet, for humans) must be loaded, e.g. the caller. */
  uids?: string[];
  inventory?: { uid: string; powerId: PowerId } | null;
}

let depsFactory: () => GameDeps = prodGameDeps;
/** Tests may inject deterministic randomness. */
export function setGameDeps(f: () => GameDeps): void {
  depsFactory = f;
}

export class GameTableTx {
  readonly wallets = new Map<string, WalletSession>();
  readonly profiles = new Map<string, ProfileDoc>();
  inventoryQty = 0;
  /** Markets resolved/voided in this transaction (payouts run after commit). */
  readonly settledMarkets: string[] = [];

  private constructor(
    private readonly db: Firestore,
    readonly machine: GameTableMachine,
    readonly now: number,
    readonly isNew: boolean,
  ) {}

  get pub(): GameTableDoc {
    return this.machine.pub;
  }

  get module(): AnyGameModule {
    return this.machine.module;
  }

  static async load(db: Firestore, tx: Transaction, tableId: string, now: number, opts: GameLoadOptions = {}): Promise<GameTableTx> {
    const game = gameOfTableId(tableId);
    if (game === 'blackjack') throw fail.notFound('TABLE_NOT_FOUND');
    const r = refs(db);
    const [ts, ps] = await tx.getAll(r.gameTable(tableId), r.gameTablePrivate(tableId));
    if (!ts.exists || !ps.exists) throw fail.notFound('TABLE_NOT_FOUND');
    const pub = ts.data() as GameTableDoc;
    const priv = ps.data() as GamePrivateDoc;
    const module = gameModule(pub.game);
    const boards = new Map<string, GameBetDoc>();
    if (module.money === 'board' && pub.seatedUids.length > 0) {
      const snaps = await tx.getAll(...pub.seatedUids.map((u) => r.gameBet(tableId, u)));
      for (const s of snaps) if (s.exists) boards.set(s.id, s.data() as GameBetDoc);
    }
    const t = new GameTableTx(db, new GameTableMachine(pub, priv, boards, module, depsFactory(), now), now, false);
    await t.loadUsers(tx, opts);
    return t;
  }

  static async create(db: Firestore, tx: Transaction, game: GameId, params: NewGameTableParams, now: number, opts: GameLoadOptions = {}): Promise<GameTableTx> {
    const module = gameModule(game);
    const { pub, priv } = newGameTableState(module, params, now);
    const t = new GameTableTx(db, new GameTableMachine(pub, priv, new Map(), module, depsFactory(), now), now, true);
    await t.loadUsers(tx, opts);
    return t;
  }

  private async loadUsers(tx: Transaction, opts: GameLoadOptions): Promise<void> {
    const r = refs(this.db);
    const uids = [...new Set<string>([...this.pub.seatedUids, ...this.pub.queue.map((q) => q.uid), ...(opts.uids ?? [])])];
    const refsToRead = [
      ...uids.map((u) => r.profile(u)),
      ...(opts.inventory ? [r.inventory(opts.inventory.uid, opts.inventory.powerId)] : []),
    ];
    if (refsToRead.length === 0) return;
    const snaps = await tx.getAll(...refsToRead);
    const humans: string[] = [];
    uids.forEach((u, i) => {
      const s = snaps[i];
      if (!s.exists) return;
      const p = s.data() as ProfileDoc;
      this.profiles.set(u, p);
      if (!p.isBot) humans.push(u);
    });
    if (opts.inventory) {
      const inv = snaps[uids.length];
      this.inventoryQty = inv.exists ? (inv.data() as InventoryDoc).quantity : 0;
    }
    if (humans.length === 0) return;
    const ws = await tx.getAll(...humans.map((u) => r.wallet(u)));
    ws.forEach((s, i) => {
      if (s.exists) this.wallets.set(humans[i], WalletSession.fromSnapshot(this.db, humans[i], s, this.now));
    });
  }

  wallet(uid: string): WalletSession {
    const w = this.wallets.get(uid);
    if (!w) throw fail.pre('PROFILE_REQUIRED', 'wallet not loaded');
    return w;
  }

  /** Applies the machine's effects and writes every document. Call once, after the machine work. */
  commit(tx: Transaction, extraWrites?: () => void): void {
    const r = refs(this.db);
    const m = this.machine;
    const now = this.now;
    const tableId = m.pub.tableId;
    const game = m.pub.game;
    const day = dayId(now);
    const profileUpdates = new Map<string, Record<string, unknown>>();
    const upd = (uid: string, data: Record<string, unknown>) => profileUpdates.set(uid, { ...(profileUpdates.get(uid) ?? {}), ...data });

    for (const e of m.effects) {
      switch (e.kind) {
        case 'debit':
          // Throws INSUFFICIENT_FUNDS: the whole transaction (and the action) is refused.
          this.wallet(e.uid).debit(e.cents, e.ledger, { tableId, handNumber: e.round });
          break;
        case 'credit': {
          const w = this.wallets.get(e.uid);
          if (w) w.credit(e.cents, e.ledger, { tableId, handNumber: e.round });
          else logger.error('game credit to an absent wallet (skipped)', { tableId, uid: e.uid, cents: e.cents, ledger: e.ledger });
          break;
        }
        case 'secret':
          tx.set(r.gameHole(tableId, e.uid), e.doc);
          break;
        case 'settle':
          for (const s of e.rows) {
            const p = this.profiles.get(s.uid);
            if (p) {
              const rank = applyRankOutcome(p, game, s.outcome, now);
              const prev = p.gameStats?.[game];
              const stats = m.module.stats ? m.module.stats(prev ?? { rounds: 0, won: 0, lost: 0, netCents: 0, biggestWinCents: 0, counters: {} }, s) : defaultFoldStats(prev, s);
              p.gameStats = { ...(p.gameStats ?? {}), [game]: stats };
              upd(s.uid, {
                rankPoints: rank.rankPoints, rankTier: rank.rankTier, weekId: rank.weekId, weeklyPoints: rank.weeklyPoints,
                rankDaily: rank.rankDaily, gameStats: { [game]: stats },
              });
            }
            if (s.affinity && !s.isBot) {
              // Blind increment, no read: Rendez-vous folds it into affinity (romance{op:'sync'}).
              tx.set(r.romance(s.uid, DEALER_OF[game]), { tablePlay: { [day]: FieldValue.increment(1) } }, { merge: true });
            }
          }
          break;
        case 'history':
          tx.set(r.gameRound(tableId, e.doc.round), e.doc);
          break;
        case 'marketCreate': {
          tx.set(r.market(e.market.marketId), e.market);
          const pt: PricePointDoc = { atMs: now, priceYes: 0.5 };
          tx.set(r.priceHistory(e.market.marketId).doc(), pt);
          break;
        }
        case 'marketStatus': {
          const data: Record<string, unknown> = { status: e.status };
          if (e.status === 'closed') data.closedAtMs = now;
          else { data.outcome = e.outcome; data.resolvedAtMs = now; this.settledMarkets.push(e.marketId); }
          tx.set(r.market(e.marketId), data, { merge: true });
          break;
        }
        case 'location': {
          const p = this.profiles.get(e.uid);
          if (p && !p.isBot) upd(e.uid, { currentTableId: e.tableId });
          break;
        }
        case 'feed':
          tx.set(r.feed().doc(), e.entry);
          break;
      }
    }
    for (const uid of m.dirtyBoards) {
      const b = m.boards.get(uid);
      if (b) tx.set(r.gameBet(tableId, uid), b);
      else tx.delete(r.gameBet(tableId, uid));
    }
    for (const [uid, data] of profileUpdates) tx.set(r.profile(uid), data, { merge: true });
    for (const w of this.wallets.values()) w.write(tx);
    extraWrites?.();
    m.pub.updatedAtMs = now;
    tx.set(r.gameTable(tableId), m.pub);
    tx.set(r.gameTablePrivate(tableId), m.priv);
  }

  /** Post-commit: pay positions of markets resolved in this transaction. */
  async afterCommit(): Promise<void> {
    for (const id of this.settledMarkets) await settleMarketPayouts(this.db, id);
  }
}

/**
 * Applies overdue deadlines of a kernel-driven table (callables' pre-pass, gamePoke, sim runner).
 * Cheap when nothing is due (one non-transactional read).
 */
export async function applyOverdueGame(db: Firestore, tableId: string, now = Date.now()): Promise<boolean> {
  const snap = await refs(db).gameTable(tableId).get();
  if (!snap.exists) return false;
  const t = snap.data() as GameTableDoc;
  const withdrawn = t.status === 'open' && !gameModule(t.game).available;
  if (!withdrawn && (t.status !== 'open' || t.deadlineMs === null || t.deadlineMs > now)) return false;
  let tt: GameTableTx | null = null;
  const changed = await db.runTransaction(async (tx) => {
    tt = await GameTableTx.load(db, tx, tableId, Date.now());
    const any = tt.machine.advance();
    if (any) tt.commit(tx);
    return any;
  });
  if (changed && tt) await (tt as GameTableTx).afterCommit();
  return changed;
}
