/// Mirrors the device theme / language (local source of truth, see
/// `SettingsController`) into `users/{uid}` via
/// [CosmeticsRepository.saveSettings]: on every change, and once each time a
/// user with a complete profile signs in. Activated by `main.dart`
/// (`container.listen(settingsSyncProvider, ...)`); tests do not use it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings_controller.dart';
import '../domain/models.dart';
import 'providers.dart';

ThemePreference themePreferenceOf(ThemeMode m) => switch (m) {
      ThemeMode.light => ThemePreference.light,
      ThemeMode.dark => ThemePreference.dark,
      ThemeMode.system => ThemePreference.system,
    };

final settingsSyncProvider = Provider<void>((ref) {
  Future<void> push(AppSettings s) async {
    try {
      await ref
          .read(cosmeticsRepositoryProvider)
          .saveSettings(theme: themePreferenceOf(s.themeMode), language: s.locale.languageCode);
    } on Object catch (e) {
      debugPrint('[settings] sync failed: $e');
    }
  }

  ref.listen<AppSettings>(settingsProvider, (prev, next) {
    if (prev == null || prev.themeMode != next.themeMode || prev.locale != next.locale) unawaited(push(next));
  });

  String? syncedUid;
  ref.listen<AsyncValue<AppUser?>>(authStateProvider, (_, next) {
    final u = next.value;
    if (u == null) {
      syncedUid = null;
    } else if (u.profileComplete && u.uid != syncedUid) {
      syncedUid = u.uid;
      unawaited(push(ref.read(settingsProvider)));
    }
  }, fireImmediately: true);
});
