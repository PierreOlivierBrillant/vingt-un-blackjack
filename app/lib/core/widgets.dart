import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/error_messages.dart';
import '../data/providers.dart';
import '../domain/models.dart';
import '../l10n/gen/app_localizations.dart';
import 'avatar.dart';
import 'money.dart';
import 'theme/app_theme.dart';

export 'avatar.dart' show AvatarPicker, AvatarPainter;

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get lang => Localizations.localeOf(this).languageCode;
  String money(int cents, {bool signed = false, bool compact = false}) =>
      formatCents(cents, locale: lang, signed: signed, compact: compact);
}

/// Original wordmark: "VINGT·UN" with a spade-diamond glyph made of shapes.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Vingt-Un',
      // Scales down rather than overflow in a crowded app bar.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 1.25,
            height: size * 1.25,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(size * 0.32),
            ),
            alignment: Alignment.center,
            child: Text(
              '21',
              style: TextStyle(
                color: cs.onPrimary,
                fontWeight: FontWeight.w900,
                fontSize: size * 0.62,
                height: 1,
              ),
            ),
          ),
          SizedBox(width: size * 0.35),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'VINGT'),
              TextSpan(text: '·', style: TextStyle(color: cs.primary)),
              const TextSpan(text: 'UN'),
            ]),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              fontSize: size,
              letterSpacing: 0.5,
              height: 1,
              color: cs.onSurface,
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// Mandatory banner on every money screen: the app only moves fake money.
class SimulationBanner extends StatelessWidget {
  const SimulationBanner({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.16),
        border: Border.all(color: p.warning.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, color: p.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text ?? context.l10n.simulationBanner,
              style: TextStyle(color: p.warning, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.icon});
  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: context.palette.textMuted),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Procedural avatar: the `avatar01`..`avatar24` drawing when [avatarId] is
/// given, otherwise initials on [hue].
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, required this.hue, this.size = 36, this.online, this.avatarId});
  final String name;
  final int hue;
  final double size;
  final bool? online;

  /// `avatar01`..`avatar24`; null = initials.
  final String? avatarId;

  @override
  Widget build(BuildContext context) {
    final bg = HSLColor.fromAHSL(1, hue % 360 + 0.0, 0.55, 0.42).toColor();
    final initials = name.isEmpty
        ? '?'
        : name.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ0-9]'), '').characters.take(2).toString().toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (avatarId != null)
            Semantics(
              label: name,
              child: SizedBox.square(dimension: size, child: CustomPaint(painter: AvatarPainter(avatarId!))),
            )
          else
            CircleAvatar(
              radius: size / 2,
              backgroundColor: bg,
              child: Text(
                initials,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36),
              ),
            ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.32,
                height: size * 0.32,
                decoration: BoxDecoration(
                  color: online! ? context.palette.win : context.palette.textMuted,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.palette.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String tierLabel(AppLocalizations l, RankTier tier) => switch (tier) {
      RankTier.bronze => l.tierBronze,
      RankTier.silver => l.tierSilver,
      RankTier.gold => l.tierGold,
      RankTier.platinum => l.tierPlatinum,
      RankTier.diamond => l.tierDiamond,
    };

/// Rank tier pill. Text colours are per-theme so the label keeps a WCAG
/// contrast ≥ 4.5:1 on the tinted badge (light pastel metals were unreadable
/// on white; see `test/widget/tier_badge_contrast_test.dart`).
class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key});
  final RankTier tier;

  /// Brand metal colour (medals, borders, the badge tint).
  static Color colorOf(RankTier t) => switch (t) {
        RankTier.bronze => const Color(0xFFCD7F32),
        RankTier.silver => const Color(0xFFB8C2CC),
        RankTier.gold => const Color(0xFFF5C451),
        RankTier.platinum => const Color(0xFF7FE0D6),
        RankTier.diamond => const Color(0xFF8AB4FF),
      };

  /// Label colour for [brightness] (dark theme: light metals; light theme:
  /// deep shades of the same hue).
  static Color textColorOf(RankTier t, Brightness brightness) => brightness == Brightness.dark
      ? switch (t) {
          RankTier.bronze => const Color(0xFFE8A56A),
          RankTier.silver => const Color(0xFFD3DAE1),
          RankTier.gold => const Color(0xFFF5C451),
          RankTier.platinum => const Color(0xFF8FE8DF),
          RankTier.diamond => const Color(0xFFA3C4FF),
        }
      : switch (t) {
          RankTier.bronze => const Color(0xFF7F4413),
          RankTier.silver => const Color(0xFF46525E),
          RankTier.gold => const Color(0xFF6E4E00),
          RankTier.platinum => const Color(0xFF0B5E56),
          RankTier.diamond => const Color(0xFF1F4FA8),
        };

  /// Alpha of the metal tint behind the label.
  static const tintAlpha = 0.16;

  @override
  Widget build(BuildContext context) {
    final c = colorOf(tier);
    final text = textColorOf(tier, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: tintAlpha),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Color.lerp(c, text, 0.4)!.withValues(alpha: 0.8)),
      ),
      child: Text(tierLabel(context.l10n, tier), style: TextStyle(color: text, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// Balance chip for app bars; taps through to the wallet.
class BalancePill extends ConsumerWidget {
  const BalancePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider).value;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: context.palette.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go('/wallet'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  wallet == null ? '—' : context.money(wallet.balanceCents),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(width: 6),
                Container(
                  decoration: BoxDecoration(color: cs.secondary, borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Uniform loading / error / empty rendering for repository streams.
///
/// * loading: spinner (`Key('async-loading')`);
/// * error: the [localizeError] message + a retry button when [onRetry] is
///   given (`Key('async-error')`);
/// * empty: when [isEmpty] returns true for the data and [empty] is given.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry, this.isEmpty, this.empty});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v.hasValue) {
      final data = v.requireValue;
      if (empty != null && (isEmpty?.call(data) ?? false)) return empty!;
      return builder(data);
    }
    if (v.hasError) return ErrorState(error: v.error!, onRetry: onRetry);
    return const Center(
      child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(key: Key('async-loading'))),
    );
  }
}

/// Localized error with an optional retry.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      key: const Key('async-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: context.palette.textMuted, size: 32),
            const SizedBox(height: 8),
            Text(describeError(l, error), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l.commonRetry)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Friendly empty list placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: p.textMuted, size: 30),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

/// Inline red error line (forms, sheets, dialogs).
class InlineError extends StatelessWidget {
  const InlineError(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: context.palette.loss),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(color: context.palette.loss, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

/// Shows [error] (any repository/auth exception) as a localized snackbar.
void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(localizeError(context.l10n, error))));
}

/// Rounded surface card used across the lobby / wallet / markets.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? context.palette.surface,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

String relativeTime(BuildContext context, DateTime at, DateTime now) {
  final l = context.l10n;
  final d = now.difference(at);
  if (d.inSeconds < 60) return l.agoSeconds(d.inSeconds.clamp(1, 59));
  if (d.inMinutes < 60) return l.agoMinutes(d.inMinutes);
  if (d.inHours < 24) return l.agoHours(d.inHours);
  return l.agoDays(d.inDays);
}
