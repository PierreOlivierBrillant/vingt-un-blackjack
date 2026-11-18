/// Backend reachability as seen by the repositories, for an app-wide banner.
library;

import 'dart:async';

import 'live.dart';

enum ConnectionStatus {
  /// Server reachable (last snapshot from the server, last callable answered).
  online,

  /// Firestore serves data from the local cache (no server connection).
  offline,

  /// The last callable could not reach the Functions emulator (timeout,
  /// refused): mutations will fail until it answers again.
  unreachable,
}

/// Fed by the Firebase repositories:
/// * [reportSnapshot] with `snapshot.metadata.isFromCache` of the always-on
///   listeners (profile, table);
/// * [reportCallable] after each callable (`CallableClient.onTransport`).
///
/// Status priority: unreachable > offline > online. `unreachable` is cleared
/// only by a callable that reaches the server (Firestore may be up while
/// Functions are down); `offline` by the next non-cache snapshot.
class ConnectionMonitor {
  ConnectionMonitor();

  final _live = Live<ConnectionStatus>(ConnectionStatus.online);
  bool _fromCache = false;
  bool _unreachable = false;

  ConnectionStatus get status => _live.value;

  /// Current status first, then each change.
  Stream<ConnectionStatus> get changes => _live.stream.distinct();

  void reportSnapshot({required bool fromCache}) {
    _fromCache = fromCache;
    _update();
  }

  void reportCallable({required bool reachable}) {
    _unreachable = !reachable;
    _update();
  }

  void _update() {
    final next = _unreachable
        ? ConnectionStatus.unreachable
        : _fromCache
            ? ConnectionStatus.offline
            : ConnectionStatus.online;
    if (next != _live.value) _live.value = next;
  }

  Future<void> dispose() => _live.close();
}
