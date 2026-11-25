/**
 * ============================================================================================
 *  "RENDEZ-VOUS" CONTRACT (Sprint 2) — PG-13 dating-sim meta layer. OWNER: rendez-vous implementer.
 * ============================================================================================
 *
 * All characters are adults (24–38), written PG-13 (flirting, confiding, holding hands; at most a
 * kiss at the finale then fade to black). Story content (scenes, choices, texts FR/EN, gift tastes,
 * rewards per tier, preset dating lines) lives in `src/romance/story/*.json` (single source, copied
 * to app/assets/story/ by tools/sync_story.mjs, SHA-256 parity tested on both sides).
 *
 * DOCUMENTS
 *  - `users/{uid}/romance/{characterId}` (RomanceDoc). READ: owner. WRITE: server.
 *  - `users/{uid}/unlocks/{cosmeticId}`  (UnlockDoc, see ./cosmetics.ts). READ: owner. WRITE: server.
 *  - `users/{uid}/private/dating`        (DatingPrivateDoc). READ: owner.
 *  - `datingProfiles/{uid}`, `datingLikes/{from}_{to}`, `datingBlocks/{a}_{b}`: server only.
 *  - `datingMatches/{pairId}` (uids sorted, joined by '_'): READ: the two members while active.
 *  - `datingMatches/{pairId}/messages/{id}`: READ: members of an active match.
 *  - `config/features` { dating: boolean }: server only (PvP dating is OFF unless enabled).
 *
 * TABLE AFFINITY: each settled round where a HUMAN staked ≥ the table minimum (hold'em: was dealt
 * in) at a table whose croupier is DEALER_OF[game] does a blind write
 * `romance/{dealer}.tablePlay[day] += 1` (no read in the table transaction). `romance{op:'sync'}`
 * folds those counters into affinity: min(TABLE_AFFINITY_DAILY_CAP, count) per day.
 */
import type { AnyGame } from './games/common';
import type { AvatarId, Cents, EpochMs, PowerId, Uid } from './types';
import type { CosmeticId } from './cosmetics';

export const DEALER_CHARACTER_IDS = ['lucas', 'camille', 'ines', 'alex', 'marco'] as const;
export const REGULAR_CHARACTER_IDS = ['jade', 'theo', 'nora', 'hugo'] as const;
export const CHARACTER_IDS = [...DEALER_CHARACTER_IDS, ...REGULAR_CHARACTER_IDS] as const;
export type CharacterId = (typeof CHARACTER_IDS)[number];

/** Croupier of each game's tables. */
export const DEALER_OF: Record<AnyGame, CharacterId> = {
  blackjack: 'lucas', roulette: 'camille', baccarat: 'ines', holdem: 'alex', craps: 'marco',
};

export const AFFINITY_MAX = 300;
/** Minimum affinity of tiers 0..5: Inconnu·e, Connaissance, Ami·e, Complice, Flirt, Coup de cœur. */
export const AFFINITY_TIER_THRESHOLDS = [0, 25, 70, 130, 200, 270] as const;
export const AFFINITY_TIER_COUNT = AFFINITY_TIER_THRESHOLDS.length; // 6
export const TABLE_AFFINITY_DAILY_CAP = 10;
export const GIFTS_PER_CHARACTER_PER_DAY = 3;
/** Affinity of a gift by the character's taste. */
export const GIFT_AFFINITY = { loved: 15, liked: 8, neutral: 3, disliked: -5 } as const;
export type GiftTaste = keyof typeof GIFT_AFFINITY;
/** Choice deltas allowed in story files. */
export const CHOICE_DELTA_MIN = -5;
export const CHOICE_DELTA_MAX = 10;
/** Date scenes are unlocked at these tiers (one date per tier, then the finale at tier 5). */
export const DATE_TIERS = [3, 4, 5] as const;

export function affinityTier(affinity: number): number {
  let t = 0;
  for (let i = 0; i < AFFINITY_TIER_THRESHOLDS.length; i++) if (affinity >= AFFINITY_TIER_THRESHOLDS[i]) t = i;
  return t;
}

export type SceneKind = 'talk' | 'smalltalk' | 'date' | 'finale';

/** A reward of a tier (characters.json) or of a duo level. */
export type Reward =
  | { kind: 'cosmetic'; id: CosmeticId }
  | { kind: 'power'; powerId: PowerId; qty: number };

/** `users/{uid}/romance/{characterId}`. */
export interface RomanceDoc {
  characterId: CharacterId;
  affinity: number;
  tier: number;
  /** Scene ids completed at least once (gallery "Souvenirs"). */
  seen: string[];
  /** UTC day ("YYYY-MM-DD") of the last talk/smalltalk scene, or null. */
  talkDay: string | null;
  gifts: { day: string; count: number };
  /** Blind-incremented by table settlements: day → rounds played at this croupier's tables. */
  tablePlay: Record<string, number>;
  /** day → rounds already folded into affinity by `sync`. */
  tableFolded: Record<string, number>;
  datesDone: string[];
  finaleDone: boolean;
  /** Tiers whose rewards were granted (never granted twice even if affinity drops and rises). */
  rewardsGranted: number[];
  updatedAtMs: EpochMs;
}

/** Per-character state returned to the client. */
export interface RomanceStateDto {
  characterId: CharacterId;
  affinity: number;
  tier: number;
  seen: string[];
  talkAvailable: boolean;
  giftsLeftToday: number;
  datesDone: string[];
  finaleDone: boolean;
}

/**
 * romance — one callable, `op` discriminated (per-op rate limits: ROMANCE_OP_RATE_LIMITS).
 *  - sync: folds pending table play into affinity, grants due rewards; returns every character.
 *  - playScene: the client played `sceneId` locally and submits the ids of the choices taken, in
 *    order. The server checks eligibility (tier, prerequisites, once per day for talk/smalltalk,
 *    date/finale conditions), replays the path from the scene start (each choice must exist at its
 *    node, the path must reach an end), applies the deltas, grants rewards. Dates debit their
 *    `reservationCents` (ledger 'reservation') only when completed.
 *  - gift: buys `giftId` (ledger 'gift') for `characterId`; affinity by taste; GIFTS_PER_CHARACTER_PER_DAY.
 * Errors: SCENE_NOT_AVAILABLE, SCENE_INVALID_PATH, TALK_DONE_TODAY, GIFT_DAILY_LIMIT, INSUFFICIENT_FUNDS.
 */
export type RomanceRequest =
  | { requestId: string; op: 'sync' }
  | { requestId: string; op: 'playScene'; characterId: CharacterId; sceneId: string; choices: string[] }
  | { requestId: string; op: 'gift'; characterId: CharacterId; giftId: string };
export interface RomanceResponse {
  characters: RomanceStateDto[];
  /** Rewards granted by this call. */
  granted: Array<Reward & { characterId: CharacterId; tier: number }>;
  affinityDelta: number;
  balanceCents: Cents | null;
}
export const ROMANCE_OP_RATE_LIMITS = {
  sync: { count: 20, windowMs: 60_000 },
  playScene: { count: 20, windowMs: 60_000 },
  gift: { count: 20, windowMs: 60_000 },
} as const;

// ============================================================================================
// Player-to-player dating ("Rencontres")
// ============================================================================================

export const DATING_INTEREST_IDS = [
  'cinema', 'music', 'videoGames', 'cooking', 'sport', 'travel', 'books', 'art', 'nature', 'tech',
  'boardGames', 'dance', 'photography', 'science', 'fashion', 'animals',
] as const;
export type DatingInterestId = (typeof DATING_INTEREST_IDS)[number];
export const DATING_LOOKING_FOR = ['friendship', 'flirt', 'both'] as const;
export type DatingLookingFor = (typeof DATING_LOOKING_FOR)[number];
export const DATING_REACTION_IDS = ['heart', 'laugh', 'wow', 'blush', 'clap', 'wink', 'star', 'sparkle'] as const;
export type DatingReactionId = (typeof DATING_REACTION_IDS)[number];
export const DATING_LIKES_PER_DAY = 10;
export const DATING_MESSAGES_PER_MATCH_PER_DAY = 30;

/** `datingProfiles/{uid}` (server only; exposed through `dating{op:'discover'}` and match docs). */
export interface DatingProfileDoc {
  uid: Uid;
  username: string;
  avatar: AvatarId;
  isBot: boolean;
  favoriteGame: AnyGame;
  interests: DatingInterestId[];
  lookingFor: DatingLookingFor;
  active: boolean;
  updatedAtMs: EpochMs;
}

/** `users/{uid}/private/dating`. */
export interface DatingPrivateDoc {
  optedIn: boolean;
  likes: { day: string; count: number };
  updatedAtMs: EpochMs;
}

/** Public card shown by `discover` and inside a match. */
export interface DatingCard {
  uid: Uid;
  username: string;
  avatar: AvatarId;
  isBot: boolean;
  favoriteGame: AnyGame;
  interests: DatingInterestId[];
  lookingFor: DatingLookingFor;
  rankTier: string;
}

export type DatingMessageKind = 'line' | 'reaction' | 'gift' | 'invite' | 'system';

/** `datingMatches/{pairId}`. */
export interface DatingMatchDoc {
  pairId: string;
  uids: [Uid, Uid];
  cards: Record<Uid, DatingCard>;
  status: 'active' | 'ended';
  createdAtMs: EpochMs;
  lastMessageAtMs: EpochMs;
  lastMessage: { fromUid: Uid; kind: DatingMessageKind; lineId: string | null; reaction: DatingReactionId | null } | null;
  /** uid → unread count. */
  unread: Record<Uid, number>;
  duoAffinity: number;
  duoTier: number;
  rewardsGranted: number[];
  /** Bot member only: when the bot answers next (sim_runner). */
  botReplyDueMs: EpochMs | null;
  /** Per-uid daily message counter (anti-spam). */
  sent: Record<Uid, { day: string; count: number }>;
}

/** `datingMatches/{pairId}/messages/{id}`. No free text, ever. */
export interface DatingMessageDoc {
  fromUid: Uid;
  kind: DatingMessageKind;
  lineId: string | null;
  reaction: DatingReactionId | null;
  giftId: string | null;
  invite: { tableId: string; game: AnyGame; code: string } | null;
  createdAtMs: EpochMs;
}

/**
 * dating — one callable, `op` discriminated. Requires `config/features.dating == true`
 * (DATING_DISABLED), a verified KYC (KYC_REQUIRED) and, except optIn, being opted in
 * (DATING_OPT_IN_REQUIRED). Blocks hide both people from each other (discover, likes, matches).
 *  - optIn / optOut (optOut ends every match).
 *  - discover → up to 10 cards (server-filtered: self, already decided, blocks both ways, inactive).
 *  - like {toUid, like}: 'clin d'œil' (DATING_LIKES_PER_DAY) or pass; mutual like → match.
 *  - send {pairId, lineId | reaction}: lineId must be allowed after the previous line (dating_lines.json).
 *  - gift {pairId, giftId}: ledger 'gift'.
 *  - invite {pairId}: the server attaches YOUR current private table code (NO_PRIVATE_TABLE).
 *  - unmatch {pairId}; block {uid}.
 */
export type DatingRequest =
  | { requestId: string; op: 'optIn'; favoriteGame: AnyGame; interests: DatingInterestId[]; lookingFor: DatingLookingFor }
  | { requestId: string; op: 'optOut' }
  | { requestId: string; op: 'discover' }
  | { requestId: string; op: 'like'; toUid: Uid; like: boolean }
  | { requestId: string; op: 'send'; pairId: string; lineId?: string; reaction?: DatingReactionId }
  | { requestId: string; op: 'gift'; pairId: string; giftId: string }
  | { requestId: string; op: 'invite'; pairId: string }
  | { requestId: string; op: 'unmatch'; pairId: string }
  | { requestId: string; op: 'block'; uid: Uid };
export interface DatingResponse {
  ok: true;
  cards: DatingCard[] | null;
  /** like: 'matched' when mutual. */
  matched: { pairId: string } | null;
  balanceCents: Cents | null;
}
export const DATING_OP_RATE_LIMITS = {
  optIn: { count: 10, windowMs: 60_000 },
  optOut: { count: 10, windowMs: 60_000 },
  discover: { count: 20, windowMs: 60_000 },
  like: { count: 30, windowMs: 60_000 },
  send: { count: 30, windowMs: 60_000 },
  gift: { count: 10, windowMs: 60_000 },
  invite: { count: 10, windowMs: 60_000 },
  unmatch: { count: 10, windowMs: 60_000 },
  block: { count: 20, windowMs: 60_000 },
} as const;

export const ROMANCE_REASONS = [
  'SCENE_NOT_AVAILABLE', 'SCENE_INVALID_PATH', 'TALK_DONE_TODAY', 'GIFT_DAILY_LIMIT', 'COSMETIC_LOCKED',
  'DATING_DISABLED', 'DATING_OPT_IN_REQUIRED', 'LIKE_DAILY_LIMIT', 'MATCH_NOT_FOUND', 'BLOCKED',
  'LINE_NOT_ALLOWED', 'NO_PRIVATE_TABLE',
] as const;
