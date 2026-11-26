/**
 * BACCARAT (Punto Banco, 8 decks) — game module of the kernel (src/games/kernel/module.ts).
 * Rules, spot ids, public state, events, markets: shared/games/baccarat.ts. Pure engine: ./engine.ts.
 *
 * ROUND: openRound (new shoe after the cut card: event 'shuffle'; per-coup markets; series market
 * of the shoe on simulated tables) → betting (setBets fast path, bots bet) → closeBetting: ONE
 * transaction deals the whole coup with `fairDealOrder(remainingBefore, seed, 8)` (burn included on
 * the first coup of a shoe), makes it public (g.coup + events for the animation), closes AND resolves
 * the per-coup markets (the outcome is certain and public in that very transaction), updates the shoe
 * counters / trend beads / series market, then phase 'live' step 'dealing' for the animation →
 * onDeadline: settlement (`settle` with the proof remainingBefore + dealt + decks 8).
 *
 * MONEY: only setBets debits (kernel). Settlement returns, for every seat with a board, the whole
 * board's return (stake included); nothing is carried over. Banker 0.95:1 is exact (whole dollars).
 */
import { z } from 'zod';
import { buildShoe, canonicalSort } from '../../engine/cards';
import { fairDealOrder } from '../../engine/fair';
import { nextFloat } from '../../engine/rng';
import { fail } from '../../shared/errors';
import {
  BACCARAT_CUT_CARDS, BACCARAT_DECKS, BACCARAT_SHOE_SIZE, BACCARAT_SHOE_THRESHOLD_PCT, BACCARAT_SPOTS, BACCARAT_TIMING,
  type BaccaratAction, type BaccaratBead, type BaccaratHand, type BaccaratPrivate, type BaccaratPublic, type BaccaratResult,
  type BaccaratSeat, type BaccaratShoePublic,
} from '../../shared/games/baccarat';
import type { BetMap, GameLimits, GameSeatSettlement } from '../../shared/games/common';
import { STAKE_TIER_LIMITS, type CardCode, type MarketKind, type StakeTier } from '../../shared/types';
import { boardTotal, defineGameModule, type GameCtx, type LockedBoard } from '../kernel/module';
import {
  BANKER_WIN_P, cutCardOut, dealCoup, dealingMs, handTotal, PAIR_P, settleBoard, shoeOutcome, shoeYesProbability, TIE_P,
} from './engine';

type Ctx = GameCtx<BaccaratPublic, BaccaratSeat, BaccaratPrivate>;

export const BACCARAT_ROUND_KINDS = ['baccaratBanker', 'baccaratTie', 'baccaratPair'] as const satisfies readonly MarketKind[];
type RoundKind = (typeof BACCARAT_ROUND_KINDS)[number];
const SERIES_KIND: MarketKind = 'baccaratBankerShoe';
const MAIN_SPOTS: readonly string[] = ['player', 'banker'];

/** Table limits: STAKE_TIER_LIMITS; side bets (tie, pairs) up to a fifth of the main maximum; a round up to twice the maximum. */
export function baccaratLimits(tier: StakeTier): GameLimits {
  const l = STAKE_TIER_LIMITS[tier];
  const side = Math.max(l.minBetCents, Math.floor(l.maxBetCents / 5 / 100) * 100);
  return { minBetCents: l.minBetCents, maxBetCents: l.maxBetCents, maxRoundCents: 2 * l.maxBetCents, extra: { sideMaxCents: side } };
}

export function freshShoe(n: number): BaccaratShoePublic {
  return { n, total: BACCARAT_SHOE_SIZE, remaining: BACCARAT_SHOE_SIZE, cutAt: BACCARAT_CUT_CARDS, coups: 0, banker: 0, player: 0, tie: 0, cutOut: false };
}

const freshPrivate = (): BaccaratPrivate => ({ remaining: canonicalSort(buildShoe(BACCARAT_DECKS)), needsBurn: true, proof: null });

const QUESTIONS: Record<RoundKind, { fr: string; en: string }> = {
  baccaratBanker: { fr: 'Le Banquier gagne ?', en: 'Banker wins?' },
  baccaratTie: { fr: 'Égalité ?', en: 'Tie?' },
  baccaratPair: { fr: 'Une paire (Joueur ou Banquier) ?', en: 'A pair (Player or Banker)?' },
};

function roundQuestion(kind: RoundKind, name: string, round: number) {
  const q = QUESTIONS[kind];
  return { fr: `${q.fr} (${name}, coup n°${round})`, en: `${q.en} (${name}, coup #${round})` };
}

function seriesQuestion(name: string, shoe: number) {
  const th = BACCARAT_SHOE_THRESHOLD_PCT;
  return {
    fr: `Le Banquier gagne au moins ${th} % des coups du sabot n°${shoe} ? (${name})`,
    en: `Banker wins at least ${th}% of the coups of shoe #${shoe}? (${name})`,
  };
}

/** The series market of the current shoe: closed at half the shoe, resolved once certain. */
function updateSeries(ctx: Ctx): void {
  const s = ctx.table.g;
  if (!s.series || s.series.shoe !== s.shoe.n) return;
  const sh = s.shoe;
  const outcome = sh.cutOut
    ? (100 * sh.banker >= BACCARAT_SHOE_THRESHOLD_PCT * sh.coups ? 'yes' : 'no')
    : shoeOutcome(sh.banker, sh.coups, sh.remaining);
  if (outcome) {
    ctx.markets.resolve('series', SERIES_KIND, outcome);
    s.series = null;
  } else if (!s.series.closed && sh.remaining <= BACCARAT_SHOE_SIZE / 2) {
    ctx.markets.close('series', SERIES_KIND);
    s.series.closed = true;
  }
}

/** A bot's board: mostly Banker or Player (sometimes following the last winner), a few side bets. */
function botBoard(ctx: Ctx, uid: string): BetMap | null {
  const rng = ctx.rng;
  if (rng.nextInt(100) < 7) return null;
  const prof = ctx.botProfile(uid);
  const min = ctx.limits.minBetCents;
  const units = prof?.betStyle === 'min' ? 1 : prof?.betStyle === 'aggressive' ? 3 + rng.nextInt(6) : 1 + rng.nextInt(3);
  const main = Math.min(ctx.limits.maxBetCents, min * units);
  const side = Math.min(ctx.limits.extra.sideMaxCents ?? min, min);
  const last = [...ctx.table.g.beads].reverse().find((b) => b.w !== 'T');
  const r = nextFloat(rng);
  const board: BetMap = {};
  if (last && r < 0.3) board[last.w === 'B' ? 'banker' : 'player'] = main; // "follow the road"
  else if (r < 0.62) board.banker = main;
  else if (r < 0.95) board.player = main;
  if (rng.nextInt(100) < 9) board.tie = side;
  if (rng.nextInt(100) < 6) board.playerPair = side;
  if (rng.nextInt(100) < 6) board.bankerPair = side;
  return boardTotal(board) > 0 ? board : { banker: min };
}

export const baccaratModule = defineGameModule<BaccaratPublic, BaccaratSeat, BaccaratPrivate, BaccaratAction>({
  game: 'baccarat',
  available: true,
  money: 'board',
  actionSchema: z.strictObject({ type: z.literal('none') }),
  limits: baccaratLimits,
  init: () => ({ g: { shoe: freshShoe(1), coup: null, beads: [], series: null }, priv: freshPrivate() }),
  seatInit: () => ({}),

  openRound(ctx: Ctx) {
    const s = ctx.table.g;
    s.coup = null;
    ctx.priv.g.proof = null;
    if (s.shoe.cutOut) {
      // the cut card came out during the previous coup: new shoe, burn on its first coup
      const n = s.shoe.n + 1;
      ctx.priv.g = freshPrivate();
      s.shoe = freshShoe(n);
      s.beads = [];
      ctx.event('shuffle', null, { shoe: n });
    }
    const name = ctx.table.name;
    for (const kind of BACCARAT_ROUND_KINDS) ctx.markets.create('round', kind, roundQuestion(kind, name, ctx.table.round));
    if (!s.series && s.shoe.coups === 0) {
      const id = ctx.markets.create('series', SERIES_KIND, seriesQuestion(name, s.shoe.n), { series: s.shoe.n });
      if (id) s.series = { shoe: s.shoe.n, closed: false };
    }
    ctx.setPhase('betting', ctx.now + BACCARAT_TIMING.bettingMs, 'betting');
  },

  validateBets(ctx, _seat, next) {
    const lim = ctx.limits;
    const sideMax = lim.extra.sideMaxCents ?? lim.maxBetCents;
    for (const [spot, v] of Object.entries(next)) {
      if (!(BACCARAT_SPOTS as readonly string[]).includes(spot)) throw fail.invalid('BAD_BET_SPOT');
      if (v === 0) continue;
      const max = MAIN_SPOTS.includes(spot) ? lim.maxBetCents : sideMax;
      if (v < lim.minBetCents || v > max) throw fail.invalid('BET_OUT_OF_RANGE');
    }
    return next;
  },

  power(_ctx, _seat, powerId, board) {
    if (powerId !== 'freeCommission' || !((board.banker ?? 0) > 0)) throw fail.invalid('POWER_NOT_APPLICABLE');
  },

  closeBetting(ctx: Ctx, _boards: LockedBoard[]) {
    const s = ctx.table.g;
    const remainingBefore = ctx.priv.g.remaining;
    const order = fairDealOrder(remainingBefore, ctx.seed!, BACCARAT_DECKS);
    const coup = dealCoup(order, { burn: ctx.priv.g.needsBurn });
    const rest = order.slice(coup.dealt.length, remainingBefore.length);
    ctx.priv.g = { remaining: canonicalSort(rest), needsBurn: false, proof: { remainingBefore, dealt: coup.dealt } };

    // public: the whole coup (the client animates it; its squeeze only shows these cards)
    s.coup = {
      player: coup.player, banker: coup.banker, playerTotal: coup.playerTotal, bankerTotal: coup.bankerTotal,
      winner: coup.winner, natural: coup.natural, playerPair: coup.playerPair, bankerPair: coup.bankerPair,
      burn: coup.burn ? { card: coup.burn.card, count: coup.burn.count } : null,
    };
    if (coup.burn) ctx.event('burn', null, { card: coup.burn.card, count: coup.burn.count });
    const seq: Array<[BaccaratHand, CardCode]> = [
      ['player', coup.player[0]], ['banker', coup.banker[0]], ['player', coup.player[1]], ['banker', coup.banker[1]],
    ];
    if (coup.player[2]) seq.push(['player', coup.player[2]]);
    if (coup.banker[2]) seq.push(['banker', coup.banker[2]]);
    const hands: Record<BaccaratHand, CardCode[]> = { player: [], banker: [] };
    for (const [hand, card] of seq) {
      hands[hand].push(card);
      ctx.event('card', null, { hand, i: hands[hand].length - 1, card, total: handTotal(hands[hand]) });
    }
    ctx.event('result', null, {
      winner: coup.winner, playerTotal: coup.playerTotal, bankerTotal: coup.bankerTotal, natural: coup.natural,
      playerPair: coup.playerPair, bankerPair: coup.bankerPair,
    });

    // shoe counters + trend beads
    const sh = s.shoe;
    sh.remaining = rest.length;
    sh.coups += 1;
    if (coup.winner === 'banker') sh.banker += 1;
    else if (coup.winner === 'player') sh.player += 1;
    else sh.tie += 1;
    const bead: BaccaratBead = {
      round: ctx.table.round, w: coup.winner === 'banker' ? 'B' : coup.winner === 'player' ? 'P' : 'T',
      p: coup.playerTotal, b: coup.bankerTotal, pp: coup.playerPair, bp: coup.bankerPair, nat: coup.natural,
    };
    s.beads = [...s.beads, bead];
    if (cutCardOut(sh.remaining)) {
      sh.cutOut = true;
      ctx.event('cut', null, { remaining: sh.remaining });
    }

    // markets: the outcome is public and certain in this transaction
    const yes: Record<RoundKind, boolean> = {
      baccaratBanker: coup.winner === 'banker',
      baccaratTie: coup.winner === 'tie',
      baccaratPair: coup.playerPair || coup.bankerPair,
    };
    for (const kind of BACCARAT_ROUND_KINDS) {
      ctx.markets.close('round', kind);
      ctx.markets.resolve('round', kind, yes[kind] ? 'yes' : 'no');
    }
    updateSeries(ctx);
    ctx.setPhase('live', ctx.now + dealingMs(coup), 'dealing');
  },

  act() {
    throw fail.pre('ILLEGAL_ACTION', 'baccarat has no game action (setBets only)');
  },
  legalActions: () => [],

  onDeadline(ctx: Ctx) {
    const s = ctx.table.g;
    const coup = s.coup;
    const proof = ctx.priv.g.proof;
    const rows: GameSeatSettlement[] = [];
    for (const seat of ctx.seats()) {
      const board = ctx.board(seat.uid);
      const total = boardTotal(board);
      if (total === 0) continue;
      // No coup on the table (never expected): every stake is returned.
      const st = coup
        ? settleBoard(board, coup, seat.powerUsed === 'freeCommission')
        : { stakedCents: total, returnCents: total, netCents: 0, counters: {}, jackpot: false };
      rows.push({
        uid: seat.uid, username: seat.username, avatar: seat.avatar, isBot: seat.isBot, seatIndex: seat.seatIndex,
        stakedCents: st.stakedCents, returnCents: st.returnCents, netCents: st.netCents, counters: st.counters,
        highlight: st.jackpot ? 'jackpot' : null,
      });
    }
    let result: BaccaratResult | null = null;
    if (coup) {
      const burnCards = proof && coup.burn ? proof.dealt.slice(1, 1 + coup.burn.count) : [];
      result = {
        player: coup.player, banker: coup.banker, playerTotal: coup.playerTotal, bankerTotal: coup.bankerTotal,
        winner: coup.winner, natural: coup.natural, playerPair: coup.playerPair, bankerPair: coup.bankerPair,
        burn: coup.burn ? { ...coup.burn, cards: burnCards } : null, shoe: s.shoe.n, coupInShoe: s.shoe.coups,
      };
    }
    ctx.settle({
      rows,
      result: (result ?? {}) as unknown as Record<string, unknown>,
      fairness: { remainingBefore: proof?.remainingBefore ?? null, dealt: proof?.dealt ?? null, decks: proof ? BACCARAT_DECKS : null },
      settledMs: BACCARAT_TIMING.settledMs,
    });
    ctx.priv.g.proof = null;
  },

  seatClear: (_ctx, _seat, board) => boardTotal(board) === 0,
  onLeaving: (_ctx, _seat, board, unlocked) => (unlocked ? {} : board),

  bot(ctx: Ctx, seat, need) {
    if (need !== 'bets') return null;
    const bets = botBoard(ctx, seat.uid);
    return bets ? { kind: 'bets', bets } : null;
  },

  fairEstimate(market, table) {
    switch (market.kind) {
      case 'baccaratBanker': return BANKER_WIN_P;
      case 'baccaratTie': return TIE_P;
      case 'baccaratPair': return PAIR_P;
      case 'baccaratBankerShoe': {
        const sh = (table?.g as BaccaratPublic | undefined)?.shoe;
        if (!sh || sh.n !== market.shoeNumber) return shoeYesProbability(0, 0, BACCARAT_SHOE_SIZE);
        return shoeYesProbability(sh.banker, sh.coups, sh.remaining);
      }
      default: return 0.5;
    }
  },

  onClose(ctx: Ctx) {
    const s = ctx.table.g;
    if (s.series && s.series.shoe === s.shoe.n) {
      const o = shoeOutcome(s.shoe.banker, s.shoe.coups, s.shoe.remaining);
      if (o) ctx.markets.resolve('series', SERIES_KIND, o);
    }
    s.series = null; // whatever is still running is voided by the kernel
  },
});
