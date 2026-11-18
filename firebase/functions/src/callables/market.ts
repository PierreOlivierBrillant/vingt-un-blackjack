/** Spectator market trading (LMSR market maker, house-side rounding). */
import { quoteBuy, quoteSell } from '../market/lmsr';
import { fail } from '../shared/errors';
import { refs } from '../shared/paths';
import type { MarketDoc, PositionDoc, PricePointDoc, ProfileDoc, TableDoc, TradeDoc } from '../shared/types';
import { WalletSession } from '../shared/wallet';
import { marketIds } from '../table/model';
import { defineCallable } from './framework';
import { S } from './schemas';

export const tradeShares = defineCallable({
  name: 'tradeShares',
  schema: S.tradeShares,
  tableIdOf: (d) => marketIds.tableOf(d.marketId),
  handler: async (tx, data, { db, uid, now }) => {
    const r = refs(db);
    const ms = await tx.get(r.market(data.marketId));
    if (!ms.exists) throw fail.notFound('MARKET_NOT_FOUND');
    const m = ms.data() as MarketDoc;
    const [ts, ps, pos] = await Promise.all([tx.get(r.table(m.tableId)), tx.get(r.profile(uid)), tx.get(r.position(uid, data.marketId))]);
    if (!ps.exists) throw fail.pre('PROFILE_REQUIRED');
    const profile = ps.data() as ProfileDoc;
    const w = await WalletSession.load(db, tx, uid, now);
    if (m.status !== 'open') throw fail.pre('MARKET_CLOSED');
    const table = ts.data() as TableDoc | undefined;
    const atTable = profile.currentTableId === m.tableId
      || (table && (table.seatedUids.includes(uid) || table.queue.some((q) => q.uid === uid)));
    if (atTable) throw fail.denied('OWN_TABLE_MARKET');

    const p: PositionDoc = pos.exists ? (pos.data() as PositionDoc) : {
      marketId: m.marketId, tableId: m.tableId, kind: m.kind, question: m.question, yesShares: 0, noShares: 0,
      costCents: 0, proceedsCents: 0, payoutCents: 0, status: 'open', updatedAtMs: now,
    };
    const key = data.side === 'yes' ? 'yesShares' : 'noShares';
    let quote;
    if (data.direction === 'buy') {
      quote = quoteBuy(m, data.side, data.shares);
      if (data.maxCostCents !== undefined && quote.amountCents > data.maxCostCents) throw fail.pre('SLIPPAGE');
      w.debit(quote.amountCents, 'marketBuy', { marketId: m.marketId, tableId: m.tableId });
      p[key] += data.shares;
      p.costCents += quote.amountCents;
    } else {
      if (p[key] < data.shares) throw fail.pre('INSUFFICIENT_SHARES');
      quote = quoteSell(m, data.side, data.shares);
      if (data.minProceedsCents !== undefined && quote.amountCents < data.minProceedsCents) throw fail.pre('SLIPPAGE');
      w.credit(quote.amountCents, 'marketSell', { marketId: m.marketId, tableId: m.tableId });
      p[key] -= data.shares;
      p.proceedsCents += quote.amountCents;
    }
    p.updatedAtMs = now;
    tx.set(r.position(uid, m.marketId), p);
    tx.update(r.market(m.marketId), {
      qYes: quote.after.qYes, qNo: quote.after.qNo, priceYes: quote.priceYesAfter,
      volumeCents: m.volumeCents + quote.amountCents, tradeCount: m.tradeCount + 1,
    });
    const tradeRef = r.trades(m.marketId).doc();
    const trade: TradeDoc = {
      tradeId: tradeRef.id, uid, username: profile.username, isBot: false, side: data.side, direction: data.direction,
      shares: data.shares, amountCents: quote.amountCents, priceYesAfter: quote.priceYesAfter, createdAtMs: now,
    };
    tx.set(tradeRef, trade);
    const pt: PricePointDoc = { atMs: now, priceYes: quote.priceYesAfter };
    tx.set(r.priceHistory(m.marketId).doc(), pt);
    w.write(tx);
    return {
      response: {
        amountCents: quote.amountCents, priceYes: quote.priceYesAfter, balanceCents: w.balance,
        position: { yesShares: p.yesShares, noShares: p.noShares },
      },
    };
  },
});
