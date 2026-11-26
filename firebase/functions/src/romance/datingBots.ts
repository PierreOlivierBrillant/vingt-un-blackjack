/**
 * The 24 bots of the "Rencontres" (every 5th sim bot: bot_005, bot_010 … bot_120), with a dating
 * card derived deterministically from their uid. Their `datingProfiles/{uid}` are written by the
 * sim runner (./bots.ts) but every server path also knows them from here, so dating works even
 * before the runner wrote them (and they always carry the visible "Bot" badge: isBot true).
 */
import { ALL_GAMES, type AnyGame } from '../shared/games/common';
import {
  DATING_INTEREST_IDS, DATING_LOOKING_FOR, type DatingCard, type DatingInterestId, type DatingProfileDoc,
} from '../shared/romance';
import { BOT_BY_UID, BOTS } from '../sim/profiles';

export const DATING_BOT_UIDS: readonly string[] = BOTS.filter((_, i) => (i + 1) % 5 === 0).map((b) => b.uid);
const DATING_BOT_SET = new Set(DATING_BOT_UIDS);

export function isDatingBot(uid: string): boolean {
  return DATING_BOT_SET.has(uid);
}

/** Small deterministic hash (FNV-1a) used for every bot choice. */
export function hash32(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

export function datingBotProfile(uid: string, now = 0): DatingProfileDoc | null {
  const b = BOT_BY_UID.get(uid);
  if (!b || !isDatingBot(uid)) return null;
  const h = hash32(uid);
  const interests: DatingInterestId[] = [];
  for (let k = 0; interests.length < 3; k++) {
    const pick = DATING_INTEREST_IDS[hash32(`${uid}:${k}`) % DATING_INTEREST_IDS.length];
    if (!interests.includes(pick)) interests.push(pick);
  }
  return {
    uid, username: b.username, avatar: b.avatar, isBot: true,
    favoriteGame: ALL_GAMES[h % ALL_GAMES.length] as AnyGame,
    interests,
    lookingFor: DATING_LOOKING_FOR[(h >>> 8) % DATING_LOOKING_FOR.length],
    active: true, updatedAtMs: now,
  };
}

export function botCard(uid: string): DatingCard | null {
  const p = datingBotProfile(uid);
  const b = BOT_BY_UID.get(uid);
  if (!p || !b) return null;
  return { uid, username: p.username, avatar: p.avatar, isBot: true, favoriteGame: p.favoriteGame, interests: p.interests, lookingFor: p.lookingFor, rankTier: b.rankTier };
}

/** Delays of the bots (ms). */
export const BOT_ACCEPT_DELAY_MS = 4_000;
export function botReplyDelayMs(seed: string): number {
  return 3_000 + (hash32(seed) % 6_000);
}
