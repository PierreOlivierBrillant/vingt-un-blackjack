import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  final ThemeMode themeMode;
  final Locale locale;
  final bool soundOn;
  final bool hapticsOn;

  AppSettings copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    bool? soundOn,
    bool? hapticsOn,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        soundOn: soundOn ?? this.soundOn,
        hapticsOn: hapticsOn ?? this.hapticsOn,
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

  Future<void> setHaptics(bool on) async {
    state = state.copyWith(hapticsOn: on);
    await _prefs.setBool(_kHaptics, on);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
