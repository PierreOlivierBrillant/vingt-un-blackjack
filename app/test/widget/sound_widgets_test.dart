import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/audio/sfx.dart';
import 'package:vingtun/core/audio/sound_providers.dart';
import 'package:vingtun/core/audio/sound_service.dart';
import 'package:vingtun/core/settings/settings_controller.dart';
import 'package:vingtun/data/error_messages.dart';
import 'package:vingtun/data/fake/fake_repositories.dart';
import 'package:vingtun/data/providers.dart';
import 'package:vingtun/features/settings/settings_screen.dart';
import 'package:vingtun/features/table/table_screen.dart';

import '../helpers.dart';
import '../table_fixtures.dart';

void main() {
  final nowMs = kTestNow.millisecondsSinceEpoch;

  testWidgets('table: casino ambience while seated, chip clinks, my arrival chimes, silence after leaving',
      (tester) async {
    usePhoneSurface(tester);
    final rec = RecordingSoundService();
    final repo = FakeTableRepository(
      myUid: 'me',
      doc: tableDoc(seats: [seatDoc(0, 'me')], deadlineMs: nowMs + 12000, eventSeq: 3),
    );
    await pumpScreen(
      tester,
      const TableScreen(tableId: 'tbl', interstitialEvery: 0),
      overrides: [tableRepositoryProvider.overrideWithValue(repo), soundBackendProvider.overrideWithValue(rec)],
    );
    expect(rec.loops[SoundChannel.ambience], Sfx.ambienceCasinoLoop);
    expect(rec.sounds, contains(Sfx.seatJoin));
    await tester.tap(find.byKey(const Key('chip-500')));
    await tester.pump();
    expect(rec.sounds.last.group, 'chip_clink');
    await tester.pumpWidget(const SizedBox());
    expect(rec.loops, isEmpty);
  });

  testWidgets('audio pauses in the background and resumes in the foreground; errors bonk', (tester) async {
    final rec = RecordingSoundService();
    await pumpScreen(
      tester,
      const AudioLifecycle(dataEvents: false, child: SizedBox()),
      overrides: [soundBackendProvider.overrideWithValue(rec)],
    );
    expect(rec.preloaded, containsAll(kTableSfx));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(rec.suspended, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(rec.suspended, isFalse);
    localizeError(l10nOf(const Locale('fr')), StateError('x'));
    expect(rec.sounds, [Sfx.uiError]);
    await tester.pumpWidget(const SizedBox());
    expect(ErrorFeedback.hook, isNull);
  });

  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets('settings ${locale.languageCode}: master switch + effects / ambience sliders', (tester) async {
      usePhoneSurface(tester);
      final rec = RecordingSoundService();
      final c = await pumpScreen(
        tester,
        const SettingsScreen(),
        locale: locale,
        overrides: [soundBackendProvider.overrideWithValue(rec)],
      );
      final l = l10nOf(locale);
      expect(find.text(l.settingsEffectsVolume), findsOneWidget);
      expect(find.text(l.settingsAmbienceVolume), findsOneWidget);
      // Drag the effects slider to the far left.
      final slider = find.descendant(of: find.byKey(const Key('volume-effects')), matching: find.byType(Slider));
      await tester.drag(slider, const Offset(-600, 0));
      await tester.pump();
      expect(c.read(settingsProvider).effectsVolume, 0);
      final amb = find.descendant(of: find.byKey(const Key('volume-ambience')), matching: find.byType(Slider));
      await tester.drag(amb, const Offset(600, 0));
      await tester.pump();
      expect(c.read(settingsProvider).ambienceVolume, 1);
      await tester.tap(find.byKey(const Key('sound-master')));
      await tester.pump();
      expect(c.read(settingsProvider).soundOn, isFalse);
      expect(rec.levels.muted, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
