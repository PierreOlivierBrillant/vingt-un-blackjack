/**
 * Where a user is seated, across both collections (`tables` for blackjack, `gameTables` for the
 * kernel games). One location per user for every game: `profiles/{uid}.currentTableId`, whose id
 * prefix gives the collection. Used by joinMatchmaking and gameJoin (ALREADY_SEATED).
 */
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { gameOfTableId, type AnyGame, type GameTableDoc } from '../shared/games/common';
import { refs } from '../shared/paths';
import type { ProfileDoc, StakeTier, TableDoc } from '../shared/types';

export interface UserLocation {
  tableId: string;
  game: AnyGame;
  status: 'seated' | 'queued';
  seatIndex: number | null;
  stakeTier: StakeTier;
  isPrivate: boolean;
}

/** The user's live seat or queue slot (re-checked on the table document), or null. Reads inside `tx`. */
export async function currentLocation(db: Firestore, tx: Transaction, profile: ProfileDoc): Promise<UserLocation | null> {
  const id = profile.currentTableId;
  if (!id) return null;
  const uid = profile.uid;
  const game = gameOfTableId(id);
  if (game === 'blackjack') {
    const t = (await tx.get(refs(db).table(id))).data() as TableDoc | undefined;
    if (!t || t.status !== 'open') return null;
    const seat = t.seats.find((s) => s?.uid === uid && s.status === 'active');
    const queued = t.queue.some((q) => q.uid === uid);
    if (!seat && !queued) return null;
    return { tableId: id, game, status: seat ? 'seated' : 'queued', seatIndex: seat?.seatIndex ?? null, stakeTier: t.stakeTier, isPrivate: t.isPrivate };
  }
  const t = (await tx.get(refs(db).gameTable(id))).data() as GameTableDoc | undefined;
  if (!t || t.status !== 'open') return null;
  const seat = t.seats.find((s) => s?.uid === uid && s.status !== 'leaving');
  const queued = t.queue.some((q) => q.uid === uid);
  if (!seat && !queued) return null;
  return { tableId: id, game, status: seat ? 'seated' : 'queued', seatIndex: seat?.seatIndex ?? null, stakeTier: t.stakeTier, isPrivate: t.isPrivate };
}
