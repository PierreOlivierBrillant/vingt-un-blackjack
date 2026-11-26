/**
 * Roulette (European, single zero) — shared contract. OWNER: roulette implementer.
 * Values in the exported lists below are spread into the global unions of ../types.ts.
 * Append new values at the END of a list (never rename/remove: Dart mirrors them).
 *
 * Rules: PLAN_SPRINT2.md « Roulette européenne ». Engine: src/games/roulette/engine.ts (pure),
 * module: src/games/roulette/module.ts. Client mirror: app/lib/features/games/roulette/.
 *
 * ROUND (table `step` in brackets)
 *   betting ['betting'] 20 s ─deadline─▶ "Rien ne va plus": the number is drawn IN THIS transaction
 *   (`seededRng(seed).nextInt(37)`), published in `g.number` + event 'spin', the per-round markets
 *   are closed and resolved ─▶ live ['spinning'] 8 s (the client animates the ball landing in
 *   `g.number`) ─deadline─▶ settlement (events 'result' + 'payout', wallet credits) ─▶ settled 6 s
 *   ─▶ next round. A round where every board is empty restarts its betting (same round number).
 *
 * BET SPOT IDS (`bets/{uid}.bets` keys; anything else → BAD_BET_SPOT). 157 spots in all:
 *   n{0..36}            plein / straight up (1 number)                                   35:1
 *   sp{a}-{b}           cheval / split, a < b adjacent on the layout: b = a + 1 in the same
 *                       street (a % 3 ≠ 0), b = a + 3, or 0-1, 0-2, 0-3                  17:1
 *   st{a}               transversale pleine / street a, a+1, a+2 (a = 1, 4, …, 34)          11:1
 *   tr0-1-2, tr0-2-3    trios with the zero                                              11:1
 *   co{a}               carré / corner a, a+1, a+3, a+4 (a = 1..32, a % 3 ≠ 0)             8:1
 *   first4              premier quatre / first four 0, 1, 2, 3                             8:1
 *   ln{a}               sixain / six line a..a+5 (a = 1, 4, …, 31)                         5:1
 *   dozen1..dozen3      douzaines 1–12, 13–24, 25–36                                       2:1
 *   col1..col3          colonnes: col1 = 1, 4, …, 34; col2 = 2, 5, …, 35; col3 = 3, 6, …, 36  2:1
 *   red, black, odd, even, low (1–18), high (19–36)   chances simples / even money          1:1
 *   Amounts: whole dollars (kernel), each spot ≥ limits.minBetCents and ≤ its type's cap
 *   (limits.extra, see ROULETTE_LIMIT_KEYS) → else BET_OUT_OF_RANGE; round total ≤ maxRoundCents.
 *   No "la partage" by default: every even-money bet loses on 0 (house edge 1/37 = 2.70 % on
 *   every spot). Power zeroShield (setBets `power: 'zeroShield'`, the board must hold an
 *   even-money bet, else POWER_NOT_APPLICABLE): on 0, the seat's even-money bets return half.
 *   Call bets (voisins du zéro, tiers, orphelins, jeu zéro, neighbours), undo, clear, repeat and
 *   double are computed by the CLIENT, which always sends the whole board.
 *
 * PUBLIC STATE `g` (RoulettePublic) — seat state `seats[i].g` (RouletteSeat) — private `g`: {}.
 *
 * EVENTS (table `events`, reset each round; kernel types join/leave/power… as well)
 *   'spin'   seat null  { number, color: 'red'|'black'|'green', spinMs }  at "Rien ne va plus"
 *   'result' seat null  { number, color }                                   at settlement
 *   'payout' seat i     { stakedCents, returnCents, netCents, wins: spotId[], shield: boolean }
 *                       one per seat that played, at settlement (after 'result')
 *
 * ROUND RESULT `rounds/{n}.result`: { number, color }. Fairness: `fairness.dealt` etc. are null;
 * verify with sha256(seed) == commit and seededRng(seed).nextInt(37) == result.number.
 *
 * PROFILE COUNTERS `gameStats.roulette.counters`: straightUps (rounds with a winning plein),
 * zeroShieldSaves (rounds where the zero shield returned money). Feed: `highlight: 'jackpot'` on a
 * winning plein (net > 0).
 *
 * MARKETS: per round rouletteRed « Rouge ? », rouletteZero « Zéro ? », rouletteDozen3
 * « 3e douzaine ? » (opened with the round, closed AND resolved in the "Rien ne va plus"
 * transaction). Simulated tables only: rouletteZeroSeries « Un zéro dans les 37 prochains tours ? »
 * (spins counted from the round it opens with; closed after ROULETTE_ZERO_SERIES_CLOSE_AFTER
 * spins; resolved YES at the first zero, NO after 37 spins without one; voided if the table closes).
 *
 * GAME ACTIONS: none (only the kernel's setBets) — any other `action.type` → INVALID_ARGUMENT.
 */
export const ROULETTE_POWER_IDS = ['zeroShield'] as const;
export const ROULETTE_MARKET_KINDS = ['rouletteRed', 'rouletteZero', 'rouletteDozen3', 'rouletteZeroSeries'] as const;
export const ROULETTE_REASONS = [] as const;

export type RoulettePowerId = (typeof ROULETTE_POWER_IDS)[number];

/** Bet types of the layout (see the spot grammar above). */
export const ROULETTE_SPOT_TYPES = ['straight', 'split', 'street', 'trio', 'corner', 'firstFour', 'line', 'dozen', 'column', 'even'] as const;
export type RouletteSpotType = (typeof ROULETTE_SPOT_TYPES)[number];

/** Payout "X to 1" of each bet type (a winning bet returns stake × (X + 1)). */
export const ROULETTE_PAYOUTS: Record<RouletteSpotType, number> = {
  straight: 35, split: 17, street: 11, trio: 11, corner: 8, firstFour: 8, line: 5, dozen: 2, column: 2, even: 1,
};

/** Even-money spot ids (chances simples). */
export const ROULETTE_EVEN_SPOTS = ['red', 'black', 'odd', 'even', 'low', 'high'] as const;

/**
 * `limits.extra` keys: maximum on ONE spot of each type (trios share the street cap, the first
 * four the corner cap; dozens and columns share `dozenMaxCents`). `limits.maxBetCents` is the
 * largest of them, `maxRoundCents` the per-round total.
 */
export const ROULETTE_LIMIT_KEYS: Record<RouletteSpotType, string> = {
  straight: 'straightMaxCents', split: 'splitMaxCents', street: 'streetMaxCents', trio: 'streetMaxCents',
  corner: 'cornerMaxCents', firstFour: 'cornerMaxCents', line: 'lineMaxCents', dozen: 'dozenMaxCents',
  column: 'dozenMaxCents', even: 'evenMaxCents',
};

/** Durations of the roulette steps (ms). */
export const ROULETTE_TIMING = { bettingMs: 20_000, spinMs: 8_000, settledMs: 6_000 } as const;

/** Numbers kept in `g.last` (history, hot / cold numbers). */
export const ROULETTE_HISTORY_LENGTH = 100;
/** Length of the long market « Un zéro dans les 37 prochains tours ? ». */
export const ROULETTE_ZERO_SERIES_LENGTH = 37;
/** The series market stops trading after this many spins (outcome still pending). */
export const ROULETTE_ZERO_SERIES_CLOSE_AFTER = 18;
/** Distinct chip colours of the table (one per seat; `RouletteSeat.color`). */
export const ROULETTE_CHIP_COLORS = 7;

export type RouletteColor = 'red' | 'black' | 'green';

/** `gameTables/{id}.g` of a roulette table. */
export interface RoulettePublic {
  /** Number of the current round once drawn ("Rien ne va plus"), null while betting. */
  number: number | null;
  /** Last drawn numbers, oldest first (max ROULETTE_HISTORY_LENGTH). */
  last: number[];
  /** Series market in progress (simulated tables): first round counted, trading closed? */
  series: { n: number; startRound: number; closed: boolean } | null;
  /** Series markets opened so far (numbering). */
  seriesCount: number;
}

/** `seats[i].g` of a roulette seat. */
export interface RouletteSeat {
  /** Chip colour of the player, 0..ROULETTE_CHIP_COLORS-1, unique at the table. */
  color: number;
}

export type RoulettePrivate = Record<string, never>;

/** Payload of the 'spin' event. */
export interface RouletteSpinEvent { number: number; color: RouletteColor; spinMs: number }
/** Payload of the 'payout' event (one per seat that played). */
export interface RoulettePayoutEvent {
  stakedCents: number;
  returnCents: number;
  netCents: number;
  /** Winning spot ids of the seat. */
  wins: string[];
  /** The zero shield returned half of the even-money bets. */
  shield: boolean;
}
