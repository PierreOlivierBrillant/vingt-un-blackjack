/**
 * Cosmetics catalog (Sprint 2). The original card backs / faces / felts are free; exclusive items
 * are unlocked by the Rendez-vous meta (character tiers, duo levels) and recorded in
 * `users/{uid}/unlocks/{cosmeticId}` (READ: owner, WRITE: server).
 *
 * Equipping always goes through `equipCardStyle` (the client may only write theme/language in
 * `users/{uid}`, see firestore.rules): it accepts a cosmetic only if `free` or unlocked.
 * Titles are public: `profiles/{uid}.title` (written by equipCardStyle, null = none).
 * The Flutter client mirrors this catalog (app/lib/domain/cosmetics.dart, checked by a test).
 */
import type { EpochMs } from './types';
import { CHARACTER_IDS, type CharacterId } from './romance';

export const FREE_CARD_BACKS = ['classicBlue', 'classicRed', 'midnight', 'emerald', 'neonGrid', 'goldFiligree'] as const;
export const FREE_CARD_FACES = ['classic', 'fourColor', 'neon'] as const;
export const FREE_FELTS = ['green', 'blue', 'red', 'purple', 'black'] as const;

const per = <S extends string>(suffix: S) => CHARACTER_IDS.map((c) => `rv_${c}_${suffix}` as `rv_${CharacterId}_${S}`);

/** Exclusive items: one card back, one felt and one title per character, plus duo items. */
export const EXCLUSIVE_CARD_BACKS = [...per('back'), 'duo_back'] as const;
export const EXCLUSIVE_FELTS = [...per('felt'), 'duo_felt'] as const;
export const TITLE_IDS = [...per('title'), 'duo_title'] as const;

export const ALL_CARD_BACKS = [...FREE_CARD_BACKS, ...EXCLUSIVE_CARD_BACKS] as const;
export const ALL_CARD_FACES = [...FREE_CARD_FACES] as const;
export const ALL_FELTS = [...FREE_FELTS, ...EXCLUSIVE_FELTS] as const;

export type CosmeticSlot = 'cardBack' | 'cardFace' | 'felt' | 'title';
export type CosmeticId = (typeof ALL_CARD_BACKS)[number] | (typeof ALL_FELTS)[number] | (typeof ALL_CARD_FACES)[number] | (typeof TITLE_IDS)[number];

export interface CosmeticInfo { slot: CosmeticSlot; free: boolean }

export const COSMETICS: Record<string, CosmeticInfo> = Object.fromEntries([
  ...FREE_CARD_BACKS.map((id) => [id, { slot: 'cardBack', free: true }]),
  ...FREE_CARD_FACES.map((id) => [id, { slot: 'cardFace', free: true }]),
  ...FREE_FELTS.map((id) => [id, { slot: 'felt', free: true }]),
  ...EXCLUSIVE_CARD_BACKS.map((id) => [id, { slot: 'cardBack', free: false }]),
  ...EXCLUSIVE_FELTS.map((id) => [id, { slot: 'felt', free: false }]),
  ...TITLE_IDS.map((id) => [id, { slot: 'title', free: false }]),
]) as Record<string, CosmeticInfo>;

/** `users/{uid}/unlocks/{cosmeticId}`. */
export interface UnlockDoc {
  cosmeticId: CosmeticId;
  slot: CosmeticSlot;
  source: 'romance' | 'duo';
  characterId: CharacterId | null;
  tier: number | null;
  pairId: string | null;
  grantedAtMs: EpochMs;
}
