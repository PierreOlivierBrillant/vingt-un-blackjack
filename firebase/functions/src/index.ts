/** Cloud Functions entry point (emulator only). Every export is an HTTPS callable (see shared/types.ts). */
export { completeProfile, submitKyc, deposit, withdraw, buyPower, claimAdReward, equipCardStyle } from './callables/account';
export { joinMatchmaking, leaveTable, placeBet, act, pokeTable } from './callables/table';
export { tradeShares } from './callables/market';
export { friendRequest, respondFriend, removeFriend } from './callables/friends';
