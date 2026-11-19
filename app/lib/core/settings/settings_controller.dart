import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/sound_service.dart';

/// Must be overridden in `main()` (and in tests) with a ready instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.locale = const Locale('fr'),
    this.soundOn = true,
    this.hapticsOn = true,
    this.effectsVolume = 0.9,
    this.ambienceVolume = 0.45,
  });

  final ThemeMode themeMode;
  final Locale locale;
  final bool soundOn;
  final bool hapticsOn;

  /// 0..1, sound effects (cards, chips, fanfares, interface).
  final double effectsVolume;

  /// 0..1, casino room tone in the lobby and at the table.
  final double ambienceVolume;

  /// Master switch [soundOn] + both levels, as the audio layer wants them.
  SoundLevels get soundLevels => SoundLevels(effects: effectsVolume, ambience: ambienceVolume, muted: !soundOn);

  AppSettings copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    bool? soundOn,
    bool? hapticsOn,
    double? effectsVolume,
    double? ambienceVolume,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        soundOn: soundOn ?? this.soundOn,
        hapticsOn: hapticsOn ?? this.hapticsOn,
        effectsVolume: effectsVolume ?? this.effectsVolume,
        ambienceVolume: ambienceVolume ?? this.ambienceVolume,
      );
}

/// Local, per-device UI settings (theme, language, feedback). The next phase
/// may mirror theme/language into `users/{uid}` but the local copy stays the
/// source of truth for instant startup.
class SettingsController extends Notifier<AppSettings> {
  static const _kTheme = 'settings.themeMode';
  static const _kLocale = 'settings.locale';
  static const _kSound = 'settings.sound';
  static const _kHaptics = 'settings.haptics';
  static const _kEffects = 'settings.effectsVolume';
  static const _kAmbience = 'settings.ambienceVolume';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final theme = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString(_kTheme),
      orElse: () => ThemeMode.dark,
    );
    final code = prefs.getString(_kLocale);
    return AppSettings(
      themeMode: theme,
      locale: Locale(code == 'en' ? 'en' : 'fr'),
      soundOn: prefs.getBool(_kSound) ?? true,
      hapticsOn: prefs.getBool(_kHaptics) ?? true,
      effectsVolume: (prefs.getDouble(_kEffects) ?? 0.9).clamp(0.0, 1.0),
      ambienceVolume: (prefs.getDouble(_kAmbience) ?? 0.45).clamp(0.0, 1.0),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kTheme, mode.name);
  }

  Future<void> setLocale(Locale locale) async {
    state = state.copyWith(locale: locale);
    await _prefs.setString(_kLocale, locale.languageCode);
  }

  Future<void> setSound(bool on) async {
    state = state.copyWith(soundOn: on);
    await _prefs.setBool(_kSound, on);
  }

  Future<void> setEffectsVolume(double v) async {
    state = state.copyWith(effectsVolume: v.clamp(0.0, 1.0));
    await _prefs.setDouble(_kEffects, state.effectsVolume);
  }

  Future<void> setAmbienceVolume(double v) async {
    state = state.copyWith(ambienceVolume: v.clamp(0.0, 1.0));
    await _prefs.setDouble(_kAmbience, state.ambienceVolume);
  }

  Future<void> setHaptics(bool on) async {
    state = state.copyWith(hapticsOn: on);
    await _prefs.setBool(_kHaptics, on);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
