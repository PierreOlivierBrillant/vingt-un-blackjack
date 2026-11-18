/** Strict zod schemas for every callable request (unknown keys rejected, integers only). */
import { z } from 'zod';
import {
  AVATAR_IDS, CARD_BACKS, CARD_FACES, FELTS, KYC_DOC_TYPES, LANGUAGES, MARKET_MAX_SHARES_PER_TRADE, PAYMENT_METHODS,
  PLAYER_ACTIONS, POWER_IDS, POWER_MAX_QUANTITY_PER_PURCHASE, STAKE_TIERS,
} from '../shared/types';
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
    power: z.enum(POWER_IDS).optional(),
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
  }).refine((d) => d.cardBack !== undefined || d.cardFace !== undefined || d.felt !== undefined, { message: 'nothing to equip' }),
};
