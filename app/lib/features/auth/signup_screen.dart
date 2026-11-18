import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../domain/backend_constants.dart';
import '../../l10n/gen/app_localizations.dart';
import 'login_screen.dart';

/// Username rule shared with the server (`completeProfile`): 3–16 chars
/// `[A-Za-z0-9_]`.
final kUsernamePattern = Backend.usernamePattern;

String? validateUsername(AppLocalizations l, String? v) =>
    kUsernamePattern.hasMatch(v?.trim() ?? '') ? null : l.authUsernameRule;

/// Language picker shared by sign-up and profile completion.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.value, required this.onChanged, this.keyPrefix = 'signup-lang'});
  final String value;
  final ValueChanged<String> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'fr', label: Text('Français', key: Key('$keyPrefix-fr'))),
          ButtonSegment(value: 'en', label: Text('English', key: Key('$keyPrefix-en'))),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

/// Email/password account + profile (username, procedural avatar,
/// language). `signUp` creates the Auth account then calls
/// `completeProfile` (welcome bonus). If the profile step fails after the
/// account was created, the router sends the user to `/complete-profile`.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _avatar = Backend.avatarIds[9];
  String? _language;
  bool _adult = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final valid = _form.currentState!.validate();
    if (!valid || !_adult) {
      if (!_adult) setState(() => _error = l.signupMustBeAdult);
      return;
    }
    final language = _language ?? context.lang;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(settingsProvider.notifier).setLocale(Locale(language));
      await ref.read(authRepositoryProvider).signUp(
            email: _email.text.trim(),
            password: _password.text,
            username: _username.text.trim(),
            avatar: _avatar,
            language: language,
          );
      if (mounted) context.go('/kyc');
    } on Object catch (e) {
      if (mounted) setState(() => _error = localizeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.signupTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  color: cs.primaryContainer,
                  child: Row(
                    children: [
                      Icon(Icons.card_giftcard, color: cs.onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.signupBonus(context.money(Backend.welcomeBonusCents, compact: true)),
                          style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('signup-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: l.email, prefixIcon: const Icon(Icons.alternate_email)),
                  validator: (v) => validateEmail(l, v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signup-password'),
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: l.password,
                    helperText: l.passwordHelp,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: l.showPassword,
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    final ok = s.length >= 8 && RegExp(r'[A-Za-z]').hasMatch(s) && RegExp(r'\d').hasMatch(s);
                    return ok ? null : l.passwordHelp;
                  },
                ),
                const SizedBox(height: 18),
                ProfileFields(
                  username: _username,
                  avatar: _avatar,
                  onAvatar: (a) => setState(() => _avatar = a),
                  language: _language ?? context.lang,
                  onLanguage: (v) => setState(() => _language = v),
                  usernameKey: const Key('signup-username'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  key: const Key('signup-adult'),
                  value: _adult,
                  onChanged: (v) => setState(() => _adult = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.signupAdultCheckbox),
                ),
                if (_error != null) InlineError(_error!, key: const Key('signup-error')),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('signup-submit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.createAccount),
                ),
                const SizedBox(height: 14),
                Text(
                  l.fakeMoneyDisclaimer,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Username + avatar grid + language (sign-up and complete-profile).
class ProfileFields extends StatelessWidget {
  const ProfileFields({
    super.key,
    required this.username,
    required this.avatar,
    required this.onAvatar,
    required this.language,
    required this.onLanguage,
    required this.usernameKey,
    this.languageKeyPrefix = 'signup-lang',
  });
  final TextEditingController username;
  final String avatar;
  final ValueChanged<String> onAvatar;
  final String language;
  final ValueChanged<String> onLanguage;
  final Key usernameKey;
  final String languageKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: usernameKey,
          controller: username,
          maxLength: 16,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l.username,
            helperText: l.authUsernameRule,
            prefixIcon: const Icon(Icons.person_outline),
            counterText: '',
          ),
          validator: (v) => validateUsername(l, v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(l.authAvatarTitle, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            AppAvatar(name: username.text, hue: 0, avatarId: avatar, size: 40),
          ],
        ),
        const SizedBox(height: 8),
        AvatarPicker(selected: avatar, onSelected: onAvatar, size: 40),
        const SizedBox(height: 16),
        Text(l.authLanguageTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        LanguagePicker(value: language, onChanged: onLanguage, keyPrefix: languageKeyPrefix),
      ],
    );
  }
}
