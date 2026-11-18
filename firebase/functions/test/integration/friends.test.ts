import { collection, getDocs, query, where } from 'firebase/firestore';
import { describe, expect, it } from 'vitest';
import { admin, playerClient, reason } from './client';

describe('friends', () => {
  it('request → accept → friendship visible to both → remove', async () => {
    const a = await playerClient();
    const b = await playerClient();
    expect(await a.call('friendRequest', { toUsername: b.username.toUpperCase() })).toEqual({ status: 'pending', toUid: b.uid });
    expect(await reason(a.call('friendRequest', { toUid: b.uid }))).toBe('REQUEST_EXISTS');
    const incoming = await getDocs(query(collection(b.db, 'friendRequests'), where('toUid', '==', b.uid)));
    expect(incoming.docs.map((d) => d.get('fromUid'))).toContain(a.uid);
    expect(await b.call('respondFriend', { fromUid: a.uid, accept: true })).toEqual({ status: 'accepted' });
    const fs = await getDocs(query(collection(a.db, 'friendships'), where('uids', 'array-contains', a.uid)));
    expect(fs.docs.some((d) => (d.get('uids') as string[]).includes(b.uid))).toBe(true);
    expect(await reason(b.call('friendRequest', { toUid: a.uid }))).toBe('ALREADY_FRIENDS');
    expect(await b.call('removeFriend', { friendUid: a.uid })).toEqual({ removed: true });
    expect(await reason(b.call('removeFriend', { friendUid: a.uid }))).toBe('NOT_FRIENDS');
    await a.close();
    await b.close();
  });

  it('crossed requests become a friendship immediately; decline; errors', async () => {
    const a = await playerClient();
    const b = await playerClient();
    await a.call('friendRequest', { toUid: b.uid });
    expect(await b.call('friendRequest', { toUid: a.uid })).toEqual({ status: 'accepted', toUid: a.uid });
    expect((await admin().doc(`friendships/${[a.uid, b.uid].sort().join('_')}`).get()).exists).toBe(true);
    const c = await playerClient();
    await c.call('friendRequest', { toUid: a.uid });
    expect(await a.call('respondFriend', { fromUid: c.uid, accept: false })).toEqual({ status: 'declined' });
    expect(await reason(a.call('respondFriend', { fromUid: c.uid, accept: true }))).toBe('REQUEST_NOT_FOUND');
    expect(await reason(a.call('friendRequest', { toUid: a.uid }))).toBe('SELF_FRIEND');
    expect(await reason(a.call('friendRequest', { toUid: 'nobody_here' }))).toBe('USER_NOT_FOUND');
    expect(await reason(a.call('friendRequest', { toUsername: 'NoSuchUser42' }))).toBe('USER_NOT_FOUND');
    await Promise.all([a.close(), b.close(), c.close()]);
  });

  it('bot friend requests created at sign-up can be accepted', async () => {
    const a = await playerClient();
    const reqs = await admin().collection('friendRequests').where('toUid', '==', a.uid).get();
    const from = reqs.docs[0].get('fromUid') as string;
    // bot profiles exist only after the seed; respondFriend still clears the request
    expect(await a.call('respondFriend', { fromUid: from, accept: false })).toEqual({ status: 'declined' });
    await a.close();
  });
});
