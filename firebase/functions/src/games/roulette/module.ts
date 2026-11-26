/**
 * ROULETTE (European, single zero) — game module. PHASE A STUB: the game is "unavailable"
 * (gameJoin → FEATURE_UNAVAILABLE, no simulated table, any open table closes and refunds).
 *
 * TO THE ROULETTE IMPLEMENTER (phase B) — replace the export below, keep its NAME
 * (`rouletteModule`, imported by src/games/registry.ts which you do not edit), and never touch
 * src/games/kernel/** (read its header in kernel/module.ts first: lifecycle, money rules, markets).
 *   export const rouletteModule = defineGameModule<RoulettePublic, RouletteSeat, RoulettePrivate, RouletteAction>({ … });
 * What to provide (rules: PLAN_SPRINT2.md « Roulette européenne »; contract: shared/games/roulette.ts):
 *  - a pure engine next to this file (wheel order, spot grammar, payouts exact to the cent);
 *  - `game: 'roulette'`, `available: true`, `money: 'board'`; `limits(tier)` (per-spot max in
 *    maxBetCents, per-type caps in `extra`, maxRoundCents);
 *  - `openRound`: `ctx.setPhase('betting', ctx.now + 20_000)`, per-round markets rouletteRed /
 *    rouletteZero / rouletteDozen3 (`ctx.markets.create('round', …)`), the series market
 *    rouletteZeroSeries on simulated tables (`create` returns null elsewhere);
 *  - `validateBets` (BAD_BET_SPOT, BET_OUT_OF_RANGE…), `power` (zeroShield on even-money bets);
 *  - `closeBetting`: number = `ctx.fairRng().nextInt(37)` ("Rien ne va plus" draws in this very
 *    transaction), publish it in `g` + an event, close AND resolve the round markets here (the
 *    number is public now), then `ctx.setPhase('live', ctx.now + ~8_000, 'spinning')`;
 *  - `onDeadline`: `ctx.settle({ rows, result: { number }, fairness: { remainingBefore: null,
 *    dealt: null, decks: null } })` — rows: staked = whole board, return = winnings + winning
 *    stakes, `highlight: 'jackpot'` on a straight-up hit, `counters` for the profile;
 *  - bots (`bot(…,'bets')`), `fairEstimate` (rouletteRed 18/37, rouletteZero 1/37…), `onClose`
 *    (resolve the series market if already certain), `seatClear` (board empty or not live),
 *    `onLeaving` (everything is removable while unlocked).
 * Tests: test/unit/roulette*.test.ts (moteur, golden, Monte-Carlo 2.70 %), fairness vectors for Dart.
 */
import { unavailableModule } from '../kernel/unavailable';

export const rouletteModule = unavailableModule('roulette');
