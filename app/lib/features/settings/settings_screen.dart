import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bootstrap/backend_config.dart';
import '../../core/audio/sfx.dart';
import '../../core/audio/sound_providers.dart';
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
              onSelectionChanged: (v) {
                ref.sfx(Sfx.uiToggle);
                ctrl.setThemeMode(v.first);
              },
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
              onSelectionChanged: (v) {
                ref.sfx(Sfx.uiToggle);
                ctrl.setLocale(Locale(v.first));
              },
            ),
          ),
          SectionHeader(l.settingsFeedback, icon: Icons.vibration),
          SwitchListTile(
            key: const Key('sound-master'),
            value: s.soundOn,
            onChanged: (v) async {
              await ctrl.setSound(v);
              if (v) ref.sfx(Sfx.uiToggle);
            },
            title: Text(l.settingsSound),
            subtitle: Text(l.settingsSoundHint),
          ),
          _VolumeTile(
            key: const Key('volume-effects'),
            icon: Icons.music_note_outlined,
            label: l.settingsEffectsVolume,
            value: s.effectsVolume,
            enabled: s.soundOn,
            onChanged: ctrl.setEffectsVolume,
            // Preview at the new level once the thumb is released.
            onChangeEnd: (_) => ref.sfx(Sfx.chipStack),
            onTry: () => ref.sfx(Sfx.winSmall),
            tryLabel: l.settingsSoundTry,
          ),
          _VolumeTile(
            key: const Key('volume-ambience'),
            icon: Icons.nightlife_outlined,
            label: l.settingsAmbienceVolume,
            value: s.ambienceVolume,
            enabled: s.soundOn,
            onChanged: ctrl.setAmbienceVolume,
          ),
          SwitchListTile(
            value: s.hapticsOn,
            onChanged: (v) {
              ctrl.setHaptics(v);
              ref.sfx(Sfx.uiToggle);
            },
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

/// Labelled 0–100 % slider, with an optional "try" button.
class _VolumeTile extends StatelessWidget {
  const _VolumeTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.onChangeEnd,
    this.onTry,
    this.tryLabel,
  });
  final IconData icon;
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onTry;
  final String? tryLabel;

  @override
  Widget build(BuildContext context) {
    final pct = '${(value * 100).round()} %';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.palette.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(pct, style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                  ],
                ),
                Slider(
                  value: value.clamp(0.0, 1.0),
                  divisions: 20,
                  label: pct,
                  onChanged: enabled ? onChanged : null,
                  onChangeEnd: enabled ? onChangeEnd : null,
                ),
              ],
            ),
          ),
          if (onTry != null)
            TextButton(onPressed: enabled ? onTry : null, child: Text(tryLabel ?? '')),
        ],
      ),
    );
  }
}
