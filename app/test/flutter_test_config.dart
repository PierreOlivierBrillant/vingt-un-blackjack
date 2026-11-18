import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the Roboto + Material Icons fonts shipped with the Flutter SDK so
/// golden images show real glyphs instead of test boxes. Goldens are
/// therefore tied to this SDK's fonts (regenerate with
/// `flutter test --update-goldens` after an SDK upgrade).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final dir = '$root/bin/cache/artifacts/material_fonts';
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      var any = false;
      for (final f in files) {
        final file = File('$dir/$f');
        if (file.existsSync()) {
          any = true;
          loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      if (any) await loader.load();
    }

    await load('Roboto', [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
      'roboto-italic.ttf',
      'roboto-blackitalic.ttf',
    ]);
    await load('MaterialIcons', ['materialicons-regular.otf']);
  }
  await testMain();
}
