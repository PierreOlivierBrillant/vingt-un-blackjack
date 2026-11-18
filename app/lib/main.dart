import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'bootstrap/firebase_backend.dart';
import 'core/settings/settings_controller.dart';
import 'data/providers.dart';
import 'data/settings_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // The app runs on the Firebase repositories; tests keep the fakes.
      useFirebaseProvider.overrideWithValue(true),
    ],
  );

  container.listen(firebaseBackendProvider, (_, next) {
    if (next.hasError) debugPrint('[firebase] init failed: ${next.error}\n${next.stackTrace}');
  }, fireImmediately: true);

  // Connecting to the emulators needs no network (it only configures the
  // SDK), so wait for it: the repositories are then ready at first frame.
  try {
    await container.read(firebaseBackendProvider.future);
  } on Object catch (e) {
    debugPrint('[firebase] initial connect failed: $e');
  }

  // Mirror theme/language into users/{uid}.
  container.listen(settingsSyncProvider, (_, _) {});

  runApp(UncontrolledProviderScope(container: container, child: const VingtUnApp()));
}
