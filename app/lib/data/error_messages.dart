/// Localized, user-facing text for every error a repository can throw:
/// each [ServerReason], each [RepositoryFailure] (incl. `unavailable` =
/// server unreachable / offline) and each [AuthFailure]. Strings: `err*`
/// keys of `lib/l10n/app_{fr,en}.arb`.
library;

import 'dart:async';
import 'dart:io' show SocketException;

import '../domain/models.dart';
import '../l10n/gen/app_localizations.dart';
import 'repositories.dart';

/// Message for any [error]: [RepositoryException] (exact server reason
/// first, then its failure family), [AuthException], timeouts / socket
/// errors (= unavailable); anything else → generic.
String localizeError(AppLocalizations l, Object error) => switch (error) {
      RepositoryException(reason: final r?) => localizeServerReason(l, r),
      RepositoryException(:final failure) => localizeFailure(l, failure),
      AuthException(:final failure) => localizeAuthFailure(l, failure),
      TimeoutException() || SocketException() => l.errFailureUnavailable,
      _ => l.errFailureUnknown,
    };

String localizeServerReason(AppLocalizations l, ServerReason v) => switch (v) {
      ServerReason.INVALID_ARGUMENT => l.errReasonInvalidArgument,
      ServerReason.UNAUTHENTICATED => l.errReasonUnauthenticated,
      ServerReason.RATE_LIMITED => l.errReasonRateLimited,
      ServerReason.REQUEST_ID_REUSED => l.errReasonRequestIdReused,
      ServerReason.PROFILE_REQUIRED => l.errReasonProfileRequired,
      ServerReason.PROFILE_EXISTS => l.errReasonProfileExists,
      ServerReason.USERNAME_TAKEN => l.errReasonUsernameTaken,
      ServerReason.KYC_REQUIRED => l.errReasonKycRequired,
      ServerReason.KYC_ALREADY_VERIFIED => l.errReasonKycAlreadyVerified,
      ServerReason.KYC_REJECTED => l.errReasonKycRejected,
      ServerReason.INSUFFICIENT_FUNDS => l.errReasonInsufficientFunds,
      ServerReason.DEPOSIT_LIMIT => l.errReasonDepositLimit,
      ServerReason.TABLE_NOT_FOUND => l.errReasonTableNotFound,
      ServerReason.TABLE_CLOSED => l.errReasonTableClosed,
      ServerReason.TABLE_FULL => l.errReasonTableFull,
      ServerReason.BAD_CODE => l.errReasonBadCode,
      ServerReason.ALREADY_SEATED => l.errReasonAlreadySeated,
      ServerReason.NOT_SEATED => l.errReasonNotSeated,
      ServerReason.BAD_PHASE => l.errReasonBadPhase,
      ServerReason.STALE_HAND => l.errReasonStaleHand,
      ServerReason.ALREADY_BET => l.errReasonAlreadyBet,
      ServerReason.BET_OUT_OF_RANGE => l.errReasonBetOutOfRange,
      ServerReason.NOT_YOUR_TURN => l.errReasonNotYourTurn,
      ServerReason.ILLEGAL_ACTION => l.errReasonIllegalAction,
      ServerReason.POWER_NOT_OWNED => l.errReasonPowerNotOwned,
      ServerReason.POWER_ALREADY_USED => l.errReasonPowerAlreadyUsed,
      ServerReason.POWER_NOT_APPLICABLE => l.errReasonPowerNotApplicable,
      ServerReason.INVENTORY_FULL => l.errReasonInventoryFull,
      ServerReason.MARKET_NOT_FOUND => l.errReasonMarketNotFound,
      ServerReason.MARKET_CLOSED => l.errReasonMarketClosed,
      ServerReason.OWN_TABLE_MARKET => l.errReasonOwnTableMarket,
      ServerReason.INSUFFICIENT_SHARES => l.errReasonInsufficientShares,
      ServerReason.SLIPPAGE => l.errReasonSlippage,
      ServerReason.MARKET_LIMIT => l.errReasonMarketLimit,
      ServerReason.USER_NOT_FOUND => l.errReasonUserNotFound,
      ServerReason.SELF_FRIEND => l.errReasonSelfFriend,
      ServerReason.ALREADY_FRIENDS => l.errReasonAlreadyFriends,
      ServerReason.REQUEST_EXISTS => l.errReasonRequestExists,
      ServerReason.REQUEST_NOT_FOUND => l.errReasonRequestNotFound,
      ServerReason.NOT_FRIENDS => l.errReasonNotFriends,
      ServerReason.AD_COOLDOWN => l.errReasonAdCooldown,
      ServerReason.AD_DAILY_LIMIT => l.errReasonAdDailyLimit,
      ServerReason.INTERNAL => l.errReasonInternal,
    };

String localizeFailure(AppLocalizations l, RepositoryFailure v) => switch (v) {
      RepositoryFailure.unavailable => l.errFailureUnavailable,
      RepositoryFailure.permissionDenied => l.errFailurePermissionDenied,
      RepositoryFailure.invalidArgument => l.errFailureInvalidArgument,
      RepositoryFailure.insufficientFunds => l.errFailureInsufficientFunds,
      RepositoryFailure.kycRequired => l.errFailureKycRequired,
      RepositoryFailure.limitExceeded => l.errFailureLimitExceeded,
      RepositoryFailure.rateLimited => l.errFailureRateLimited,
      RepositoryFailure.notFound => l.errFailureNotFound,
      RepositoryFailure.unknown => l.errFailureUnknown,
    };

String localizeAuthFailure(AppLocalizations l, AuthFailure v) => switch (v) {
      AuthFailure.invalidCredentials => l.errAuthInvalidCredentials,
      AuthFailure.invalidEmail => l.errAuthInvalidEmail,
      AuthFailure.emailInUse => l.errAuthEmailInUse,
      AuthFailure.weakPassword => l.errAuthWeakPassword,
      AuthFailure.usernameTaken => l.errAuthUsernameTaken,
      AuthFailure.invalidUsername => l.errAuthInvalidUsername,
      AuthFailure.profileExists => l.errAuthProfileExists,
      AuthFailure.tooManyRequests => l.errAuthTooManyRequests,
      AuthFailure.network => l.errAuthNetwork,
      AuthFailure.unknown => l.errAuthUnknown,
    };
