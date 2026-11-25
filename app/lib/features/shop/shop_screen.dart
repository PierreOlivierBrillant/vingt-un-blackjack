import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../domain/backend_constants.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ads/ad_widgets.dart';

(String name, String desc) powerCopy(AppLocalizations l, PowerType t) => switch (t) {
      PowerType.freeSplit => (l.powerFreeSplit, l.powerFreeSplitDesc),
      PowerType.freeDouble => (l.powerFreeDouble, l.powerFreeDoubleDesc),
      PowerType.freeInsurance => (l.powerFreeInsurance, l.powerFreeInsuranceDesc),
      PowerType.peek => (l.powerPeek, l.powerPeekDesc),
      PowerType.secondChance => (l.powerSecondChance, l.powerSecondChanceDesc),
      PowerType.zeroShield => (l.powerZeroShield, l.powerZeroShieldDesc),
      PowerType.freeCommission => (l.powerFreeCommission, l.powerFreeCommissionDesc),
      PowerType.safetyNet => (l.powerSafetyNet, l.powerSafetyNetDesc),
    };

IconData powerIcon(PowerType t) => switch (t) {
      PowerType.freeSplit => Icons.call_split,
      PowerType.freeDouble => Icons.exposure_plus_2,
      PowerType.freeInsurance => Icons.shield_outlined,
      PowerType.peek => Icons.visibility,
      PowerType.secondChance => Icons.replay,
      PowerType.zeroShield => Icons.exposure_zero,
      PowerType.freeCommission => Icons.percent,
      PowerType.safetyNet => Icons.health_and_safety_outlined,
    };

Color powerColor(PowerType t) => switch (t) {
      PowerType.freeSplit => const Color(0xFF8E5CFF),
      PowerType.freeDouble => const Color(0xFFF5C451),
      PowerType.freeInsurance => const Color(0xFF3BC9DB),
      PowerType.peek => const Color(0xFFED4163),
      PowerType.secondChance => const Color(0xFF00E701),
      PowerType.zeroShield => const Color(0xFF2FBF71),
      PowerType.freeCommission => const Color(0xFFE0A44A),
      PowerType.safetyNet => const Color(0xFF5C9DFF),
    };

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final offers = ref.watch(powerOffersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.shopTitle), actions: const [BalancePill()]),
      body: AsyncBody(
        value: offers,
        builder: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l.shopIntro, style: TextStyle(color: context.palette.textMuted)),
            const SizedBox(height: 12),
            const RewardedAdTile(),
            const SizedBox(height: 12),
            for (final o in list) ...[
              _PowerTile(offer: o),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _PowerTile extends ConsumerWidget {
  const _PowerTile({required this.offer});
  final PowerOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final (name, desc) = powerCopy(l, offer.type);
    final color = powerColor(offer.type);
    return Panel(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.5)!]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12)],
            ),
            child: Icon(powerIcon(offer.type), color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(l.shopOwned(offer.owned), style: TextStyle(fontSize: 11.5, color: context.palette.textMuted, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: Key('buy-${offer.type.name}'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(shopRepositoryProvider).buy(offer.type, idempotencyKey: newIdempotencyKey());
                messenger.showSnackBar(SnackBar(content: Text(l.shopBought(name))));
              } on Object catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
              }
            },
            child: Text(context.money(offer.priceCents)),
          ),
        ],
      ),
    );
  }
}

/// Result of [PowersSheet] meaning "no power" (null = dismissed).
const kDisarmPower = 'disarm';

/// Bottom sheet at the table: pick one owned power for this hand. Pops with
/// the chosen [PowerType] (or null). [usable] says which powers can apply
/// now; [usedThisHand] disables everything (one power per hand).
class PowersSheet extends ConsumerWidget {
  const PowersSheet({super.key, this.armed, this.usedThisHand, this.usable});
  final PowerType? armed;
  final PowerType? usedThisHand;
  final bool Function(PowerType)? usable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final offers = ref.watch(powerOffersProvider).value ?? const [];
    final used = usedThisHand;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.powersSheetTitle, style: Theme.of(context).textTheme.titleMedium),
            Text(
              used != null ? l.tablePowerUsed(powerCopy(l, used).$1) : '${l.powersSheetHint} ${l.tablePowerHint}',
              style: TextStyle(color: context.palette.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final o in offers)
              ListTile(
                key: Key('power-${o.type.name}'),
                enabled: used == null && o.owned > 0 && (usable?.call(o.type) ?? true),
                selected: armed == o.type,
                leading: Icon(powerIcon(o.type), color: powerColor(o.type)),
                title: Text(powerCopy(l, o.type).$1),
                subtitle: Text(powerCopy(l, o.type).$2, style: const TextStyle(fontSize: 11.5)),
                trailing: Text('×${o.owned}', style: const TextStyle(fontWeight: FontWeight.w800)),
                onTap: () => Navigator.of(context).pop(o.type),
              ),
            if (armed != null)
              TextButton(
                key: const Key('power-disarm'),
                onPressed: () => Navigator.of(context).pop(kDisarmPower),
                child: Text(l.tablePowerNone),
              ),
            TextButton.icon(
              key: const Key('power-shop'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopScreen()));
              },
              icon: const Icon(Icons.storefront_outlined),
              label: Text(l.tablePowerShop),
            ),
          ],
        ),
      ),
    );
  }
}


/// "Watch an ad, get 5 $" (server-capped by `claimAdReward`).
class RewardedAdTile extends ConsumerWidget {
  const RewardedAdTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final now = ref.watch(clockProvider)();
    final state = ref.watch(adStateProvider).value ?? const AdState();
    final left = state.remainingAt(now);
    return Panel(
      child: Row(
        children: [
          Icon(Icons.ondemand_video, color: context.palette.gold, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.walletWatchAd(context.money(Backend.adRewardCents)), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(l.adRewardsLeft(left), style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
              ],
            ),
          ),
          FilledButton.tonal(
            key: const Key('shop-rewarded-ad'),
            onPressed: left == 0
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final cents = await showRewardedAd(context);
                    if (cents != null) {
                      messenger.showSnackBar(SnackBar(content: Text(l.adRewardCredited(context.mounted ? context.money(cents) : '$cents'))));
                    }
                  },
            child: const Icon(Icons.play_arrow),
          ),
        ],
      ),
    );
  }
}