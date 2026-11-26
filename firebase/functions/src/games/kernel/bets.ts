/**
 * setBets fast path (pure). Bet-board games store each seat's board in `gameTables/{id}/bets/{uid}`:
 * a bet only reads the table and writes that document + the wallet (never the table document), so
 * seven players betting at once do not contend. The client sends the WHOLE desired board; the
 * wallet is debited (ledger 'bet') or refunded (ledger 'refund') by the difference of the totals.
 * The betting-close transaction re-reads every board (Firestore serializability: a bet committed
 * before it is included, a bet racing it is retried and then refused with BAD_PHASE).
 */
import { fail } from '../../shared/errors';
import type { BetMap, GameBetDoc, GameTableDoc } from '../../shared/games/common';
import { DECISION_GRACE_MS, POWER_GAME, type PowerId } from '../../shared/types';
import { boardTotal, cleanBoard, type AnyGameModule, type ReadCtx } from './module';

export interface SetBetsInput {
  table: GameTableDoc;
  module: AnyGameModule;
  uid: string;
  round: number;
  bets: BetMap;
  power?: PowerId;
  /** Current `bets/{uid}` document (null if none). */
  board: GameBetDoc | null;
  /** Owned quantity of `power` (only read when a power is requested). */
  inventoryQty: number;
  now: number;
}

export interface SetBetsPlan {
  doc: GameBetDoc;
  debitCents: number;
  refundCents: number;
  /** Power taken from the inventory by this call (null if none / already attached to the board). */
  powerConsumed: PowerId | null;
}

export function planSetBets(p: SetBetsInput): SetBetsPlan {
  const t = p.table;
  const m = p.module;
  if (t.status !== 'open') throw fail.pre('TABLE_CLOSED');
  if (!m.available) throw fail.pre('FEATURE_UNAVAILABLE');
  if (m.money !== 'board') throw fail.pre('ILLEGAL_ACTION', 'no bet board in this game');
  if (t.phase !== 'betting') throw fail.pre('BAD_PHASE');
  if (p.round !== t.round) throw fail.pre('STALE_HAND');
  const seat = t.seats.find((s) => s?.uid === p.uid) ?? null;
  if (!seat || seat.status !== 'active') throw fail.pre('NOT_SEATED');
  // Humans get DECISION_GRACE_MS after the displayed deadline (the close waits for it too).
  if (t.deadlineMs === null || p.now > t.deadlineMs + DECISION_GRACE_MS) throw fail.pre('BAD_PHASE', 'betting is closed');
  for (const v of Object.values(p.bets)) {
    if (!Number.isSafeInteger(v) || v < 0 || v % 100 !== 0) throw fail.invalid('BET_OUT_OF_RANGE');
  }
  const current = p.board?.bets ?? {};
  const view: ReadCtx = { game: t.game, now: p.now, table: t, limits: t.limits };
  const next = cleanBoard(m.validateBets(view, seat, cleanBoard(p.bets), { ...current }));
  for (const v of Object.values(next)) {
    if (!Number.isSafeInteger(v) || v < 0 || v % 100 !== 0) throw new Error('kernel: validateBets returned a bad amount');
  }
  const total = boardTotal(next);
  if ((total > 0 && total < t.limits.minBetCents) || total > t.limits.maxRoundCents) throw fail.invalid('BET_OUT_OF_RANGE');

  let power = p.board?.power ?? null;
  let consumed: PowerId | null = null;
  if (p.power) {
    if (POWER_GAME[p.power] !== t.game) throw fail.invalid('WRONG_GAME');
    if (power && power !== p.power) throw fail.pre('POWER_ALREADY_USED');
    if (!power && p.inventoryQty < 1) throw fail.pre('POWER_NOT_OWNED');
    m.power(view, seat, p.power, next);
    if (!power) {
      consumed = p.power;
      power = p.power;
    }
  }
  const old = p.board?.totalCents ?? boardTotal(current);
  return {
    doc: {
      uid: p.uid, seatIndex: seat.seatIndex, isBot: false, round: t.round, bets: next, totalCents: total, power,
      previous: p.board?.previous ?? {}, updatedAtMs: p.now,
    },
    debitCents: Math.max(0, total - old),
    refundCents: Math.max(0, old - total),
    powerConsumed: consumed,
  };
}
