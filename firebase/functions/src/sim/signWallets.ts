/**
 * One-off backfill: (re)signs every wallet document with the current signing key.
 *
 * Run this once after enabling wallet signatures on a database that was seeded or persisted BEFORE
 * the feature existed — otherwise those wallets have no signature and every callable rejects them
 * with WALLET_INTEGRITY. A fresh database does not need it (wallets are signed from creation).
 *
 *   node lib/sim/signWallets.js
 * Requires FIRESTORE_EMULATOR_HOST (tools/sign_wallets.ps1 sets it) and the same WALLET_SIGNING_KEY
 * / key file the Functions runtime uses.
 */
import { firestore } from '../shared/admin';
import type { WalletDoc } from '../shared/types';
import { walletSignature } from '../shared/wallet';

export async function signAllWallets(): Promise<number> {
  const db = firestore();
  const snaps = await db.collectionGroup('private').get();
  let signed = 0;
  for (const d of snaps.docs) {
    if (d.id !== 'wallet') continue; // the "private" group also holds kyc/suggestions/ads
    const uid = d.ref.parent.parent?.id;
    if (!uid) continue;
    const doc = d.data() as WalletDoc;
    const sig = walletSignature(uid, doc);
    if (doc.sig === sig) continue;
    await d.ref.set({ sig }, { merge: true });
    signed++;
  }
  return signed;
}

if (require.main === module) {
  signAllWallets()
    .then((n) => {
      console.log(`signWallets: signed ${n} wallet(s)`);
      process.exit(0);
    })
    .catch((e) => {
      console.error('signWallets failed:', (e as Error).message);
      process.exit(1);
    });
}
