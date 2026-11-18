import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ids.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../domain/backend_constants.dart';
import 'signup_screen.dart';

/// Shown (router redirect) while the signed-in Auth account has no
/// `profiles/{uid}` yet ([AppUser.profileComplete] false): picks username,
/// avatar and language and calls `completeProfile`.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _username;
  String _avatar = Backend.avatarIds.first;
  String? _language;
  bool _busy = false;
  String? _error;

  /// Same key while the user retries the same profile (server de-dup);
  /// a new one when they change the username.
  String _key = newIdempotencyKey();
  String _keyFor = '';

  @override
  void initState() {
    super.initState();
    final u = ref.read(authRepositoryProvider).currentUser;
    _username = TextEditingController(text: u?.username ?? '');
    if (u != null && Backend.avatarIds.contains(u.avatar)) _avatar = u.avatar;
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    if (!_form.currentState!.validate()) return;
    final name = _username.text.trim();
    final language = _language ?? context.lang;
    final sig = '$name|$_avatar|$language';
    if (sig != _keyFor) {
      _key = newIdempotencyKey();
      _keyFor = sig;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(settingsProvider.notifier).setLocale(Locale(language));
      await ref
          .read(authRepositoryProvider)
          .completeProfile(username: name, avatar: _avatar, language: language, idempotencyKey: _key);
      if (mounted) context.go('/lobby');
    } on Object catch (e) {
      if (mounted) setState(() => _error = localizeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final email = ref.watch(authStateProvider).value?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(l.completeProfileTitle),
        actions: [
          TextButton(
            key: const Key('complete-signout'),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: Text(l.signOut),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.completeProfileIntro, key: const Key('complete-profile-intro')),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(email, style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                ],
                const SizedBox(height: 18),
                ProfileFields(
                  username: _username,
                  avatar: _avatar,
                  onAvatar: (a) => setState(() => _avatar = a),
                  language: _language ?? context.lang,
                  onLanguage: (v) => setState(() => _language = v),
                  usernameKey: const Key('complete-username'),
                  languageKeyPrefix: 'complete-lang',
                ),
                if (_error != null) InlineError(_error!, key: const Key('complete-error')),
                const SizedBox(height: 18),
                FilledButton(
                  key: const Key('complete-submit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.completeProfileSubmit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
