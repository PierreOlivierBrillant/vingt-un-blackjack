/**
 * The single overdue-deadline hook of every callable (framework.setOverdueHook): routes on the
 * table id prefix — blackjack ids to table/service.applyOverdue, `rl-`/`bc-`/`ho-`/`cr-` ids to the
 * kernel's applyOverdueGame. Also used by the sim runner.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { gameOfTableId } from '../shared/games/common';
import { applyOverdue } from '../table/service';
import { applyOverdueGame } from './kernel/tx';

export async function applyOverdueAny(db: Firestore, tableId: string, now = Date.now()): Promise<boolean> {
  return gameOfTableId(tableId) === 'blackjack' ? applyOverdue(db, tableId, now) : applyOverdueGame(db, tableId, now);
}
