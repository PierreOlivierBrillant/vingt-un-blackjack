/**
 * Firestore security rules: every row of the security table, positive AND negative.
 * Run inside `firebase emulators:exec --only firestore` (FIRESTORE_EMULATOR_HOST is set).
 */
import {
  assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where, type Firestore,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

let env: RulesTestEnvironment;
const ALICE = 'alice';
const BOB = 'bob';
const EVE = 'eve';

const alice = (): Firestore => env.authenticatedContext(ALICE).firestore() as unknown as Firestore;
const bob = (): Firestore => env.authenticatedContext(BOB).firestore() as unknown as Firestore;
const eve = (): Firestore => env.authenticatedContext(EVE).firestore() as unknown as Firestore;
const anon = (): Firestore => env.unauthenticatedContext().firestore() as unknown as Firestore;

const SETTINGS = { theme: 'dark', language: 'fr', cardBack: 'classicBlue', cardFace: 'classic', felt: 'green', updatedAtMs: 1 };

beforeAll(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-blackjack-rules',
    firestore: { rules: readFileSync(resolve(__dirname, '../../../firestore.rules'), 'utf8'), host, port: Number(port) },
  });
});

afterAll(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const put = (p: string, d: object) => setDoc(doc(db, p), d);
    await put(`profiles/${ALICE}`, { username: 'alice', rankPoints: 0 });
    await put(`users/${ALICE}`, SETTINGS);
    await put(`users/${ALICE}/private/wallet`, { balanceCents: 100000 });
    await put(`users/${ALICE}/private/kyc`, { status: 'none' });
    await put(`users/${ALICE}/ledger/e1`, { amountCents: 100000 });
    await put(`users/${ALICE}/inventory/peek`, { quantity: 1 });
    await put(`users/${ALICE}/positions/m1`, { yesShares: 3 });
    await put('tables/t1', { phase: 'betting' });
    await put('tables/t1/private/state', { shoe: ['AS'], seed: 'x' });
    await put(`tables/t1/peeks/${ALICE}`, { holeCard: 'KD' });
    await put('tables/t1/hands/00000001', { handNumber: 1 });
    await put('markets/m1', { priceYes: 0.5 });
    await put('markets/m1/trades/tr1', { shares: 1 });
    await put('markets/m1/priceHistory/p1', { priceYes: 0.5 });
    await put(`friendships/${ALICE}_${BOB}`, { uids: [ALICE, BOB] });
    await put(`friendRequests/${BOB}_${ALICE}`, { fromUid: BOB, toUid: ALICE });
    await put('feed/f1', { amountCents: 100 });
    await put('usernames/alice', { uid: ALICE });
    await put('tableCodes/ABC123', { tableId: 't1' });
    await put(`idempotency/${ALICE}_req12345`, { fn: 'deposit' });
    await put(`rateLimits/${ALICE}`, { deposit: { count: 1 } });
    // Sprint 2: kernel-driven games
    await put('gameTables/rl-t1', { phase: 'betting', game: 'roulette' });
    await put('gameTables/rl-t1/private/state', { seed: 'x', g: {} });
    await put(`gameTables/rl-t1/bets/${ALICE}`, { bets: { red: 100 } });
    await put(`gameTables/ho-t1/holes/${ALICE}`, { cards: ['AS', 'KD'] });
    await put('gameTables/rl-t1/rounds/00000001', { round: 1 });
    // Sprint 2: Rendez-vous, cosmetics, dating
    await put(`users/${ALICE}/romance/lucas`, { affinity: 10 });
    await put(`users/${ALICE}/unlocks/rv_lucas_back`, { cosmeticId: 'rv_lucas_back' });
    await put(`users/${ALICE}/private/dating`, { optedIn: true });
    await put(`datingMatches/${ALICE}_${BOB}`, { uids: [ALICE, BOB], status: 'active', lastMessageAtMs: 1 });
    await put(`datingMatches/${ALICE}_${BOB}/messages/m1`, { fromUid: BOB, kind: 'line', lineId: 'hello' });
    await put(`datingMatches/${ALICE}_${EVE}`, { uids: [ALICE, EVE], status: 'ended', lastMessageAtMs: 1 });
    await put(`datingMatches/${ALICE}_${EVE}/messages/m1`, { fromUid: EVE, kind: 'line', lineId: 'hello' });
    await put(`datingProfiles/${ALICE}`, { uid: ALICE, active: true });
    await put(`datingLikes/${BOB}_${ALICE}`, { fromUid: BOB });
    await put(`datingBlocks/${ALICE}_${EVE}`, { by: ALICE });
    await put('config/features', { dating: false });
  });
});

describe('profiles/{uid}', () => {
  it('signed-in users can read any profile', async () => {
    await assertSucceeds(getDoc(doc(bob(), `profiles/${ALICE}`)));
  });
  it('unauthenticated cannot read', async () => {
    await assertFails(getDoc(doc(anon(), `profiles/${ALICE}`)));
  });
  it('nobody can write a profile (not even the owner: rank, stats)', async () => {
    await assertFails(updateDoc(doc(alice(), `profiles/${ALICE}`), { rankPoints: 99999 }));
    await assertFails(setDoc(doc(bob(), `profiles/${BOB}`), { username: 'bob' }));
    await assertFails(deleteDoc(doc(alice(), `profiles/${ALICE}`)));
  });
});

describe('users/{uid} settings', () => {
  it('owner reads, others cannot', async () => {
    await assertSucceeds(getDoc(doc(alice(), `users/${ALICE}`)));
    await assertFails(getDoc(doc(bob(), `users/${ALICE}`)));
    await assertFails(getDoc(doc(anon(), `users/${ALICE}`)));
  });
  it('owner updates theme / language / updatedAtMs only (also with set merge, as the app does)', async () => {
    await assertSucceeds(updateDoc(doc(alice(), `users/${ALICE}`), { theme: 'light', language: 'en', updatedAtMs: 2 }));
    await assertSucceeds(setDoc(doc(alice(), `users/${ALICE}`), { theme: 'system', updatedAtMs: 3 }, { merge: true }));
    await assertSucceeds(updateDoc(doc(alice(), `users/${ALICE}`), { language: 'fr' }));
  });
  it('card styles are no longer client-writable, not even free ones (equipCardStyle checks unlocks)', async () => {
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { felt: 'blue' }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { cardBack: 'neonGrid' }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { cardFace: 'neon' }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { theme: 'light', felt: 'blue', updatedAtMs: 2 }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { cardBack: 'rv_lucas_back' })); // exclusive, even if unlocked
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { felt: 'rv_camille_felt' }));
    await assertFails(setDoc(doc(alice(), `users/${ALICE}`), { ...SETTINGS, cardBack: 'duo_back' }));
    await assertFails(setDoc(doc(alice(), `users/${ALICE}`), { felt: 'rv_ines_felt' }, { merge: true }));
  });
  it('owner can create own settings doc with theme / language only', async () => {
    await assertSucceeds(setDoc(doc(bob(), `users/${BOB}`), { theme: 'dark', language: 'fr', updatedAtMs: 1 }));
  });
  it('creating a settings doc with card styles is refused', async () => {
    await assertFails(setDoc(doc(bob(), `users/${BOB}`), SETTINGS));
    await assertFails(setDoc(doc(bob(), `users/${BOB}`), { theme: 'dark', felt: 'green' }));
  });
  it('rejects non-whitelisted fields (money, rank) and bad values', async () => {
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { balanceCents: 1e9 }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { rankPoints: 1 }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { theme: 'hacker' }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { language: 'de' }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { cardBack: 'x' }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}`), { updatedAtMs: 'now' }));
    await assertFails(setDoc(doc(bob(), `users/${BOB}`), { ...SETTINGS, isAdmin: true }));
  });
  it('others cannot write, nobody deletes', async () => {
    await assertFails(updateDoc(doc(bob(), `users/${ALICE}`), { theme: 'light' }));
    await assertFails(setDoc(doc(anon(), `users/${ALICE}`), SETTINGS));
    await assertFails(deleteDoc(doc(alice(), `users/${ALICE}`)));
  });
});

describe('users/{uid}/private/*, ledger, inventory, positions, kyc', () => {
  const paths = [`users/${ALICE}/private/wallet`, `users/${ALICE}/private/kyc`, `users/${ALICE}/ledger/e1`, `users/${ALICE}/inventory/peek`, `users/${ALICE}/positions/m1`];
  it('owner can read', async () => {
    for (const p of paths) await assertSucceeds(getDoc(doc(alice(), p)));
    await assertSucceeds(getDocs(collection(alice(), `users/${ALICE}/ledger`)));
  });
  it('others cannot read', async () => {
    for (const p of paths) {
      await assertFails(getDoc(doc(bob(), p)));
      await assertFails(getDoc(doc(anon(), p)));
    }
  });
  it('nobody can write (wallet, ledger, inventory, positions, kyc)', async () => {
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}/private/wallet`), { balanceCents: 1e9 }));
    await assertFails(setDoc(doc(alice(), `users/${ALICE}/private/kyc`), { status: 'verified' }));
    await assertFails(setDoc(doc(alice(), `users/${ALICE}/ledger/e2`), { amountCents: 5 }));
    await assertFails(setDoc(doc(alice(), `users/${ALICE}/inventory/freeSplit`), { quantity: 99 }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}/positions/m1`), { yesShares: 1000 }));
    await assertFails(deleteDoc(doc(alice(), `users/${ALICE}/ledger/e1`)));
    await assertFails(setDoc(doc(bob(), `users/${ALICE}/private/wallet`), { balanceCents: 0 }));
  });
});

describe('tables/{id}', () => {
  it('signed-in read, unauthenticated cannot', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'tables/t1')));
    await assertFails(getDoc(doc(anon(), 'tables/t1')));
  });
  it('nobody writes table state (cards, bets, phase)', async () => {
    await assertFails(updateDoc(doc(alice(), 'tables/t1'), { phase: 'settled' }));
    await assertFails(setDoc(doc(alice(), 'tables/t2'), { phase: 'betting' }));
    await assertFails(deleteDoc(doc(alice(), 'tables/t1')));
  });
  it('private shoe / hole card / seed: nobody reads or writes', async () => {
    await assertFails(getDoc(doc(alice(), 'tables/t1/private/state')));
    await assertFails(getDoc(doc(anon(), 'tables/t1/private/state')));
    await assertFails(getDocs(collection(alice(), 'tables/t1/private')));
    await assertFails(setDoc(doc(alice(), 'tables/t1/private/state'), { shoe: [] }));
  });
  it('peeks/{uid}: only that uid reads; nobody writes', async () => {
    await assertSucceeds(getDoc(doc(alice(), `tables/t1/peeks/${ALICE}`)));
    await assertFails(getDoc(doc(bob(), `tables/t1/peeks/${ALICE}`)));
    await assertFails(setDoc(doc(bob(), `tables/t1/peeks/${BOB}`), { holeCard: 'AS' }));
  });
  it('hands history readable by signed-in, not writable', async () => {
    await assertSucceeds(getDoc(doc(bob(), 'tables/t1/hands/00000001')));
    await assertFails(getDoc(doc(anon(), 'tables/t1/hands/00000001')));
    await assertFails(setDoc(doc(bob(), 'tables/t1/hands/00000002'), { handNumber: 2 }));
  });
});

describe('markets, trades, priceHistory', () => {
  it('signed-in read', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'markets/m1')));
    await assertSucceeds(getDocs(collection(alice(), 'markets/m1/trades')));
    await assertSucceeds(getDocs(collection(alice(), 'markets/m1/priceHistory')));
  });
  it('unauthenticated cannot read', async () => {
    await assertFails(getDoc(doc(anon(), 'markets/m1')));
    await assertFails(getDocs(collection(anon(), 'markets/m1/trades')));
  });
  it('nobody writes', async () => {
    await assertFails(updateDoc(doc(alice(), 'markets/m1'), { priceYes: 0.99 }));
    await assertFails(setDoc(doc(alice(), 'markets/m1/trades/tr2'), { shares: 1 }));
    await assertFails(setDoc(doc(alice(), 'markets/m1/priceHistory/p2'), { priceYes: 0.1 }));
  });
});

describe('friendships and friendRequests', () => {
  it('participants read friendships, query by array-contains', async () => {
    await assertSucceeds(getDoc(doc(alice(), `friendships/${ALICE}_${BOB}`)));
    await assertSucceeds(getDoc(doc(bob(), `friendships/${ALICE}_${BOB}`)));
    await assertSucceeds(getDocs(query(collection(alice(), 'friendships'), where('uids', 'array-contains', ALICE))));
  });
  it('non-participants cannot read; nobody writes', async () => {
    await assertFails(getDoc(doc(eve(), `friendships/${ALICE}_${BOB}`)));
    await assertFails(getDocs(collection(eve(), 'friendships')));
    await assertFails(setDoc(doc(eve(), `friendships/${ALICE}_${EVE}`), { uids: [ALICE, EVE] }));
    await assertFails(deleteDoc(doc(alice(), `friendships/${ALICE}_${BOB}`)));
  });
  it('requests: sender and recipient read, query by toUid', async () => {
    await assertSucceeds(getDoc(doc(alice(), `friendRequests/${BOB}_${ALICE}`)));
    await assertSucceeds(getDoc(doc(bob(), `friendRequests/${BOB}_${ALICE}`)));
    await assertSucceeds(getDocs(query(collection(alice(), 'friendRequests'), where('toUid', '==', ALICE))));
  });
  it('requests: others cannot read; nobody writes', async () => {
    await assertFails(getDoc(doc(eve(), `friendRequests/${BOB}_${ALICE}`)));
    await assertFails(setDoc(doc(eve(), `friendRequests/${EVE}_${ALICE}`), { fromUid: EVE, toUid: ALICE }));
    await assertFails(deleteDoc(doc(alice(), `friendRequests/${BOB}_${ALICE}`)));
  });
});

describe('feed', () => {
  it('signed-in read, no write', async () => {
    await assertSucceeds(getDocs(collection(alice(), 'feed')));
    await assertFails(getDocs(collection(anon(), 'feed')));
    await assertFails(setDoc(doc(alice(), 'feed/f2'), { amountCents: 1e9 }));
  });
});

describe('gameTables/{id} (kernel-driven games)', () => {
  it('table state: signed-in read, unauthenticated cannot, nobody writes', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'gameTables/rl-t1')));
    await assertSucceeds(getDocs(query(collection(bob(), 'gameTables'), where('game', '==', 'roulette'))));
    await assertFails(getDoc(doc(anon(), 'gameTables/rl-t1')));
    await assertFails(updateDoc(doc(alice(), 'gameTables/rl-t1'), { phase: 'settled' }));
    await assertFails(setDoc(doc(alice(), 'gameTables/rl-t2'), { phase: 'betting' }));
    await assertFails(deleteDoc(doc(alice(), 'gameTables/rl-t1')));
  });
  it('private state (seed, shoe, deck): nobody reads or writes', async () => {
    await assertFails(getDoc(doc(alice(), 'gameTables/rl-t1/private/state')));
    await assertFails(getDocs(collection(alice(), 'gameTables/rl-t1/private')));
    await assertFails(setDoc(doc(alice(), 'gameTables/rl-t1/private/state'), { seed: 'mine' }));
  });
  it('bet boards: public to signed-in users, never client-written (not even your own)', async () => {
    await assertSucceeds(getDoc(doc(bob(), `gameTables/rl-t1/bets/${ALICE}`)));
    await assertSucceeds(getDocs(collection(bob(), 'gameTables/rl-t1/bets')));
    await assertFails(getDoc(doc(anon(), `gameTables/rl-t1/bets/${ALICE}`)));
    await assertFails(setDoc(doc(alice(), `gameTables/rl-t1/bets/${ALICE}`), { bets: { red: 1e9 } }));
    await assertFails(deleteDoc(doc(alice(), `gameTables/rl-t1/bets/${ALICE}`)));
  });
  it('hole cards: only that player reads; nobody writes', async () => {
    await assertSucceeds(getDoc(doc(alice(), `gameTables/ho-t1/holes/${ALICE}`)));
    await assertFails(getDoc(doc(bob(), `gameTables/ho-t1/holes/${ALICE}`)));
    await assertFails(getDocs(collection(bob(), 'gameTables/ho-t1/holes')));
    await assertFails(setDoc(doc(alice(), `gameTables/ho-t1/holes/${ALICE}`), { cards: ['AS', 'AH'] }));
  });
  it('round history: signed-in read, not writable', async () => {
    await assertSucceeds(getDoc(doc(bob(), 'gameTables/rl-t1/rounds/00000001')));
    await assertFails(getDoc(doc(anon(), 'gameTables/rl-t1/rounds/00000001')));
    await assertFails(setDoc(doc(bob(), 'gameTables/rl-t1/rounds/00000002'), { round: 2 }));
  });
});

describe('Rendez-vous: romance, unlocks, private/dating', () => {
  const paths = [`users/${ALICE}/romance/lucas`, `users/${ALICE}/unlocks/rv_lucas_back`, `users/${ALICE}/private/dating`];
  it('owner reads (affinity, unlocked cosmetics, dating opt-in)', async () => {
    for (const p of paths) await assertSucceeds(getDoc(doc(alice(), p)));
    await assertSucceeds(getDocs(collection(alice(), `users/${ALICE}/unlocks`)));
    await assertSucceeds(getDocs(collection(alice(), `users/${ALICE}/romance`)));
  });
  it('others cannot read; nobody writes (no self-unlocked cosmetic, no affinity edit)', async () => {
    for (const p of paths) {
      await assertFails(getDoc(doc(bob(), p)));
      await assertFails(getDoc(doc(anon(), p)));
    }
    await assertFails(setDoc(doc(alice(), `users/${ALICE}/unlocks/duo_back`), { cosmeticId: 'duo_back' }));
    await assertFails(updateDoc(doc(alice(), `users/${ALICE}/romance/lucas`), { affinity: 300 }));
    await assertFails(setDoc(doc(alice(), `users/${ALICE}/romance/camille`), { tablePlay: { '2026-11-26': 99 } }));
    await assertFails(setDoc(doc(alice(), `users/${ALICE}/private/dating`), { optedIn: true }));
  });
});

describe('datingMatches and messages', () => {
  it('members of an ACTIVE match read it and query their matches', async () => {
    await assertSucceeds(getDoc(doc(alice(), `datingMatches/${ALICE}_${BOB}`)));
    await assertSucceeds(getDoc(doc(bob(), `datingMatches/${ALICE}_${BOB}`)));
    await assertSucceeds(getDocs(query(collection(alice(), 'datingMatches'), where('uids', 'array-contains', ALICE), where('status', '==', 'active'))));
  });
  it('an ended match is no longer readable; non-members and unfiltered queries are refused', async () => {
    await assertFails(getDoc(doc(alice(), `datingMatches/${ALICE}_${EVE}`)));
    await assertFails(getDoc(doc(eve(), `datingMatches/${ALICE}_${BOB}`)));
    await assertFails(getDoc(doc(anon(), `datingMatches/${ALICE}_${BOB}`)));
    await assertFails(getDocs(query(collection(alice(), 'datingMatches'), where('uids', 'array-contains', ALICE))));
    await assertFails(getDocs(collection(eve(), 'datingMatches')));
  });
  it('messages: members of an active match only; nobody writes (no free text, ever)', async () => {
    await assertSucceeds(getDocs(collection(alice(), `datingMatches/${ALICE}_${BOB}/messages`)));
    await assertSucceeds(getDoc(doc(bob(), `datingMatches/${ALICE}_${BOB}/messages/m1`)));
    await assertFails(getDoc(doc(eve(), `datingMatches/${ALICE}_${BOB}/messages/m1`)));
    await assertFails(getDoc(doc(alice(), `datingMatches/${ALICE}_${EVE}/messages/m1`))); // ended
    await assertFails(setDoc(doc(alice(), `datingMatches/${ALICE}_${BOB}/messages/m2`), { kind: 'line', text: 'hi' }));
    await assertFails(updateDoc(doc(alice(), `datingMatches/${ALICE}_${BOB}`), { status: 'ended' }));
    await assertFails(setDoc(doc(eve(), `datingMatches/${EVE}_${BOB}`), { uids: [EVE, BOB], status: 'active' }));
  });
});

describe('server-only collections', () => {
  for (const p of [
    'usernames/alice', 'tableCodes/ABC123', `idempotency/${ALICE}_req12345`, `rateLimits/${ALICE}`,
    `datingProfiles/${ALICE}`, `datingLikes/${BOB}_${ALICE}`, `datingBlocks/${ALICE}_${EVE}`, 'config/features',
  ]) {
    it(`${p.split('/')[0]}: no read, no write`, async () => {
      await assertFails(getDoc(doc(alice(), p)));
      await assertFails(setDoc(doc(alice(), p), { x: 1 }));
    });
  }
  it('unknown collections are denied', async () => {
    await assertFails(getDoc(doc(alice(), 'admin/config')));
    await assertFails(setDoc(doc(alice(), 'admin/config'), { x: 1 }));
  });
});
