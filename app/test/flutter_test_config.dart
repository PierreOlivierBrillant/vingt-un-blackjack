import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the Roboto + Material Icons fonts EMBEDDED in `test/fonts/` (copied
/// from the Flutter SDK's material_fonts artifact, Apache 2.0 — see the
/// licence files there), so every platform (Windows dev machines, the Linux
/// CI) lays text out with exactly the same metrics. Nothing depends on the
/// system fonts or on the SDK cache being populated.
///
/// Golden comparisons tolerate a tiny fraction of differing pixels
/// ([kGoldenTolerance]) to absorb anti-aliasing differences between hosts.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // VINGTUN_TEST_SYSTEM_FONTS=1 skips the embedded fonts (square test glyphs,
  // much wider than Roboto): a stress test for layouts.
  if (Platform.environment['VINGTUN_TEST_SYSTEM_FONTS'] == '1') return testMain();
  final dir = _fontsDir();
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('${dir.path}/$f');
      if (!file.existsSync()) throw StateError('Missing test font ${file.path}');
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
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

  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(Uri.parse('${current.basedir}placeholder.dart'));
  }
  await testMain();
}

/// Fraction of pixels allowed to differ in a golden comparison (0.3 %).
const kGoldenTolerance = 0.003;

Directory _fontsDir() {
  // `flutter test` runs with the package root as the working directory.
  for (final candidate in ['test/fonts', 'app/test/fonts']) {
    final d = Directory(candidate);
    if (d.existsSync()) return d;
  }
  throw StateError('test/fonts not found from ${Directory.current.path}');
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= kGoldenTolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
