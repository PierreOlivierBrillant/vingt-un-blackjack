import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../core/ids.dart';
import '../repositories.dart';
import '../server_errors.dart';

/// Low-level transport for one callable, abstracted so the retry/idempotency
/// logic is unit-testable without Firebase.
typedef CallableTransport = Future<Object?> Function(String name, Map<String, Object?> data);

/// Raised by a [CallableTransport] for a server-side `HttpsError` (or, with
/// code `internal-transport`, for a client-side transport failure).
class CallableError implements Exception {
  const CallableError(this.code, this.details, [this.message]);
  final String code;
  final Object? details;
  final String? message;
  @override
  String toString() => 'CallableError($code, $details)';
}

/// Calls backend callables with the conventions of `types.ts`:
/// * every request carries a `requestId` (the idempotency key);
/// * a transport failure (timeout / unreachable) is retried with the SAME
///   `requestId`, so the server executes the mutation at most once;
/// * server errors become [RepositoryException]s carrying the exact
///   [ServerReason].
class CallableClient {
  CallableClient(
    this._transport, {
    this.retries = 2,
    this.retryDelay = const Duration(milliseconds: 600),
    this.onTransport,
  });

  /// Transport over a real [FirebaseFunctions] instance. Every call times out
  /// after [timeout] (→ `deadline-exceeded`, retried, then `unavailable`).
  factory CallableClient.firebase(
    FirebaseFunctions functions, {
    Duration timeout = const Duration(seconds: 12),
    void Function(bool reachable)? onTransport,
  }) {
    return CallableClient(
      (name, data) async {
        try {
          final r = await functions
              .httpsCallable(name, options: HttpsCallableOptions(timeout: timeout))
              .call<Object?>(data);
          return r.data;
        } on FirebaseFunctionsException catch (e) {
          throw CallableError(e.code, e.details, e.message);
        } on TimeoutException {
          rethrow;
        } on Exception catch (e) {
          // Socket / platform errors: the server was not reached.
          throw CallableError('internal-transport', null, e.toString());
        }
      },
      onTransport: onTransport,
    );
  }

  final CallableTransport _transport;
  final int retries;
  final Duration retryDelay;

  /// Called after each call with `true` when the server answered (success or
  /// a server-side error) and `false` when it could not be reached.
  final void Function(bool reachable)? onTransport;

  static bool _isTransient(String code) =>
      code == 'unavailable' || code == 'deadline-exceeded' || code == 'internal-transport';

  /// Calls [name] with [data] + `requestId` ([idempotencyKey] or a fresh one).
  /// Returns the response map (empty map when the server returned null).
  Future<Map<String, Object?>> call(String name, Map<String, Object?> data, {String? idempotencyKey}) async {
    final requestId = idempotencyKey ?? newIdempotencyKey();
    final payload = {...data, 'requestId': requestId};
    var attempt = 0;
    while (true) {
      try {
        final res = await _transport(name, payload);
        onTransport?.call(true);
        if (res is Map) return res.map((k, v) => MapEntry(k.toString(), v as Object?));
        return const {};
      } on CallableError catch (e) {
        final transient = _isTransient(e.code);
        if (transient && attempt < retries) {
          attempt++;
          await Future<void>.delayed(retryDelay * attempt);
          continue;
        }
        onTransport?.call(!transient);
        debugPrint('[callable] $name failed: ${e.code} ${e.details}');
        if (e.code == 'internal-transport') throw RepositoryException(RepositoryFailure.unavailable, e.message);
        throw mapServerError(e.code, e.details, e.message);
      } on TimeoutException {
        if (attempt < retries) {
          attempt++;
          continue;
        }
        onTransport?.call(false);
        throw const RepositoryException(RepositoryFailure.unavailable, 'timeout');
      }
    }
  }
}
