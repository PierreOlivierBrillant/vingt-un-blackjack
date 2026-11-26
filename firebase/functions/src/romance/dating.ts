/**
 * dating{op} — "Rencontres" between players, inside the callable's transaction
 * (src/callables/dating.ts). Contract: shared/romance.ts. Gates, in this order:
 *   config/features.dating == true (DATING_DISABLED, the classroom default) → profile
 *   (PROFILE_REQUIRED) → verified KYC (KYC_REQUIRED) → opted in, except optIn (DATING_OPT_IN_REQUIRED).
 * No free text ever travels: lines are ids of story/dating_lines.json (LINE_NOT_ALLOWED), invites
 * carry a code the SERVER reads from the inviter's current private table (NO_PRIVATE_TABLE).
 * Blocks hide both people from each other: discover filters both directions, likes are refused,
 * the match ends (and its messages become unreadable, firestore.rules).
 * The bots' side (accepting likes, answering) runs in the sim runner: ./bots.ts.
 */
import type { DocumentSnapshot, Firestore, Transaction } from 'firebase-admin/firestore';
import type { UnlockDoc } from '../shared/cosmetics';
import { AppError, fail } from '../shared/errors';
import { gameOfTableId, type AnyGame } from '../shared/games/common';
import { pairIdOf, refs } from '../shared/paths';
import {
  DATING_LIKES_PER_DAY, DUO_GIFT_AFFINITY, DUO_REWARDS,
  type DatingCard, type DatingMatchDoc, type DatingMessageDoc, type DatingPrivateDoc, type DatingProfileDoc,
  type DatingRequest, type DatingResponse, type Uid,
} from '../shared/romance';
import { dayId } from '../shared/time';
import type { ProfileDoc, RankTier } from '../shared/types';
import { WalletSession } from '../shared/wallet';
import { botCard, botReplyDelayMs, datingBotProfile, DATING_BOT_UIDS } from './datingBots';
import { canSend, lineAllowed, otherOf, rankCards, recordMessage } from './datingRules';
import { STORY } from './story';

export interface DatingCtx { db: Firestore; uid: string; now: number }

/** Likes doc `datingLikes/{from}_{to}`. */
export interface DatingLikeDoc {
  fromUid: Uid;
  toUid: Uid;
  like: boolean;
  /** A like to a bot waiting for the sim runner to answer it. */
  botPending: boolean;
  createdAtMs: number;
}

/** `datingBlocks/{a}_{b}` (sorted pair). */
export interface DatingBlockDoc {
  uids: [Uid, Uid];
  /** Who blocked (one or both members). */
  by: Uid[];
  createdAtMs: number;
}

export const DISCOVER_COUNT = 10;
const DISCOVER_SCAN = 300;

const OK: DatingResponse = { ok: true, cards: null, matched: null, balanceCents: null };

export function normalizePrivate(snap: DocumentSnapshot | undefined, now: number): DatingPrivateDoc {
  const d = (snap?.exists ? snap.data() : undefined) as Partial<DatingPrivateDoc> | undefined;
  return {
    optedIn: d?.optedIn === true,
    likes: d?.likes && typeof d.likes.day === 'string' ? { day: d.likes.day, count: d.likes.count ?? 0 } : { day: '', count: 0 },
    favoriteGame: d?.favoriteGame ?? null,
    interests: Array.isArray(d?.interests) ? d.interests : [],
    lookingFor: d?.lookingFor ?? null,
    updatedAtMs: d?.updatedAtMs ?? now,
  };
}

export function cardOf(p: DatingProfileDoc, rankTier: RankTier): DatingCard {
  return { uid: p.uid, username: p.username, avatar: p.avatar, isBot: p.isBot, favoriteGame: p.favoriteGame, interests: [...p.interests], lookingFor: p.lookingFor, rankTier };
}

/** Dating profile of `uid` (a human's document, or a bot's from code when absent). */
function profileOf(uid: Uid, snap: DocumentSnapshot | undefined): DatingProfileDoc | null {
  if (snap?.exists) return snap.data() as DatingProfileDoc;
  return datingBotProfile(uid);
}

export function newMatch(a: DatingCard, b: DatingCard, now: number): DatingMatchDoc {
  const uids = [a.uid, b.uid].sort() as [Uid, Uid];
  const bot = a.isBot ? a.uid : b.isBot ? b.uid : null;
  const pairId = pairIdOf(a.uid, b.uid);
  return {
    pairId, uids, cards: { [a.uid]: a, [b.uid]: b }, status: 'active', createdAtMs: now, lastMessageAtMs: now,
    lastMessage: null, unread: { [a.uid]: 0, [b.uid]: 0 }, duoAffinity: 0, duoTier: 0, rewardsGranted: [],
    // a bot opens the conversation a few seconds after the match
    botReplyDueMs: bot ? now + botReplyDelayMs(`${pairId}|open`) : null,
    sent: {}, lastLine: null, duoDaily: {},
  };
}

function endMatch(tx: Transaction, db: Firestore, m: DatingMatchDoc): void {
  tx.update(refs(db).datingMatch(m.pairId), { status: 'ended', botReplyDueMs: null });
}

function rateLimited(): AppError {
  return new AppError('resource-exhausted', 'RATE_LIMITED', 'too many messages in this match today');
}

/** The active match `pairId` with `uid` as a member, else MATCH_NOT_FOUND. */
async function requireMatch(tx: Transaction, db: Firestore, pairId: string, uid: Uid): Promise<DatingMatchDoc> {
  const snap = await tx.get(refs(db).datingMatch(pairId));
  const m = snap.exists ? (snap.data() as DatingMatchDoc) : null;
  if (!m || !m.uids.includes(uid) || m.status !== 'active') throw fail.notFound('MATCH_NOT_FOUND');
  return m;
}

/** Reads the unlock docs needed by `dueTiers` for the human members (reads before writes). */
async function prepareDuoRewards(tx: Transaction, db: Firestore, m: DatingMatchDoc, dueTiers: number[]): Promise<Array<{ uid: Uid; id: string; tier: number }>> {
  const wanted: Array<{ uid: Uid; id: string; tier: number }> = [];
  for (const tier of dueTiers) {
    const id = DUO_REWARDS[tier];
    if (!id) continue;
    for (const uid of m.uids) if (!m.cards[uid]?.isBot) wanted.push({ uid, id, tier });
  }
  if (!wanted.length) return [];
  const snaps = await tx.getAll(...wanted.map((w) => refs(db).unlock(w.uid, w.id)));
  return wanted.filter((_, i) => !snaps[i].exists);
}

function writeDuoRewards(tx: Transaction, db: Firestore, m: DatingMatchDoc, grants: Array<{ uid: Uid; id: string; tier: number }>, now: number): void {
  for (const g of grants) {
    const slot = g.id === 'duo_back' ? 'cardBack' : g.id === 'duo_felt' ? 'felt' : 'title';
    const unlock: UnlockDoc = { cosmeticId: g.id as UnlockDoc['cosmeticId'], slot, source: 'duo', characterId: null, tier: g.tier, pairId: m.pairId, grantedAtMs: now };
    tx.set(refs(db).unlock(g.uid, g.id), unlock);
  }
}

/**
 * Appends a message to the match (reads the duo unlocks first, then writes message + match). Used by
 * the callable (send / gift / invite) and by the bots (./bots.ts).
 */
export async function postMessage(
  tx: Transaction, db: Firestore, m: DatingMatchDoc, msg: DatingMessageDoc, now: number, opts: { extraDuo?: number; wallet?: WalletSession } = {},
): Promise<void> {
  const today = dayId(now);
  const due = recordMessage(m, msg, today, opts.extraDuo ?? 0);
  const grants = await prepareDuoRewards(tx, db, m, due);
  const other = otherOf(m, msg.fromUid);
  // the bot member answers a few seconds after a human message (sim runner, ./bots.ts)
  if (m.cards[msg.fromUid]?.isBot) m.botReplyDueMs = null;
  else if (m.cards[other]?.isBot && m.botReplyDueMs === null) m.botReplyDueMs = now + botReplyDelayMs(`${m.pairId}|${now}`);
  const r = refs(db);
  tx.set(r.datingMessages(m.pairId).doc(), msg);
  tx.set(r.datingMatch(m.pairId), m);
  writeDuoRewards(tx, db, m, grants, now);
  opts.wallet?.write(tx);
}

export async function datingOp(tx: Transaction, data: DatingRequest, ctx: DatingCtx): Promise<DatingResponse> {
  const { db, uid, now } = ctx;
  const r = refs(db);
  const today = dayId(now);
  const [features, profileSnap, kyc, privSnap] = await tx.getAll(r.features(), r.profile(uid), r.kyc(uid), r.datingPrivate(uid));
  if (features.get('dating') !== true) throw fail.pre('DATING_DISABLED');
  if (!profileSnap.exists) throw fail.pre('PROFILE_REQUIRED');
  if (kyc.get('status') !== 'verified') throw fail.pre('KYC_REQUIRED');
  const me = profileSnap.data() as ProfileDoc;
  const priv = normalizePrivate(privSnap, now);
  if (data.op !== 'optIn' && !priv.optedIn) throw fail.pre('DATING_OPT_IN_REQUIRED');

  switch (data.op) {
    case 'optIn': {
      const p: DatingProfileDoc = {
        uid, username: me.username, avatar: me.avatar, isBot: false, favoriteGame: data.favoriteGame,
        interests: [...data.interests], lookingFor: data.lookingFor, active: true, updatedAtMs: now,
      };
      tx.set(r.datingProfile(uid), p);
      tx.set(r.datingPrivate(uid), { ...priv, optedIn: true, favoriteGame: data.favoriteGame, interests: [...data.interests], lookingFor: data.lookingFor, updatedAtMs: now });
      return OK;
    }

    case 'optOut': {
      const matches = await tx.get(db.collection('datingMatches').where('uids', 'array-contains', uid).where('status', '==', 'active'));
      tx.set(r.datingProfile(uid), { active: false, updatedAtMs: now }, { merge: true });
      tx.set(r.datingPrivate(uid), { ...priv, optedIn: false, updatedAtMs: now });
      for (const d of matches.docs) endMatch(tx, db, d.data() as DatingMatchDoc);
      return OK;
    }

    case 'discover': {
      const [profiles, likes, blocks] = await Promise.all([
        tx.get(db.collection('datingProfiles').where('active', '==', true).limit(DISCOVER_SCAN)),
        tx.get(db.collection('datingLikes').where('fromUid', '==', uid).limit(2_000)),
        tx.get(db.collection('datingBlocks').where('uids', 'array-contains', uid)),
      ]);
      const hidden = new Set<string>([uid]);
      for (const l of likes.docs) hidden.add(l.get('toUid') as string);
      for (const b of blocks.docs) for (const x of b.get('uids') as string[]) hidden.add(x);
      const pool = new Map<string, DatingProfileDoc>();
      for (const d of profiles.docs) {
        const p = d.data() as DatingProfileDoc;
        if (!hidden.has(p.uid)) pool.set(p.uid, p);
      }
      for (const b of DATING_BOT_UIDS) if (!hidden.has(b) && !pool.has(b)) pool.set(b, datingBotProfile(b)!);
      const ranked = rankCards(
        { uid, interests: priv.interests ?? [] },
        [...pool.values()].map((p) => cardOf(p, botCard(p.uid)?.rankTier ?? 'bronze')),
        today,
      );
      // humans first (they are the point), then bots; both groups ranked
      const top = [...ranked.filter((c) => !c.isBot), ...ranked.filter((c) => c.isBot)].slice(0, DISCOVER_COUNT);
      const humans = top.filter((c) => !c.isBot);
      const ps = humans.length ? await tx.getAll(...humans.map((c) => r.profile(c.uid))) : [];
      const fresh = new Map(ps.filter((s) => s.exists).map((s) => [s.id, s.data() as ProfileDoc]));
      const cards = top
        .filter((c) => c.isBot || fresh.has(c.uid))
        .map((c) => (c.isBot ? c : { ...c, username: fresh.get(c.uid)!.username, avatar: fresh.get(c.uid)!.avatar, rankTier: fresh.get(c.uid)!.rankTier }));
      return { ...OK, cards };
    }

    case 'like': {
      const to = data.toUid;
      if (to === uid) throw fail.invalid('INVALID_ARGUMENT', 'cannot like yourself');
      const pairId = pairIdOf(uid, to);
      const [targetSnap, targetProfileSnap, blockSnap, mineSnap, theirsSnap, matchSnap] = await tx.getAll(
        r.datingProfile(to), r.profile(to), r.datingBlock(uid, to), r.datingLike(uid, to), r.datingLike(to, uid), r.datingMatch(pairId),
      );
      const block = blockSnap.exists ? (blockSnap.data() as DatingBlockDoc) : null;
      if (block?.by.includes(uid)) throw fail.pre('BLOCKED');
      const target = profileOf(to, targetSnap);
      // blocked BY them, gone or opted out: indistinguishable on purpose (blocks hide people)
      if (block || !target || !target.active || (!target.isBot && !targetProfileSnap.exists)) throw fail.notFound('USER_NOT_FOUND');
      const mine = mineSnap.exists ? (mineSnap.data() as DatingLikeDoc) : null;
      const theirs = theirsSnap.exists ? (theirsSnap.data() as DatingLikeDoc) : null;
      const match = matchSnap.exists ? (matchSnap.data() as DatingMatchDoc) : null;
      if (match?.status === 'active') return { ...OK, matched: { pairId } };
      const likes = priv.likes.day === today ? priv.likes : { day: today, count: 0 };
      const newLike = data.like && !(mine?.like === true);
      if (newLike && likes.count >= DATING_LIKES_PER_DAY) throw fail.pre('LIKE_DAILY_LIMIT');
      const mutual = data.like && theirs?.like === true;
      const doc: DatingLikeDoc = { fromUid: uid, toUid: to, like: data.like, botPending: data.like && target.isBot && !mutual, createdAtMs: mine?.createdAtMs ?? now };
      tx.set(r.datingLike(uid, to), doc);
      if (newLike) tx.set(r.datingPrivate(uid), { ...priv, likes: { day: today, count: likes.count + 1 }, updatedAtMs: now });
      if (mutual && !match) {
        const myCard = cardOf({ uid, username: me.username, avatar: me.avatar, isBot: false, favoriteGame: priv.favoriteGame ?? 'blackjack', interests: priv.interests ?? [], lookingFor: priv.lookingFor ?? 'both', active: true, updatedAtMs: now }, me.rankTier);
        const theirTier = target.isBot ? (botCard(to)?.rankTier ?? 'bronze') : (targetProfileSnap.get('rankTier') as RankTier);
        tx.set(r.datingMatch(pairId), newMatch(myCard, cardOf(target, theirTier), now));
        return { ...OK, matched: { pairId } };
      }
      return OK;
    }

    case 'send': {
      const m = await requireMatch(tx, db, data.pairId, uid);
      if (!canSend(m, uid, today)) throw rateLimited();
      let msg: DatingMessageDoc;
      if (data.lineId !== undefined) {
        if (!lineAllowed(m, uid, data.lineId)) throw fail.invalid('LINE_NOT_ALLOWED');
        msg = { fromUid: uid, kind: 'line', lineId: data.lineId, reaction: null, giftId: null, invite: null, createdAtMs: now };
      } else {
        msg = { fromUid: uid, kind: 'reaction', lineId: null, reaction: data.reaction!, giftId: null, invite: null, createdAtMs: now };
      }
      await postMessage(tx, db, m, msg, now);
      return OK;
    }

    case 'gift': {
      const gift = STORY.giftById.get(data.giftId);
      if (!gift || !gift.drink) throw fail.invalid('INVALID_ARGUMENT', 'only drinks can be offered to a match');
      const m = await requireMatch(tx, db, data.pairId, uid);
      const wallet = await WalletSession.load(db, tx, uid, now);
      if (!canSend(m, uid, today)) throw rateLimited();
      wallet.debit(gift.priceCents, 'gift', { itemId: gift.id });
      const msg: DatingMessageDoc = { fromUid: uid, kind: 'gift', lineId: null, reaction: null, giftId: gift.id, invite: null, createdAtMs: now };
      await postMessage(tx, db, m, msg, now, { extraDuo: DUO_GIFT_AFFINITY, wallet });
      return { ...OK, balanceCents: wallet.balance };
    }

    case 'invite': {
      const m = await requireMatch(tx, db, data.pairId, uid);
      if (!canSend(m, uid, today)) throw rateLimited();
      const tableId = me.currentTableId;
      if (!tableId) throw fail.pre('NO_PRIVATE_TABLE');
      const game: AnyGame = gameOfTableId(tableId);
      const [tableSnap, codes] = await Promise.all([
        tx.get(game === 'blackjack' ? r.table(tableId) : r.gameTable(tableId)),
        tx.get(db.collection('tableCodes').where('tableId', '==', tableId).limit(1)),
      ]);
      if (!tableSnap.exists || tableSnap.get('status') !== 'open' || tableSnap.get('isPrivate') !== true || codes.empty) throw fail.pre('NO_PRIVATE_TABLE');
      const msg: DatingMessageDoc = {
        fromUid: uid, kind: 'invite', lineId: null, reaction: null, giftId: null,
        invite: { tableId, game, code: codes.docs[0].id }, createdAtMs: now,
      };
      await postMessage(tx, db, m, msg, now);
      return OK;
    }

    case 'unmatch': {
      const m = await requireMatch(tx, db, data.pairId, uid);
      endMatch(tx, db, m);
      return OK;
    }

    case 'block': {
      const other = data.uid;
      if (other === uid) throw fail.invalid('INVALID_ARGUMENT', 'cannot block yourself');
      const [blockSnap, matchSnap] = await tx.getAll(r.datingBlock(uid, other), r.datingMatch(pairIdOf(uid, other)));
      const prev = blockSnap.exists ? (blockSnap.data() as DatingBlockDoc) : null;
      const block: DatingBlockDoc = { uids: [uid, other].sort() as [Uid, Uid], by: [...new Set([...(prev?.by ?? []), uid])].sort(), createdAtMs: prev?.createdAtMs ?? now };
      tx.set(r.datingBlock(uid, other), block);
      const m = matchSnap.exists ? (matchSnap.data() as DatingMatchDoc) : null;
      if (m?.status === 'active') endMatch(tx, db, m);
      return OK;
    }
  }
}

