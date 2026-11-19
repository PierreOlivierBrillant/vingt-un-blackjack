/**
 * ============================================================================================
 *  SINGLE SOURCE OF TRUTH — Firestore document shapes, callable contracts, enums, constants.
 * ============================================================================================
 *
 * This file is read by the Flutter client authors. Everything the client can read or call is
 * described here. The backend imports these types, so the server cannot drift from this file
 * without a type error.
 *
 * GLOBAL CONVENTIONS
 * ------------------
 *  - Project id: `demo-blackjack` (emulators only). Functions region: `us-central1`.
 *    Callable URL: http://<host>:5001/demo-blackjack/us-central1/<name>
 *  - MONEY: every amount is an INTEGER number of US cents (`...Cents`). $12.34 === 1234.
 *    Never floats. Table bets must be whole dollars (multiples of 100 cents).
 *  - TIME: every timestamp is an INTEGER number of milliseconds since the Unix epoch (UTC),
 *    field names end in `Ms` (e.g. `createdAtMs`, `deadlineMs`). Not Firestore Timestamps.
 *  - Absent optional values are stored as `null`, never omitted, unless marked `?`.
 *  - Cards: 2-character codes `${rank}${suit}`; rank ∈ "A23456789TJQK" (T = ten),
 *    suit ∈ "SHDC". Example "AS", "TH", "QC".
 *  - The client NEVER writes money, cards, bets, ranks, markets, friendships. All mutations go
 *    through the callables below. The only client-writable document is `users/{uid}`
 *    (whitelisted settings fields, see `UserSettingsDoc`).
 *
 * CALLABLE CONVENTIONS
 * --------------------
 *  - Every callable requires a signed-in Firebase Auth user (else `unauthenticated`).
 *  - Every request has `requestId`: a client-generated unique string, 8..64 chars of
 *    [A-Za-z0-9_-] (use a UUID v4). Re-sending the same `requestId` (e.g. after a network
 *    timeout) returns the ORIGINAL response without executing twice (idempotency). Reusing a
 *    requestId for a different callable fails with `invalid-argument` / REQUEST_ID_REUSED.
 *  - Unknown fields are rejected (strict schemas) with `invalid-argument` / INVALID_ARGUMENT.
 *  - Errors are Firebase `HttpsError`s: `code` is the gRPC-style code (string), and
 *    `details` is always `{ reason: ErrorReason }` — switch on `details.reason` in the client.
 *  - Per-user rate limits apply (see RATE_LIMITS); exceeding → `resource-exhausted` / RATE_LIMITED.
 *  - Callables touching a table first apply that table's overdue timeouts (server clock).
 *
 * CLIENT GUIDE (typical flows)
 * ----------------------------
 *  - Sign up with Firebase Auth email/password → `completeProfile` → listen to `profiles/{uid}`,
 *    `users/{uid}`, `users/{uid}/private/wallet`, `users/{uid}/private/kyc`.
 *  - Wallet history: `users/{uid}/ledger` orderBy('createdAtMs','desc').
 *  - Lobby: `tables` where('status','==','open').where('isPrivate','==',false) (orderBy updatedAtMs desc).
 *  - Play: `joinMatchmaking` → listen to `tables/{tableId}`. In 'betting' call `placeBet` with
 *    `handNumber`. When `turn` points at your seat call `act`. Timers: show `deadlineMs - now`.
 *    There is NO server scheduler: if `now > deadlineMs + 500 ms` and the doc has not changed, call
 *    `pokeTable` (the server re-checks its own clock; calling early is harmless, it just returns
 *    advanced:false). Bots and other players' timeouts progress the same way.
 *  - Animate `events` (ordered by `seq`); render `seats[i].hands`, `dealer.cards` (hole card hidden
 *    while `dealer.holeHidden`), results in phase 'settled' (`hands[].result`, `roundNetCents`).
 *  - Fairness screen: `fairness.currentCommit` before the hand; after it `tables/{id}/hands/{n}`.
 *  - Spectator: `markets` where('status','==','open').orderBy('createdAtMs','desc'), or
 *    where('tableId','==',id).orderBy('createdAtMs','desc'); chart from `markets/{id}/priceHistory`
 *    orderBy('atMs'); activity `markets/{id}/trades` orderBy('createdAtMs','desc'); positions
 *    `users/{uid}/positions`. You cannot trade on the table you sit at (OWN_TABLE_MARKET).
 *  - Leaderboards and friends: see ProfileDoc / FriendRequestDoc / FriendshipDoc.
 */

// ============================================================================================
// Primitive aliases
// ============================================================================================

/** Integer number of US cents. */
export type Cents = number;
/** Integer milliseconds since Unix epoch (UTC). */
export type EpochMs = number;
/** Card code, e.g. "AS", "TD", "9H". See header. */
export type CardCode = string;
/** Firebase Auth uid (bots: "bot_001".."bot_060"). */
export type Uid = string;

// ============================================================================================
// Enums
// ============================================================================================

export const STAKE_TIERS = ['low', 'mid', 'high'] as const;
/** Betting level chosen in matchmaking. Limits in STAKE_TIER_LIMITS. */
export type StakeTier = (typeof STAKE_TIERS)[number];

export const RANK_TIERS = ['bronze', 'silver', 'gold', 'platinum', 'diamond'] as const;
/** Leaderboard tier derived from `rankPoints` (see RANK_TIER_THRESHOLDS). */
export type RankTier = (typeof RANK_TIERS)[number];

export const POWER_IDS = ['freeSplit', 'freeDouble', 'freeInsurance', 'peek', 'secondChance'] as const;
/**
 * Shop powers (bought with fake money, max ONE power used per seat per hand, validated server-side):
 *  - freeSplit:      `act{action:'split', power:'freeSplit'}` — the new hand's bet is paid by the house
 *                    (you win it if it wins, you lose nothing extra if it loses).
 *  - freeDouble:     `act{action:'double', power:'freeDouble'}` — the doubled half is house-paid.
 *  - freeInsurance:  `act{action:'insurance', amountCents>0, power:'freeInsurance'}` — insurance stake
 *                    is house-paid (pays 2:1 if the dealer has blackjack, costs nothing otherwise).
 *  - peek:           `act{action:'peek', power:'peek'}` during YOUR turn — the dealer hole card is
 *                    written to `tables/{id}/peeks/{yourUid}` (only you can read it). Does not end the turn.
 *  - secondChance:   `act{action:'hit'|'double', power:'secondChance'}` — if the drawn card busts the
 *                    hand, it is discarded (event `secondChance`) and replaced by the next card (once).
 */
export type PowerId = (typeof POWER_IDS)[number];

export const PLAYER_ACTIONS = ['hit', 'stand', 'double', 'split', 'surrender', 'insurance', 'peek'] as const;
/** Actions for `act`. `insurance` is only valid in phase 'insurance'; others in 'playerTurns'. */
export type PlayerAction = (typeof PLAYER_ACTIONS)[number];

/**
 * Table phases (the server moves between them; deadlines in TIMING):
 *  - idle:        nobody seated / waiting for players. `deadlineMs` null.
 *  - betting:     seated players may `placeBet` until `deadlineMs` (15 s). Ends early when every
 *                 seated human has bet. Bots bet at phase start.
 *  - insurance:   dealer shows an Ace; each betting seat decides insurance (`act{action:'insurance'}`,
 *                 amountCents 0 = decline) until `deadlineMs` (20 s, timeout = decline).
 *  - playerTurns: `turn` points at the seat/hand to act; `deadlineMs` = 20 s (timeout = stand).
 *                 Bot turns have a short deadline (≈0.7–1.8 s) and are played by the server.
 *  - settled:     hand finished (dealer played, payouts done). Results visible for 6 s, then betting.
 *  - closed:      table permanently closed (no humans left on a non-simulated table).
 */
export const TABLE_PHASES = ['idle', 'betting', 'insurance', 'playerTurns', 'settled', 'closed'] as const;
export type TablePhase = (typeof TABLE_PHASES)[number];

/**
 * Hand outcome:
 *  blackjack (natural, pays 3:2) | win (1:1) | push (bet returned) | lose | bust | surrender (half back)
 */
export const HAND_RESULTS = ['blackjack', 'win', 'push', 'lose', 'bust', 'surrender'] as const;
export type HandResult = (typeof HAND_RESULTS)[number];

export const PAYMENT_METHODS = ['card', 'crypto', 'bankTransfer'] as const;
/** Simulated payment method. No card/crypto/bank data ever reaches the server. */
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

export const KYC_DOC_TYPES = ['passport', 'idCard', 'driverLicense'] as const;
export type KycDocType = (typeof KYC_DOC_TYPES)[number];

/** none (never submitted) → pending (fake review ≈3 s) → verified | rejected. */
export type KycStatus = 'none' | 'pending' | 'verified' | 'rejected';

export const THEMES = ['dark', 'light', 'system'] as const;
export type Theme = (typeof THEMES)[number];
export const LANGUAGES = ['fr', 'en'] as const;
export type Language = (typeof LANGUAGES)[number];
export const CARD_BACKS = ['classicBlue', 'classicRed', 'midnight', 'emerald', 'neonGrid', 'goldFiligree'] as const;
export type CardBack = (typeof CARD_BACKS)[number];
export const CARD_FACES = ['classic', 'fourColor', 'neon'] as const;
export type CardFace = (typeof CARD_FACES)[number];
export const FELTS = ['green', 'blue', 'red', 'purple', 'black'] as const;
export type Felt = (typeof FELTS)[number];

/** Avatar ids "avatar01".."avatar24" (drawn procedurally by the client). */
export const AVATAR_IDS = Array.from({ length: 24 }, (_, i) => `avatar${String(i + 1).padStart(2, '0')}`);
export type AvatarId = string;

export const LEDGER_TYPES = [
  'welcomeBonus', 'deposit', 'withdrawal', 'bet', 'double', 'split', 'insurance', 'payout', 'refund',
  'powerPurchase', 'marketBuy', 'marketSell', 'marketPayout', 'adReward',
] as const;
/** Wallet movement type. Debits have negative `amountCents`, credits positive. */
export type LedgerType = (typeof LEDGER_TYPES)[number];

/**
 * Spectator market kinds (binary YES/NO, LMSR market maker):
 *  - dealerBust:          "Le croupier saute ?" for one hand. Open from betting until just before the
 *                         dealer reveals; resolves YES if the dealer busts.
 *  - playerWins:          "{username} gagne ?" for one seat and hand: YES if the seat's total return
 *                         is greater than its total stake (net > 0). Opens at the deal, closes when the
 *                         seat finishes (all hands busted/surrendered) or before the dealer reveals.
 *  - natural:             "Un blackjack naturel ?": YES if any player OR the dealer has a natural.
 *                         Only open during betting (closes at the deal).
 *  - shoeDealerBustRate:  long market per shoe: "Le croupier saute dans ≥ 28 % des mains de ce sabot ?".
 *                         Closes once 50 % of the shoe is dealt, resolves at the shoe change.
 */
export const MARKET_KINDS = ['dealerBust', 'playerWins', 'natural', 'shoeDealerBustRate'] as const;
export type MarketKind = (typeof MARKET_KINDS)[number];
/** open (tradable) → closed (no trading, outcome pending) → resolved (paid) | void (refunded). */
export type MarketStatus = 'open' | 'closed' | 'resolved' | 'void';
export type MarketSide = 'yes' | 'no';
export type TradeDirection = 'buy' | 'sell';

// ============================================================================================
// Constants (server-enforced; the client may display them)
// ============================================================================================

export const SEATS_PER_TABLE = 5;
export const DECKS_PER_SHOE = 6;
export const SHOE_SIZE = DECKS_PER_SHOE * 52; // 312
/** Reshuffle (new shoe) between hands when fewer than this many cards remain (≈75 % penetration). */
export const CUT_CARD_REMAINING = 78;
/** Maximum hands per seat after splits. */
export const MAX_HANDS_PER_SEAT = 4;

export const STAKE_TIER_LIMITS: Record<StakeTier, { minBetCents: Cents; maxBetCents: Cents }> = {
  low: { minBetCents: 100, maxBetCents: 10_000 }, //   $1 – $100
  mid: { minBetCents: 500, maxBetCents: 50_000 }, //   $5 – $500
  high: { minBetCents: 2_500, maxBetCents: 250_000 }, // $25 – $2,500
};

/** Phase durations in ms. */
export const TIMING = {
  // 20 s: a classroom callable can take ~3 s on the emulator; the window still ends
  // early as soon as every seated human has bet.
  bettingMs: 20_000,
  decisionMs: 20_000,
  insuranceMs: 20_000,
  settledMs: 6_000,
  botMinMs: 700,
  botMaxMs: 1_800,
} as const;

/**
 * Extra time a HUMAN decision gets after its displayed deadline before the server applies the
 * timeout (auto stand / decline / deal without them): a callable can take ~3 s on the classroom
 * emulator and phone clocks drift, so a tap made in the last second must still count.
 * Bot deadlines are not affected.
 */
export const DECISION_GRACE_MS = 2_500;

/** A human who skips this many betting rounds in a row is removed from the table (frees the seat). */
export const MISSED_ROUNDS_LIMIT = 5;

/** Minimum `rankPoints` for each tier. */
export const RANK_TIER_THRESHOLDS: Record<RankTier, number> = {
  bronze: 0, silver: 500, gold: 1_500, platinum: 3_500, diamond: 7_000,
};
/** Rank points per settled seat-hand, by best outcome of the seat (clamped at 0). */
export const RANK_POINTS = { blackjack: 15, win: 10, push: 2, lose: -4 } as const;

export const WELCOME_BONUS_CENTS = 100_000; // $1,000
export const DEPOSIT_MIN_CENTS = 500; //       $5
export const DEPOSIT_MAX_CENTS = 100_000; //   $1,000 per deposit
export const DEPOSIT_DAILY_CAP_CENTS = 500_000; // $5,000 per UTC day
export const WITHDRAW_MIN_CENTS = 500;
export const WITHDRAW_MAX_CENTS = 500_000;
/** KYC fake review delay. */
export const KYC_REVIEW_MS = 3_000;
export const KYC_MIN_AGE_YEARS = 18;

/** Power prices (cents per unit). */
export const POWER_PRICES_CENTS: Record<PowerId, Cents> = {
  freeSplit: 2_000, freeDouble: 2_500, freeInsurance: 1_000, peek: 3_000, secondChance: 4_000,
};
export const POWER_MAX_QUANTITY_PER_PURCHASE = 10;
export const POWER_MAX_INVENTORY = 99;

export const AD_REWARD_CENTS = 500; // $5
export const AD_REWARD_DAILY_MAX = 10;
export const AD_REWARD_COOLDOWN_MS = 30_000;

/** Each winning market share pays this many cents. Prices are shown in cents (0..100). */
export const MARKET_SHARE_PAYOUT_CENTS = 100;
export const MARKET_MAX_SHARES_PER_TRADE = 1_000;
/** LMSR liquidity parameter b (in shares). Max house loss per market = b·ln2 dollars. */
export const MARKET_LIQUIDITY: Record<MarketKind, number> = {
  dealerBust: 60, playerWins: 60, natural: 60, shoeDealerBustRate: 200,
};
export const SHOE_BUST_RATE_THRESHOLD = 0.28;

/** Fixed-window per-user rate limits: max `count` calls per `windowMs`, per callable. */
export const RATE_LIMITS: Record<CallableName, { count: number; windowMs: number }> = {
  completeProfile: { count: 5, windowMs: 60_000 },
  submitKyc: { count: 10, windowMs: 60_000 },
  deposit: { count: 10, windowMs: 60_000 },
  withdraw: { count: 10, windowMs: 60_000 },
  joinMatchmaking: { count: 10, windowMs: 60_000 },
  leaveTable: { count: 10, windowMs: 60_000 },
  placeBet: { count: 20, windowMs: 10_000 },
  act: { count: 30, windowMs: 10_000 },
  pokeTable: { count: 30, windowMs: 10_000 },
  buyPower: { count: 10, windowMs: 60_000 },
  tradeShares: { count: 20, windowMs: 10_000 },
  friendRequest: { count: 20, windowMs: 60_000 },
  respondFriend: { count: 30, windowMs: 60_000 },
  removeFriend: { count: 20, windowMs: 60_000 },
  claimAdReward: { count: 5, windowMs: 60_000 },
  equipCardStyle: { count: 20, windowMs: 60_000 },
};

// ============================================================================================
// Firestore documents
// ============================================================================================

/**
 * `profiles/{uid}` — public profile. READ: any signed-in user. WRITE: server only.
 * Created by `completeProfile` (humans) or the seed script (bots, `isBot: true`).
 * Leaderboards: global = orderBy('rankPoints','desc'); weekly = where('weekId','==',currentWeekId)
 * .orderBy('weeklyPoints','desc'); friends = fetch friend uids. Search by username prefix:
 * where('usernameLower','>=',q).where('usernameLower','<',q+'').
 */
export interface ProfileDoc {
  uid: Uid;
  /** 3..16 chars [A-Za-z0-9_], unique case-insensitively. */
  username: string;
  usernameLower: string;
  avatar: AvatarId;
  isBot: boolean;
  rankPoints: number;
  rankTier: RankTier;
  /** Points earned during `weekId`; reset to 0 when a new ISO week starts (on next update). */
  weeklyPoints: number;
  /** ISO week id, e.g. "2026-W47". */
  weekId: string;
  stats: ProfileStats;
  /**
   * Table the user is seated or queued at, else null. Use it for "watch his table".
   * Humans: updated transactionally. Bots: synced by sim_runner every ~10 s.
   */
  currentTableId: string | null;
  /** Last server-observed activity. Client shows "online" if now - lastSeenAtMs < 120000. */
  lastSeenAtMs: EpochMs;
  kycVerified: boolean;
  createdAtMs: EpochMs;
}

export interface ProfileStats {
  handsPlayed: number;
  handsWon: number;
  handsLost: number;
  handsPushed: number;
  blackjacks: number;
  /** Sum of (return − stake) over all settled hands. */
  netCents: Cents;
  biggestWinCents: Cents;
}

/**
 * `users/{uid}` — the user's own settings. READ: owner. WRITE: owner may create/update ONLY these
 * fields, with exactly these enum values: theme, language, cardBack, cardFace, felt, updatedAtMs
 * (updatedAtMs must be an int). Also writable through `equipCardStyle`.
 */
export interface UserSettingsDoc {
  theme: Theme;
  language: Language;
  cardBack: CardBack;
  cardFace: CardFace;
  felt: Felt;
  updatedAtMs: EpochMs;
}

/** `users/{uid}/private/wallet`. READ: owner. WRITE: server only. Never negative. */
export interface WalletDoc {
  balanceCents: Cents;
  totalDepositedCents: Cents;
  totalWithdrawnCents: Cents;
  /** Deposits on UTC day `day` ("YYYY-MM-DD"), for the daily cap. */
  dailyDeposit: { day: string; amountCents: Cents };
  updatedAtMs: EpochMs;
}

/** `users/{uid}/private/kyc`. READ: owner. No birth date or document number is stored. */
export interface KycDoc {
  status: KycStatus;
  docType: KycDocType | null;
  submittedAtMs: EpochMs | null;
  /** While pending: the time after which the next `submitKyc{refresh:true}`/deposit/withdraw verifies. */
  verifyAfterMs: EpochMs | null;
  verifiedAtMs: EpochMs | null;
  rejectionReason: 'underage' | null;
}

/** `users/{uid}/private/suggestions` — friend suggestions (bot uids of similar rank). READ: owner. */
export interface FriendSuggestionsDoc {
  uids: Uid[];
  updatedAtMs: EpochMs;
}

/** `users/{uid}/private/ads` — rewarded-ad bookkeeping. READ: owner. */
export interface AdStateDoc {
  day: string;
  claimedToday: number;
  lastClaimAtMs: EpochMs;
}

/** `users/{uid}/ledger/{entryId}` — append-only wallet history. READ: owner. Order by createdAtMs desc. */
export interface LedgerEntryDoc {
  entryId: string;
  type: LedgerType;
  /** Signed: debit < 0, credit > 0. */
  amountCents: Cents;
  balanceAfterCents: Cents;
  createdAtMs: EpochMs;
  tableId: string | null;
  handNumber: number | null;
  marketId: string | null;
  powerId: PowerId | null;
  method: PaymentMethod | null;
}

/** `users/{uid}/inventory/{powerId}` — owned powers. READ: owner. */
export interface InventoryDoc {
  powerId: PowerId;
  quantity: number;
  updatedAtMs: EpochMs;
}

/** `users/{uid}/positions/{marketId}` — spectator market position. READ: owner. */
export interface PositionDoc {
  marketId: string;
  tableId: string;
  kind: MarketKind;
  question: LocalizedText;
  yesShares: number;
  noShares: number;
  /** Total cents spent buying. */
  costCents: Cents;
  /** Total cents received from selling. */
  proceedsCents: Cents;
  /** Cents paid at resolution (100 per winning share) or refunded on void. */
  payoutCents: Cents;
  status: 'open' | 'won' | 'lost' | 'void';
  updatedAtMs: EpochMs;
}

export interface LocalizedText { fr: string; en: string }

/** One hand of a seat as shown publicly on the table. */
export interface SeatHandDoc {
  cards: CardCode[];
  /** Best total (soft if `soft`). */
  total: number;
  soft: boolean;
  /** Amount at risk used for payout (doubles after a double). */
  betCents: Cents;
  /** Part of betCents actually paid by the player (less than betCents when a free power was used). */
  stakedCents: Cents;
  doubled: boolean;
  fromSplit: boolean;
  splitAces: boolean;
  surrendered: boolean;
  busted: boolean;
  /** Natural blackjack (2 cards, not from a split). */
  blackjack: boolean;
  /** No more actions on this hand. */
  done: boolean;
  /** Set when the hand is settled. */
  result: HandResult | null;
  /** Cents returned to the player at settlement (stake included). */
  returnCents: Cents | null;
}

export interface SeatInsuranceDoc {
  betCents: Cents;
  stakedCents: Cents;
  decided: boolean;
  result: 'win' | 'lose' | null;
}

/** A seat at a table (`TableDoc.seats[i]`, null when empty). */
export interface SeatDoc {
  seatIndex: number; // 0..4, dealt left to right in this order
  uid: Uid;
  username: string;
  avatar: AvatarId;
  isBot: boolean;
  rankTier: RankTier;
  /** 'leaving' = will be removed after the current hand (hands auto-stand). */
  status: 'active' | 'leaving';
  joinedAtMs: EpochMs;
  /** Initial bet for the current hand, 0 if not betting this hand. */
  betCents: Cents;
  /** Empty during betting; filled from the deal. */
  hands: SeatHandDoc[];
  insurance: SeatInsuranceDoc | null;
  /** Power used this hand (max 1). */
  powerUsed: PowerId | null;
  /** Set at settlement: total return − total stake for this hand. */
  roundNetCents: Cents | null;
  /** Consecutive betting rounds without a bet (humans are removed after 3). */
  missedRounds: number;
}

export interface DealerDoc {
  /** Visible cards. While `holeHidden`, only the up card (index 0) is listed. */
  cards: CardCode[];
  holeHidden: boolean;
  /** Total of the visible cards (null before the deal). */
  total: number | null;
  soft: boolean;
  blackjack: boolean;
  busted: boolean;
}

/**
 * Animation/event log of the current hand (reset when betting opens), in order of `seq`.
 * The client animates events with `seq` greater than the last one it rendered.
 *  - shuffle: a new shoe was started (before the deal).
 *  - bet: seat placed `amountCents`.
 *  - deal: card to seat/hand. dealerUp: dealer up card. dealerHole: face-down card (card = null).
 *  - peek: dealer checked for blackjack (`dealerBlackjack` tells the result).
 *  - insurance: seat took (amountCents > 0) or declined insurance.
 *  - hit / double / split / stand / surrender: player actions (`card` = card drawn if any).
 *    For split, the two resulting hands then receive `deal` events.
 *  - secondChance: `card` was discarded (it would have busted); the next `hit`/`double` event of the
 *    same hand carries the replacement.
 *  - power: seat used `power` (for peek the card is NOT shown).
 *  - timeout: the current decision timed out (auto stand / decline).
 *  - reveal: dealer hole card turned face up (`card`). dealerHit: dealer drew `card`.
 *  - settle: one hand settled (`result`, `amountCents` = returned cents).
 *  - leave / join: seat changes.
 */
export const TABLE_EVENT_TYPES = [
  'shuffle', 'bet', 'deal', 'dealerUp', 'dealerHole', 'peek', 'insurance', 'hit', 'double', 'split', 'stand',
  'surrender', 'secondChance', 'power', 'timeout', 'reveal', 'dealerHit', 'settle', 'join', 'leave',
] as const;
export type TableEventType = (typeof TABLE_EVENT_TYPES)[number];

export interface TableEvent {
  seq: number;
  type: TableEventType;
  seatIndex: number | null;
  handIndex: number | null;
  card: CardCode | null;
  amountCents: Cents | null;
  result: HandResult | null;
  power: PowerId | null;
  dealerBlackjack: boolean | null;
  atMs: EpochMs;
}

/** Queued human waiting for a seat (bots yield their seat at the next betting round). */
export interface QueueEntry {
  uid: Uid;
  username: string;
  avatar: AvatarId;
  rankTier: RankTier;
  queuedAtMs: EpochMs;
}

/**
 * `tables/{tableId}` — public table state. READ: signed-in. WRITE: server only.
 * Lobby: where('status','==','open').where('isPrivate','==',false) (client filters by stakeTier).
 */
export interface TableDoc {
  tableId: string;
  name: string;
  stakeTier: StakeTier;
  minBetCents: Cents;
  maxBetCents: Cents;
  isPrivate: boolean;
  /** Permanent table driven by sim_runner (bots come and go). */
  simManaged: boolean;
  status: 'open' | 'closed';
  phase: TablePhase;
  phaseStartedAtMs: EpochMs;
  /** When the current phase/turn times out (server clock). Null when nothing is pending. */
  deadlineMs: EpochMs | null;
  /** Incremented each time betting opens. 0 before the first hand. Send it with `act`/`placeBet`. */
  handNumber: number;
  shoe: ShoeInfo;
  /** Always length SEATS_PER_TABLE (5); null = empty seat. */
  seats: (SeatDoc | null)[];
  dealer: DealerDoc;
  /** Whose turn it is in 'playerTurns', else null. */
  turn: { seatIndex: number; handIndex: number } | null;
  fairness: FairnessPublic;
  events: TableEvent[];
  /** Highest `seq` ever issued on this table (monotonic across hands). */
  eventSeq: number;
  humanCount: number;
  botCount: number;
  /** uids of seated players (humans and bots). */
  seatedUids: Uid[];
  queue: QueueEntry[];
  /** Ids of the spectator markets of the current hand / shoe. `players` keyed by seat index ("0".."4"). */
  markets: { dealerBust: string | null; natural: string | null; shoe: string | null; players: Record<string, string> };
  /** Rank tier used for matchmaking (tier of the first human seated). */
  rankTier: RankTier;
  createdAtMs: EpochMs;
  updatedAtMs: EpochMs;
}

export interface ShoeInfo {
  shoeNumber: number;
  totalCards: number; // 312
  cardsRemaining: number;
  /** Hands completed in this shoe, dealer busts, hands with at least one natural. */
  handsDealt: number;
  dealerBusts: number;
  naturals: number;
}

export interface FairnessPublic {
  /** SHA-256 (hex) of the current hand's seed, published when betting opens. */
  currentCommit: string | null;
  currentHandNumber: number;
  /** Proof of the last finished hand; full proof in `tables/{id}/hands/{handNumber}`. */
  lastHandNumber: number | null;
  lastCommit: string | null;
  lastSeed: string | null;
}

/**
 * `tables/{tableId}/hands/{handNumber}` (doc id = handNumber zero-padded to 8 digits) — history of
 * a finished hand, with the provably-fair proof. READ: signed-in.
 * Verify: sha256(seed) == commit; dealt == fairDealOrder(remainingBefore, seed)[0..dealt.length)
 * (canonical sort by rank "A23456789TJQK" then suit "SHDC", Fisher-Yates with SHA-256 DRBG
 * `block_i = SHA-256(seed + ":" + i)`, 32-bit big-endian words, rejection sampling).
 */
export interface HandHistoryDoc {
  tableId: string;
  handNumber: number;
  startedAtMs: EpochMs;
  endedAtMs: EpochMs;
  dealerCards: CardCode[];
  dealerTotal: number;
  seats: Array<{ seatIndex: number; uid: Uid; username: string; isBot: boolean; hands: SeatHandDoc[]; netCents: Cents }>;
  fairness: { commit: string; seed: string; remainingBefore: CardCode[]; dealt: CardCode[] };
}

/** `tables/{tableId}/peeks/{uid}` — result of the peek power. READ: only that uid. */
export interface PeekDoc {
  handNumber: number;
  holeCard: CardCode;
  createdAtMs: EpochMs;
}

/**
 * `markets/{marketId}` — spectator market. READ: signed-in.
 * LMSR: cost C(qYes,qNo) = b·ln(e^(qYes/b) + e^(qNo/b)) dollars; price of YES = e^(qYes/b)/(…).
 * Buying is rounded UP to the cent, selling DOWN (house never loses to rounding).
 */
export interface MarketDoc {
  marketId: string;
  tableId: string;
  tableName: string;
  kind: MarketKind;
  /** Hand number for per-hand markets, null for shoe markets. */
  handNumber: number | null;
  shoeNumber: number;
  /** For playerWins. */
  subjectUid: Uid | null;
  subjectUsername: string | null;
  subjectSeatIndex: number | null;
  question: LocalizedText;
  status: MarketStatus;
  outcome: MarketSide | null;
  /** LMSR liquidity (shares). */
  b: number;
  /** Outstanding shares sold by the market maker. */
  qYes: number;
  qNo: number;
  /** Current YES price in [0,1] (display ×100 as ¢). NO price = 1 − priceYes. */
  priceYes: number;
  volumeCents: Cents;
  tradeCount: number;
  /** True once every position of a resolved/void market has been paid. */
  payoutsDone: boolean;
  createdAtMs: EpochMs;
  closedAtMs: EpochMs | null;
  resolvedAtMs: EpochMs | null;
}

/** `markets/{marketId}/trades/{tradeId}` — public activity feed. READ: signed-in. */
export interface TradeDoc {
  tradeId: string;
  uid: Uid;
  username: string;
  isBot: boolean;
  side: MarketSide;
  direction: TradeDirection;
  shares: number;
  /** Cents paid (buy) or received (sell). */
  amountCents: Cents;
  priceYesAfter: number;
  createdAtMs: EpochMs;
}

/** `markets/{marketId}/priceHistory/{pointId}` — chart points. READ: signed-in. Order by atMs. */
export interface PricePointDoc {
  atMs: EpochMs;
  priceYes: number;
}

/**
 * `friendRequests/{fromUid}_{toUid}` — pending requests. READ: sender or recipient
 * (query where('toUid','==',me) / where('fromUid','==',me)). WRITE: server only.
 * Deleted when answered.
 */
export interface FriendRequestDoc {
  fromUid: Uid;
  toUid: Uid;
  fromUsername: string;
  toUsername: string;
  fromAvatar: AvatarId;
  createdAtMs: EpochMs;
}

/**
 * `friendships/{uidA}_{uidB}` (uids sorted ascending) — READ: the two participants
 * (query where('uids','array-contains',me)). WRITE: server only.
 */
export interface FriendshipDoc {
  uids: [Uid, Uid];
  usernames: Record<Uid, string>;
  sinceMs: EpochMs;
}

/** `feed/{entryId}` — "recent wins" ticker. READ: signed-in. Order by createdAtMs desc. */
export interface FeedEntryDoc {
  username: string;
  avatar: AvatarId;
  isBot: boolean;
  kind: 'blackjack' | 'bigWin' | 'market';
  amountCents: Cents;
  tableId: string | null;
  createdAtMs: EpochMs;
}

/*
 * Server-only collections (all client access denied): `tables/{id}/private/state` (shoe, hole card,
 * seed), `usernames/{lower}`, `tableCodes/{code}`, `idempotency/{uid}_{requestId}`, `rateLimits/{uid}`.
 */

// ============================================================================================
// Error reasons (HttpsError.details.reason)
// ============================================================================================

export const ERROR_REASONS = [
  'INVALID_ARGUMENT', //       schema violation (wrong type, decimal, negative, out of bounds, unknown field)
  'UNAUTHENTICATED', //        no auth
  'RATE_LIMITED', //           resource-exhausted
  'REQUEST_ID_REUSED', //      same requestId used for another callable
  'PROFILE_REQUIRED', //       call completeProfile first (failed-precondition)
  'PROFILE_EXISTS', //         completeProfile twice (already-exists)
  'USERNAME_TAKEN', //         already-exists
  'KYC_REQUIRED', //           deposit/withdraw without verified KYC (failed-precondition)
  'KYC_ALREADY_VERIFIED', //   failed-precondition
  'KYC_REJECTED', //           failed-precondition (KYC was rejected as underage; final)
  'INSUFFICIENT_FUNDS', //     failed-precondition
  'DEPOSIT_LIMIT', //          per-deposit or daily cap exceeded (failed-precondition)
  'TABLE_NOT_FOUND', //        not-found
  'TABLE_CLOSED', //           failed-precondition
  'TABLE_FULL', //             failed-precondition (private table full)
  'BAD_CODE', //               not-found (private code)
  'ALREADY_SEATED', //         joinMatchmaking while seated elsewhere (failed-precondition)
  'NOT_SEATED', //             failed-precondition
  'BAD_PHASE', //              action not allowed in this phase (failed-precondition)
  'STALE_HAND', //             handNumber does not match the current hand (failed-precondition)
  'ALREADY_BET', //            failed-precondition
  'BET_OUT_OF_RANGE', //       invalid-argument (min/max or not whole dollars)
  'NOT_YOUR_TURN', //          failed-precondition (also: acting on someone else's seat)
  'ILLEGAL_ACTION', //         failed-precondition (e.g. double on 3 cards)
  'POWER_NOT_OWNED', //        failed-precondition
  'POWER_ALREADY_USED', //     failed-precondition (one power per hand)
  'POWER_NOT_APPLICABLE', //   invalid-argument (power does not match the action)
  'INVENTORY_FULL', //         failed-precondition
  'MARKET_NOT_FOUND', //       not-found
  'MARKET_CLOSED', //          failed-precondition
  'OWN_TABLE_MARKET', //       permission-denied: betting on a market of the table you sit/queue at
  'INSUFFICIENT_SHARES', //    failed-precondition (sell more than owned)
  'SLIPPAGE', //               failed-precondition (cost above maxCostCents / proceeds below minProceedsCents)
  'MARKET_LIMIT', //           failed-precondition (trade would push the price to within ~2e-9 of 0 or 1)
  'USER_NOT_FOUND', //         not-found
  'SELF_FRIEND', //            invalid-argument
  'ALREADY_FRIENDS', //        already-exists
  'REQUEST_EXISTS', //         already-exists
  'REQUEST_NOT_FOUND', //      not-found
  'NOT_FRIENDS', //            not-found
  'AD_COOLDOWN', //            failed-precondition
  'AD_DAILY_LIMIT', //         failed-precondition
  'INTERNAL', //               internal
] as const;
export type ErrorReason = (typeof ERROR_REASONS)[number];

export interface ErrorDetails { reason: ErrorReason }

// ============================================================================================
// Callables
// ============================================================================================

/** Base fields of every request. */
export interface BaseRequest {
  /** 8..64 chars [A-Za-z0-9_-]. Unique per logical operation; reuse it on retry. */
  requestId: string;
}

/**
 * completeProfile — after Firebase Auth sign-up (email/password). Creates profiles/{uid},
 * users/{uid} (default settings: dark, fr, classicBlue, classic, green), wallet with the
 * welcome bonus (ledger 'welcomeBonus'), friend suggestions, and 1–2 incoming bot friend requests.
 * Errors: PROFILE_EXISTS, USERNAME_TAKEN, INVALID_ARGUMENT.
 */
export interface CompleteProfileRequest extends BaseRequest {
  /** 3..16 chars [A-Za-z0-9_]. */
  username: string;
  avatar: AvatarId;
  /** Optional initial language (default 'fr'). */
  language?: Language;
}
export interface CompleteProfileResponse { uid: Uid; username: string; balanceCents: Cents }

/**
 * submitKyc — simulated identity check. Either submit `{docType, birthDate}` or poll with
 * `{refresh: true}`.
 *  - Under 18 → NO error: the response (and `users/{uid}/private/kyc`) has status 'rejected',
 *    rejectionReason 'underage'. Rejection is final (later submits/deposits → KYC_REJECTED).
 *  - Otherwise status 'pending' with verifyAfterMs = now + KYC_REVIEW_MS (≈3 s). The next call after
 *    that time — `submitKyc{refresh:true}`, deposit, withdraw — flips it to 'verified' (sim_runner
 *    also completes due reviews every ~10 s). Listen to `users/{uid}/private/kyc` for the change.
 *  - Submitting again while pending just returns the pending status.
 * birthDate must be a real calendar date "YYYY-MM-DD", not in the future, year ≥ 1900. It is used for
 * the age check only and is NOT stored.
 * Errors: KYC_ALREADY_VERIFIED, KYC_REJECTED, INVALID_ARGUMENT (bad date), PROFILE_REQUIRED.
 */
export type SubmitKycRequest =
  | (BaseRequest & { docType: KycDocType; /** "YYYY-MM-DD" */ birthDate: string })
  | (BaseRequest & { refresh: true });
export interface SubmitKycResponse { status: KycStatus; verifyAfterMs: EpochMs | null; rejectionReason: 'underage' | null }

/**
 * deposit — simulated deposit (no payment data is sent: only amount + method).
 * amountCents: integer, DEPOSIT_MIN_CENTS..DEPOSIT_MAX_CENTS; daily cap DEPOSIT_DAILY_CAP_CENTS.
 * Errors: KYC_REQUIRED, DEPOSIT_LIMIT, INVALID_ARGUMENT, PROFILE_REQUIRED.
 */
export interface DepositRequest extends BaseRequest { amountCents: Cents; method: PaymentMethod }
export interface DepositResponse { balanceCents: Cents; ledgerEntryId: string }

/** withdraw — amountCents WITHDRAW_MIN..WITHDRAW_MAX and ≤ balance. Errors: KYC_REQUIRED, INSUFFICIENT_FUNDS. */
export interface WithdrawRequest extends BaseRequest { amountCents: Cents; method: PaymentMethod }
export interface WithdrawResponse { balanceCents: Cents; ledgerEntryId: string }

/**
 * joinMatchmaking — find a seat.
 *  - mode 'quick': public table of `stakeTier`. Priority: tables with humans of the same rank
 *    tier, then tables with humans, then tables with only bots (a bot yields its seat), else a new
 *    table with 2 bots. If no seat is free right now you are `queued` and seated at the next
 *    betting round (`profiles/{uid}.currentTableId` is set immediately).
 *  - mode 'createPrivate': new private table (no bots), returns a 6-char `code` to share.
 *  - mode 'joinCode': join the private table with `code` (stakeTier ignored).
 * If already seated/queued at a table, returns that table (status 'seated'/'queued') for 'quick'
 * of the same tier; otherwise ALREADY_SEATED (leave first).
 * Errors: BAD_CODE, TABLE_FULL, ALREADY_SEATED, PROFILE_REQUIRED.
 */
export interface JoinMatchmakingRequest extends BaseRequest {
  mode: 'quick' | 'createPrivate' | 'joinCode';
  stakeTier: StakeTier;
  /** Required for 'joinCode': 6 chars [A-Z0-9] (case-insensitive). */
  code?: string;
}
export interface JoinMatchmakingResponse {
  tableId: string;
  status: 'seated' | 'queued';
  seatIndex: number | null;
  /** Private table code (createPrivate / joinCode), else null. */
  code: string | null;
}

/**
 * leaveTable — leave (or leave the queue). During betting, an unplayed bet is refunded. During a
 * hand, your seat becomes 'leaving': remaining hands auto-stand and are settled normally.
 */
export interface LeaveTableRequest extends BaseRequest { tableId: string }
export interface LeaveTableResponse { left: true; refundedCents: Cents }

/**
 * placeBet — phase 'betting' only, once per hand. amountCents: whole dollars within the table's
 * min/max. Debits the wallet (ledger 'bet').
 * Errors: BAD_PHASE, STALE_HAND, ALREADY_BET, BET_OUT_OF_RANGE, INSUFFICIENT_FUNDS, NOT_SEATED.
 */
export interface PlaceBetRequest extends BaseRequest { tableId: string; handNumber: number; amountCents: Cents }
export interface PlaceBetResponse { betCents: Cents; balanceCents: Cents; phase: TablePhase }

/**
 * act — a decision on YOUR seat (the seat is derived from your uid; there is no seat parameter).
 * `handIndex` (optional) must equal `table.turn.handIndex` (ignored for insurance).
 * - hit / stand / double / split / surrender / peek: phase 'playerTurns' and `turn` is your seat.
 *   surrender only on the first two cards of an unsplit hand; double on two cards (not split aces);
 *   split on two equal-value cards while you have < 4 hands; 'peek' requires power 'peek'.
 * - insurance: phase 'insurance', amountCents 0 (decline) .. floor(betCents/2).
 * - double/split debit an extra stake equal to the hand's bet (unless free power).
 * - power: optional PowerId consumed from inventory (see PowerId doc for valid combinations).
 * Errors: BAD_PHASE, STALE_HAND, NOT_YOUR_TURN, ILLEGAL_ACTION, INSUFFICIENT_FUNDS, POWER_NOT_OWNED,
 * POWER_ALREADY_USED, POWER_NOT_APPLICABLE, NOT_SEATED.
 */
export interface ActRequest extends BaseRequest {
  tableId: string;
  handNumber: number;
  action: PlayerAction;
  handIndex?: number;
  amountCents?: Cents;
  power?: PowerId;
}
export interface ActResponse { phase: TablePhase; balanceCents: Cents }

/** pokeTable — ask the server to apply overdue deadlines (server re-checks its own clock). */
export interface PokeTableRequest extends BaseRequest { tableId: string }
export interface PokeTableResponse { phase: TablePhase; handNumber: number; deadlineMs: EpochMs | null; advanced: boolean }

/** buyPower — quantity 1..10, inventory max 99. Errors: INSUFFICIENT_FUNDS, INVENTORY_FULL. */
export interface BuyPowerRequest extends BaseRequest { powerId: PowerId; quantity: number }
export interface BuyPowerResponse { quantity: number; balanceCents: Cents }

/**
 * tradeShares — buy or sell YES/NO shares (integer 1..1000) on an open market.
 * Buy: pays ceil(LMSR cost) cents; optional `maxCostCents` slippage guard.
 * Sell: receives floor(LMSR proceeds); you must own the shares; optional `minProceedsCents`.
 * Errors: MARKET_NOT_FOUND, MARKET_CLOSED, OWN_TABLE_MARKET, INSUFFICIENT_FUNDS, INSUFFICIENT_SHARES, SLIPPAGE.
 */
export interface TradeSharesRequest extends BaseRequest {
  marketId: string;
  side: MarketSide;
  direction: TradeDirection;
  shares: number;
  maxCostCents?: Cents;
  minProceedsCents?: Cents;
}
export interface TradeSharesResponse {
  amountCents: Cents;
  priceYes: number;
  balanceCents: Cents;
  position: { yesShares: number; noShares: number };
}

/**
 * friendRequest — by uid or username (exactly one). If the other user already sent you a request,
 * you become friends immediately (status 'accepted'). Requests to bots are accepted by sim_runner.
 * Errors: USER_NOT_FOUND, SELF_FRIEND, ALREADY_FRIENDS, REQUEST_EXISTS.
 */
export type FriendRequestRequest =
  | (BaseRequest & { toUid: Uid })
  | (BaseRequest & { toUsername: string });
export interface FriendRequestResponse { status: 'pending' | 'accepted'; toUid: Uid }

/** respondFriend — answer a request you received. Errors: REQUEST_NOT_FOUND. */
export interface RespondFriendRequest extends BaseRequest { fromUid: Uid; accept: boolean }
export interface RespondFriendResponse { status: 'accepted' | 'declined' }

/** removeFriend — Errors: NOT_FRIENDS. */
export interface RemoveFriendRequest extends BaseRequest { friendUid: Uid }
export interface RemoveFriendResponse { removed: true }

/**
 * claimAdReward — after a fake rewarded ad. +AD_REWARD_CENTS, max AD_REWARD_DAILY_MAX per UTC day,
 * at least AD_REWARD_COOLDOWN_MS apart. `adId`: 1..40 chars [A-Za-z0-9_-] (free-form).
 */
export interface ClaimAdRewardRequest extends BaseRequest { adId: string }
export interface ClaimAdRewardResponse { rewardCents: Cents; balanceCents: Cents; remainingToday: number }

/** equipCardStyle — at least one field. Same effect as writing users/{uid} directly. */
export interface EquipCardStyleRequest extends BaseRequest { cardBack?: CardBack; cardFace?: CardFace; felt?: Felt }
export interface EquipCardStyleResponse { cardBack: CardBack; cardFace: CardFace; felt: Felt }

/** Name → [request, response] map of every callable. */
export interface Callables {
  completeProfile: [CompleteProfileRequest, CompleteProfileResponse];
  submitKyc: [SubmitKycRequest, SubmitKycResponse];
  deposit: [DepositRequest, DepositResponse];
  withdraw: [WithdrawRequest, WithdrawResponse];
  joinMatchmaking: [JoinMatchmakingRequest, JoinMatchmakingResponse];
  leaveTable: [LeaveTableRequest, LeaveTableResponse];
  placeBet: [PlaceBetRequest, PlaceBetResponse];
  act: [ActRequest, ActResponse];
  pokeTable: [PokeTableRequest, PokeTableResponse];
  buyPower: [BuyPowerRequest, BuyPowerResponse];
  tradeShares: [TradeSharesRequest, TradeSharesResponse];
  friendRequest: [FriendRequestRequest, FriendRequestResponse];
  respondFriend: [RespondFriendRequest, RespondFriendResponse];
  removeFriend: [RemoveFriendRequest, RemoveFriendResponse];
  claimAdReward: [ClaimAdRewardRequest, ClaimAdRewardResponse];
  equipCardStyle: [EquipCardStyleRequest, EquipCardStyleResponse];
}
export type CallableName = keyof Callables;
export const CALLABLE_NAMES: CallableName[] = [
  'completeProfile', 'submitKyc', 'deposit', 'withdraw', 'joinMatchmaking', 'leaveTable', 'placeBet', 'act',
  'pokeTable', 'buyPower', 'tradeShares', 'friendRequest', 'respondFriend', 'removeFriend', 'claimAdReward',
  'equipCardStyle',
];
