import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings_controller.dart';

/// Ports of the Firebase emulators (see `firebase/firebase.json`).
abstract final class EmulatorPorts {
  static const auth = 9099;
  static const firestore = 8080;
  static const functions = 5001;
}

/// Firebase project id. The `demo-` prefix guarantees no real project exists.
const kFirebaseProjectId = 'demo-blackjack';

/// Functions region used by the backend callables.
const kFunctionsRegion = 'us-central1';

/// Host baked in at build time with `--dart-define=BACKEND_HOST=192.168.1.20`.
/// `10.0.2.2` is the Android emulator's alias for the host machine.
const kDefaultBackendHost = String.fromEnvironment(
  'BACKEND_HOST',
  defaultValue: '10.0.2.2',
);

@immutable
class BackendConfig {
  const BackendConfig({required this.host, this.isCustom = false});

  final String host;

  /// True when the user typed a host on the "Serveur" screen.
  final bool isCustom;

  Uri get authUri => Uri(scheme: 'http', host: host, port: EmulatorPorts.auth, path: '/');
  Uri get firestoreUri =>
      Uri(scheme: 'http', host: host, port: EmulatorPorts.firestore, path: '/');
  Uri get functionsUri =>
      Uri(scheme: 'http', host: host, port: EmulatorPorts.functions, path: '/');

  @override
  bool operator ==(Object other) =>
      other is BackendConfig && other.host == host && other.isCustom == isCustom;

  @override
  int get hashCode => Object.hash(host, isCustom);
}

/// Validates a host typed by the user: an IPv4 address or a DNS-style name.
/// No scheme, no port, no path.
bool isValidBackendHost(String value) {
  final v = value.trim();
  if (v.isEmpty || v.length > 253) return false;
  final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(v);
  if (ipv4 != null) {
    return List.generate(4, (i) => int.parse(ipv4.group(i + 1)!)).every((n) => n <= 255);
  }
  return RegExp(r'^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$')
      .hasMatch(v);
}

/// Persisted backend host. Changing it rebuilds [firebaseBackendProvider],
/// which connects a fresh named Firebase app to the new host (no restart).
class BackendConfigController extends Notifier<BackendConfig> {
  static const _kHost = 'backend.host';

  @override
  BackendConfig build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_kHost);
    if (saved != null && isValidBackendHost(saved)) {
      return BackendConfig(host: saved, isCustom: true);
    }
    return const BackendConfig(host: kDefaultBackendHost);
  }

  Future<void> setHost(String host) async {
    final h = host.trim();
    if (!isValidBackendHost(h)) {
      throw ArgumentError.value(host, 'host', 'invalid host');
    }
    state = BackendConfig(host: h, isCustom: true);
    await ref.read(sharedPreferencesProvider).setString(_kHost, h);
  }

  Future<void> resetToDefault() async {
    state = const BackendConfig(host: kDefaultBackendHost);
    await ref.read(sharedPreferencesProvider).remove(_kHost);
  }
}

final backendConfigProvider =
    NotifierProvider<BackendConfigController, BackendConfig>(BackendConfigController.new);
