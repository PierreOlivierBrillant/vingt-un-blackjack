/**
 * CRAPS — game module. PHASE A STUB: the game is "unavailable" (gameJoin → FEATURE_UNAVAILABLE,
 * no simulated table, any open table closes and refunds).
 *
 * TO THE CRAPS IMPLEMENTER (phase B) — replace the export below, keep its NAME
 * (`crapsModule`, imported by src/games/registry.ts which you do not edit), and never touch
 * src/games/kernel/** (read its header in kernel/module.ts first: lifecycle, money rules, markets).
 *   export const crapsModule = defineGameModule<CrapsPublic, CrapsSeat, CrapsPrivate, CrapsAction>({ … });
 * What to provide (rules: PLAN_SPRINT2.md « Craps »; contract: shared/games/craps.ts):
 *  - a pure engine (pass/don't pass, come/don't come, odds 3-4-5×, lay, place, field, props;
 *    every payout exact to the cent; place 6/8 and lay 5/9/6/8 by multiples of $3 → BET_INCREMENT);
 *  - `game: 'craps'`, `available: true`, `money: 'board'`. EVERY ROLL IS A ROUND (own seed, own
 *    rounds/{n}): `openRound` = betting between rolls (shooter in `g`, turn on the shooter);
 *    `validateBets` refuses removing contract bets (BET_NOT_REMOVABLE) and a shooter without a
 *    line bet (MUST_BET_LINE); `act` {type:'roll'} by the shooter only (NOT_SHOOTER) — a roll
 *    action has no debit; `onDeadline` auto-rolls after 15 s;
 *  - the roll: `ctx.fairRng()` → `nextInt(6)+1` twice; `ctx.settle({ rows, carry, … })` where
 *    `carry` keeps the bets still working on the board (the kernel enforces: carry ≤ board,
 *    row.staked = board − carry, winnings always paid to the wallet);
 *  - markets: per-roll crapsSeven, series crapsPoint for the duration of a point (sim tables);
 *  - `seatClear` false while contract bets are on the board (a leaving player's bets keep working
 *    and resolve by deadlines alone, a leaving shooter's dice pass on), `onLeaving` returns the
 *    non-removable bets; `power` safetyNet; bots; `fairEstimate`; `onClose`.
 * Tests: test/unit/craps*.test.ts (pass line 1.41 % Monte-Carlo, golden, fairness vectors).
 */
import { unavailableModule } from '../kernel/unavailable';

export const crapsModule = unavailableModule('craps');
