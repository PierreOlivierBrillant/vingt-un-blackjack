/**
 * CRAPS — game module (rules, spot ids, state, events: shared/games/craps.ts; pure engine:
 * ./engine.ts; bots: ./bots.ts). 8 seats, rotating shooter, EVERY ROLL IS A ROUND:
 *  - openRound: betting between two rolls (step 'comeOut' | 'point'), `turn` on the shooter, the
 *    per-roll market crapsSeven; the dice pass on first after a seven-out / a declined come-out or
 *    when the shooter left;
 *  - validateBets: contract bets, odds, $3 increments, the shooter's line bet (engine.checkBoard);
 *  - act {type:'roll'}: the shooter's gesture (no debit) brings the close of the bets forward to
 *    `g.rollAt`; otherwise the dice roll automatically at the deadline (15 s for a human shooter);
 *  - closeBetting: arms the safety nets, then either "no roll" (shooter without a line bet on the
 *    come-out: the dice pass on) or the roll: `ctx.fairRng()` → `nextInt(6)+1` twice, public at
 *    once (markets closed and resolved in this transaction), phase 'live' for the dice flight;
 *  - onDeadline (end of the flight): every board settled by the engine, `carry` = what stays up,
 *    the puck moves, long market crapsPoint created when a point is set (sim tables only);
 *  - seatClear: no money left, or no contract bet outside the live phase (a leaving player's
 *    contract bets keep working and resolve by deadlines alone, a leaving shooter's dice pass on).
 */
import { z } from 'zod';
import { fail } from '../../shared/errors';
import type { BetMap, GameLimits, GameRankOutcome, GameSeatDoc, GameSeatSettlement, GameTableDoc } from '../../shared/games/common';
import {
  CRAPS_HISTORY, CRAPS_MAX_ROUND_MULTIPLE, CRAPS_TIMING,
  type CrapsAction, type CrapsPoint, type CrapsPrivate, type CrapsPublic, type CrapsRoundResult, type CrapsSeat,
} from '../../shared/games/craps';
import { DECISION_GRACE_MS, STAKE_TIER_LIMITS, type LocalizedText, type StakeTier } from '../../shared/types';
import { defineGameModule, type GameCtx, type ReadCtx } from '../kernel/module';
import { botBoard } from './bots';
import { checkBoard, contractBets, hasLineBet, pMakePoint, pointAfter, rollDice, settleBoard, verdictOf } from './engine';

type Ctx = GameCtx<CrapsPublic, CrapsSeat, CrapsPrivate>;
type View = ReadCtx<CrapsPublic, CrapsSeat>;
type Seat = GameSeatDoc<CrapsSeat>;

const NO_FAIRNESS = { remainingBefore: null, dealt: null, decks: null };
/** Average P(point made | a point is set) = Σ P(N)·P(make N) / P(point) = 67/165. */
export const CRAPS_POINT_AVERAGE = 67 / 165;

export function crapsLimits(tier: StakeTier): GameLimits {
  const l = STAKE_TIER_LIMITS[tier];
  return { minBetCents: l.minBetCents, maxBetCents: l.maxBetCents, maxRoundCents: l.maxBetCents * CRAPS_MAX_ROUND_MULTIPLE, extra: {} };
}

export function initialCrapsState(): CrapsPublic {
  return {
    point: null, shooter: null, shooterUid: null, shooterRolls: 0, shooterPoints: 0, passDice: null, rollAt: null, roll: null,
    dice: null, rolls: [], pointSeries: 0,
  };
}

const isShooter = (t: GameTableDoc<CrapsPublic, CrapsSeat>, seat: Seat) => t.g.shooter === seat.seatIndex && t.g.shooterUid === seat.uid;

/** First active seat after `after` in seat order (wrapping; itself when alone), skipping `skip`. */
function nextShooter(ctx: Ctx, after: number | null, skip: number | null = null): Seat | null {
  const active = ctx.seats().filter((s) => s.status === 'active' && s.seatIndex !== skip);
  if (active.length === 0) return null;
  if (after === null) return active[0];
  return active.find((s) => s.seatIndex > after) ?? active[0];
}

function setShooter(ctx: Ctx, seat: Seat | null, reason: 'start' | 'sevenOut' | 'declined' | 'left'): void {
  const g = ctx.table.g;
  g.shooter = seat?.seatIndex ?? null;
  g.shooterUid = seat?.uid ?? null;
  g.shooterRolls = 0;
  g.shooterPoints = 0;
  ctx.event('shooter', g.shooter, { uid: g.shooterUid, reason });
}

/** Length of the betting window: 15 s for a human shooter, shorter with a bot (or no) shooter. */
function windowMs(ctx: Ctx): number {
  const g = ctx.table.g;
  const shooter = g.shooter === null ? null : ctx.table.seats[g.shooter];
  if (shooter && !shooter.isBot) return CRAPS_TIMING.shooterMs;
  return ctx.seats().some((s) => !s.isBot && s.status === 'active') ? CRAPS_TIMING.botShooterMs : CRAPS_TIMING.botsOnlyMs;
}

function sevenQuestion(t: { name: string; round: number }): LocalizedText {
  return { fr: `Un sept au prochain lancer ? (${t.name}, lancer n°${t.round})`, en: `A seven on the next roll? (${t.name}, roll #${t.round})` };
}
function pointQuestion(t: { name: string }, point: CrapsPoint): LocalizedText {
  return { fr: `Le lanceur fait son point de ${point} ? (${t.name})`, en: `Does the shooter make the point of ${point}? (${t.name})` };
}

/** Rank outcome of a roll: the net against the stake of the bets the roll DECIDED (winning bets stay up). */
export function crapsRank(row: GameSeatSettlement): GameRankOutcome {
  const action = row.counters.actionCents ?? 0;
  if (action <= 0) return 'none';
  if (row.netCents >= 5 * action) return 'bigWin';
  if (row.netCents * 2 >= action) return 'win';
  if (row.netCents * 2 <= -action) return 'lose';
  return 'none';
}

function legal(ctx: Ctx, seat: Seat): CrapsAction[] {
  const g = ctx.table.g;
  if (ctx.table.phase !== 'betting' || !isShooter(ctx.table, seat) || seat.status !== 'active') return [];
  if (g.point === null && !hasLineBet(ctx.board(seat.uid))) return [];
  if (g.rollAt !== null && ctx.now < g.rollAt) return [];
  return [{ type: 'roll' }];
}

const allBoards = (ctx: Ctx): Record<string, BetMap> => Object.fromEntries(ctx.seats().map((s) => [s.uid, ctx.board(s.uid)]));

export const crapsModule = defineGameModule<CrapsPublic, CrapsSeat, CrapsPrivate, CrapsAction>({
  game: 'craps',
  available: true,
  money: 'board',
  actionSchema: z.strictObject({ type: z.literal('roll') }),

  limits: (tier) => crapsLimits(tier),
  init: () => ({ g: initialCrapsState(), priv: {} }),
  seatInit: () => ({ safetyNet: false }),

  openRound(ctx: Ctx) {
    const g = ctx.table.g;
    g.rollAt = null;
    g.roll = null;
    const cur = g.shooter === null ? null : ctx.table.seats[g.shooter];
    const valid = !!cur && cur.uid === g.shooterUid && cur.status === 'active';
    if (g.passDice) {
      setShooter(ctx, nextShooter(ctx, g.shooter), g.passDice);
      g.passDice = null;
    } else if (!valid) {
      const next = nextShooter(ctx, g.shooter);
      if (next || g.shooter !== null) setShooter(ctx, next, g.shooterUid === null ? 'start' : 'left');
    }
    ctx.markets.create('round', 'crapsSeven', sevenQuestion(ctx.table));
    ctx.setPhase('betting', ctx.now + windowMs(ctx), g.point === null ? 'comeOut' : 'point');
    ctx.setTurn(g.shooter);
  },

  validateBets(ctx: View, seat, next, current) {
    const l = ctx.limits;
    checkBoard(next, current, { point: ctx.table.g.point, minBetCents: l.minBetCents, maxBetCents: l.maxBetCents, shooter: isShooter(ctx.table, seat) });
    return next;
  },

  power(ctx: View, seat, powerId, board) {
    if (powerId !== 'safetyNet') throw fail.invalid('POWER_NOT_APPLICABLE');
    if (ctx.table.g.point !== null) throw fail.invalid('POWER_NOT_APPLICABLE', 'the safety net is set on the come-out');
    if (!((board.pass ?? 0) > 0)) throw fail.invalid('POWER_NOT_APPLICABLE', 'the safety net covers a Pass Line bet');
    if (seat.g.safetyNet) throw fail.invalid('POWER_NOT_APPLICABLE', 'your safety net is already armed');
  },

  closeBetting(ctx: Ctx, boards) {
    const g = ctx.table.g;
    g.rollAt = null;
    for (const b of boards) {
      const seat = ctx.table.seats[b.seatIndex];
      if (b.power === 'safetyNet' && seat && !seat.g.safetyNet && g.point === null && (b.bets.pass ?? 0) > 0) {
        seat.g.safetyNet = true;
        ctx.event('power', b.seatIndex, { power: 'safetyNet' });
      }
    }
    const shooter = g.shooter === null ? null : ctx.table.seats[g.shooter];
    if (g.point === null && shooter && !hasLineBet(ctx.board(shooter.uid))) {
      // The shooter declined (no line bet on the come-out): no roll, the dice pass on.
      ctx.event('noRoll', shooter.seatIndex, { reason: 'noLineBet' });
      g.passDice = 'declined';
      const result: CrapsRoundResult = { dice: null, total: null, pointBefore: null, pointAfter: null, verdict: null, shooter: shooter.seatIndex, noRoll: true };
      ctx.setTurn(null);
      ctx.settle({ rows: [], carry: allBoards(ctx), result: { ...result }, fairness: NO_FAIRNESS, settledMs: CRAPS_TIMING.noRollSettledMs });
      return;
    }
    const [d1, d2] = rollDice(ctx.fairRng());
    const total = d1 + d2;
    const roll = { d1, d2, total, pointBefore: g.point, verdict: verdictOf(g.point, total) };
    g.roll = roll;
    g.dice = [d1, d2];
    g.rolls = [...g.rolls, { d1, d2, round: ctx.table.round }].slice(-CRAPS_HISTORY);
    if (shooter) g.shooterRolls += 1;
    ctx.event('roll', g.shooter, { ...roll });
    // The dice are public from now on: the per-roll market and a decided point market resolve now.
    ctx.markets.close('round', 'crapsSeven');
    ctx.markets.resolve('round', 'crapsSeven', total === 7 ? 'yes' : 'no');
    if (roll.verdict === 'pointMade' || roll.verdict === 'sevenOut') {
      ctx.markets.close('series', 'crapsPoint');
      ctx.markets.resolve('series', 'crapsPoint', roll.verdict === 'pointMade' ? 'yes' : 'no');
    }
    ctx.setTurn(null);
    ctx.setPhase('live', ctx.now + CRAPS_TIMING.rollMs, 'rolling');
  },

  act(ctx: Ctx, seat) {
    const g = ctx.table.g;
    if (ctx.table.phase !== 'betting') throw fail.pre('BAD_PHASE', 'the dice are already out');
    if (!isShooter(ctx.table, seat)) throw fail.pre('NOT_SHOOTER');
    if (g.point === null && !hasLineBet(ctx.board(seat.uid))) throw fail.pre('MUST_BET_LINE');
    if (g.rollAt !== null && ctx.now < g.rollAt) return { data: { rollAt: g.rollAt } };
    // Bets close when the dice are out: not before the minimum window, never after the normal close.
    const natural = (ctx.table.deadlineMs ?? ctx.now) + DECISION_GRACE_MS;
    const rollAt = Math.min(natural, Math.max(ctx.now + CRAPS_TIMING.diceOutMs, ctx.table.phaseStartedAtMs + CRAPS_TIMING.minWindowMs));
    g.rollAt = rollAt;
    ctx.setPhase('betting', rollAt - DECISION_GRACE_MS, ctx.table.step);
    ctx.event('throw', seat.seatIndex, { at: rollAt });
    return { data: { rollAt } };
  },

  legalActions: (ctx: Ctx, seat) => legal(ctx, seat),

  onDeadline(ctx: Ctx) {
    const g = ctx.table.g;
    const roll = g.roll;
    if (!roll) {
      // Nothing was rolled (defensive): everything stays on the board.
      const result: CrapsRoundResult = { dice: null, total: null, pointBefore: g.point, pointAfter: g.point, verdict: null, shooter: g.shooter, noRoll: true };
      ctx.settle({ rows: [], carry: allBoards(ctx), result: { ...result }, fairness: NO_FAIRNESS, settledMs: CRAPS_TIMING.noRollSettledMs });
      return;
    }
    const rows: GameSeatSettlement[] = [];
    const carry: Record<string, BetMap> = {};
    for (const seat of ctx.seats()) {
      const board = ctx.board(seat.uid);
      if (Object.keys(board).length === 0) continue;
      const st = settleBoard(board, { pointBefore: roll.pointBefore, d1: roll.d1, d2: roll.d2, safetyNet: seat.g.safetyNet, leaving: seat.status === 'leaving' });
      carry[seat.uid] = st.carry;
      if (seat.g.safetyNet && st.safetyNetSpent) seat.g.safetyNet = false;
      if (st.outcomes.length === 0) continue;
      const wins: Record<string, number> = {};
      const lost: string[] = [];
      const pushed: string[] = [];
      const returned: string[] = [];
      const moved: Record<string, string> = {};
      for (const o of st.outcomes) {
        if (o.outcome === 'win') wins[o.spot] = o.wonCents;
        else if (o.outcome === 'lose') lost.push(o.spot);
        else if (o.outcome === 'push') pushed.push(o.spot);
        else if (o.outcome === 'refund') returned.push(o.spot);
        else if (o.outcome === 'travel' && o.to) moved[o.spot] = o.to;
      }
      ctx.event('pay', seat.seatIndex, { wins, lost, pushed, returned, moved, net: st.netCents, safetyNet: st.safetyNetRefund });
      if (st.stakedCents === 0 && st.returnCents === 0 && st.actionCents === 0) continue; // only travels
      const counters: Record<string, number> = {};
      if (st.actionCents > 0) counters.actionCents = st.actionCents;
      if (roll.verdict === 'pointMade' && isShooter(ctx.table, seat)) counters.pointsMade = 1;
      if (st.hardways > 0) counters.hardways = st.hardways;
      if (st.longShots > 0) counters.longShots = st.longShots;
      rows.push({
        uid: seat.uid, username: seat.username, avatar: seat.avatar, isBot: seat.isBot, seatIndex: seat.seatIndex,
        stakedCents: st.stakedCents, returnCents: st.returnCents, netCents: st.netCents, counters,
        highlight: st.longShots > 0 ? 'jackpot' : null,
      });
    }
    const after = pointAfter(roll.pointBefore, roll.total);
    if (roll.verdict === 'pointOn') {
      ctx.event('puck', null, { point: after });
      const id = ctx.markets.create('series', 'crapsPoint', pointQuestion(ctx.table, after!), { series: g.pointSeries + 1 });
      if (id) g.pointSeries += 1;
    } else if (roll.verdict === 'pointMade') {
      ctx.event('point', g.shooter, { point: roll.pointBefore });
      ctx.event('puck', null, { point: null });
      g.shooterPoints += 1;
    } else if (roll.verdict === 'sevenOut') {
      ctx.event('puck', null, { point: null });
      g.passDice = 'sevenOut';
    }
    g.point = after;
    const result: CrapsRoundResult = {
      dice: [roll.d1, roll.d2], total: roll.total, pointBefore: roll.pointBefore, pointAfter: after, verdict: roll.verdict,
      shooter: g.shooter, noRoll: false,
    };
    ctx.settle({ rows, carry, result: { ...result }, fairness: NO_FAIRNESS, settledMs: CRAPS_TIMING.settledMs });
  },

  seatClear(ctx: View, _seat, board) {
    if (Object.values(board).every((v) => !(v > 0))) return true;
    // While the dice are out nothing may be refunded; otherwise only contract bets keep a seat.
    return ctx.table.phase !== 'live' && Object.keys(contractBets(board, ctx.table.g.point)).length === 0;
  },

  onLeaving(ctx: Ctx, seat, board) {
    const g = ctx.table.g;
    if (ctx.table.phase === 'betting' && isShooter(ctx.table, seat)) {
      // A leaving shooter's dice pass on now (the point, if any, goes on with the next shooter).
      setShooter(ctx, nextShooter(ctx, seat.seatIndex, seat.seatIndex), 'left');
      ctx.setTurn(g.shooter);
    }
    return contractBets(board, g.point);
  },

  bot(ctx: Ctx, seat, need) {
    if (need === 'turn') {
      const actions = legal(ctx, seat);
      return actions.length > 0 ? { kind: 'action', action: actions[0] } : null;
    }
    const bets = botBoard({
      current: ctx.board(seat.uid), point: ctx.table.g.point, shooter: isShooter(ctx.table, seat), limits: ctx.limits,
      profile: ctx.botProfile(seat.uid), rng: ctx.rng,
    });
    return bets ? { kind: 'bets', bets } : null;
  },

  rank: (row) => crapsRank(row),
  countsForAffinity: (row, limits) => (row.counters.actionCents ?? 0) >= limits.minBetCents,

  fairEstimate(market, table) {
    if (market.kind === 'crapsSeven') return 1 / 6;
    if (market.kind === 'crapsPoint') {
      const p = (table?.g as Partial<CrapsPublic> | undefined)?.point ?? null;
      return p === null ? CRAPS_POINT_AVERAGE : pMakePoint(p);
    }
    return 0.5;
  },

  onClose(ctx: Ctx) {
    // Nothing is certain at closing: the kernel voids the point market still running.
    ctx.table.g.rollAt = null;
  },
});
