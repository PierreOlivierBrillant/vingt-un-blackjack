/**
 * Server-side secret used to sign wallet documents (mitigation for the "direct emulator write"
 * vulnerability). The key lives ONLY in the Functions runtime, never in Firestore, so a client
 * that reaches the Firestore emulator with "owner" access can rewrite a balance but cannot forge
 * its signature: the tampered wallet is then rejected by every callable (WALLET_INTEGRITY), and
 * the fake money cannot be played. See shared/wallet.ts.
 *
 * Key source, in order:
 *   1. process.env.WALLET_SIGNING_KEY  — set this for a real deployment (treated as raw bytes).
 *   2. a random 32-byte key persisted to a gitignored file next to the functions. It is stable
 *      across emulator restarts (so --import/--export keeps working) and is created on first use.
 *      LAN clients only reach the emulator APIs, not the teacher's filesystem, so it stays secret.
 *   3. a process-lifetime random key, only if the filesystem is read-only (should not happen).
 */
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

let cached: Buffer | null = null;

/** The wallet signing key (cached for the process lifetime). */
export function walletSigningKey(): Buffer {
  if (cached) return cached;
  const fromEnv = process.env.WALLET_SIGNING_KEY;
  if (fromEnv && fromEnv.length >= 16) {
    cached = Buffer.from(fromEnv, 'utf8');
    return cached;
  }
  // __dirname is lib/shared at runtime, so this resolves to functions/.wallet-signing-key.
  const file = process.env.WALLET_KEY_FILE ?? resolve(__dirname, '../../.wallet-signing-key');
  try {
    if (existsSync(file)) {
      const hex = readFileSync(file, 'utf8').trim();
      if (hex.length >= 32) {
        cached = Buffer.from(hex, 'hex');
        return cached;
      }
    }
    const key = randomBytes(32);
    writeFileSync(file, key.toString('hex'), { mode: 0o600 });
    cached = key;
    return cached;
  } catch {
    cached = randomBytes(32);
    return cached;
  }
}

/** Test helper: forget the cached key (so a test can set a fresh WALLET_SIGNING_KEY). */
export function resetWalletSigningKeyForTests(): void {
  cached = null;
}
