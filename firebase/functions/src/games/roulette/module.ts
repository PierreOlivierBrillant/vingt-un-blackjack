/**
 * ROULETTE (European, single zero) — game module driven by the generic kernel
 * (src/games/kernel/, read its header in kernel/module.ts). Rules: PLAN_SPRINT2.md « Roulette
 * européenne »; contract (spot ids, `g`, events, markets): shared/games/roulette.ts; pure engine:
 * ./engine.ts; bots: ./bots.ts.
 *
 * ROUND
 *  - openRound: `g.number` cleared, per-round markets rouletteRed / rouletteZero / rouletteDozen3,
 *    the series market rouletteZeroSeries on simulated tables (`create` returns null elsewhere),
 *    then 20 s of betting (bots place their boards through the kernel).
 *  - closeBetting ("Rien ne va plus"): the number is drawn IN THIS transaction with
 *    `ctx.fairRng().nextInt(37)` (the only randomness of the outcome), published in `g` and the
 *    'spin' event; the round markets are closed and resolved here (the number is public now), the
 *    series market advances; then 'live' / 'spinning' for ROULETTE_TIMING.spinMs.
 *  - onDeadline (the ball has landed): every board is settled (return = winnings + winning stakes,
 *    zero shield on the even chances), events 'result' + 'payout', `highlight: 'jackpot'` on a
 *    winning plein, profile counters, then 'settled'.
 * MONEY: nothing here ever debits (only the kernel's setBets does). A leaving player's board is
 * refunded while betting and settled normally once locked (`seatClear` waits for the spin).
 */
import { z } from 'zod';
import { fail } from '../../shared/errors';
import type { GameSeatSettlement } from '../../shared/games/common';
import {
  ROULETTE_CHIP_COLORS, ROULETTE_HISTORY_LENGTH, ROULETTE_TIMING, ROULETTE_ZERO_SERIES_CLOSE_AFTER, ROULETTE_ZERO_SERIES_LENGTH,
  type RoulettePayoutEvent, type RoulettePrivate, type RoulettePublic, type RouletteSeat, type RouletteSpinEvent,
} from '../../shared/games/roulette';
import type { MarketDoc } from '../../shared/types';
import { boardTotal, defineGameModule, type GameCtx } from '../kernel/module';
import { botBoard } from './bots';
import { colorOf, hasEvenMoney, rouletteLimits, settleBoard, validateBoard } from './engine';

/** Roulette has no game action of its own: only the kernel's setBets. */
export type RouletteAction = never;

type Ctx = GameCtx<RoulettePublic, RouletteSeat, RoulettePrivate>;

export interface RouletteOptions {
  bettingMs?: number;
  spinMs?: number;
  settledMs?: number;
}

const DOZEN3 = (n: number) => n >= 25;

/** Spins of the running series already drawn (the current round counts once its number is out). */
export function seriesSpinsDone(g: RoulettePublic, round: number): number {
  if (!g.series) return 0;
  return round - g.series.startRound + (g.number !== null ? 1 : 0);
}

/** Fair YES probability of a roulette market (sim bots trade toward it). */
export function rouletteFairEstimate(kind: MarketDoc['kind'], table: { round: number; g: RoulettePublic } | null): number {
  switch (kind) {
    case 'rouletteRed':
      return 18 / 37;
    case 'rouletteZero':
      return 1 / 37;
    case 'rouletteDozen3':
      return 12 / 37;
    case 'rouletteZeroSeries': {
      const done = table ? seriesSpinsDone(table.g, table.round) : 0;
      return 1 - (36 / 37) ** Math.max(1, ROULETTE_ZERO_SERIES_LENGTH - done);
    }
    default:
      return 0.5;
  }
}

export function makeRouletteModule(opts: RouletteOptions = {}) {
  const bettingMs = opts.bettingMs ?? ROULETTE_TIMING.bettingMs;
  const spinMs = opts.spinMs ?? ROULETTE_TIMING.spinMs;
  const settledMs = opts.settledMs ?? ROULETTE_TIMING.settledMs;

  return defineGameModule<RoulettePublic, RouletteSeat, RoulettePrivate, RouletteAction>({
    game: 'roulette',
    available: true,
    money: 'board',
    actionSchema: z.never(),
    limits: rouletteLimits,
    init: () => ({ g: { number: null, last: [], series: null, seriesCount: 0 }, priv: {} }),
    seatInit(ctx, seat) {
      const used = new Set(ctx.seats().filter((s) => s.uid !== seat.uid).map((s) => (s.g as Partial<RouletteSeat>).color));
      let color = seat.seatIndex % ROULETTE_CHIP_COLORS;
      for (let c = 0; c < ROULETTE_CHIP_COLORS; c++) {
        if (!used.has(c)) {
          color = c;
          break;
        }
      }
      return { color };
    },

    openRound(ctx: Ctx) {
      const g = ctx.table.g;
      const name = ctx.table.name;
      const r = ctx.table.round;
      g.number = null;
      ctx.markets.create('round', 'rouletteRed', { fr: `Rouge ? (${name}, tour n°${r})`, en: `Red? (${name}, spin #${r})` });
      ctx.markets.create('round', 'rouletteZero', { fr: `Zéro ? (${name}, tour n°${r})`, en: `Zero? (${name}, spin #${r})` });
      ctx.markets.create('round', 'rouletteDozen3', { fr: `3e douzaine ? (${name}, tour n°${r})`, en: `3rd dozen? (${name}, spin #${r})` });
      if (!g.series) {
        const n = g.seriesCount + 1;
        const id = ctx.markets.create('series', 'rouletteZeroSeries', {
          fr: `Un zéro dans les ${ROULETTE_ZERO_SERIES_LENGTH} prochains tours ? (${name})`,
          en: `A zero within the next ${ROULETTE_ZERO_SERIES_LENGTH} spins? (${name})`,
        }, { series: n });
        if (id) {
          g.series = { n, startRound: r, closed: false };
          g.seriesCount = n;
        }
      }
      ctx.setPhase('betting', ctx.now + bettingMs, 'betting');
    },

    validateBets: (ctx, _seat, next) => validateBoard(next, ctx.limits),

    power(_ctx, _seat, powerId, board) {
      if (powerId !== 'zeroShield' || !hasEvenMoney(board)) throw fail.invalid('POWER_NOT_APPLICABLE');
    },

    closeBetting(ctx: Ctx) {
      const g = ctx.table.g;
      // "Rien ne va plus": the one fair draw of the round, in this very transaction.
      const n = ctx.fairRng().nextInt(37);
      g.number = n;
      g.last = [...g.last, n].slice(-ROULETTE_HISTORY_LENGTH);
      const spin: RouletteSpinEvent = { number: n, color: colorOf(n), spinMs };
      ctx.event('spin', null, { ...spin });
      // The number is public from now on: close AND resolve the round markets here.
      const outcomes: Array<['rouletteRed' | 'rouletteZero' | 'rouletteDozen3', boolean]> = [
        ['rouletteRed', colorOf(n) === 'red'], ['rouletteZero', n === 0], ['rouletteDozen3', DOZEN3(n)],
      ];
      for (const [kind, yes] of outcomes) {
        ctx.markets.close('round', kind);
        ctx.markets.resolve('round', kind, yes ? 'yes' : 'no');
      }
      if (g.series) {
        const done = seriesSpinsDone(g, ctx.table.round);
        if (n === 0) {
          ctx.markets.resolve('series', 'rouletteZeroSeries', 'yes');
          g.series = null;
        } else if (done >= ROULETTE_ZERO_SERIES_LENGTH) {
          ctx.markets.resolve('series', 'rouletteZeroSeries', 'no');
          g.series = null;
        } else if (!g.series.closed && done >= ROULETTE_ZERO_SERIES_CLOSE_AFTER) {
          ctx.markets.close('series', 'rouletteZeroSeries');
          g.series.closed = true;
        }
      }
      ctx.setPhase('live', ctx.now + spinMs, 'spinning');
    },

    act() {
      throw fail.pre('ILLEGAL_ACTION', 'roulette has no game action');
    },
    legalActions: () => [],

    onDeadline(ctx: Ctx) {
      const g = ctx.table.g;
      const n = g.number;
      const rows: GameSeatSettlement[] = [];
      const payouts: Array<[number, RoulettePayoutEvent]> = [];
      for (const seat of ctx.seats()) {
        const board = ctx.board(seat.uid);
        const staked = boardTotal(board);
        if (staked === 0) continue;
        // A number is always drawn before this deadline; without one (corrupt state) stakes are returned.
        const out = n === null
          ? { returnCents: staked, wins: [], straightHit: false, shieldCents: 0 }
          : settleBoard(board, n, seat.powerUsed === 'zeroShield');
        const counters: Record<string, number> = {};
        if (out.straightHit) counters.straightUps = 1;
        if (out.shieldCents > 0) counters.zeroShieldSaves = 1;
        rows.push({
          uid: seat.uid, username: seat.username, avatar: seat.avatar, isBot: seat.isBot, seatIndex: seat.seatIndex,
          stakedCents: staked, returnCents: out.returnCents, netCents: out.returnCents - staked, counters,
          highlight: out.straightHit ? 'jackpot' : null,
        });
        payouts.push([seat.seatIndex, {
          stakedCents: staked, returnCents: out.returnCents, netCents: out.returnCents - staked, wins: out.wins, shield: out.shieldCents > 0,
        }]);
      }
      if (n !== null) ctx.event('result', null, { number: n, color: colorOf(n) });
      for (const [seatIndex, p] of payouts) ctx.event('payout', seatIndex, { ...p });
      ctx.settle({
        rows,
        result: n === null ? { number: null, void: true } : { number: n, color: colorOf(n) },
        fairness: { remainingBefore: null, dealt: null, decks: null },
        settledMs,
      });
    },

    // Locked boards are only in play while the ball spins.
    seatClear: (ctx, _seat, board) => ctx.table.phase !== 'live' || boardTotal(board) === 0,
    onLeaving: (_ctx, _seat, board, unlocked) => (unlocked ? {} : board),

    bot(ctx: Ctx, seat, need) {
      if (need !== 'bets') return null;
      const bets = botBoard(ctx.rng, ctx.botProfile(seat.uid), ctx.limits);
      return bets ? { kind: 'bets', bets } : null;
    },

    fairEstimate: (market, table) => rouletteFairEstimate(market.kind, table ? { round: table.round, g: table.g } : null),

    onClose(ctx: Ctx) {
      // The series is resolved as soon as it is certain (closeBetting): what is left is voided by the kernel.
      ctx.table.g.series = null;
    },
  });
}

export const rouletteModule = makeRouletteModule();
