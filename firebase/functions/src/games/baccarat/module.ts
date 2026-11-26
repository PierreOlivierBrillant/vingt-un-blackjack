/**
 * BACCARAT (Punto Banco, 8 decks) — game module. PHASE A STUB: the game is "unavailable"
 * (gameJoin → FEATURE_UNAVAILABLE, no simulated table, any open table closes and refunds).
 *
 * TO THE BACCARAT IMPLEMENTER (phase B) — replace the export below, keep its NAME
 * (`baccaratModule`, imported by src/games/registry.ts which you do not edit), and never touch
 * src/games/kernel/** (read its header in kernel/module.ts first: lifecycle, money rules, markets).
 *   export const baccaratModule = defineGameModule<BaccaratPublic, BaccaratSeat, BaccaratPrivate, BaccaratAction>({ … });
 * What to provide (rules: PLAN_SPRINT2.md « Baccarat Punto Banco »; contract: shared/games/baccarat.ts):
 *  - a pure engine (drawing table, Banker 0.95:1 exact to the cent, pairs, burn rule);
 *  - `game: 'baccarat'`, `available: true`, `money: 'board'`; `init` builds the 416-card shoe in
 *    `priv.g` (cut 16 from the end); spots player / banker / tie / playerPair / bankerPair;
 *  - `openRound`: betting phase, per-round markets baccaratBanker / baccaratTie / baccaratPair,
 *    series baccaratBankerShoe on simulated tables (one series per shoe);
 *  - `closeBetting`: deal with `fairDealOrder(remaining, ctx.seed!, 8)` (burn included in the same
 *    proof), close the markets no later than the transaction that shows cards, resolve them when
 *    the coup is decided; animate with 'live' steps (squeeze is client-side, no secret);
 *  - `onDeadline` → `ctx.settle({ rows, result, fairness: { remainingBefore, dealt, decks: 8 } })`;
 *    `power` freeCommission (no 5 % on a Banker win); bots; `fairEstimate`; `onClose`.
 * Tests: test/unit/baccarat*.test.ts (Banker 1.06 %, Player 1.24 % Monte-Carlo, golden, fairness vectors).
 */
import { unavailableModule } from '../kernel/unavailable';

export const baccaratModule = unavailableModule('baccarat');
