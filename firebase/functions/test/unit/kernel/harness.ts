/**
 * In-memory world for the kernel tests: one table (public + private state + bet boards), the
 * humans' wallets and inventories. `tx()` runs a function on a fresh GameTableMachine like one
 * Firestore transaction (all-or-nothing: a debit above the balance rolls everything back, as
 * WalletSession.debit does in GameTableTx), and `setBets()` mirrors the callable's fast path.
 */
import { fastRng, sha256Hex } from '../../../src/engine';
import { planSetBets } from '../../../src/games/kernel/bets';
import type { GameEffect } from '../../../src/games/kernel/effects';
import { GameTableMachine, newGameTableState, type GameDeps } from '../../../src/games/kernel/machine';
import type { AnyGameModule } from '../../../src/games/kernel/module';
import { AppError, fail } from '../../../src/shared/errors';
import type { BetMap, GameBetDoc, GamePrivateDoc, GameTableDoc } from '../../../src/shared/games/common';
import type { PowerId, StakeTier } from '../../../src/shared/types';
import { BOTS } from '../../../src/sim/profiles';
import type { PlayerInfo } from '../../../src/table/model';

export const human = (i: number): PlayerInfo => ({ uid: `h${i}`, username: `Human${i}`, avatar: 'avatar01', rankTier: 'bronze', isBot: false });
export const bot = (i: number): PlayerInfo => ({ uid: BOTS[i].uid, username: BOTS[i].username, avatar: BOTS[i].avatar, rankTier: BOTS[i].rankTier, isBot: true });

export function testDeps(seed = 1): GameDeps {
  let n = 0;
  return { rng: fastRng(seed), newSeed: () => sha256Hex(`seed-${seed}-${n++}`) };
}

export interface WorldOptions {
  tableId?: string;
  isPrivate?: boolean;
  simManaged?: boolean;
  stakeTier?: StakeTier;
  seed?: number;
}

export function reasonOf(fn: () => unknown): string {
  try {
    fn();
  } catch (e) {
    if (e instanceof AppError) return e.reason;
    if ((e as Error)?.name === 'ZodError') return 'INVALID_ARGUMENT';
    throw e;
  }
  return 'NO_ERROR';
}

export class World {
  now = 1_000_000;
  pub: GameTableDoc;
  priv: GamePrivateDoc;
  boards = new Map<string, GameBetDoc>();
  wallets = new Map<string, number>();
  inventory = new Map<string, number>();
  effects: GameEffect[] = [];
  /** Effects of the last transaction. */
  last: GameEffect[] = [];
  /** Sum of settled nets of each human (from 'settle' effects). */
  nets = new Map<string, number>();
  readonly deps: GameDeps;

  constructor(readonly module: AnyGameModule, opts: WorldOptions = {}) {
    this.deps = testDeps(opts.seed ?? 1);
    const s = newGameTableState(module, {
      tableId: opts.tableId ?? `${module.game === 'holdem' ? 'ho' : 'rl'}-t1`, name: 'Test', stakeTier: opts.stakeTier ?? 'low',
      isPrivate: opts.isPrivate ?? false, simManaged: opts.simManaged ?? false, rankTier: 'bronze',
    }, this.now);
    this.pub = s.pub;
    this.priv = s.priv;
  }

  fund(uid: string, cents: number): void {
    this.wallets.set(uid, cents);
  }

  /** One transaction on a fresh machine. Applies money effects atomically; rolls back on any error. */
  tx<T>(fn: (m: GameTableMachine) => T): T {
    const m = new GameTableMachine(structuredClone(this.pub), structuredClone(this.priv),
      new Map([...this.boards].map(([k, v]) => [k, structuredClone(v)])), this.module, this.deps, this.now);
    const out = fn(m);
    const w = new Map(this.wallets);
    for (const e of m.effects) {
      if (e.kind === 'debit') {
        const bal = w.get(e.uid);
        if (bal === undefined) throw fail.pre('PROFILE_REQUIRED');
        if (bal < e.cents) throw fail.pre('INSUFFICIENT_FUNDS');
        w.set(e.uid, bal - e.cents);
      } else if (e.kind === 'credit') {
        const bal = w.get(e.uid);
        if (bal !== undefined) w.set(e.uid, bal + e.cents); // absent wallet: logged and skipped by GameTableTx
      }
    }
    this.pub = m.pub;
    this.priv = m.priv;
    this.boards = m.boards;
    this.wallets = w;
    this.last = [...m.effects];
    this.effects.push(...m.effects);
    for (const e of m.effects) {
      if (e.kind !== 'settle') continue;
      for (const r of e.rows) if (!r.isBot) this.nets.set(r.uid, (this.nets.get(r.uid) ?? 0) + r.netCents);
    }
    return out;
  }

  /** gameAction setBets fast path (only the board and the wallet change). */
  setBets(uid: string, bets: BetMap, power?: PowerId, round = this.pub.round) {
    const plan = planSetBets({
      table: this.pub, module: this.module, uid, round, bets, power, board: this.boards.get(uid) ?? null,
      inventoryQty: power ? this.inventory.get(`${uid}:${power}`) ?? 0 : 0, now: this.now,
    });
    const bal = this.wallets.get(uid) ?? 0;
    if (plan.debitCents > bal) throw fail.pre('INSUFFICIENT_FUNDS');
    this.wallets.set(uid, bal - plan.debitCents + plan.refundCents);
    this.boards.set(uid, plan.doc);
    if (plan.powerConsumed) this.inventory.set(`${uid}:${plan.powerConsumed}`, (this.inventory.get(`${uid}:${plan.powerConsumed}`) ?? 0) - 1);
    return plan;
  }

  graceMs(): number {
    return new GameTableMachine(this.pub, this.priv, this.boards, this.module, this.deps, this.now).graceMs();
  }

  /** Moves the clock and applies due deadlines. */
  tick(ms: number): boolean {
    this.now += ms;
    return this.tx((m) => m.advance());
  }

  /** Jumps to the current deadline (+ the human grace) and applies it. */
  expire(): boolean {
    if (this.pub.deadlineMs === null) {
      this.last = [];
      return false;
    }
    this.now = Math.max(this.now, this.pub.deadlineMs + this.graceMs());
    return this.tx((m) => m.advance());
  }

  until(pred: (t: GameTableDoc) => boolean, maxSteps = 300): void {
    for (let i = 0; i < maxSteps && !pred(this.pub); i++) {
      if (this.pub.deadlineMs === null) break;
      this.expire();
    }
    if (!pred(this.pub)) throw new Error(`condition not reached (phase ${this.pub.phase}, round ${this.pub.round})`);
  }

  ofKind<K extends GameEffect['kind']>(k: K, list: GameEffect[] = this.effects): Extract<GameEffect, { kind: K }>[] {
    return list.filter((e): e is Extract<GameEffect, { kind: K }> => e.kind === k);
  }

  boardTotal(uid: string): number {
    return this.boards.get(uid)?.totalCents ?? 0;
  }

  seat(uid: string) {
    return this.pub.seats.find((s) => s?.uid === uid) ?? null;
  }
}
