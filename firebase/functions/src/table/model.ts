/** Server-only table state and the side effects produced by the table state machine. */
import type { RoundState } from '../engine/round';
import type {
  CardCode, FeedEntryDoc, HandHistoryDoc, MarketDoc, MarketSide, RankTier,
} from '../shared/types';

/** `tables/{id}/private/state` — never readable by clients. */
export interface TablePrivateDoc {
  /** Undealt cards (any order) before the current hand. */
  shoe: CardCode[];
  /** Engine state of the current hand (contains the dealing order, i.e. the hole card). */
  round: RoundState | null;
  /** Shoe snapshot at the deal, for the fairness proof. */
  remainingBefore: CardCode[] | null;
  /** Secret seed of the current hand (revealed in history after settlement). */
  seed: string | null;
  commit: string | null;
  /** Number of engine events already copied to the public event log. */
  roundEventsApplied: number;
  startedAtMs: number | null;
  /** The long shoe market was already closed (50 % of the shoe dealt). */
  shoeMarketClosed?: boolean;
}

export interface PlayerInfo {
  uid: string;
  username: string;
  avatar: string;
  rankTier: RankTier;
  isBot: boolean;
}

export interface SeatSettlement {
  uid: string;
  username: string;
  avatar: string;
  isBot: boolean;
  seatIndex: number;
  stakedCents: number;
  returnCents: number;
  netCents: number;
  outcome: 'blackjack' | 'win' | 'push' | 'lose';
  handsWon: number;
  handsLost: number;
  handsPushed: number;
  blackjacks: number;
}

export type Effect =
  | { kind: 'settle'; handNumber: number; seats: SeatSettlement[] }
  | { kind: 'refund'; uid: string; cents: number; handNumber: number }
  | { kind: 'peek'; uid: string; holeCard: CardCode; handNumber: number }
  | { kind: 'history'; doc: HandHistoryDoc }
  | { kind: 'marketCreate'; market: MarketDoc }
  | { kind: 'marketStatus'; marketId: string; status: 'closed' | 'resolved' | 'void'; outcome: MarketSide | null }
  | { kind: 'location'; uid: string; tableId: string | null }
  | { kind: 'feed'; entry: FeedEntryDoc };

/** Market id helpers (`{tableId}__...`, so the table can be recovered from a market id). */
export const marketIds = {
  dealerBust: (tableId: string, hand: number) => `${tableId}__h${hand}__dealerBust`,
  natural: (tableId: string, hand: number) => `${tableId}__h${hand}__natural`,
  player: (tableId: string, hand: number, seat: number) => `${tableId}__h${hand}__p${seat}`,
  shoe: (tableId: string, shoe: number) => `${tableId}__s${shoe}__shoe`,
  tableOf: (marketId: string) => marketId.split('__')[0] ?? null,
};
