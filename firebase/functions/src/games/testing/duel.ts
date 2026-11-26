/**
 * TEST-ONLY module "duel" — a simplified player-vs-player game with stacks (hold'em-like), used
 * to exercise the kernel's 'stack' money style (property tests, integration tests, load probe).
 * NEVER in the production registry: tests swap it in with `overrideGameModuleForTests`.
 *
 * Hand: every active seat with at least the ante pays it into the pot (chips, not wallet), gets one
 * private card (`holes/{uid}`) from `fairDealOrder(buildShoe(1), seed, 1)`; then, from the seat
 * after the button, each player either `play`s (adds one more ante, or what is left) or `fold`s.
 * Showdown: the highest rank among players who played (ace high) wins the pot; ties split it in
 * whole dollars, odd dollars to the first winner after the button. Everybody folding but one wins
 * the pot. Timeout = fold; two timeouts in a row = sitting out; three hands sitting out = seat
 * removed (stack cashed out by the kernel). `rebuy` between hands is the only wallet debit.
 * Market: "the board card is an ace?", the board card being the card after the hole cards (secret
 * to everybody), revealed — and the market closed and resolved — at the showdown.
 */
import { z } from 'zod';
import { buildShoe, RANKS } from '../../engine/cards';
import { fairDealOrder } from '../../engine/fair';
import { fail } from '../../shared/errors';
import type { GameId, GameLimits, GameSeatDoc, GameSeatSettlement } from '../../shared/games/common';
import { GAME_TIMING, type GameRankOutcome } from '../../shared/games/common';
import type { CardCode, StakeTier } from '../../shared/types';
import { defineGameModule, type AnyGameModule, type GameCtx } from '../kernel/module';

export interface DuelPublic {
  pot: number;
  button: number;
  /** Seat indices dealt in this hand, in turn order. */
  order: number[];
  board: CardCode | null;
  winners: number[];
}
export interface DuelSeat {
  inHand: boolean;
  acted: boolean;
  folded: boolean;
  committed: number;
  timeouts: number;
  handsOut: number;
}
export interface DuelPrivate {
  deck: CardCode[];
  cards: Record<string, CardCode>;
  board: CardCode | null;
}
export type DuelAction = { type: 'fold' } | { type: 'play' } | { type: 'rebuy'; cents: number };

export interface DuelOptions {
  game?: GameId;
  decisionMs?: number;
  settledMs?: number;
}

const ANTE: Record<StakeTier, number> = { low: 100, mid: 500, high: 2_500 };
const rankOf = (c: CardCode) => (c[0] === 'A' ? 13 : RANKS.indexOf(c[0]));

export function duelModule(opts: DuelOptions = {}): AnyGameModule {
  const game: GameId = opts.game ?? 'holdem';
  const decisionMs = opts.decisionMs ?? GAME_TIMING.decisionMs;
  const settledMs = opts.settledMs ?? 4_000;
  type Ctx = GameCtx<DuelPublic, DuelSeat, DuelPrivate>;
  type Seat = GameSeatDoc<DuelSeat>;
  const ante = (l: GameLimits) => l.extra.anteCents;

  function setTurnOrShowdown(ctx: Ctx): void {
    const t = ctx.table;
    const alive = t.g.order.map((i) => t.seats[i]).filter((s): s is Seat => !!s && !s.g.folded);
    const next = t.g.order.map((i) => t.seats[i]).find((s): s is Seat => !!s && !s.g.folded && !s.g.acted);
    if (alive.length <= 1 || !next) { showdown(ctx); return; }
    ctx.setTurn(next.seatIndex);
    const bot = next.isBot && next.status === 'active';
    ctx.setPhase('live', ctx.now + (bot ? ctx.botDelayMs() : next.status === 'active' ? decisionMs : 0), 'decide');
  }

  function showdown(ctx: Ctx): void {
    const t = ctx.table;
    const dealt = t.g.order.map((i) => t.seats[i]).filter((s): s is Seat => !!s);
    const alive = dealt.filter((s) => !s.g.folded);
    let winners: Seat[];
    if (alive.length === 0) winners = dealt; // cannot happen (the last player standing wins at once); keeps the pot zero-sum
    else if (alive.length === 1) winners = alive;
    else {
      const best = Math.max(...alive.map((s) => rankOf(ctx.priv.g.cards[s.uid])));
      winners = alive.filter((s) => rankOf(ctx.priv.g.cards[s.uid]) === best);
    }
    const won = new Map<number, number>();
    const pot = t.g.pot;
    if (winners.length > 0) {
      const dollars = pot / 100;
      const share = Math.floor(dollars / winners.length);
      let odd = dollars - share * winners.length;
      for (const w of winners) {
        const extra = odd > 0 ? 1 : 0;
        odd -= extra;
        won.set(w.seatIndex, (share + extra) * 100);
      }
    }
    const board = ctx.priv.g.board;
    t.g.board = board;
    ctx.event('showdown', null, { board, cards: Object.fromEntries(alive.map((s) => [s.seatIndex, ctx.priv.g.cards[s.uid]])) });
    ctx.markets.close('round', 'holdemBoardAce');
    ctx.markets.resolve('round', 'holdemBoardAce', board && board[0] === 'A' ? 'yes' : 'no');
    const rows: GameSeatSettlement[] = [];
    for (const s of dealt) {
      const ret = won.get(s.seatIndex) ?? 0;
      s.stackCents = (s.stackCents ?? 0) + ret;
      rows.push({
        uid: s.uid, username: s.username, avatar: s.avatar, isBot: s.isBot, seatIndex: s.seatIndex, stakedCents: s.g.committed,
        returnCents: ret, netCents: ret - s.g.committed, counters: ret > 0 ? { pots: 1 } : {}, highlight: null,
      });
      s.g.inHand = false;
    }
    t.g.pot = 0;
    t.g.winners = winners.map((w) => w.seatIndex);
    ctx.settle({
      rows, result: { board, winners: t.g.winners, pot },
      fairness: { remainingBefore: buildShoe(1), dealt: ctx.priv.g.deck.slice(0, dealt.length + 1), decks: 1 }, settledMs,
    });
  }

  function fold(ctx: Ctx, s: Seat): void {
    s.g.folded = true;
    s.g.acted = true;
    ctx.event('fold', s.seatIndex);
  }

  /** A fold outside the folder's turn (leaving, sitting out): ends the hand if one player is left. */
  function foldOffTurn(ctx: Ctx, s: Seat): void {
    fold(ctx, s);
    const t = ctx.table;
    const alive = t.g.order.map((i) => t.seats[i]).filter((x): x is Seat => !!x && !x.g.folded);
    if (alive.length <= 1 || t.turn?.seatIndex === s.seatIndex) setTurnOrShowdown(ctx);
  }

  return defineGameModule<DuelPublic, DuelSeat, DuelPrivate, DuelAction>({
    game,
    available: true,
    money: 'stack',
    actionSchema: z.discriminatedUnion('type', [
      z.strictObject({ type: z.literal('fold') }),
      z.strictObject({ type: z.literal('play') }),
      z.strictObject({ type: z.literal('rebuy'), cents: z.number().int().min(100).max(10_000_000) }),
    ]),
    limits: (tier) => {
      const a = ANTE[tier];
      return {
        minBetCents: a, maxBetCents: a, maxRoundCents: a * 2,
        extra: { anteCents: a, smallBlindCents: a, bigBlindCents: 2 * a, minBuyInCents: 10 * a, maxBuyInCents: 50 * a },
      };
    },
    init: () => ({ g: { pot: 0, button: -1, order: [], board: null, winners: [] }, priv: { deck: [], cards: {}, board: null } }),
    seatInit: () => ({ inHand: false, acted: false, folded: false, committed: 0, timeouts: 0, handsOut: 0 }),
    canStart(ctx: Ctx) {
      return ctx.seats().filter((s) => s.status === 'active' && (s.stackCents ?? 0) >= ante(ctx.limits)).length >= 2;
    },
    openRound(ctx: Ctx) {
      const t = ctx.table;
      for (const s of ctx.seats()) {
        if (s.status === 'sittingOut') {
          s.g.handsOut += 1;
          if (s.g.handsOut >= 3) ctx.removeSeat(s.seatIndex);
        }
      }
      const n = t.seats.length;
      const eligible = (i: number) => {
        const s = t.seats[i];
        return !!s && s.status === 'active' && (s.stackCents ?? 0) >= ante(ctx.limits);
      };
      if ([...Array(n).keys()].filter(eligible).length < 2) { ctx.idle(); return; }
      let b = t.g.button;
      for (let k = 0; k < n; k++) { b = (b + 1 + n) % n; if (eligible(b)) break; }
      t.g.button = b;
      const order: number[] = [];
      for (let k = 1; k <= n; k++) { const i = (b + k) % n; if (eligible(i)) order.push(i); }
      const deck = fairDealOrder(buildShoe(1), ctx.seed!, 1);
      ctx.priv.g = { deck, cards: {}, board: deck[order.length] };
      t.g.order = order;
      t.g.board = null;
      t.g.winners = [];
      t.g.pot = 0;
      for (const s of ctx.seats()) s.g = { ...s.g, inHand: false, acted: false, folded: false, committed: 0 };
      order.forEach((i, k) => {
        const s = t.seats[i] as Seat;
        const a = ante(ctx.limits);
        s.stackCents = (s.stackCents ?? 0) - a;
        t.g.pot += a;
        s.g.inHand = true;
        s.g.committed = a;
        ctx.priv.g.cards[s.uid] = deck[k];
        ctx.secret(s.uid, [deck[k]]);
        ctx.event('ante', i, { cents: a });
      });
      ctx.markets.create('round', 'holdemBoardAce', { fr: `La carte du tableau est un As ? (${t.name}, main n°${t.round})`, en: `Is the board card an ace? (${t.name}, hand #${t.round})` });
      setTurnOrShowdown(ctx);
    },
    validateBets: () => { throw fail.pre('ILLEGAL_ACTION'); },
    power: () => { throw fail.invalid('POWER_NOT_APPLICABLE'); },
    closeBetting: (ctx: Ctx) => ctx.idle(),
    act(ctx: Ctx, seat, action) {
      const t = ctx.table;
      if (action.type === 'rebuy') {
        if (t.phase === 'live' && seat.g.inHand) throw fail.pre('REBUY_NOT_ALLOWED');
        if (action.cents % 100 !== 0 || (seat.stackCents ?? 0) + action.cents > ctx.limits.extra.maxBuyInCents) throw fail.invalid('BUY_IN_OUT_OF_RANGE');
        seat.stackCents = (seat.stackCents ?? 0) + action.cents;
        ctx.event('rebuy', seat.seatIndex, { cents: action.cents });
        return { debitCents: action.cents, ledger: 'buyIn', data: { stackCents: seat.stackCents } };
      }
      if (t.phase !== 'live') throw fail.pre('BAD_PHASE');
      if (t.turn?.seatIndex !== seat.seatIndex) throw fail.pre('NOT_YOUR_TURN');
      if (!seat.g.inHand || seat.g.acted) throw fail.pre('ILLEGAL_ACTION');
      seat.g.timeouts = 0;
      if (action.type === 'fold') fold(ctx, seat);
      else {
        const add = Math.min(ante(ctx.limits), seat.stackCents ?? 0);
        seat.stackCents = (seat.stackCents ?? 0) - add;
        seat.g.committed += add;
        t.g.pot += add;
        seat.g.acted = true;
        ctx.event('play', seat.seatIndex, { cents: add });
      }
      setTurnOrShowdown(ctx);
      return {};
    },
    legalActions(ctx: Ctx, seat) {
      const t = ctx.table;
      if (t.phase === 'live' && t.turn?.seatIndex === seat.seatIndex && seat.g.inHand && !seat.g.acted) return [{ type: 'fold' }, { type: 'play' }];
      const room = ctx.limits.extra.maxBuyInCents - (seat.stackCents ?? 0);
      if (!(t.phase === 'live' && seat.g.inHand) && room >= 100) return [{ type: 'rebuy', cents: 100 }];
      return [];
    },
    onDeadline(ctx: Ctx) {
      const t = ctx.table;
      const s = t.turn ? (t.seats[t.turn.seatIndex] as Seat | null) : null;
      if (!s) { setTurnOrShowdown(ctx); return; }
      ctx.event('timeout', s.seatIndex);
      s.g.timeouts += 1;
      fold(ctx, s);
      if (!s.isBot && s.status === 'active' && s.g.timeouts >= 2) {
        s.status = 'sittingOut';
        ctx.event('sitOut', s.seatIndex);
      }
      setTurnOrShowdown(ctx);
    },
    seatClear: (ctx, seat) => !(ctx.table.phase === 'live' && seat.g.inHand),
    onLeaving(ctx: Ctx, seat) {
      if (ctx.table.phase === 'live' && seat.g.inHand && !seat.g.folded) foldOffTurn(ctx, seat);
      return {};
    },
    onSitOut(ctx: Ctx, seat) {
      if (ctx.table.phase === 'live' && seat.g.inHand && !seat.g.folded) foldOffTurn(ctx, seat);
    },
    onSitIn(_ctx, seat) {
      seat.g.timeouts = 0;
      seat.g.handsOut = 0;
    },
    bot(ctx: Ctx, seat, need) {
      if (need !== 'turn') return null;
      const card = ctx.priv.g.cards[seat.uid];
      const strong = card ? rankOf(card) >= 7 : false;
      return { kind: 'action', action: strong || ctx.rng.nextInt(10) < 4 ? { type: 'play' } : { type: 'fold' } };
    },
    botBuyInCents: (limits) => limits.extra.maxBuyInCents,
    rank(row, limits): GameRankOutcome {
      const bb = limits.extra.bigBlindCents;
      if (row.netCents >= 10 * bb) return 'bigWin';
      if (row.netCents >= bb) return 'win';
      if (row.netCents <= -bb) return 'lose';
      return 'none';
    },
    countsForAffinity: (row) => row.stakedCents > 0,
    fairEstimate: () => 4 / 52,
  });
}
