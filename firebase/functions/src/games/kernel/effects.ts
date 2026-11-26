/** Side effects produced by the GameTableMachine and applied by GameTableTx (one transaction). */
import type { GameRankOutcome, GameRoundDoc, GameSeatSettlement, GameSecretDoc } from '../../shared/games/common';
import type { FeedEntryDoc, MarketDoc, MarketKind, MarketSide } from '../../shared/types';

export type GameEffect =
  /** Wallet debit of a human (only from that user's own action, never from a deadline). */
  | { kind: 'debit'; uid: string; cents: number; ledger: 'bet' | 'buyIn'; round: number }
  /** Wallet credit of a human (absent wallet: logged, no error). */
  | { kind: 'credit'; uid: string; cents: number; ledger: 'payout' | 'refund' | 'cashOut'; round: number }
  | { kind: 'secret'; uid: string; doc: GameSecretDoc }
  /** Profile stats, rank points, affinity, for each row (rank outcome already computed). */
  | { kind: 'settle'; round: number; rows: Array<GameSeatSettlement & { outcome: GameRankOutcome; affinity: boolean }> }
  | { kind: 'history'; doc: GameRoundDoc }
  | { kind: 'marketCreate'; market: MarketDoc }
  | { kind: 'marketStatus'; marketId: string; status: 'closed' | 'resolved' | 'void'; outcome: MarketSide | null }
  | { kind: 'location'; uid: string; tableId: string | null }
  | { kind: 'feed'; entry: FeedEntryDoc };

/** Market ids of kernel-driven tables (see MARKET_KINDS doc in shared/types.ts). */
export const gameMarketIds = {
  round: (tableId: string, round: number, kind: MarketKind) => `${tableId}__r${round}__${kind}`,
  series: (tableId: string, series: number, kind: MarketKind) => `${tableId}__w${series}__${kind}`,
};
