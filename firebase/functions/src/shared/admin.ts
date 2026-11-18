/**
 * Firebase Admin initialisation shared by callables, the seed script and the sim runner.
 * Always targets project `demo-blackjack`; outside the Functions emulator the caller must set
 * FIRESTORE_EMULATOR_HOST (the tools/*.ps1 scripts do) — we refuse to run against production.
 */
import { getApps, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

export const PROJECT_ID = 'demo-blackjack';

let app: App | null = null;
let db: Firestore | null = null;

export function adminApp(): App {
  if (!app) {
    if (!process.env.FIRESTORE_EMULATOR_HOST && !process.env.FUNCTIONS_EMULATOR) {
      throw new Error('FIRESTORE_EMULATOR_HOST is not set: this backend only runs against the Firebase emulators.');
    }
    app = getApps()[0] ?? initializeApp({ projectId: PROJECT_ID });
  }
  return app;
}

export function firestore(): Firestore {
  if (!db) {
    db = getFirestore(adminApp());
  }
  return db;
}
