/**
 * Random number sources. The engine never calls Math.random: every random decision
 * goes through an injected `Rng`, so a fixed seed gives a fully deterministic game.
 *
 *  - cryptoRng():      production source, `crypto.randomInt` (CSPRNG).
 *  - seededRng(hex):   deterministic SHA-256 counter-mode DRBG. Used for the provably-fair
 *                      per-hand deal order (anyone can recompute it from the revealed seed).
 *  - fastRng(n):       deterministic, fast, NON-cryptographic (sfc32). Only for Monte-Carlo
 *                      tests and bot "noise" in tests; never for dealing real hands.
 */
import { createHash, randomBytes, randomInt } from 'node:crypto';

export interface Rng {
  /** Uniform integer in [0, maxExclusive). maxExclusive must be an integer in [1, 2^32]. */
  nextInt(maxExclusive: number): number;
}

function checkBound(n: number): void {
  if (!Number.isInteger(n) || n < 1 || n > 0x1_0000_0000) throw new RangeError(`bad bound ${n}`);
}

export function cryptoRng(): Rng {
  return {
    nextInt(n: number): number {
      checkBound(n);
      if (n === 1) return 0;
      // crypto.randomInt requires max - min <= 2^48 - 1; our bounds are far below that.
      return randomInt(0, n);
    },
  };
}

/** 32 random bytes from the CSPRNG, hex encoded (64 chars). */
export function newSeedHex(): string {
  return randomBytes(32).toString('hex');
}

/**
 * Deterministic DRBG: block_i = SHA-256(seed + ":" + i). Uniform integers by rejection
 * sampling on 32-bit words (no modulo bias). Specified precisely so third parties can
 * re-implement it for verification.
 */
export function seededRng(seed: string): Rng {
  let counter = 0;
  let block: Buffer = Buffer.alloc(0);
  let offset = 32;
  const nextU32 = (): number => {
    if (offset >= 32) {
      block = createHash('sha256').update(`${seed}:${counter}`).digest();
      counter++;
      offset = 0;
    }
    const v = block.readUInt32BE(offset);
    offset += 4;
    return v;
  };
  return {
    nextInt(n: number): number {
      checkBound(n);
      if (n === 1) return 0;
      const limit = Math.floor(0x1_0000_0000 / n) * n;
      for (;;) {
        const x = nextU32();
        if (x < limit) return x % n;
      }
    },
  };
}

/** sfc32, seeded from an integer. Fast deterministic PRNG for simulations/tests only. */
export function fastRng(seed: number): Rng {
  let a = 0x9e3779b9 ^ seed;
  let b = 0x243f6a88 ^ (seed * 31);
  let c = 0xb7e15162 ^ (seed * 17);
  let d = 1;
  const next = (): number => {
    a >>>= 0; b >>>= 0; c >>>= 0; d >>>= 0;
    const t = (a + b) | 0;
    a = b ^ (b >>> 9);
    b = (c + (c << 3)) | 0;
    c = (c << 21) | (c >>> 11);
    d = (d + 1) | 0;
    const r = (t + d) | 0;
    c = (c + r) | 0;
    return r >>> 0;
  };
  for (let i = 0; i < 15; i++) next();
  return {
    nextInt(n: number): number {
      checkBound(n);
      if (n === 1) return 0;
      const limit = Math.floor(0x1_0000_0000 / n) * n;
      for (;;) {
        const x = next();
        if (x < limit) return x % n;
      }
    },
  };
}

/** Uniform float in [0,1) from an Rng (53 bits are not needed here; 2^32 resolution). */
export function nextFloat(rng: Rng): number {
  return rng.nextInt(0x1_0000_0000) / 0x1_0000_0000;
}

/** In-place Fisher-Yates (Durstenfeld) shuffle. Returns the same array. */
export function shuffleInPlace<T>(arr: T[], rng: Rng): T[] {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = rng.nextInt(i + 1);
    const t = arr[i];
    arr[i] = arr[j];
    arr[j] = t;
  }
  return arr;
}
