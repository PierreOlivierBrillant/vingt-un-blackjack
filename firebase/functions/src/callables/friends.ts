/** Friend requests and friendships (server-only writes). */
import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { fail } from '../shared/errors';
import { refs } from '../shared/paths';
import type { FriendRequestDoc, FriendshipDoc, ProfileDoc } from '../shared/types';
import { defineCallable } from './framework';
import { S } from './schemas';

async function profileOf(db: Firestore, tx: Transaction, uid: string): Promise<ProfileDoc | null> {
  const s = await tx.get(refs(db).profile(uid));
  return s.exists ? (s.data() as ProfileDoc) : null;
}

function friendship(a: ProfileDoc, b: ProfileDoc, now: number): FriendshipDoc {
  const uids = [a.uid, b.uid].sort() as [string, string];
  return { uids, usernames: { [a.uid]: a.username, [b.uid]: b.username }, sinceMs: now };
}

export const friendRequest = defineCallable({
  name: 'friendRequest',
  schema: S.friendRequest,
  handler: async (tx, data, { db, uid, now }) => {
    const r = refs(db);
    const me = await profileOf(db, tx, uid);
    if (!me) throw fail.pre('PROFILE_REQUIRED');
    let toUid: string;
    if ('toUid' in data) toUid = data.toUid;
    else {
      const u = await tx.get(r.username(data.toUsername.toLowerCase()));
      if (!u.exists) throw fail.notFound('USER_NOT_FOUND');
      toUid = u.get('uid') as string;
    }
    if (toUid === uid) throw fail.invalid('SELF_FRIEND');
    const [other, fs, mine, theirs] = await Promise.all([
      profileOf(db, tx, toUid), tx.get(r.friendship(uid, toUid)), tx.get(r.friendRequest(uid, toUid)), tx.get(r.friendRequest(toUid, uid)),
    ]);
    if (!other) throw fail.notFound('USER_NOT_FOUND');
    if (fs.exists) throw fail.exists('ALREADY_FRIENDS');
    if (mine.exists) throw fail.exists('REQUEST_EXISTS');
    if (theirs.exists) {
      tx.delete(r.friendRequest(toUid, uid));
      tx.set(r.friendship(uid, toUid), friendship(me, other, now));
      return { response: { status: 'accepted' as const, toUid } };
    }
    const req: FriendRequestDoc = {
      fromUid: uid, toUid, fromUsername: me.username, toUsername: other.username, fromAvatar: me.avatar, createdAtMs: now,
    };
    tx.set(r.friendRequest(uid, toUid), req);
    return { response: { status: 'pending' as const, toUid } };
  },
});

export const respondFriend = defineCallable({
  name: 'respondFriend',
  schema: S.respondFriend,
  handler: async (tx, data, { db, uid, now }) => {
    const r = refs(db);
    const [req, me, other, fs] = await Promise.all([
      tx.get(r.friendRequest(data.fromUid, uid)), profileOf(db, tx, uid), profileOf(db, tx, data.fromUid), tx.get(r.friendship(uid, data.fromUid)),
    ]);
    if (!me) throw fail.pre('PROFILE_REQUIRED');
    if (!req.exists) throw fail.notFound('REQUEST_NOT_FOUND');
    tx.delete(r.friendRequest(data.fromUid, uid));
    if (data.accept && other && !fs.exists) tx.set(r.friendship(uid, data.fromUid), friendship(me, other, now));
    return { response: { status: data.accept ? ('accepted' as const) : ('declined' as const) } };
  },
});

export const removeFriend = defineCallable({
  name: 'removeFriend',
  schema: S.removeFriend,
  handler: async (tx, data, { db, uid }) => {
    const r = refs(db);
    const fs = await tx.get(r.friendship(uid, data.friendUid));
    if (!fs.exists) throw fail.notFound('NOT_FRIENDS');
    tx.delete(r.friendship(uid, data.friendUid));
    return { response: { removed: true as const } };
  },
});
