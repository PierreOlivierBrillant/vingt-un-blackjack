/**
 * Baccarat (Punto Banco, 8 decks) — shared contract. OWNER: baccarat implementer.
 * Values in the exported lists below are spread into the global unions of ../types.ts.
 * Append new values at the END of a list (never rename/remove: Dart mirrors them).
 *
 * ============================================================================================
 *  RULES (server: src/games/baccarat/engine.ts; client: app/lib/features/games/baccarat/)
 * ============================================================================================
 *  - Shoe of 8 decks (416 cards). Cut card 16 cards from the end: the coup during which the cut card
 *    comes out (≤ 16 cards left after it) is the last one of the shoe; the next coup starts a new shoe.
 *  - Burn: on the first coup of every shoe, the first card is turned face up and as many cards as its
 *    value are burned face down (ace 1, 2–9 face value, ten / J / Q / K 10). The burn card, the burned
 *    cards and the coup are ONE deal order: `fairDealOrder(remainingBefore, seed, 8)` — the proof of
 *    `rounds/{n}` covers the burn.
 *  - Deal order: Player 1, Banker 1, Player 2, Banker 2, then Player's third card, then Banker's.
 *    Card value: ace 1, 2–9 face value, ten and faces 0; a hand's total is the sum mod 10.
 *    Natural: either hand totals 8 or 9 with two cards → both stand. Otherwise Player draws on 0–5.
 *    Banker (Player stood): draws on 0–5. Banker (Player drew a third card worth p): 0–2 draws;
 *    3 draws unless p = 8; 4 draws on p 2–7; 5 on p 4–7; 6 on p 6–7; 7 stands.
 *  - Payouts ("to 1", stake returned on a win): player 1:1; banker 0.95:1 (exact: bets are whole
 *    dollars, 5 % of a dollar is 5 cents; power `freeCommission`: 1:1); tie 8:1 and, on a tie, the
 *    player and banker bets are returned (push); playerPair / bankerPair (the side's first two cards
 *    have the same rank, e.g. 7♥ 7♠ or K♣ K♦ — K Q is not a pair) 11:1.
 *
 * SPOT IDS (`bets/{uid}.bets`): 'player', 'banker', 'tie', 'playerPair', 'bankerPair' (BACCARAT_SPOTS).
 *  Every non-zero spot is ≥ limits.minBetCents; player / banker ≤ limits.maxBetCents; tie and pairs
 *  ≤ limits.extra.sideMaxCents (a fifth of maxBetCents), the whole board ≤ limits.maxRoundCents
 *  (twice maxBetCents) — else BET_OUT_OF_RANGE. Betting both Player and Banker is allowed.
 *
 * POWER `freeCommission` (setBets `power`): only with a Banker bet on the board (else
 *  POWER_NOT_APPLICABLE); that coup, a winning Banker bet is paid 1:1.
 *
 * GAME ACTIONS: none — a coup is only played with setBets (BaccaratAction `{type:'none'}` is refused).
 *
 * PUBLIC STATE `gameTables/{id}.g` = BaccaratPublic. SEAT STATE `seats[i].g` = {} (nothing).
 * PRIVATE STATE `private/state.g` = BaccaratPrivate (server only).
 *
 * STEPS (`table.step`): 'betting' (phase betting), 'dealing' (phase live: the coup is fully dealt and
 *  public, the client animates it until `deadlineMs`, then the round settles).
 *
 * EVENTS (`table.events`, payload `d`), all emitted in the transaction that closes betting, in order:
 *  - 'shuffle'  {shoe}                         new shoe (at the opening of its first coup)
 *  - 'burn'     {card, count}                  burn card shown, `count` cards burned face down
 *  - 'card'     {hand:'player'|'banker', i:0|1|2, card, total}   one card, in deal order
 *               (`total` = that hand's total after this card; i = 2 is the third card, laid sideways)
 *  - 'result'   {winner, playerTotal, bankerTotal, natural, playerPair, bankerPair}
 *  - 'cut'      {remaining}                    the cut card came out: last coup of this shoe
 *  The squeeze is a client animation of cards that are ALREADY public: no information is hidden.
 *
 * TREND BOARDS: `g.beads` lists the coups of the current shoe (oldest first). The client derives the
 *  Bead Plate (one cell per coup, 6 rows, column by column), the Big Road (a new column each time the
 *  winner changes; ties are marked on the previous cell, never a new cell; a column longer than 6
 *  turns right: "dragon tail") and the Big Eye Boy (derived road) from it.
 *
 * ROUND RESULT (`rounds/{n}.result`): BaccaratResult. FAIRNESS: `remainingBefore` (the undealt cards
 *  before the coup: 416 on the first coup of a shoe), `dealt` (burn card + burned cards + coup cards,
 *  in deal order), `decks: 8`.
 *
 * MARKETS (spectators; never on your own table):
 *  - per coup, open during betting, closed AND resolved in the transaction that deals the coup:
 *    baccaratBanker "Le Banquier gagne ?" (yes = Banker wins; a tie is no), baccaratTie "Égalité ?",
 *    baccaratPair "Une paire ?" (yes = Player pair or Banker pair).
 *  - long, simulated tables only, one per shoe (series number = shoe number): baccaratBankerShoe
 *    "Le Banquier gagne au moins 46 % des coups du sabot ?" (Banker wins / coups of the shoe, ties
 *    included in the coups). Created with the shoe's first coup, closed once half of the shoe is dealt,
 *    resolved as soon as the outcome is certain (at the latest by the coup where the cut card comes out).
 *
 * PROFILE COUNTERS (`gameStats.baccarat.counters`, only non-zero ones are added per coup):
 *  bankerWins / playerWins (your Banker / Player bet won), tieWins, pairWins (pair bets won),
 *  naturals (coups you played that were naturals), commissionSaved (cents saved by freeCommission).
 *  Feed highlight 'jackpot': a winning tie or pair bet.
 */
import type { CardCode } from '../types';

export const BACCARAT_POWER_IDS = ['freeCommission'] as const;
export const BACCARAT_MARKET_KINDS = ['baccaratBanker', 'baccaratTie', 'baccaratPair', 'baccaratBankerShoe'] as const;
export const BACCARAT_REASONS = [] as const;

export type BaccaratPowerId = (typeof BACCARAT_POWER_IDS)[number];

export const BACCARAT_SPOTS = ['player', 'banker', 'tie', 'playerPair', 'bankerPair'] as const;
export type BaccaratSpot = (typeof BACCARAT_SPOTS)[number];

export const BACCARAT_DECKS = 8;
export const BACCARAT_SHOE_SIZE = BACCARAT_DECKS * 52; // 416
/** The cut card sits this many cards from the end of the shoe. */
export const BACCARAT_CUT_CARDS = 16;

/** Winnings per unit staked ("to 1"); the stake comes back on a win. Banker: 0.95 (5 % commission). */
export const BACCARAT_PAYOUTS: Record<BaccaratSpot, number> = { player: 1, banker: 0.95, tie: 8, playerPair: 11, bankerPair: 11 };

/** Long market: Banker wins at least this share (percent) of the coups of the shoe. */
export const BACCARAT_SHOE_THRESHOLD_PCT = 46;

/** Durations (ms). The 'dealing' step lasts burn + 4 cards + third cards + reveal (client animation). */
export const BACCARAT_TIMING = {
  bettingMs: 20_000,
  burnMs: 2_600,
  cardMs: 650,
  thirdCardMs: 1_500,
  revealMs: 2_600,
  settledMs: 5_000,
} as const;

export type BaccaratHand = 'player' | 'banker';
export type BaccaratWinner = 'player' | 'banker' | 'tie';

/** The coup on the table (public as soon as it is dealt). */
export interface BaccaratCoupPublic {
  /** Cards in deal order (index 2 = third card, laid sideways). */
  player: CardCode[];
  banker: CardCode[];
  playerTotal: number;
  bankerTotal: number;
  winner: BaccaratWinner;
  /** A hand totalled 8 or 9 with two cards. */
  natural: boolean;
  playerPair: boolean;
  bankerPair: boolean;
  /** First coup of a shoe: the burn card and how many cards were burned face down. */
  burn: { card: CardCode; count: number } | null;
}

/** One coup of the current shoe (trend boards). */
export interface BaccaratBead {
  round: number;
  /** Winner: P(layer), B(anker), T(ie). */
  w: 'P' | 'B' | 'T';
  /** Player and Banker totals. */
  p: number;
  b: number;
  pp: boolean;
  bp: boolean;
  nat: boolean;
}

/** Shoe counters (public). */
export interface BaccaratShoePublic {
  /** Shoe number at this table (1, 2…). */
  n: number;
  total: number;
  /** Undealt cards (burned cards excluded). */
  remaining: number;
  cutAt: number;
  /** Coups dealt from this shoe and how they ended. */
  coups: number;
  banker: number;
  player: number;
  tie: number;
  /** The cut card came out: the next coup starts a new shoe. */
  cutOut: boolean;
}

/** `gameTables/{id}.g` of a baccarat table. */
export interface BaccaratPublic {
  shoe: BaccaratShoePublic;
  /** The coup being played (phase live, step 'dealing') or just settled; null during betting. */
  coup: BaccaratCoupPublic | null;
  /** Coups of the current shoe, oldest first (Bead Plate / Big Road / Big Eye Boy). */
  beads: BaccaratBead[];
  /** Long market of the current shoe (sim tables), else null. */
  series: { shoe: number; closed: boolean } | null;
}

/** `private/state.g`: the undealt cards (canonical order) and the proof of the coup being dealt. */
export interface BaccaratPrivate {
  remaining: CardCode[];
  needsBurn: boolean;
  proof: { remainingBefore: CardCode[]; dealt: CardCode[] } | null;
}

export type BaccaratSeat = Record<string, never>;
export type BaccaratAction = { type: 'none' };

/** `rounds/{n}.result` of a baccarat coup. */
export interface BaccaratResult extends Omit<BaccaratCoupPublic, 'burn'> {
  /** Burn card, count and the burned cards (revealed with the proof). */
  burn: { card: CardCode; count: number; cards: CardCode[] } | null;
  shoe: number;
  /** Position of the coup in its shoe (1, 2…). */
  coupInShoe: number;
}
