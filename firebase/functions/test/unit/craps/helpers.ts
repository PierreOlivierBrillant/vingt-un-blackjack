/** Shared helpers of the craps unit tests: seeds that roll chosen dice, a craps World. */
import { seededRng, sha256Hex } from '../../../src/engine';
import { rollDice } from '../../../src/games/craps/engine';
import { crapsModule } from '../../../src/games/craps/module';
import type { CrapsPublic, CrapsSeat } from '../../../src/shared/games/craps';
import type { GameSeatDoc } from '../../../src/shared/games/common';
import { human, World, type WorldOptions } from '../kernel/harness';

const cache = new Map<string, string>();

/** A round seed whose provably-fair dice are exactly [d1, d2] (searched deterministically). */
export function seedFor(d1: number, d2: number): string {
  const key = `${d1}${d2}`;
  const hit = cache.get(key);
  if (hit) return hit;
  for (let i = 0; i < 100_000; i++) {
    const seed = sha256Hex(`craps-dice-${i}`);
    const [a, b] = rollDice(seededRng(seed));
    const k = `${a}${b}`;
    if (!cache.has(k)) cache.set(k, seed);
    if (a === d1 && b === d2) return seed;
  }
  throw new Error(`no seed for ${d1}+${d2}`);
}

/** A die pair for a total (the first combination in order, or the hard way when asked). */
export function diceFor(total: number, hard = false): [number, number] {
  if (hard) return [total / 2, total / 2];
  for (let a = 1; a <= 6; a++) {
    const b = total - a;
    if (b >= 1 && b <= 6 && a !== b) return [a, b];
  }
  return [total / 2, total / 2];
}

/** A craps World whose next rounds roll the given dice (then deterministic seeds). */
export class CrapsWorld extends World {
  private queue: string[] = [];
  constructor(opts: WorldOptions = {}) {
    super(crapsModule, { tableId: 'cr-t1', ...opts });
    const fallback = this.deps.newSeed;
    this.deps.newSeed = () => this.queue.shift() ?? fallback();
  }

  /** Dice of the next rounds (each entry = one round's seed). */
  rolls(...dice: Array<[number, number] | number>): this {
    for (const d of dice) {
      const [a, b] = typeof d === 'number' ? diceFor(d) : d;
      this.queue.push(seedFor(a, b));
    }
    return this;
  }

  get g(): CrapsPublic {
    return this.pub.g as unknown as CrapsPublic;
  }

  seatG(uid: string): CrapsSeat {
    return (this.seat(uid) as GameSeatDoc<CrapsSeat> | null)!.g;
  }

  board(uid: string): Record<string, number> {
    return this.boards.get(uid)?.bets ?? {};
  }

  /** Seats humans h1..hn with `cents` each. */
  seatHumans(n: number, cents = 100_000): this {
    for (let i = 1; i <= n; i++) {
      this.fund(`h${i}`, cents);
      this.tx((m) => m.join(human(i)));
    }
    return this;
  }

  /** The shooter (a human) throws. */
  roll(uid: string) {
    return this.tx((m) => m.action(uid, this.pub.round, { type: 'roll' }));
  }

  /** Runs deadlines until the current roll is settled (betting → live → settled). */
  playRoll(): void {
    const start = this.pub.round;
    this.until((t) => t.round === start && t.phase === 'settled', 10);
  }

  /** From settled, opens the next betting window. */
  nextWindow(): void {
    const start = this.pub.round;
    this.until((t) => t.round > start && t.phase === 'betting', 10);
  }
}
