import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/data/error_messages.dart';
import 'package:vingtun/data/firebase/callable_client.dart';
import 'package:vingtun/data/repositories.dart';
import 'package:vingtun/data/server_errors.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/l10n/gen/app_localizations.dart';

import 'contract_parity_test.dart' show loadContract;


void main() {
  group('mapServerError', () {
    test('ServerReason mirrors ERROR_REASONS exactly', () {
      expect(ServerReason.values.map((r) => r.name).toList(), [for (final x in loadContract()['errorReasons']! as List) x as String]);
    });

    test('details.reason wins and keeps the exact reason', () {
      final e = mapServerError('failed-precondition', {'reason': 'INSUFFICIENT_FUNDS'}, 'nope');
      expect(e.reason, ServerReason.INSUFFICIENT_FUNDS);
      expect(e.failure, RepositoryFailure.insufficientFunds);
      expect(e.message, 'nope');
      expect(mapServerError('failed-precondition', {'reason': 'KYC_REQUIRED'}).failure, RepositoryFailure.kycRequired);
      expect(mapServerError('failed-precondition', {'reason': 'DEPOSIT_LIMIT'}).failure, RepositoryFailure.limitExceeded);
      expect(mapServerError('resource-exhausted', {'reason': 'RATE_LIMITED'}).failure, RepositoryFailure.rateLimited);
      expect(mapServerError('not-found', {'reason': 'BAD_CODE'}).failure, RepositoryFailure.notFound);
      expect(mapServerError('permission-denied', {'reason': 'OWN_TABLE_MARKET'}).failure, RepositoryFailure.permissionDenied);
    });

    test('every reason maps to a failure', () {
      for (final r in ServerReason.values) {
        final e = mapServerError('failed-precondition', {'reason': r.name});
        expect(e.reason, r);
      }
    });

    test('without a known reason the gRPC code decides', () {
      expect(mapServerError('unavailable', null).failure, RepositoryFailure.unavailable);
      expect(mapServerError('deadline-exceeded', null).failure, RepositoryFailure.unavailable);
      expect(mapServerError('not-found', {'reason': 'SOMETHING_NEW'}).failure, RepositoryFailure.notFound);
      expect(mapServerError('not-found', {'reason': 'SOMETHING_NEW'}).reason, isNull);
      expect(mapServerError('resource-exhausted', 'x').failure, RepositoryFailure.rateLimited);
      expect(mapServerError('weird', null).failure, RepositoryFailure.unknown);
    });
  });

  group('CallableClient', () {
    late List<(String, Map<String, Object?>)> calls;
    late List<Object?> script; // per call: an Exception to throw, or a response
    CallableClient client({int retries = 2}) => CallableClient(
          (name, data) async {
            calls.add((name, Map.of(data)));
            final next = script.removeAt(0);
            if (next is Exception) throw next;
            return next;
          },
          retries: retries,
          retryDelay: Duration.zero,
        );

    setUp(() {
      calls = [];
      script = [];
    });

    test('transient errors are retried with the SAME requestId', () async {
      script = [const CallableError('unavailable', null), TimeoutException('t'), {'balanceCents': 1500, 'ledgerEntryId': 'L1'}];
      final r = await client().call('deposit', {'amountCents': 500, 'method': 'card'}, idempotencyKey: 'req-0001-abcdef');
      expect(r, {'balanceCents': 1500, 'ledgerEntryId': 'L1'});
      expect(calls, hasLength(3));
      expect(calls.map((c) => c.$2['requestId']).toSet(), {'req-0001-abcdef'});
      expect(calls.first.$1, 'deposit');
      expect(calls.first.$2, {'amountCents': 500, 'method': 'card', 'requestId': 'req-0001-abcdef'});
    });

    test('a generated requestId is valid (8..64 [A-Za-z0-9_-]) and reused across retries', () async {
      script = [const CallableError('deadline-exceeded', null), const <String, Object?>{}];
      await client().call('pokeTable', {'tableId': 't1'});
      final ids = calls.map((c) => c.$2['requestId']! as String).toSet();
      expect(ids, hasLength(1));
      expect(ids.single, matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
    });

    test('server errors become RepositoryException with the reason and are NOT retried', () async {
      script = [const CallableError('failed-precondition', {'reason': 'INSUFFICIENT_FUNDS'}, 'low balance')];
      await expectLater(
        client().call('placeBet', {'tableId': 't', 'handNumber': 1, 'amountCents': 100}, idempotencyKey: 'k-12345678'),
        throwsA(isA<RepositoryException>()
            .having((e) => e.reason, 'reason', ServerReason.INSUFFICIENT_FUNDS)
            .having((e) => e.failure, 'failure', RepositoryFailure.insufficientFunds)),
      );
      expect(calls, hasLength(1));
    });

    test('exhausted retries → unavailable', () async {
      script = [for (var i = 0; i < 3; i++) const CallableError('unavailable', null)];
      await expectLater(
        client().call('act', const {}, idempotencyKey: 'k-12345678'),
        throwsA(isA<RepositoryException>().having((e) => e.failure, 'f', RepositoryFailure.unavailable)),
      );
      expect(calls, hasLength(3));
      calls.clear();
      script = [TimeoutException('a'), TimeoutException('b'), TimeoutException('c')];
      await expectLater(
        client().call('act', const {}, idempotencyKey: 'k-12345678'),
        throwsA(isA<RepositoryException>().having((e) => e.failure, 'f', RepositoryFailure.unavailable)),
      );
      expect(calls, hasLength(3));
    });

    test('a null response becomes an empty map', () async {
      script = [null];
      expect(await client().call('leaveTable', {'tableId': 't'}), isEmpty);
    });
  });

  group('localizeError', () {
    for (final locale in const [Locale('fr'), Locale('en')]) {
      final l = lookupAppLocalizations(locale);
      test('${locale.languageCode}: a distinct, non-empty message for every ServerReason', () {
        final msgs = {for (final r in ServerReason.values) r: localizeError(l, RepositoryException(failureForReason(r), null, r))};
        expect(msgs.values.every((m) => m.trim().isNotEmpty), isTrue);
        // USERNAME_TAKEN and PROFILE_EXISTS may share text with their auth twins, not with each other.
        expect(msgs.values.toSet(), hasLength(ServerReason.values.length));
      });
      test('${locale.languageCode}: every RepositoryFailure and AuthFailure', () {
        for (final f in RepositoryFailure.values) {
          expect(localizeError(l, RepositoryException(f)), isNotEmpty, reason: f.name);
        }
        expect({for (final f in RepositoryFailure.values) localizeFailure(l, f)}, hasLength(RepositoryFailure.values.length));
        for (final f in AuthFailure.values) {
          expect(localizeError(l, AuthException(f)), isNotEmpty, reason: f.name);
        }
        expect({for (final f in AuthFailure.values) localizeAuthFailure(l, f)}, hasLength(AuthFailure.values.length));
        expect(localizeError(l, TimeoutException('x')), localizeFailure(l, RepositoryFailure.unavailable));
        expect(localizeError(l, StateError('?')), localizeFailure(l, RepositoryFailure.unknown));
      });
    }
    test('FR and EN differ', () {
      final fr = lookupAppLocalizations(const Locale('fr'));
      final en = lookupAppLocalizations(const Locale('en'));
      for (final r in ServerReason.values) {
        expect(localizeServerReason(fr, r), isNot(localizeServerReason(en, r)), reason: r.name);
      }
      expect(localizeFailure(fr, RepositoryFailure.unavailable), contains('injoignable'));
      expect(localizeFailure(en, RepositoryFailure.unavailable), contains('unreachable'));
    });
  });
}
