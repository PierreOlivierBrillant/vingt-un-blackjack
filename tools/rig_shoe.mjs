#!/usr/bin/env node
/**
 * TEST TOOL — EMULATOR ONLY. Forces the next hand of a table to a scenario (dealer shows an ace,
 * a pair for a player...) so that rare situations (insurance, split...) can be checked by hand on
 * the AVD. It never touches the callables: it rewrites, through the Admin SDK, the next hand's
 * secret seed (`tables/{id}/private/state.seed`) and its public commitment
 * (`fairness.currentCommit = sha256(seed)`), so the hand stays provably fair and verifiable.
 * The deal order is `fairDealOrder(shoe, seed)` (src/engine/fair.ts); seeds are drawn at random
 * until that order matches the scenario.
 *
 *   $env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8080'
 *   node tools/rig_shoe.mjs --table <tableId> --scenario dealer-ace [--players 1] [--seat 0] [--dealer-bj]
 *   node tools/rig_shoe.mjs --code ABC123 --scenario pair
 *
 * Scenarios (seats counted among the seats that will bet, in seat order; --players = how many):
 *   dealer-ace        dealer up card is an ace, hole card is not a ten (insurance offered, lost)
 *                     (--dealer-bj: hole card IS a ten — insurance pays, dealer blackjack)
 *   pair              player --seat gets a pair of 8s (split), dealer up card 5 or 6
 *   dealer-ace-pair   both
 * Run it while the table is in the BETTING phase (before every human has bet): it waits up to
 * --wait seconds for that phase.
 */
import { createRequire } from 'node:module';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const fnDir = path.join(here, '..', 'firebase', 'functions');
const require = createRequire(path.join(fnDir, 'package.json'));

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('Refusing to run: FIRESTORE_EMULATOR_HOST is not set (emulator only).');
  process.exit(2);
}
process.env.GCLOUD_PROJECT ??= 'demo-blackjack';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : 'true']);
    return acc;
  }, []),
);
const scenario = args.scenario ?? 'dealer-ace';
const players = Number(args.players ?? 1);
const seat = Number(args.seat ?? 0);
const dealerBj = args['dealer-bj'] === 'true';
const waitS = Number(args.wait ?? 60);

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { fairDealOrder, commitForSeed } = require(path.join(fnDir, 'lib', 'engine'));

initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = getFirestore();

const rank = (c) => c.slice(0, -1);
const isTen = (c) => ['T', 'J', 'Q', 'K'].includes(rank(c));

/** Positions in the deal order: round 0 = each seat then dealer up; round 1 = each seat then hole. */
function positions(n) {
  return {
    first: (k) => k,
    up: n,
    second: (k) => n + 1 + k,
    hole: 2 * n + 1,
  };
}

function matches(order) {
  const p = positions(players);
  const up = order[p.up];
  const hole = order[p.hole];
  const wantAce = scenario === 'dealer-ace' || scenario === 'dealer-ace-pair';
  const wantPair = scenario === 'pair' || scenario === 'dealer-ace-pair';
  if (wantAce) {
    if (rank(up) !== 'A') return false;
    if (dealerBj !== isTen(hole)) return false;
  } else if (!['5', '6'].includes(rank(up))) {
    return false;
  }
  if (wantPair) {
    const a = order[p.first(seat)];
    const b = order[p.second(seat)];
    if (rank(a) !== '8' || rank(b) !== '8') return false;
  }
  // Nobody else gets a natural (keeps the scenario readable).
  for (let k = 0; k < players; k++) {
    const a = order[p.first(k)];
    const b = order[p.second(k)];
    if ((rank(a) === 'A' && isTen(b)) || (rank(b) === 'A' && isTen(a))) return false;
  }
  return true;
}

async function findTableId() {
  if (args.table) return args.table;
  if (!args.code) throw new Error('--table <id> or --code <privateCode> is required');
  const snap = await db.doc(`tableCodes/${String(args.code).toUpperCase()}`).get();
  if (!snap.exists) throw new Error(`no table with code ${args.code}`);
  return snap.data().tableId;
}

const tableId = await findTableId();
const pubRef = db.doc(`tables/${tableId}`);
const privRef = db.doc(`tables/${tableId}/private/state`);

const deadline = Date.now() + waitS * 1000;
let pub;
for (;;) {
  pub = (await pubRef.get()).data();
  if (!pub) throw new Error(`table ${tableId} not found`);
  if (pub.phase === 'betting') break;
  if (Date.now() > deadline) throw new Error(`table ${tableId} not in betting phase (phase=${pub.phase})`);
  await new Promise((r) => setTimeout(r, 500));
}

const priv = (await privRef.get()).data();
let seed = null;
let order = null;
for (let tries = 1; tries <= 2_000_000; tries++) {
  const s = randomBytes(32).toString('hex');
  const o = fairDealOrder(priv.shoe, s, 6);
  if (matches(o)) {
    seed = s;
    order = o;
    console.log(`scenario '${scenario}' found after ${tries} seeds`);
    break;
  }
}
if (!seed) throw new Error('no matching seed found');

await db.runTransaction(async (tx) => {
  const p = (await tx.get(pubRef)).data();
  if (p.phase !== 'betting' || p.handNumber !== pub.handNumber) throw new Error('hand moved on; run again');
  tx.update(privRef, { seed, commit: commitForSeed(seed) });
  tx.update(pubRef, { 'fairness.currentCommit': commitForSeed(seed) });
});
const n = 2 * players + 2;
console.log(`table ${tableId} hand #${pub.handNumber} rigged; first ${n} cards: ${order.slice(0, n).join(' ')}`);
process.exit(0);
