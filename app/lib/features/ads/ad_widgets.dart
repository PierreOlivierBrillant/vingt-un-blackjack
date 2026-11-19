import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sfx.dart';
import '../../core/audio/sound_providers.dart';
import '../../core/ids.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../domain/backend_constants.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';

IconData adIcon(String id) => switch (id) {
      'coin' => Icons.currency_bitcoin,
      'bank' => Icons.account_balance,
      'ai' => Icons.smart_toy,
      _ => Icons.pets,
    };

(String tagline, String cta) adCopy(AppLocalizations l, String id) => switch (id) {
      'coin' => (l.adCoinTagline, l.adCoinCta),
      'bank' => (l.adBankTagline, l.adBankCta),
      'ai' => (l.adAiTagline, l.adAiCta),
      _ => (l.adNftTagline, l.adNftCta),
    };

class _AdLabel extends StatelessWidget {
  const _AdLabel();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white70),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(context.l10n.adLabel, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800)),
      );
}

/// Parody banner ad (clearly labelled, never links anywhere).
class AdBanner extends ConsumerWidget {
  const AdBanner({super.key, this.index = 0});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(adsRepositoryProvider).inventory(AdFormat.banner);
    final ad = ads[index % ads.length];
    final (tagline, cta) = adCopy(context.l10n, ad.id);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(colors: [ad.color, Color.lerp(ad.color, Colors.black, 0.45)!]),
      ),
      child: Row(
        children: [
          Icon(adIcon(ad.id), color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(ad.brand,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    const _AdLabel(),
                  ],
                ),
                Text(tagline, style: const TextStyle(color: Colors.white, fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Text(
                cta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: ad.color, fontWeight: FontWeight.w900, fontSize: 11.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen parody interstitial with a short forced countdown.
Future<void> showInterstitialAd(BuildContext context, {Duration lock = const Duration(seconds: 4)}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    pageBuilder: (_, _, _) => _Interstitial(lock: lock),
  );
}

class _Interstitial extends ConsumerStatefulWidget {
  const _Interstitial({required this.lock});
  final Duration lock;
  @override
  ConsumerState<_Interstitial> createState() => _InterstitialState();
}

class _InterstitialState extends ConsumerState<_Interstitial> {
  late int _left = widget.lock.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.read(soundProvider).play(Sfx.adInterstitialSting);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) t.cancel();
      setState(() => _left = (_left - 1).clamp(0, 99));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = ref.watch(adsRepositoryProvider).inventory(AdFormat.interstitial)[2];
    final (tagline, cta) = adCopy(context.l10n, ad.id);
    return Material(
      color: Color.lerp(ad.color, Colors.black, 0.55),
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(adIcon(ad.id), size: 96, color: Colors.white),
                    const SizedBox(height: 12),
                    Text(ad.brand, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(tagline, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: ad.color),
                      child: Text(cta),
                    ),
                    const SizedBox(height: 12),
                    Text(context.l10n.adParodyNotice, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const Positioned(left: 12, top: 12, child: _AdLabel()),
            Positioned(
              right: 8,
              top: 8,
              child: _left > 0
                  ? Chip(label: Text(context.l10n.adCloseIn(_left)))
                  : IconButton.filledTonal(
                      key: const Key('ad-close'),
                      tooltip: context.l10n.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rewarded parody video: watch the fake progress bar, get a small credit
/// (server-capped via `claimAdReward`).
Future<int?> showRewardedAd(BuildContext context, {Duration length = const Duration(seconds: 5)}) {
  return showDialog<int>(context: context, barrierDismissible: false, builder: (_) => _Rewarded(length: length));
}

class _Rewarded extends ConsumerStatefulWidget {
  const _Rewarded({required this.length});
  final Duration length;
  @override
  ConsumerState<_Rewarded> createState() => _RewardedState();
}

class _RewardedState extends ConsumerState<_Rewarded> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.length)..forward();
  String? _error;
  bool _claiming = false;
  final _idempotencyKey = newIdempotencyKey();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _claim(ParodyAd ad) async {
    setState(() => _claiming = true);
    try {
      final r = await ref.read(adsRepositoryProvider).claimReward(ad.id, idempotencyKey: _idempotencyKey);
      if (mounted) Navigator.of(context).pop(r.rewardCents);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _claiming = false;
          _error = localizeError(context.l10n, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ad = ref.watch(adsRepositoryProvider).inventory(AdFormat.rewarded)[0];
    final (tagline, _) = adCopy(l, ad.id);
    return AlertDialog(
      title: Row(children: [Expanded(child: Text(l.adRewardedTitle)), const _AdLabel()]),
      content: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(color: ad.color, borderRadius: BorderRadius.circular(12)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.rotate(angle: _c.value * 6.28, child: Icon(adIcon(ad.id), size: 64, color: Colors.white)),
                  Positioned(
                    bottom: 8,
                    left: 10,
                    right: 10,
                    child: Text(tagline, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _c.value),
            const SizedBox(height: 8),
            Text(
              _c.isCompleted ? l.adRewardReady(context.money(Backend.adRewardCents)) : l.adRewardWatching,
              style: TextStyle(color: context.palette.textMuted),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: context.palette.loss)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.close)),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => FilledButton(
            key: const Key('ad-claim'),
            onPressed: _c.isCompleted && !_claiming ? () => _claim(ad) : null,
            child: Text(l.adClaim),
          ),
        ),
      ],
    );
  }
}
