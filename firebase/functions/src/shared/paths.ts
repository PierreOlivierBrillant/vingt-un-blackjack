/** Firestore document references (single place for every path listed in shared/types.ts). */
import type { DocumentReference, Firestore } from 'firebase-admin/firestore';

export const refs = (db: Firestore) => ({
  profile: (uid: string) => db.doc(`profiles/${uid}`),
  settings: (uid: string) => db.doc(`users/${uid}`),
  wallet: (uid: string) => db.doc(`users/${uid}/private/wallet`),
  kyc: (uid: string) => db.doc(`users/${uid}/private/kyc`),
  suggestions: (uid: string) => db.doc(`users/${uid}/private/suggestions`),
  ads: (uid: string) => db.doc(`users/${uid}/private/ads`),
  ledger: (uid: string) => db.collection(`users/${uid}/ledger`),
  inventory: (uid: string, powerId: string) => db.doc(`users/${uid}/inventory/${powerId}`),
  position: (uid: string, marketId: string) => db.doc(`users/${uid}/positions/${marketId}`),
  username: (lower: string) => db.doc(`usernames/${lower}`),
  table: (tableId: string) => db.doc(`tables/${tableId}`),
  tablePrivate: (tableId: string) => db.doc(`tables/${tableId}/private/state`),
  peek: (tableId: string, uid: string) => db.doc(`tables/${tableId}/peeks/${uid}`),
  hand: (tableId: string, handNumber: number) => db.doc(`tables/${tableId}/hands/${String(handNumber).padStart(8, '0')}`),
  tableCode: (code: string) => db.doc(`tableCodes/${code}`),
  market: (marketId: string) => db.doc(`markets/${marketId}`),
  trades: (marketId: string) => db.collection(`markets/${marketId}/trades`),
  priceHistory: (marketId: string) => db.collection(`markets/${marketId}/priceHistory`),
  friendRequest: (from: string, to: string) => db.doc(`friendRequests/${from}_${to}`),
  friendship: (a: string, b: string) => db.doc(`friendships/${[a, b].sort().join('_')}`),
  feed: () => db.collection('feed'),
  idempotency: (uid: string, requestId: string) => db.doc(`idempotency/${uid}_${requestId}`),
  rateLimit: (uid: string) => db.doc(`rateLimits/${uid}`),
});

export type Refs = ReturnType<typeof refs>;
export type Ref = DocumentReference;
