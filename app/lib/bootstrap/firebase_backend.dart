import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_config.dart';

/// Explicit options: there is no google-services.json. Every value is a
/// placeholder accepted by the emulators; nothing points at a real project.
///
/// The API key is a fake with the SHAPE of a real one (`AIza` + 35 chars):
/// the Android Functions SDK rejects a malformed key ("Please set a valid API
/// key") before even calling the emulator. It authorizes nothing.
const kDemoFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyD3m0-EmulatorOnly-NotARealKey0000',
  appId: '1:000000000000:android:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: kFirebaseProjectId,
  storageBucket: '$kFirebaseProjectId.appspot.com',
);

/// Handles to the Firebase SDK, all wired to the emulators on one host.
class FirebaseBackend {
  FirebaseBackend({
    required this.host,
    required this.app,
    required this.auth,
    required this.firestore,
    required this.functions,
  });

  final String host;
  final FirebaseApp app;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
}

/// Creates (or reuses) a named Firebase app per backend host and connects
/// Auth/Firestore/Functions to the emulators there. Using one named app per
/// host lets the user change server at runtime: emulator endpoints can only
/// be set before an instance is first used, so a new host gets a new app.
///
/// The `[DEFAULT]` app must exist too: the FlutterFire platform interfaces
/// build their default delegate from `Firebase.app()` even when a named app
/// is requested (`FirebaseFirestorePlatform.instance`). It is created with
/// the same demo options and wired to the emulators of the first host, so
/// even an accidental default-instance call can only reach an emulator.
class FirebaseBootstrap {
  static final _connected = <String>{};

  static String appNameFor(String host) =>
      'vingtun-${host.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';

  static Future<FirebaseApp> _app(String? name) async {
    final appName = name ?? defaultFirebaseAppName;
    final existing = Firebase.apps.where((a) => a.name == appName);
    if (existing.isNotEmpty) return existing.first;
    return name == null
        ? Firebase.initializeApp(options: kDemoFirebaseOptions)
        : Firebase.initializeApp(name: name, options: kDemoFirebaseOptions);
  }

  /// Points one app's services at the emulators. Marked done only after all
  /// three calls succeeded, so a failure is retried instead of silently
  /// leaving a service on its production endpoint.
  static Future<void> _wire(FirebaseApp app, String host) async {
    if (_connected.contains(app.name)) return;
    await FirebaseAuth.instanceFor(app: app).useAuthEmulator(host, EmulatorPorts.auth);
    FirebaseFirestore.instanceFor(app: app).useFirestoreEmulator(host, EmulatorPorts.firestore);
    FirebaseFunctions.instanceFor(app: app, region: kFunctionsRegion)
        .useFunctionsEmulator(host, EmulatorPorts.functions);
    _connected.add(app.name);
  }

  static Future<FirebaseBackend> connect(String host) async {
    await _wire(await _app(null), host);
    final app = await _app(appNameFor(host));
    await _wire(app, host);

    final auth = FirebaseAuth.instanceFor(app: app);
    final firestore = FirebaseFirestore.instanceFor(app: app);
    final functions = FirebaseFunctions.instanceFor(app: app, region: kFunctionsRegion);
    debugPrint('[firebase] app "${app.name}" -> emulators on $host');
    return FirebaseBackend(
      host: host,
      app: app,
      auth: auth,
      firestore: firestore,
      functions: functions,
    );
  }
}

/// Firebase handles for the current backend host. Initialisation never needs
/// the network, but if the plugin itself fails (e.g. in a unit test without
/// platform channels) the error surfaces here and the UI keeps running.
///
/// The next phase builds its Firebase repositories on top of this provider.
final firebaseBackendProvider = FutureProvider<FirebaseBackend>((ref) async {
  final host = ref.watch(backendConfigProvider.select((c) => c.host));
  return FirebaseBootstrap.connect(host);
});
