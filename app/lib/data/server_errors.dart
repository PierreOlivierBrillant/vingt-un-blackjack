// Names mirror the wire values exactly (SCREAMING_CASE on purpose).
// ignore_for_file: constant_identifier_names
/// Mirror of `ERROR_REASONS` in `firebase/functions/src/shared/types.ts`
/// (`HttpsError.details.reason`). [mapServerError] turns a callable error
/// code + reason into the typed [RepositoryException] the UI localizes.
library;

import 'repositories.dart';

enum ServerReason {
  INVALID_ARGUMENT,
  UNAUTHENTICATED,
  RATE_LIMITED,
  REQUEST_ID_REUSED,
  PROFILE_REQUIRED,
  PROFILE_EXISTS,
  USERNAME_TAKEN,
  KYC_REQUIRED,
  KYC_ALREADY_VERIFIED,
  KYC_REJECTED,
  INSUFFICIENT_FUNDS,
  DEPOSIT_LIMIT,
  TABLE_NOT_FOUND,
  TABLE_CLOSED,
  TABLE_FULL,
  BAD_CODE,
  ALREADY_SEATED,
  NOT_SEATED,
  BAD_PHASE,
  STALE_HAND,
  ALREADY_BET,
  BET_OUT_OF_RANGE,
  NOT_YOUR_TURN,
  ILLEGAL_ACTION,
  POWER_NOT_OWNED,
  POWER_ALREADY_USED,
  POWER_NOT_APPLICABLE,
  INVENTORY_FULL,
  MARKET_NOT_FOUND,
  MARKET_CLOSED,
  OWN_TABLE_MARKET,
  INSUFFICIENT_SHARES,
  SLIPPAGE,
  MARKET_LIMIT,
  USER_NOT_FOUND,
  SELF_FRIEND,
  ALREADY_FRIENDS,
  REQUEST_EXISTS,
  REQUEST_NOT_FOUND,
  NOT_FRIENDS,
  AD_COOLDOWN,
  AD_DAILY_LIMIT,
  INTERNAL,
  // Sprint 2 — kernel-driven games
  BAD_BET_SPOT,
  BET_INCREMENT,
  BET_NOT_REMOVABLE,
  WRONG_GAME,
  // roulette (none yet)
  // baccarat (none yet)
  // hold'em
  BUY_IN_OUT_OF_RANGE,
  REBUY_NOT_ALLOWED,
  SITTING_OUT,
  BUY_IN_REQUIRED,
  // craps
  NOT_SHOOTER,
  MUST_BET_LINE,
  // Rendez-vous
  SCENE_NOT_AVAILABLE,
  SCENE_INVALID_PATH,
  TALK_DONE_TODAY,
  GIFT_DAILY_LIMIT,
  COSMETIC_LOCKED,
  DATING_DISABLED,
  DATING_OPT_IN_REQUIRED,
  LIKE_DAILY_LIMIT,
  MATCH_NOT_FOUND,
  BLOCKED,
  LINE_NOT_ALLOWED,
  NO_PRIVATE_TABLE,
  // Sprint 2 (A1) — game or feature not implemented yet / withdrawn
  FEATURE_UNAVAILABLE,
}

ServerReason? serverReasonFromWire(Object? v) {
  if (v is! String) return null;
  for (final r in ServerReason.values) {
    if (r.name == v) return r;
  }
  return null;
}

/// Coarse family of a reason (kept for code that only needs the category).
RepositoryFailure failureForReason(ServerReason r) => switch (r) {
      ServerReason.INSUFFICIENT_FUNDS || ServerReason.INSUFFICIENT_SHARES => RepositoryFailure.insufficientFunds,
      ServerReason.KYC_REQUIRED || ServerReason.KYC_REJECTED => RepositoryFailure.kycRequired,
      ServerReason.DEPOSIT_LIMIT ||
      ServerReason.AD_DAILY_LIMIT ||
      ServerReason.AD_COOLDOWN ||
      ServerReason.INVENTORY_FULL ||
      ServerReason.MARKET_LIMIT ||
      ServerReason.TABLE_FULL ||
      ServerReason.GIFT_DAILY_LIMIT ||
      ServerReason.LIKE_DAILY_LIMIT ||
      ServerReason.TALK_DONE_TODAY =>
        RepositoryFailure.limitExceeded,
      ServerReason.RATE_LIMITED => RepositoryFailure.rateLimited,
      ServerReason.TABLE_NOT_FOUND ||
      ServerReason.BAD_CODE ||
      ServerReason.MARKET_NOT_FOUND ||
      ServerReason.USER_NOT_FOUND ||
      ServerReason.REQUEST_NOT_FOUND ||
      ServerReason.NOT_FRIENDS ||
      ServerReason.MATCH_NOT_FOUND =>
        RepositoryFailure.notFound,
      ServerReason.UNAUTHENTICATED ||
      ServerReason.OWN_TABLE_MARKET ||
      ServerReason.BLOCKED ||
      ServerReason.DATING_DISABLED =>
        RepositoryFailure.permissionDenied,
      ServerReason.INTERNAL => RepositoryFailure.unknown,
      _ => RepositoryFailure.invalidArgument,
    };

/// Maps a Firebase Functions error (`code` like `failed-precondition`,
/// `details` like `{reason: 'INSUFFICIENT_FUNDS'}`) to a typed exception.
/// Transport failures (`unavailable`, `deadline-exceeded`) become
/// [RepositoryFailure.unavailable] with no reason.
RepositoryException mapServerError(String code, Object? details, [String? message]) {
  final reasonRaw = details is Map ? details['reason'] : null;
  final reason = serverReasonFromWire(reasonRaw);
  if (reason != null) return RepositoryException(failureForReason(reason), message, reason);
  final failure = switch (code) {
    'unavailable' || 'deadline-exceeded' => RepositoryFailure.unavailable,
    'permission-denied' || 'unauthenticated' => RepositoryFailure.permissionDenied,
    'invalid-argument' || 'out-of-range' => RepositoryFailure.invalidArgument,
    'not-found' => RepositoryFailure.notFound,
    'resource-exhausted' => RepositoryFailure.rateLimited,
    'failed-precondition' => RepositoryFailure.invalidArgument,
    _ => RepositoryFailure.unknown,
  };
  return RepositoryException(failure, message);
}
