/**
 * Firestore glue for the table state machine: loads every document a table transaction may
 * need (table, private state, seated players' profiles and human wallets) BEFORE any write,
 * runs the machine, then applies its effects and writes everything in the same transaction.
 */
import { FieldValue, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { settleMarketPayouts } from './markets';
import { fail } from '../shared/errors';
import { refs } from '../shared/paths';
import { DEALER_OF } from '../shared/romance';
import { dayId, weekId } from '../shared/time';
import type { InventoryDoc, PowerId, PricePointDoc, ProfileDoc, TableDoc } from '../shared/types';
import { RANK_POINTS } from '../shared/types';
import { rankTierFor } from '../sim/profiles';
import { WalletSession } from '../shared/wallet';
import { newTableState, prodDeps, TableMachine, type MachineDeps, type NewTableParams } from './machine';
import type { TablePrivateDoc } from './model';

export interface LoadOptions {
  /** Extra users whose profile (and wallet, for humans) must be loaded, e.g. the caller. */
  uids?: string[];
  inventory?: { uid: string; powerId: PowerId } | null;
}

let depsFactory: () => MachineDeps = prodDeps;
/** Tests may inject deterministic randomness. */
export function setMachineDeps(f: () => MachineDeps): void {
  depsFactory = f;
}

export class TableTx {
  readonly wallets = new Map<string, WalletSession>();
  readonly profiles = new Map<string, ProfileDoc>();
  inventoryQty = 0;
  /** Markets resolved/voided in this transaction (payouts run after commit). */
  readonly settledMarkets: string[] = [];

  private constructor(
    private readonly db: Firestore,
    readonly machine: TableMachine,
    readonly now: number,
    readonly isNew: boolean,
  ) {}

  get pub(): TableDoc {
    return this.machine.pub;
  }

  static async load(db: Firestore, tx: Transaction, tableId: string, now: number, opts: LoadOptions = {}): Promise<TableTx> {
    const r = refs(db);
    const [ts, ps] = await Promise.all([tx.get(r.table(tableId)), tx.get(r.tablePrivate(tableId))]);
    if (!ts.exists || !ps.exists) throw fail.notFound('TABLE_NOT_FOUND');
    const pub = ts.data() as TableDoc;
    const priv = ps.data() as TablePrivateDoc;
    const t = new TableTx(db, new TableMachine(pub, priv, depsFactory(), now), now, false);
    await t.loadUsers(tx, opts);
    return t;
  }

  static async create(db: Firestore, tx: Transaction, params: NewTableParams, now: number, opts: LoadOptions = {}): Promise<TableTx> {
    const deps = depsFactory();
    const { pub, priv } = newTableState(params, now, deps);
    const t = new TableTx(db, new TableMachine(pub, priv, deps, now), now, true);
    await t.loadUsers(tx, opts);
    return t;
  }

  private async loadUsers(tx: Transaction, opts: LoadOptions): Promise<void> {
    const r = refs(this.db);
    const uids = new Set<string>([...this.pub.seatedUids, ...this.pub.queue.map((q) => q.uid), ...(opts.uids ?? [])]);
    const list = [...uids];
    const snaps = await Promise.all(list.map((u) => tx.get(r.profile(u))));
    const humans: string[] = [];
    snaps.forEach((s, i) => {
      if (!s.exists) return;
      const p = s.data() as ProfileDoc;
      this.profiles.set(list[i], p);
      if (!p.isBot) humans.push(list[i]);
    });
    const ws = await Promise.all(humans.map((u) => WalletSession.load(this.db, tx, u, this.now).catch(() => null)));
    ws.forEach((w, i) => { if (w) this.wallets.set(humans[i], w); });
    if (opts.inventory) {
      const inv = await tx.get(r.inventory(opts.inventory.uid, opts.inventory.powerId));
      this.inventoryQty = inv.exists ? (inv.data() as InventoryDoc).quantity : 0;
    }
  }

  wallet(uid: string): WalletSession {
    const w = this.wallets.get(uid);
    if (!w) throw fail.pre('PROFILE_REQUIRED', 'wallet not loaded');
    return w;
  }

  /** Apply effects and write all documents. Call once, after the machine work. */
  commit(tx: Transaction, extraWrites?: () => void): void {
    const r = refs(this.db);
    const m = this.machine;
    const now = this.now;
    const tableId = m.pub.tableId;
    const currentWeek = weekId(now);
    const profileUpdates = new Map<string, Record<string, unknown>>();
    const upd = (uid: string, data: Record<string, unknown>) => profileUpdates.set(uid, { ...(profileUpdates.get(uid) ?? {}), ...data });

    for (const e of m.effects) {
      switch (e.kind) {
        case 'settle':
          for (const s of e.seats) {
            if (!s.isBot) this.wallet(s.uid).credit(s.returnCents, 'payout', { tableId, handNumber: e.handNumber });
            const p = this.profiles.get(s.uid);
            if (!p) continue;
            const pts = RANK_POINTS[s.outcome];
            p.rankPoints = Math.max(0, p.rankPoints + pts);
            p.rankTier = rankTierFor(p.rankPoints);
            if (p.weekId !== currentWeek) { p.weekId = currentWeek; p.weeklyPoints = 0; }
            p.weeklyPoints = Math.max(0, p.weeklyPoints + pts);
            const st = p.stats;
            st.handsPlayed += 1;
            st.handsWon += s.handsWon;
            st.handsLost += s.handsLost;
            st.handsPushed += s.handsPushed;
            st.blackjacks += s.blackjacks;
            st.netCents += s.netCents;
            st.biggestWinCents = Math.max(st.biggestWinCents, s.netCents);
            upd(s.uid, { rankPoints: p.rankPoints, rankTier: p.rankTier, weekId: p.weekId, weeklyPoints: p.weeklyPoints, stats: st });
            // Rendez-vous table affinity: blind increment (no read) for a human who played at least the minimum.
            if (!s.isBot && s.stakedCents >= m.pub.minBetCents) {
              tx.set(r.romance(s.uid, DEALER_OF.blackjack), { tablePlay: { [dayId(now)]: FieldValue.increment(1) } }, { merge: true });
            }
          }
          break;
        case 'refund':
          if (this.wallets.has(e.uid)) this.wallet(e.uid).credit(e.cents, 'refund', { tableId, handNumber: e.handNumber });
          break;
        case 'peek':
          tx.set(r.peek(tableId, e.uid), { handNumber: e.handNumber, holeCard: e.holeCard, createdAtMs: now });
          break;
        case 'history':
          tx.set(r.hand(tableId, e.doc.handNumber), e.doc);
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
    for (const [uid, data] of profileUpdates) tx.set(r.profile(uid), data, { merge: true });
    for (const w of this.wallets.values()) w.write(tx);
    extraWrites?.();
    m.pub.updatedAtMs = now;
    tx.set(r.table(tableId), m.pub);
    tx.set(r.tablePrivate(tableId), m.priv);
  }

  /** Post-commit: pay positions of markets resolved in this transaction. */
  async afterCommit(): Promise<void> {
    for (const id of this.settledMarkets) {
      await settleMarketPayouts(this.db, id);
    }
  }
}

/**
 * Applies overdue deadlines of a table (used by every callable, `pokeTable` and the sim runner).
 * Cheap when nothing is due (one non-transactional read).
 */
export async function applyOverdue(db: Firestore, tableId: string, now = Date.now()): Promise<boolean> {
  const snap = await refs(db).table(tableId).get();
  if (!snap.exists) return false;
  const t = snap.data() as TableDoc;
  if (t.status !== 'open' || t.deadlineMs === null || t.deadlineMs > now) return false;
  let tt: TableTx | null = null;
  const changed = await db.runTransaction(async (tx) => {
    tt = await TableTx.load(db, tx, tableId, Date.now());
    const any = tt.machine.advance();
    if (any) tt.commit(tx);
    return any;
  });
  if (changed && tt) await (tt as TableTx).afterCommit();
  return changed;
}
