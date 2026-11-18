/**
 * The ~60 fake bot players, generated deterministically (fixed seed) so the seed script, the
 * table state machine and the tests all agree on uids, names and personalities without any
 * Firestore read. Pure module.
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

function build(): BotProfile[] {
  const rng = fastRng(60_060);
  return NAMES.map((username, i) => {
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

export const BOTS: readonly BotProfile[] = build();
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

/** Bots not owned by a simulated table: used to fill matchmaking tables. */
export const FREE_BOTS: readonly BotProfile[] = BOTS.slice(SIM_TABLE_COUNT * SIM_ROSTER_SIZE);

export const SIM_TABLE_NAMES = [
  'Monte-Carlo', 'Las Vegas Strip', 'Atlantic', 'Riviera', 'Macao Nights', 'Le Lion d’Or', 'Blue Lagoon', 'Diamond Room',
];
export const SIM_TABLE_TIERS: StakeTier[] = ['low', 'low', 'low', 'mid', 'mid', 'mid', 'high', 'low'];

/** Friend suggestions: up to 5 bots closest in rank points to `points`, stable for a given uid. */
export function suggestionsFor(uid: string, points: number, n = 5): string[] {
  let h = 0;
  for (const ch of uid) h = (h * 31 + ch.charCodeAt(0)) | 0;
  const ranked = [...BOTS].sort((a, b) => Math.abs(a.rankPoints - points) - Math.abs(b.rankPoints - points));
  const pool = ranked.slice(0, 12);
  const out: string[] = [];
  for (let i = 0; out.length < n && i < pool.length; i++) {
    const pick = pool[Math.abs(h + i * 7) % pool.length];
    if (!out.includes(pick.uid)) out.push(pick.uid);
  }
  for (const b of pool) if (out.length < n && !out.includes(b.uid)) out.push(b.uid);
  return out;
}
