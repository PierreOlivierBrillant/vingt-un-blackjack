/**
 * The 120 fake bot players, generated deterministically (fixed seeds) so the seed script, the
 * table state machines and the tests all agree on uids, names and personalities without any
 * Firestore read. Pure module.
 *
 * Sprint 2: bots 1..60 are strictly identical to Sprint 1 (same seed, same order). Bots 61..108
 * are the rosters of the kernel games' simulated tables (8 rosters of 6, see gameSimRoster), bots
 * 109..120 are 12 more free bots (matchmaking tables of every game).
 */
import { fastRng, nextFloat } from '../engine/rng';
import type { AvatarId, RankTier, StakeTier } from '../shared/types';
import { RANK_TIER_THRESHOLDS, RANK_TIERS } from '../shared/types';

const NAMES = [
  'LuckyLuc', 'AceOfMarie', 'Kev_21', 'SplitQueen', 'CamilleBJ', 'HitMeHugo', 'NoBustNico', 'Soft17Sarah',
  'DoubleDown_Dan', 'InesAllIn', 'TheCountess', 'JulesJackpot', 'MaxStands', 'LeaLuckyCharm', 'TomTenTen',
  'ChipStacker', 'Yasmine_Ace', 'RiverRaph', 'Manon21', 'KingOfClubs', 'PaulinePeek', 'Antoine_A7',
  'DealerSlayer', 'BettyBets', 'Zoe_Splits', 'MehdiMoney', 'ChloeChips', 'Gaby_Gamble', 'TheShoeWhisperer',
  'LucasLowCard', 'EmmaEvenMoney', 'NathanNatural', 'ClaraCutCard', 'Sami_Surrender', 'OliviaOdds',
  'BastienBank', 'JadeJoker', 'Victor_Vegas', 'LouLuck', 'HugoHighRoller', 'AliceAces', 'Remi_Risky',
  'SophieSoft', 'EthanEdge', 'Lina_Lucky7', 'MathisMarker', 'NoraNoBust', 'Theo_Twentyone', 'ElsaEights',
  'AdamAnte', 'LolaLimit', 'KarimKings', 'MiaMartingale', 'Gabin_Gold', 'RoseRoyale', 'Axel_Aces',
  'CelesteCards', 'Ilyes_Insure', 'JuliaJack', 'OscarOnTilt',
] as const;

/** Sprint 2 bots (61..120): game sim rosters then free bots. Unique case-insensitively with NAMES. */
const NAMES_V2 = [
  'RougeRemy', 'NoirNadia', 'ZeroZoe', 'PleinPierre', 'ChevalChris', 'CarreClaire', 'SixainSam', 'DouzaineDina',
  'ColonneColin', 'ImpairIrene', 'PasseParis', 'ManqueMarc', 'PuntoPaul', 'BancoBea', 'EgaliteEli', 'SabotSimon',
  'SqueezeSue', 'NaturelNoe', 'PaireParfaite', 'FlopFabien', 'TurnTina', 'BluffBenoit', 'AllInAmelie', 'PocketPietro',
  'ButtonBella', 'BigBlindBob', 'CheckRaiseCleo', 'SuitedSuzie', 'NutsNathan', 'FoldFanny', 'RoyalRayan', 'StraddleStan',
  'DiceDiego', 'SnakeEyesSofia', 'BoxcarsBen', 'HardEightHana', 'YoYoYanis', 'PointPauline', 'ComeOutCyril', 'FieldFelix',
  'ShooterSarah', 'SevenOutSeb', 'OddsOlga', 'LayLeon', 'PlaceSixPia', 'PuckPatrice', 'StickmanSteve', 'CrapsCarla',
  'LuckyLaura', 'VelvetVince', 'NeonNina', 'JetonJules', 'TapisTess', 'MiseMaxime', 'RouletteRita', 'BaccaraBruno',
  'PokerPaloma', 'CrapsCedric', 'CasinoCamelia', 'JackpotJoy',
] as const;

export interface BotProfile {
  uid: string;
  username: string;
  avatar: AvatarId;
  rankPoints: number;
  rankTier: RankTier;
  /** 0..1 — probability of a basic-strategy mistake. */
  noise: number;
  /** Preferred stake tier. */
  stakeTier: StakeTier;
  /** Bet = whole dollars around this fraction of the table range. */
  betStyle: 'min' | 'flat' | 'aggressive';
  /** Market trading appetite 0..1. */
  traderAppetite: number;
  /** Seed for deterministic history generation. */
  seed: number;
}

export function rankTierFor(points: number): RankTier {
  let tier: RankTier = 'bronze';
  for (const t of RANK_TIERS) if (points >= RANK_TIER_THRESHOLDS[t]) tier = t;
  return tier;
}

function build(names: readonly string[], seed: number, offset: number): BotProfile[] {
  const rng = fastRng(seed);
  return names.map((username, j) => {
    const i = offset + j;
    // Skewed rank distribution: many bronze/silver, few diamond.
    const u = nextFloat(rng);
    const rankPoints = Math.round(9_000 * u ** 2.2) + rng.nextInt(60);
    const tierIdx = rng.nextInt(10);
    const stakeTier: StakeTier = tierIdx < 5 ? 'low' : tierIdx < 9 ? 'mid' : 'high';
    const styles = ['min', 'flat', 'aggressive'] as const;
    return {
      uid: `bot_${String(i + 1).padStart(3, '0')}`,
      username,
      avatar: `avatar${String((i % 24) + 1).padStart(2, '0')}`,
      rankPoints,
      rankTier: rankTierFor(rankPoints),
      noise: 0.02 + nextFloat(rng) * 0.18,
      stakeTier,
      betStyle: styles[rng.nextInt(3)],
      traderAppetite: nextFloat(rng),
      seed: 1_000 + i,
    };
  });
}

/** Sprint 1 bots (bot_001..bot_060), unchanged. */
export const BOTS_V1: readonly BotProfile[] = build(NAMES, 60_060, 0);
export const BOTS: readonly BotProfile[] = [...BOTS_V1, ...build(NAMES_V2, 120_120, NAMES.length)];
export const BOT_BY_UID: ReadonlyMap<string, BotProfile> = new Map(BOTS.map((b) => [b.uid, b]));

export function isBotUid(uid: string): boolean {
  return BOT_BY_UID.has(uid);
}

/** Number of permanent simulated tables and their bot rosters (disjoint, 6 bots each). */
export const SIM_TABLE_COUNT = 8;
export const SIM_ROSTER_SIZE = 6;

export function simTableId(i: number): string {
  return `sim-${String(i + 1).padStart(2, '0')}`;
}

export function simRoster(tableIndex: number): BotProfile[] {
  return BOTS.slice(tableIndex * SIM_ROSTER_SIZE, (tableIndex + 1) * SIM_ROSTER_SIZE);
}

/** Kernel games' simulated tables: 8 rosters of 6 bots (bots 61..108), 2 tables per game by default. */
export const GAME_SIM_ROSTERS = 8;
const GAME_SIM_FIRST_BOT = 60;
const GAME_SIM_PREFIXES = ['rl', 'bc', 'ho', 'cr'] as const;

/** Id of the n-th (0-based) simulated table of a kernel game, from its id prefix: `rl-sim-01`. */
export function gameSimTableId(prefix: string, n: number): string {
  return `${prefix}-sim-${String(n + 1).padStart(2, '0')}`;
}

/**
 * Bot roster of a kernel game's simulated table (`<prefix>-sim-NN`), or null for any other id.
 * Tables 1 and 2 of each game have their own roster; further tables (more than 2 per game) reuse
 * the rosters cyclically.
 */
export function gameSimRoster(tableId: string): BotProfile[] | null {
  const m = /^(rl|bc|ho|cr)-sim-(\d{2})$/.exec(tableId);
  if (!m) return null;
  const g = (GAME_SIM_PREFIXES as readonly string[]).indexOf(m[1]);
  const n = Number(m[2]) - 1;
  if (n < 0) return null;
  const slot = (g * 2 + n) % GAME_SIM_ROSTERS;
  const start = GAME_SIM_FIRST_BOT + slot * SIM_ROSTER_SIZE;
  return BOTS.slice(start, start + SIM_ROSTER_SIZE);
}

/** Bots not owned by a simulated table (bots 49..60 and 109..120): used to fill matchmaking tables. */
export const FREE_BOTS: readonly BotProfile[] = [
  ...BOTS.slice(SIM_TABLE_COUNT * SIM_ROSTER_SIZE, BOTS_V1.length),
  ...BOTS.slice(GAME_SIM_FIRST_BOT + GAME_SIM_ROSTERS * SIM_ROSTER_SIZE),
];

export const SIM_TABLE_NAMES = [
  'Monte-Carlo', 'Las Vegas Strip', 'Atlantic', 'Riviera', 'Macao Nights', 'Le Lion d’Or', 'Blue Lagoon', 'Diamond Room',
];
export const SIM_TABLE_TIERS: StakeTier[] = ['low', 'low', 'low', 'mid', 'mid', 'mid', 'high', 'low'];

/** Friend suggestions: up to 5 bots closest in rank points to `points`, stable for a given uid. */
export function suggestionsFor(uid: string, points: number, n = 5): string[] {
  let h = 0;
  for (const ch of uid) h = (h * 31 + ch.charCodeAt(0)) | 0;
  const ranked = [...BOTS_V1].sort((a, b) => Math.abs(a.rankPoints - points) - Math.abs(b.rankPoints - points));
  const pool = ranked.slice(0, 12);
  const out: string[] = [];
  for (let i = 0; out.length < n && i < pool.length; i++) {
    const pick = pool[Math.abs(h + i * 7) % pool.length];
    if (!out.includes(pick.uid)) out.push(pick.uid);
  }
  for (const b of pool) if (out.length < n && !out.includes(b.uid)) out.push(b.uid);
  return out;
}
