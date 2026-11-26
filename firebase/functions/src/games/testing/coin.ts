/**
 * TEST-ONLY module "coin" — a simplified roulette played on bet boards, used to exercise the
 * kernel (property tests, integration tests, load probe). NEVER in the production registry:
 * tests swap it in with `overrideGameModuleForTests(game, coinModule({ game }))`.
 *
 * One draw per round: n = fairRng().nextInt(37); 0 = edge, 1..18 heads, 19..36 tails.
 * Spots: heads 1:1, tails 1:1, edge 35:1 (house edge 1/37, like roulette). The game's power (e.g.
 * zeroShield when played as 'roulette') gives half of the heads/tails stakes back on an edge.
 * Markets: one per round ("heads?", closed and resolved when the coin is drawn, i.e. in the
 * transaction that makes the outcome public) and, on simulated tables, one series market
 * ("an edge within the next 10 rounds?", closed after 5 rounds, resolved when certain).
 */
import { z } from 'zod';
import { fail } from '../../shared/errors';
import type { BetMap, GameId, GameLimits, GameSeatSettlement } from '../../shared/games/common';
import { POWER_GAME, type MarketKind, type StakeTier } from '../../shared/types';
import { boardTotal, defineGameModule, type AnyGameModule, type GameCtx } from '../kernel/module';

export const COIN_SPOTS = ['heads', 'tails', 'edge'] as const;
export type CoinSpot = (typeof COIN_SPOTS)[number];
export const COIN_SERIES_LENGTH = 10;

export interface CoinPublic {
  /** Last draws (most recent last, max 20). */
  last: number[];
  /** Draw of the current round once betting closed, else null. */
  outcome: number | null;
  /** Series market in progress (sim tables). */
  series: { n: number; startRound: number; closed: boolean } | null;
  seriesCount: number;
}
export type CoinSeat = Record<string, never>;
export type CoinPrivate = Record<string, never>;
export type CoinAction = { type: 'cheer' };

export interface CoinOptions {
  game?: GameId;
  bettingMs?: number;
  flipMs?: number;
  settledMs?: number;
}

const ROUND_KIND: Record<GameId, MarketKind> = { roulette: 'rouletteRed', baccarat: 'baccaratBanker', craps: 'crapsSeven', holdem: 'holdemBoardAce' };
const SERIES_KIND: Partial<Record<GameId, MarketKind>> = { roulette: 'rouletteZeroSeries', baccarat: 'baccaratBankerShoe', craps: 'crapsPoint' };

const LIMITS: Record<StakeTier, GameLimits> = {
  low: { minBetCents: 100, maxBetCents: 10_000, maxRoundCents: 30_000, extra: {} },
  mid: { minBetCents: 500, maxBetCents: 50_000, maxRoundCents: 150_000, extra: {} },
  high: { minBetCents: 2_500, maxBetCents: 250_000, maxRoundCents: 750_000, extra: {} },
};

export const sideOf = (n: number): CoinSpot => (n === 0 ? 'edge' : n <= 18 ? 'heads' : 'tails');

/** Return (stake included) of a board for draw `n`. */
export function coinReturn(bets: BetMap, n: number, shield: boolean): number {
  const side = sideOf(n);
  let ret = 0;
  for (const [spot, v] of Object.entries(bets)) {
    if (spot === side) ret += spot === 'edge' ? v * 36 : v * 2;
    else if (side === 'edge' && shield && (spot === 'heads' || spot === 'tails')) ret += v / 2;
  }
  return ret;
}

export function coinModule(opts: CoinOptions = {}): AnyGameModule {
  const game: GameId = opts.game ?? 'roulette';
  const bettingMs = opts.bettingMs ?? 20_000;
  const flipMs = opts.flipMs ?? 3_000;
  const settledMs = opts.settledMs ?? 4_000;
  const roundKind = ROUND_KIND[game];
  const seriesKind = SERIES_KIND[game] ?? null;
  type Ctx = GameCtx<CoinPublic, CoinSeat, CoinPrivate>;

  const g = (ctx: { table: { g: CoinPublic } }) => ctx.table.g;

  return defineGameModule<CoinPublic, CoinSeat, CoinPrivate, CoinAction>({
    game,
    available: true,
    money: 'board',
    actionSchema: z.strictObject({ type: z.literal('cheer') }),
    limits: (tier) => structuredClone(LIMITS[tier]),
    init: () => ({ g: { last: [], outcome: null, series: null, seriesCount: 0 }, priv: {} }),
    seatInit: () => ({}),
    openRound(ctx: Ctx) {
      const s = g(ctx);
      s.outcome = null;
      ctx.markets.create('round', roundKind, { fr: `Pile ? (${ctx.table.name}, coup n°${ctx.table.round})`, en: `Heads? (${ctx.table.name}, round #${ctx.table.round})` });
      if (seriesKind && !s.series) {
        const n = s.seriesCount + 1;
        const id = ctx.markets.create('series', seriesKind, {
          fr: `Une tranche dans les ${COIN_SERIES_LENGTH} prochains coups ? (${ctx.table.name})`,
          en: `An edge within the next ${COIN_SERIES_LENGTH} rounds? (${ctx.table.name})`,
        }, { series: n });
        if (id) { s.series = { n, startRound: ctx.table.round, closed: false }; s.seriesCount = n; }
      }
      ctx.setPhase('betting', ctx.now + bettingMs, 'betting');
    },
    validateBets(ctx, _seat, next) {
      for (const [spot, v] of Object.entries(next)) {
        if (!(COIN_SPOTS as readonly string[]).includes(spot)) throw fail.invalid('BAD_BET_SPOT');
        if (v > ctx.limits.maxBetCents) throw fail.invalid('BET_OUT_OF_RANGE');
      }
      return next;
    },
    power(_ctx, _seat, powerId, board) {
      if (POWER_GAME[powerId] !== game || !(board.heads || board.tails)) throw fail.invalid('POWER_NOT_APPLICABLE');
    },
    closeBetting(ctx: Ctx) {
      const s = g(ctx);
      const n = ctx.fairRng().nextInt(37);
      s.outcome = n;
      s.last = [...s.last, n].slice(-20);
      ctx.event('flip', null, { n, side: sideOf(n) });
      // the outcome is public from now on: close and resolve in this very transaction
      ctx.markets.close('round', roundKind);
      ctx.markets.resolve('round', roundKind, sideOf(n) === 'heads' ? 'yes' : 'no');
      if (seriesKind && s.series) {
        const done = ctx.table.round - s.series.startRound + 1;
        if (n === 0) { ctx.markets.resolve('series', seriesKind, 'yes'); s.series = null; }
        else if (done >= COIN_SERIES_LENGTH) { ctx.markets.resolve('series', seriesKind, 'no'); s.series = null; }
        else if (!s.series.closed && done >= COIN_SERIES_LENGTH / 2) { ctx.markets.close('series', seriesKind); s.series.closed = true; }
      }
      ctx.setPhase('live', ctx.now + flipMs, 'flipping');
    },
    act(ctx: Ctx, seat) {
      ctx.event('cheer', seat.seatIndex);
      return {};
    },
    legalActions: () => [{ type: 'cheer' }],
    onDeadline(ctx: Ctx) {
      const s = g(ctx);
      const n = s.outcome ?? 0;
      const rows: GameSeatSettlement[] = [];
      for (const seat of ctx.seats()) {
        const b = ctx.board(seat.uid);
        const staked = boardTotal(b);
        if (staked === 0) continue;
        const ret = coinReturn(b, n, seat.powerUsed !== null);
        const edgeHit = n === 0 && (b.edge ?? 0) > 0;
        rows.push({
          uid: seat.uid, username: seat.username, avatar: seat.avatar, isBot: seat.isBot, seatIndex: seat.seatIndex,
          stakedCents: staked, returnCents: ret, netCents: ret - staked, counters: edgeHit ? { edges: 1 } : {},
          highlight: edgeHit ? 'jackpot' : null,
        });
      }
      ctx.settle({ rows, result: { n, side: sideOf(n) }, fairness: { remainingBefore: null, dealt: null, decks: null }, settledMs });
    },
    seatClear: (_ctx, _seat, board) => boardTotal(board) === 0,
    onLeaving: (_ctx, _seat, board, unlocked) => (unlocked ? {} : board),
    bot(ctx: Ctx, seat, need) {
      if (need !== 'bets') return null;
      if (ctx.rng.nextInt(100) < 7) return null;
      const min = ctx.limits.minBetCents;
      const r = ctx.rng.nextInt(10);
      const spot: CoinSpot = r === 0 ? 'edge' : r < 6 ? 'heads' : 'tails';
      const units = 1 + ((ctx.botProfile(seat.uid)?.seed ?? 0) + ctx.rng.nextInt(3)) % 3;
      return { kind: 'bets', bets: { [spot]: min * units } };
    },
    fairEstimate(market, table) {
      if (market.kind === roundKind) return 18 / 37;
      const s = table?.g;
      const left = s?.series ? COIN_SERIES_LENGTH - (table!.round - s.series.startRound) : COIN_SERIES_LENGTH;
      return 1 - (36 / 37) ** Math.max(1, left);
    },
    onClose(ctx: Ctx) {
      g(ctx).series = null; // the kernel voids the series market that is still running
    },
  });
}
