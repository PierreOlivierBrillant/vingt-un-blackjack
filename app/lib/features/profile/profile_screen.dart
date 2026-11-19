import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/backend_constants.dart';
import '../../domain/models.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = context.palette;
    final user = ref.watch(authStateProvider).value;
    // Live values (the signed-in user object is a snapshot from sign-in).
    final profile = user == null ? null : ref.watch(profileProvider(user.uid)).value;
    final kyc = ref.watch(kycStatusProvider).value ?? user?.kycStatus ?? KycStatus.none;
    final points = profile?.rankPoints ?? 0;
    final tier = profile?.rankTier ?? user?.rankTier ?? RankTier.bronze;
    Widget tile(IconData icon, String title, String route, {String? subtitle, Key? key}) => ListTile(
          key: key,
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.navProfile)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Panel(
              child: Row(
                children: [
                  AppAvatar(name: user?.username ?? '?', hue: user?.avatarHue ?? 140, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.username ?? '—', style: Theme.of(context).textTheme.titleMedium),
                        Text(user?.email ?? '', style: TextStyle(color: p.textMuted, fontSize: 12)),
                        const SizedBox(height: 6),
                        Row(children: [
                          TierBadge(tier, key: const Key('profile-tier')),
                          const SizedBox(width: 6),
                          _KycChip(status: kyc),
                        ]),
                        if (profile != null) ...[
                          const SizedBox(height: 8),
                          _RankProgress(points: points, tier: tier),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          tile(Icons.bolt, l.shopTitle, '/shop', subtitle: l.shopSubtitle, key: const Key('nav-shop')),
          tile(Icons.style, l.customizeTitle, '/customize', subtitle: l.customizeSubtitle, key: const Key('nav-customize')),
          tile(Icons.people_outline, l.friendsTitle, '/friends', key: const Key('nav-friends')),
          tile(Icons.verified_user_outlined, l.kycTitle, '/kyc', key: const Key('nav-kyc')),
          tile(Icons.smart_toy_outlined, l.lobbyDealerDemo, '/dealer-demo', key: const Key('nav-dealer')),
          tile(Icons.campaign_outlined, l.adsTitle, '/ads', key: const Key('nav-ads')),
          tile(Icons.settings_outlined, l.settingsTitle, '/settings', key: const Key('nav-settings')),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              icon: const Icon(Icons.logout),
              label: Text(l.signOut),
            ),
          ),
        ],
      ),
    );
  }
}

class _KycChip extends StatelessWidget {
  const _KycChip({required this.status});
  final KycStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final (text, color) = switch (status) {
      KycStatus.verified => (l.kycVerified, p.win),
      KycStatus.pending => (l.kycPending, p.warning),
      KycStatus.rejected => (l.kycRejected, p.loss),
      KycStatus.none => (l.kycNotStarted, p.textMuted),
    };
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// Ranking points and progress towards the next tier (thresholds shared
/// with the backend, `RANK_TIER_THRESHOLDS`).
class _RankProgress extends StatelessWidget {
  const _RankProgress({required this.points, required this.tier});
  final int points;
  final RankTier tier;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final next = tier.index + 1 < RankTier.values.length ? RankTier.values[tier.index + 1] : null;
    final from = Backend.rankTierThresholds[tier] ?? 0;
    final to = next == null ? null : Backend.rankTierThresholds[next]!;
    final progress = to == null ? 1.0 : ((points - from) / (to - from)).clamp(0.0, 1.0);
    return Column(
      key: const Key('profile-rank'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            color: TierBadge.colorOf(next ?? tier),
            backgroundColor: p.surfaceSunken,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${l.profileRankPoints(points)} · ${next == null ? l.profileRankMax : l.profileRankNext(to! - points, tierLabel(l, next))}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.textMuted, fontSize: 11.5),
        ),
      ],
    );
  }
}