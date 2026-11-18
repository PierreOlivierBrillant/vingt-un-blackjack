import 'package:flutter/material.dart';

import '../../core/widgets.dart';
import 'ad_widgets.dart';

/// Showcase of the three parody ad formats.
class AdsDemoScreen extends StatelessWidget {
  const AdsDemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.adsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.adsIntro),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++) ...[AdBanner(index: i), const SizedBox(height: 10)],
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('ads-interstitial'),
            onPressed: () => showInterstitialAd(context),
            icon: const Icon(Icons.fullscreen),
            label: Text(l.adsShowInterstitial),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('ads-rewarded'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final cents = await showRewardedAd(context);
              if (cents != null && context.mounted) {
                messenger.showSnackBar(SnackBar(content: Text(l.adRewardCredited(context.money(cents)))));
              }
            },
            icon: const Icon(Icons.ondemand_video),
            label: Text(l.adsShowRewarded),
          ),
        ],
      ),
    );
  }
}
