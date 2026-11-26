/** Strict zod schemas for every callable request (unknown keys rejected, integers only). */
import { z } from 'zod';
import {
  AVATAR_IDS, BLACKJACK_POWER_IDS, CARD_BACKS, CARD_FACES, FELTS, KYC_DOC_TYPES, LANGUAGES, MARKET_MAX_SHARES_PER_TRADE, PAYMENT_METHODS,
  PLAYER_ACTIONS, POWER_IDS, POWER_MAX_QUANTITY_PER_PURCHASE, STAKE_TIERS,
} from '../shared/types';
import { TITLE_IDS } from '../shared/cosmetics';
import { ALL_GAMES, GAME_IDS, type AnyGame, type GameActionRequest } from '../shared/games/common';
import { CHARACTER_IDS, DATING_INTEREST_IDS, DATING_LOOKING_FOR, DATING_REACTION_IDS } from '../shared/romance';
import { requestIdSchema } from './framework';

const cents = (min: number, max: number) => z.number().int().min(min).max(max);
const id = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/);
const uid = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);
const base = { requestId: requestIdSchema };
const MAX_CENTS = 1_000_000_000; // $10M: anything above is nonsense for every field

export const S = {
  completeProfile: z.strictObject({
    ...base,
    username: z.string().regex(/^[A-Za-z0-9_]{3,16}$/),
    avatar: z.enum(AVATAR_IDS as [string, ...string[]]),
    language: z.enum(LANGUAGES).optional(),
  }),
  submitKyc: z.union([
    z.strictObject({ ...base, docType: z.enum(KYC_DOC_TYPES), birthDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) }),
    z.strictObject({ ...base, refresh: z.literal(true) }),
  ]),
  deposit: z.strictObject({ ...base, amountCents: cents(1, MAX_CENTS), method: z.enum(PAYMENT_METHODS) }),
  withdraw: z.strictObject({ ...base, amountCents: cents(1, MAX_CENTS), method: z.enum(PAYMENT_METHODS) }),
  joinMatchmaking: z.strictObject({
    ...base,
    mode: z.enum(['quick', 'createPrivate', 'joinCode']),
    stakeTier: z.enum(STAKE_TIERS),
    code: z.string().regex(/^[A-Za-z0-9]{6}$/).optional(),
  }),
  leaveTable: z.strictObject({ ...base, tableId: id }),
  placeBet: z.strictObject({ ...base, tableId: id, handNumber: z.number().int().min(0).max(1e12), amountCents: cents(1, MAX_CENTS) }),
  act: z.strictObject({
    ...base,
    tableId: id,
    handNumber: z.number().int().min(0).max(1e12),
    action: z.enum(PLAYER_ACTIONS),
    handIndex: z.number().int().min(0).max(3).optional(),
    amountCents: cents(0, MAX_CENTS).optional(),
    power: z.enum(BLACKJACK_POWER_IDS).optional(),
  }),
  pokeTable: z.strictObject({ ...base, tableId: id }),
  buyPower: z.strictObject({ ...base, powerId: z.enum(POWER_IDS), quantity: z.number().int().min(1).max(POWER_MAX_QUANTITY_PER_PURCHASE) }),
  tradeShares: z.strictObject({
    ...base,
    marketId: id,
    side: z.enum(['yes', 'no']),
    direction: z.enum(['buy', 'sell']),
    shares: z.number().int().min(1).max(MARKET_MAX_SHARES_PER_TRADE),
    maxCostCents: cents(0, MAX_CENTS).optional(),
    minProceedsCents: cents(0, MAX_CENTS).optional(),
  }),
  friendRequest: z.union([
    z.strictObject({ ...base, toUid: uid }),
    z.strictObject({ ...base, toUsername: z.string().regex(/^[A-Za-z0-9_]{3,16}$/) }),
  ]),
  respondFriend: z.strictObject({ ...base, fromUid: uid, accept: z.boolean() }),
  removeFriend: z.strictObject({ ...base, friendUid: uid }),
  claimAdReward: z.strictObject({ ...base, adId: z.string().regex(/^[A-Za-z0-9_-]{1,40}$/) }),
  equipCardStyle: z.strictObject({
    ...base,
    cardBack: z.enum(CARD_BACKS).optional(),
    cardFace: z.enum(CARD_FACES).optional(),
    felt: z.enum(FELTS).optional(),
    title: z.enum(TITLE_IDS).nullable().optional(),
  }).refine((d) => d.cardBack !== undefined || d.cardFace !== undefined || d.felt !== undefined || d.title !== undefined, { message: 'nothing to equip' }),

  // Sprint 2 — kernel-driven games (shared/games/common.ts)
  gameJoin: z.strictObject({
    ...base,
    game: z.enum(GAME_IDS),
    mode: z.enum(['quick', 'createPrivate', 'joinCode']),
    stakeTier: z.enum(STAKE_TIERS),
    code: z.string().regex(/^[A-Za-z0-9]{6}$/).optional(),
    buyInCents: cents(1, MAX_CENTS).optional(),
  }),
  gameLeave: z.strictObject({ ...base, tableId: id }),
  /** Strict envelope; `action` is validated afterwards (kernel actions here, game actions by the module's schema). */
  gameAction: z.strictObject({ ...base, tableId: id, round: z.number().int().min(0).max(1e12), action: z.unknown() }) as unknown as z.ZodType<GameActionRequest>,
  gamePoke: z.strictObject({ ...base, tableId: id }),
};

/** Bet spot ids: game-specific grammar (shared/games/<game>.ts), checked here for shape only. */
export const BET_SPOT_ID = /^[A-Za-z0-9:_-]{1,32}$/;
const MAX_SPOTS = 200;

/** gameAction `action`: first only its `type` (then the precise schema below, or the module's). */
export const actionTypeSchema = z.looseObject({ type: z.string().regex(/^[A-Za-z][A-Za-z0-9]{0,31}$/) });

export const kernelActionSchemas = {
  setBets: z.strictObject({
    type: z.literal('setBets'),
    bets: z.record(z.string().regex(BET_SPOT_ID), cents(0, MAX_CENTS)).refine((b) => Object.keys(b).length <= MAX_SPOTS, { message: 'too many bet spots' }),
    power: z.enum(POWER_IDS).optional(),
  }),
  sitOut: z.strictObject({ type: z.literal('sitOut') }),
  sitIn: z.strictObject({ type: z.literal('sitIn') }),
};

// Sprint 2 — Rendez-vous (shared/romance.ts): strict request shapes; the romance implementer (phase B) owns the handlers.
const characterId = z.enum(CHARACTER_IDS);
const pairId = z.string().regex(/^[A-Za-z0-9_-]{3,260}$/);

export const romanceSchema = z.discriminatedUnion('op', [
  z.strictObject({ ...base, op: z.literal('sync') }),
  z.strictObject({ ...base, op: z.literal('playScene'), characterId, sceneId: id, choices: z.array(id).max(64) }),
  z.strictObject({ ...base, op: z.literal('gift'), characterId, giftId: id }),
]);

export const datingSchema = z.discriminatedUnion('op', [
  z.strictObject({
    ...base, op: z.literal('optIn'), favoriteGame: z.enum(ALL_GAMES as [AnyGame, ...AnyGame[]]),
    interests: z.array(z.enum(DATING_INTEREST_IDS)).length(3).refine((a) => new Set(a).size === a.length, { message: 'duplicate interest' }),
    lookingFor: z.enum(DATING_LOOKING_FOR),
  }),
  z.strictObject({ ...base, op: z.literal('optOut') }),
  z.strictObject({ ...base, op: z.literal('discover') }),
  z.strictObject({ ...base, op: z.literal('like'), toUid: uid, like: z.boolean() }),
  z.strictObject({ ...base, op: z.literal('send'), pairId, lineId: id.optional(), reaction: z.enum(DATING_REACTION_IDS).optional() }),
  z.strictObject({ ...base, op: z.literal('gift'), pairId, giftId: id }),
  z.strictObject({ ...base, op: z.literal('invite'), pairId }),
  z.strictObject({ ...base, op: z.literal('unmatch'), pairId }),
  z.strictObject({ ...base, op: z.literal('block'), uid }),
]).refine((d) => d.op !== 'send' || (d.lineId === undefined) !== (d.reaction === undefined), { message: 'send: exactly one of lineId / reaction' });
