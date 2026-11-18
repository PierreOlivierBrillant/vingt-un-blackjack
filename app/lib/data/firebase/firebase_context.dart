/// Shared plumbing of the Firebase repositories: SDK handles, callables,
/// the per-user stream switch, guarded snapshot streams and small caches.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../bootstrap/firebase_backend.dart';
import '../../domain/models.dart';
import '../connection_status.dart';
import '../repositories.dart';
import 'backend_api.dart';
import 'callable_client.dart';
import 'firebase_errors.dart';
import 'stream_utils.dart';

typedef Json = Map<String, Object?>;

Json jsonOf(Map<String, dynamic>? data) => data == null ? const {} : Map<String, Object?>.from(data);

class FirebaseContext {
  FirebaseContext(this.backend, {required this.monitor, required this.now})
      : callables = CallableClient.firebase(
          backend.functions,
          onTransport: (ok) => monitor.reportCallable(reachable: ok),
        );

  final FirebaseBackend backend;
  final ConnectionMonitor monitor;
  final DateTime Function() now;
  final CallableClient callables;

  FirebaseFirestore get db => backend.firestore;
  FirebaseAuth get auth => backend.auth;

  /// Current uid (null when signed out).
  String? get uid => auth.currentUser?.uid;

  /// Current uid, or [RepositoryException] permissionDenied when signed out.
  String requireUid() {
    final u = uid;
    if (u == null) throw const RepositoryException(RepositoryFailure.permissionDenied, 'signed out', ServerReason.UNAUTHENTICATED);
    return u;
  }

  /// uid changes (current value first).
  Stream<String?> get uidChanges => auth.authStateChanges().map((u) => u?.uid).distinct();

  /// Rebuilds [build] for each signed-in uid; emits [signedOut] while signed
  /// out. Errors are [RepositoryException]s.
  Stream<T> perUser<T>(Stream<T> Function(String uid) build, T signedOut) =>
      guardStream(switchMap<String?, T>(uidChanges, (u) => u == null ? Stream.value(signedOut) : build(u)));

  DocumentReference<Map<String, dynamic>> doc(String path) => db.doc(path);
  CollectionReference<Map<String, dynamic>> col(String path) => db.collection(path);

  /// Document data (null when missing). With [reportCache] the snapshot
  /// metadata feeds the connection monitor.
  Stream<Json?> docData(String path, {bool reportCache = false}) => guardStream(
        doc(path).snapshots(includeMetadataChanges: reportCache).map((s) {
          if (reportCache) monitor.reportSnapshot(fromCache: s.metadata.isFromCache);
          return s.exists ? jsonOf(s.data()) : null;
        }),
      );

  /// Query documents as (id, data) pairs.
  Stream<List<(String, Json)>> queryDocs(Query<Map<String, dynamic>> q) =>
      guardStream(q.snapshots().map((s) => [for (final d in s.docs) (d.id, jsonOf(d.data()))]));

  /// Callable with the error mapping of [CallableClient].
  Future<Json> call(String name, Json data, {String? idempotencyKey}) =>
      callables.call(name, data, idempotencyKey: idempotencyKey);

  /// Live profiles of [uids] (chunked `whereIn` on `uid`, ≤ 10 per query).
  Stream<List<PlayerProfile>> profilesOf(List<String> uids) {
    final unique = uids.toSet().toList();
    if (unique.isEmpty) return Stream.value(const []);
    return combineLatestList([
      for (final chunk in chunked(unique, QueryLimits.whereIn))
        queryDocs(col(FirestorePaths.profiles).where('uid', whereIn: chunk))
            .map((docs) => [for (final (id, d) in docs) PlayerProfile.fromDoc(d, id: id)]),
    ]).map((lists) => [for (final l in lists) ...l]);
  }

  late final tableNames = FieldCache(this, (id) => FirestorePaths.table(id), (d) => d['name'] is String ? d['name']! as String : null);

  /// marketId → "Table name #hand" (ledger details).
  late final marketLabels = FieldCache(this, (id) => FirestorePaths.market(id), (d) {
    final name = d['tableName'];
    if (name is! String) return null;
    final hand = d['handNumber'];
    return hand is num ? '$name #${hand.toInt()}' : name;
  });
}

/// One-shot lookups of a derived string per document, cached for the session
/// (table names, market labels). Failures resolve to null.
class FieldCache {
  FieldCache(this._ctx, this._path, this._extract);
  final FirebaseContext _ctx;
  final String Function(String id) _path;
  final String? Function(Json data) _extract;
  final _values = <String, String?>{};
  final _pending = <String, Future<String?>>{};

  String? cached(String id) => _values[id];

  Future<String?> get(String id) {
    if (_values.containsKey(id)) return Future.value(_values[id]);
    return _pending[id] ??= () async {
      try {
        final snap = await _ctx.doc(_path(id)).get();
        return _values[id] = snap.exists ? _extract(jsonOf(snap.data())) : null;
      } on Object {
        return null; // not cached: retried next time
      } finally {
        unawaited(_pending.remove(id));
      }
    }();
  }

  Future<Map<String, String>> getAll(Iterable<String> ids) async {
    final out = <String, String>{};
    for (final id in ids.toSet()) {
      final v = await get(id);
      if (v != null) out[id] = v;
    }
    return out;
  }
}
