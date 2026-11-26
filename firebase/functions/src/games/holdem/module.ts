/**
 * TEXAS HOLD'EM No-Limit (player vs player) — game module. PHASE A STUB: the game is
 * "unavailable" (gameJoin → FEATURE_UNAVAILABLE, no simulated table, any open table closes and
 * refunds every stack and queued buy-in).
 *
 * TO THE HOLD'EM IMPLEMENTER (phase B) — replace the export below, keep its NAME
 * (`holdemModule`, imported by src/games/registry.ts which you do not edit), and never touch
 * src/games/kernel/** (read its header in kernel/module.ts first: lifecycle, money rules, markets).
 *   export const holdemModule = defineGameModule<HoldemPublic, HoldemSeat, HoldemPrivate, HoldemAction>({ … });
 * What to provide (rules: PLAN_SPRINT2.md « Texas Hold'em »; contract: shared/games/holdem.ts):
 *  - a pure engine (betting rounds, min raise, incomplete all-in, side pots, 5-of-7 evaluator);
 *  - `game: 'holdem'`, `available: true`, `money: 'stack'`; `limits(tier).extra` = smallBlindCents,
 *    bigBlindCents, minBuyInCents (40 BB), maxBuyInCents (100 BB) — the kernel validates the
 *    gameJoin buy-in (BUY_IN_OUT_OF_RANGE), debits it into `seats[i].stackCents` and credits the
 *    stack back ('cashOut') when the seat is removed / the table closes;
 *  - `canStart` (≥ 2 players with chips), `openRound`: button, blinds (chips stack → pot, NOT a
 *    wallet debit), deal `fairDealOrder(buildShoe(1), ctx.seed!, 1)` with fixed positions, hole
 *    cards through `ctx.secret(uid, cards)`, `ctx.setTurn` + `ctx.setPhase('live', …)`;
 *    per-round markets holdemBoardAce / holdemBoardFlush, closed at the flop (or at the
 *    transaction that ends the hand), resolved on the board fixed at the deal;
 *  - `act` (fold/check/call/bet/raise/allIn; `rebuy` returns `{ debitCents, ledger: 'buyIn' }`
 *    between hands), `legalActions`, `onDeadline` (timeout = check if possible else fold, sitting
 *    out after 2 timeouts, `ctx.removeSeat` after 3 hands out), `onSitOut` / `onSitIn`;
 *  - `settle` rows: staked = chips put in the pot, return = chips won (no wallet credit: chips are
 *    already moved between stacks), `rank` override (±1 big blind), `countsForAffinity` (dealt in);
 *  - `seatClear` (not in a live hand), `onLeaving` (fold/auto-act, stack credited at hand end),
 *    `botBuyInCents`, bots (`bot(…,'turn')`), `fairEstimate`. No powers (`power` → POWER_NOT_APPLICABLE).
 * Tests: test/unit/holdem*.test.ts (evaluator, side pots, zero-sum exact, golden, fairness vectors).
 */
import { unavailableModule } from '../kernel/unavailable';

export const holdemModule = unavailableModule('holdem');
