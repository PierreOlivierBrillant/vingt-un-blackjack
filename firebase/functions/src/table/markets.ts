/**
 * Firestore side of spectator markets: payouts at resolution (idempotent: guarded by
 * `payoutsDone` and per-position status) and bot trades from the sim runner.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { refs } from '../shared/paths';
import type { MarketDoc, MarketSide, PositionDoc, PricePointDoc, TradeDoc } from '../shared/types';
import { WalletSession } from '../shared/wallet';
import { payoutCents, quoteBuy } from '../market/lmsr';

const BATCH = 100;

/**
 * Pays every open position of a resolved market (100¢ per winning share) or refunds the net cost
 * of every position of a void market. Safe to call repeatedly and concurrently.
 */
export async function settleMarketPayouts(db: Firestore, marketId: string): Promise<number> {
  const r = refs(db);
  let paid = 0;
  for (let round = 0; round < 1000; round++) {
    const done = await db.runTransaction(async (tx) => {
      const ms = await tx.get(r.market(marketId));
      if (!ms.exists) return true;
      const m = ms.data() as MarketDoc;
      if ((m.status !== 'resolved' && m.status !== 'void') || m.payoutsDone) return true;
      const q = db.collectionGroup('positions').where('marketId', '==', marketId).where('status', '==', 'open').limit(BATCH);
      const ps = await tx.get(q);
      if (ps.empty) {
        tx.update(r.market(marketId), { payoutsDone: true });
        return true;
      }
      const owners = ps.docs.map((d) => d.ref.parent.parent!.id);
      const wallets = await Promise.all(owners.map((u) => WalletSession.load(db, tx, u, Date.now()).catch(() => null)));
      ps.docs.forEach((d, i) => {
        const pos = d.data() as PositionDoc;
        let amount: number;
        let status: PositionDoc['status'];
        if (m.status === 'void') {
          amount = Math.max(0, pos.costCents - pos.proceedsCents);
          status = 'void';
        } else {
          amount = payoutCents(pos, m.outcome as MarketSide);
          status = amount > 0 ? 'won' : 'lost';
        }
        const w = wallets[i];
        if (w && amount > 0) w.credit(amount, m.status === 'void' ? 'refund' : 'marketPayout', { marketId, tableId: m.tableId });
        tx.update(d.ref, { status, payoutCents: amount, updatedAtMs: Date.now() });
        paid++;
      });
      for (const w of wallets) w?.write(tx);
      return false;
    });
    if (done) break;
  }
  return paid;
}

/** Bot trade (no wallet: bots only move prices and fill the activity feed). */
export async function botTrade(db: Firestore, marketId: string, bot: { uid: string; username: string }, side: MarketSide, shares: number): Promise<boolean> {
  const r = refs(db);
  return db.runTransaction(async (tx) => {
    const ms = await tx.get(r.market(marketId));
    if (!ms.exists) return false;
    const m = ms.data() as MarketDoc;
    if (m.status !== 'open') return false;
    let q;
    try { q = quoteBuy(m, side, shares); } catch { return false; }
    const now = Date.now();
    tx.update(r.market(marketId), {
      qYes: q.after.qYes, qNo: q.after.qNo, priceYes: q.priceYesAfter, volumeCents: m.volumeCents + q.amountCents,
      tradeCount: m.tradeCount + 1,
    });
    const tradeRef = r.trades(marketId).doc();
    const trade: TradeDoc = {
      tradeId: tradeRef.id, uid: bot.uid, username: bot.username, isBot: true, side, direction: 'buy', shares,
      amountCents: q.amountCents, priceYesAfter: q.priceYesAfter, createdAtMs: now,
    };
    tx.set(tradeRef, trade);
    const pt: PricePointDoc = { atMs: now, priceYes: q.priceYesAfter };
    tx.set(r.priceHistory(marketId).doc(), pt);
    return true;
  });
}
