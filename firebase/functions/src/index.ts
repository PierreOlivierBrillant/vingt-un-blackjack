/**
 * Cloud Functions entry point (emulator only). Every export is an HTTPS callable (see shared/types.ts).
 * Complete since Sprint 2 phase A: phase B fills the game modules and the romance/dating handlers
 * without touching this file.
 */
export { completeProfile, submitKyc, deposit, withdraw, buyPower, claimAdReward, equipCardStyle } from './callables/account';
export { joinMatchmaking, leaveTable, placeBet, act, pokeTable } from './callables/table';
export { tradeShares } from './callables/market';
export { friendRequest, respondFriend, removeFriend } from './callables/friends';
export { gameJoin, gameLeave, gameAction, gamePoke } from './callables/games';
export { romance } from './callables/romance';
export { dating } from './callables/dating';
