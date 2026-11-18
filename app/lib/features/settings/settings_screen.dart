import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bootstrap/backend_config.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final host = ref.watch(backendConfigProvider).host;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader(l.settingsTheme, icon: Icons.palette_outlined),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              key: const Key('theme-switch'),
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l.themeSystem), icon: const Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight), icon: const Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark), icon: const Icon(Icons.dark_mode)),
              ],
              selected: {s.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (v) => ctrl.setThemeMode(v.first),
            ),
          ),
          SectionHeader(l.settingsLanguage, icon: Icons.translate),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              key: const Key('language-switch'),
              segments: const [
                ButtonSegment(value: 'fr', label: Text('Français')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.locale.languageCode},
              showSelectedIcon: false,
              onSelectionChanged: (v) => ctrl.setLocale(Locale(v.first)),
            ),
          ),
          SectionHeader(l.settingsFeedback, icon: Icons.vibration),
          SwitchListTile(
            value: s.soundOn,
            onChanged: ctrl.setSound,
            title: Text(l.settingsSound),
          ),
          SwitchListTile(
            value: s.hapticsOn,
            onChanged: ctrl.setHaptics,
            title: Text(l.settingsHaptics),
          ),
          SectionHeader(l.serverTitle, icon: Icons.dns_outlined),
          ListTile(
            title: Text(host),
            subtitle: Text(l.settingsServerHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/server'),
          ),
          SectionHeader(l.settingsAbout, icon: Icons.info_outline),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l.settingsAboutBody, style: TextStyle(color: context.palette.textMuted, fontSize: 12.5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(l.rulesSummary, style: TextStyle(color: context.palette.textMuted, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
