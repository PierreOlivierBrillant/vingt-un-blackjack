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
      ServerReason.TABLE_FULL =>
        RepositoryFailure.limitExceeded,
      ServerReason.RATE_LIMITED => RepositoryFailure.rateLimited,
      ServerReason.TABLE_NOT_FOUND ||
      ServerReason.BAD_CODE ||
      ServerReason.MARKET_NOT_FOUND ||
      ServerReason.USER_NOT_FOUND ||
      ServerReason.REQUEST_NOT_FOUND ||
      ServerReason.NOT_FRIENDS =>
        RepositoryFailure.notFound,
      ServerReason.UNAUTHENTICATED || ServerReason.OWN_TABLE_MARKET => RepositoryFailure.permissionDenied,
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
