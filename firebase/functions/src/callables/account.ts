/** Profile, simulated KYC, simulated wallet, shop, ads, card styles. */
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { BOT_BY_UID, suggestionsFor } from '../sim/profiles';
import { fail } from '../shared/errors';
import { refs } from '../shared/paths';
import { ageYears, dayId, weekId } from '../shared/time';
import type {
  AdStateDoc, FriendRequestDoc, InventoryDoc, KycDoc, ProfileDoc, UserSettingsDoc,
} from '../shared/types';
import {
  AD_REWARD_CENTS, AD_REWARD_COOLDOWN_MS, AD_REWARD_DAILY_MAX, DEPOSIT_DAILY_CAP_CENTS, DEPOSIT_MAX_CENTS,
  DEPOSIT_MIN_CENTS, KYC_MIN_AGE_YEARS, KYC_REVIEW_MS, POWER_MAX_INVENTORY, POWER_PRICES_CENTS, WELCOME_BONUS_CENTS,
  WITHDRAW_MAX_CENTS, WITHDRAW_MIN_CENTS,
} from '../shared/types';
import { COSMETICS } from '../shared/cosmetics';
import { WalletSession } from '../shared/wallet';
import { defineCallable } from './framework';
import { S } from './schemas';

export const DEFAULT_SETTINGS: Omit<UserSettingsDoc, 'updatedAtMs'> = {
  theme: 'dark', language: 'fr', cardBack: 'classicBlue', cardFace: 'classic', felt: 'green',
};

export function emptyStats(): ProfileDoc['stats'] {
  return { handsPlayed: 0, handsWon: 0, handsLost: 0, handsPushed: 0, blackjacks: 0, netCents: 0, biggestWinCents: 0 };
}

async function requireProfile(db: Firestore, tx: Transaction, uid: string): Promise<ProfileDoc> {
  const p = await tx.get(refs(db).profile(uid));
  if (!p.exists) throw fail.pre('PROFILE_REQUIRED');
  return p.data() as ProfileDoc;
}

export const completeProfile = defineCallable({
  name: 'completeProfile',
  schema: S.completeProfile,
  tableIdOf: () => null,
  handler: async (tx, data, { db, uid, now }) => {
    const r = refs(db);
    const lower = data.username.toLowerCase();
    const [prof, uname] = await Promise.all([tx.get(r.profile(uid)), tx.get(r.username(lower))]);
    if (prof.exists) throw fail.exists('PROFILE_EXISTS');
    if (uname.exists) throw fail.exists('USERNAME_TAKEN');
    // bot requests to pre-fill the "friends" screen
    const suggestions = suggestionsFor(uid, 0);
    const profile: ProfileDoc = {
      uid, username: data.username, usernameLower: lower, avatar: data.avatar, isBot: false,
      rankPoints: 0, rankTier: 'bronze', weeklyPoints: 0, weekId: weekId(now), stats: emptyStats(),
      currentTableId: null, lastSeenAtMs: now, kycVerified: false, createdAtMs: now,
    };
    tx.set(r.username(lower), { uid });
    tx.set(r.profile(uid), profile);
    tx.set(r.settings(uid), { ...DEFAULT_SETTINGS, language: data.language ?? 'fr', updatedAtMs: now } satisfies UserSettingsDoc);
    const kyc: KycDoc = { status: 'none', docType: null, submittedAtMs: null, verifyAfterMs: null, verifiedAtMs: null, rejectionReason: null };
    tx.set(r.kyc(uid), kyc);
    tx.set(r.suggestions(uid), { uids: suggestions.slice(2), updatedAtMs: now });
    for (const botUid of suggestions.slice(0, 2)) {
      const bot = BOT_BY_UID.get(botUid)!;
      const req: FriendRequestDoc = {
        fromUid: bot.uid, toUid: uid, fromUsername: bot.username, toUsername: data.username, fromAvatar: bot.avatar, createdAtMs: now,
      };
      tx.set(r.friendRequest(bot.uid, uid), req);
    }
    const w = WalletSession.create(db, uid, now);
    w.credit(WELCOME_BONUS_CENTS, 'welcomeBonus');
    w.write(tx);
    return { response: { uid, username: data.username, balanceCents: w.balance } };
  },
});

/** Reads the KYC doc and promotes pending → verified when the fake review delay elapsed. */
async function loadKyc(db: Firestore, tx: Transaction, uid: string, now: number): Promise<{ kyc: KycDoc; promote: boolean }> {
  const snap = await tx.get(refs(db).kyc(uid));
  if (!snap.exists) throw fail.pre('PROFILE_REQUIRED');
  const kyc = snap.data() as KycDoc;
  const promote = kyc.status === 'pending' && kyc.verifyAfterMs !== null && now >= kyc.verifyAfterMs;
  if (promote) {
    kyc.status = 'verified';
    kyc.verifiedAtMs = now;
  }
  return { kyc, promote };
}

function writeKycPromotion(db: Firestore, tx: Transaction, uid: string, kyc: KycDoc): void {
  tx.set(refs(db).kyc(uid), kyc);
  tx.update(refs(db).profile(uid), { kycVerified: true });
}

async function requireVerifiedKyc(db: Firestore, tx: Transaction, uid: string, now: number): Promise<() => void> {
  const { kyc, promote } = await loadKyc(db, tx, uid, now);
  if (kyc.status === 'rejected') throw fail.pre('KYC_REJECTED');
  if (kyc.status !== 'verified') throw fail.pre('KYC_REQUIRED');
  return () => { if (promote) writeKycPromotion(db, tx, uid, kyc); };
}

export const submitKyc = defineCallable({
  name: 'submitKyc',
  schema: S.submitKyc,
  handler: async (tx, data, { db, uid, now }) => {
    const { kyc, promote } = await loadKyc(db, tx, uid, now);
    const out = () => ({ status: kyc.status, verifyAfterMs: kyc.verifyAfterMs, rejectionReason: kyc.rejectionReason });
    if ('refresh' in data) {
      if (promote) writeKycPromotion(db, tx, uid, kyc);
      return { response: out() };
    }
    if (kyc.status === 'verified') throw fail.pre('KYC_ALREADY_VERIFIED');
    if (kyc.status === 'rejected') throw fail.pre('KYC_REJECTED');
    if (kyc.status === 'pending') return { response: out() }; // already under review
    const age = ageYears(data.birthDate, now);
    if (age === null) throw fail.invalid('INVALID_ARGUMENT', 'birthDate');
    kyc.docType = data.docType;
    kyc.submittedAtMs = now;
    if (age < KYC_MIN_AGE_YEARS) {
      kyc.status = 'rejected';
      kyc.rejectionReason = 'underage';
      kyc.verifyAfterMs = null;
    } else {
      kyc.status = 'pending';
      kyc.verifyAfterMs = now + KYC_REVIEW_MS;
    }
    tx.set(refs(db).kyc(uid), kyc); // the birth date itself is never stored
    return { response: out() };
  },
});

export const deposit = defineCallable({
  name: 'deposit',
  schema: S.deposit,
  handler: async (tx, data, { db, uid, now }) => {
    const commitKyc = await requireVerifiedKyc(db, tx, uid, now);
    const w = await WalletSession.load(db, tx, uid, now);
    if (data.amountCents < DEPOSIT_MIN_CENTS || data.amountCents > DEPOSIT_MAX_CENTS) throw fail.pre('DEPOSIT_LIMIT');
    const today = dayId(now);
    const usedToday = w.doc.dailyDeposit.day === today ? w.doc.dailyDeposit.amountCents : 0;
    if (usedToday + data.amountCents > DEPOSIT_DAILY_CAP_CENTS) throw fail.pre('DEPOSIT_LIMIT');
    const id = w.credit(data.amountCents, 'deposit', { method: data.method });
    w.doc.dailyDeposit = { day: today, amountCents: usedToday + data.amountCents };
    w.doc.totalDepositedCents += data.amountCents;
    commitKyc();
    w.write(tx);
    return { response: { balanceCents: w.balance, ledgerEntryId: id } };
  },
});

export const withdraw = defineCallable({
  name: 'withdraw',
  schema: S.withdraw,
  handler: async (tx, data, { db, uid, now }) => {
    const commitKyc = await requireVerifiedKyc(db, tx, uid, now);
    const w = await WalletSession.load(db, tx, uid, now);
    if (data.amountCents < WITHDRAW_MIN_CENTS || data.amountCents > WITHDRAW_MAX_CENTS) throw fail.invalid('INVALID_ARGUMENT', 'amount out of range');
    const id = w.debit(data.amountCents, 'withdrawal', { method: data.method });
    w.doc.totalWithdrawnCents += data.amountCents;
    commitKyc();
    w.write(tx);
    return { response: { balanceCents: w.balance, ledgerEntryId: id } };
  },
});

export const buyPower = defineCallable({
  name: 'buyPower',
  schema: S.buyPower,
  handler: async (tx, data, { db, uid, now }) => {
    const r = refs(db);
    const w = await WalletSession.load(db, tx, uid, now);
    const inv = await tx.get(r.inventory(uid, data.powerId));
    const have = inv.exists ? (inv.data() as InventoryDoc).quantity : 0;
    if (have + data.quantity > POWER_MAX_INVENTORY) throw fail.pre('INVENTORY_FULL');
    w.debit(POWER_PRICES_CENTS[data.powerId] * data.quantity, 'powerPurchase', { powerId: data.powerId });
    const doc: InventoryDoc = { powerId: data.powerId, quantity: have + data.quantity, updatedAtMs: now };
    tx.set(r.inventory(uid, data.powerId), doc);
    w.write(tx);
    return { response: { quantity: doc.quantity, balanceCents: w.balance } };
  },
});

export const claimAdReward = defineCallable({
  name: 'claimAdReward',
  schema: S.claimAdReward,
  handler: async (tx, _data, { db, uid, now }) => {
    const r = refs(db);
    const w = await WalletSession.load(db, tx, uid, now);
    const snap = await tx.get(r.ads(uid));
    const today = dayId(now);
    const prev = snap.exists ? (snap.data() as AdStateDoc) : { day: today, claimedToday: 0, lastClaimAtMs: 0 };
    const claimed = prev.day === today ? prev.claimedToday : 0;
    if (claimed >= AD_REWARD_DAILY_MAX) throw fail.pre('AD_DAILY_LIMIT');
    if (now - prev.lastClaimAtMs < AD_REWARD_COOLDOWN_MS) throw fail.pre('AD_COOLDOWN');
    w.credit(AD_REWARD_CENTS, 'adReward');
    const next: AdStateDoc = { day: today, claimedToday: claimed + 1, lastClaimAtMs: now };
    tx.set(r.ads(uid), next);
    w.write(tx);
    return { response: { rewardCents: AD_REWARD_CENTS, balanceCents: w.balance, remainingToday: AD_REWARD_DAILY_MAX - next.claimedToday } };
  },
});

export const equipCardStyle = defineCallable({
  name: 'equipCardStyle',
  schema: S.equipCardStyle,
  handler: async (tx, data, { db, uid, now }) => {
    const profile = await requireProfile(db, tx, uid);
    const r = refs(db);
    // Exclusive cosmetics must be unlocked (users/{uid}/unlocks/{id}); free ones always are.
    const wanted: string[] = [data.cardBack, data.cardFace, data.felt, data.title ?? undefined].filter((x) => x !== undefined);
    const locked = wanted.filter((id) => !COSMETICS[id]?.free);
    const [snap, ...unlocks] = await Promise.all([tx.get(r.settings(uid)), ...locked.map((id) => tx.get(r.unlock(uid, id)))]);
    if (unlocks.some((u) => !u.exists)) throw fail.pre('COSMETIC_LOCKED');
    const cur = { ...DEFAULT_SETTINGS, ...(snap.data() as Partial<UserSettingsDoc> | undefined) };
    const next: UserSettingsDoc = {
      theme: cur.theme, language: cur.language,
      cardBack: data.cardBack ?? cur.cardBack, cardFace: data.cardFace ?? cur.cardFace, felt: data.felt ?? cur.felt,
      updatedAtMs: now,
    };
    tx.set(r.settings(uid), next);
    let title = profile.title ?? null;
    if (data.title !== undefined) {
      title = data.title;
      tx.set(r.profile(uid), { title }, { merge: true });
    }
    return { response: { cardBack: next.cardBack, cardFace: next.cardFace, felt: next.felt, title } };
  },
});
