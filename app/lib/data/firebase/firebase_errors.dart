/// Mapping of Firebase SDK errors (Firestore listeners, Auth) to the typed
/// repository exceptions. The code → failure functions are pure.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import '../../domain/models.dart';
import '../repositories.dart';

/// Firestore / gRPC error code → failure family.
RepositoryFailure failureForFirestoreCode(String code) => switch (code) {
      'permission-denied' || 'unauthenticated' => RepositoryFailure.permissionDenied,
      'unavailable' || 'deadline-exceeded' || 'aborted' => RepositoryFailure.unavailable,
      'not-found' => RepositoryFailure.notFound,
      'resource-exhausted' => RepositoryFailure.rateLimited,
      'invalid-argument' || 'failed-precondition' || 'out-of-range' => RepositoryFailure.invalidArgument,
      _ => RepositoryFailure.unknown,
    };

/// Any error from a listener / read → [RepositoryException] (never rethrows
/// the raw SDK type to the UI).
RepositoryException toRepositoryException(Object error) => switch (error) {
      RepositoryException() => error,
      FirebaseException(:final code, :final message) =>
        RepositoryException(failureForFirestoreCode(code), message ?? code),
      TimeoutException() => const RepositoryException(RepositoryFailure.unavailable, 'timeout'),
      _ => RepositoryException(RepositoryFailure.unknown, error.toString()),
    };

/// Re-emits every error of [source] as a [RepositoryException].
Stream<T> guardStream<T>(Stream<T> source) => source.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleError: (e, st, sink) => sink.addError(toRepositoryException(e), st),
      ),
    );

/// `FirebaseAuthException.code` → [AuthFailure].
AuthFailure authFailureForCode(String code) => switch (code) {
      'invalid-credential' ||
      'invalid-login-credentials' ||
      'wrong-password' ||
      'user-not-found' ||
      'user-disabled' ||
      'user-mismatch' =>
        AuthFailure.invalidCredentials,
      'invalid-email' || 'missing-email' => AuthFailure.invalidEmail,
      'email-already-in-use' || 'credential-already-in-use' => AuthFailure.emailInUse,
      'weak-password' || 'missing-password' => AuthFailure.weakPassword,
      'too-many-requests' => AuthFailure.tooManyRequests,
      'network-request-failed' || 'unavailable' || 'internal-error' => AuthFailure.network,
      _ => AuthFailure.unknown,
    };

/// `completeProfile` server errors that are really sign-up form errors.
/// Returns null when [e] is not one of them.
AuthException? authExceptionForProfileError(RepositoryException e) => switch (e.reason) {
      ServerReason.USERNAME_TAKEN => AuthException(AuthFailure.usernameTaken, e.message),
      ServerReason.INVALID_ARGUMENT => AuthException(AuthFailure.invalidUsername, e.message),
      ServerReason.PROFILE_EXISTS => AuthException(AuthFailure.profileExists, e.message),
      _ => null,
    };
