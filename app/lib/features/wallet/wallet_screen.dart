import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'payment_sheet.dart';

// TODO(screens): dedicated labels for double/split/insurance/refund/
// marketBuy/marketSell (interim: closest existing strings).
String ledgerLabel(AppLocalizations l, LedgerKind k) => switch (k) {
      LedgerKind.welcomeBonus => l.ledgerWelcome,
      LedgerKind.deposit => l.ledgerDeposit,
      LedgerKind.withdrawal => l.ledgerWithdrawal,
      LedgerKind.bet || LedgerKind.double || LedgerKind.split || LedgerKind.insurance => l.ledgerBet,
      LedgerKind.payout => l.ledgerWin,
      LedgerKind.refund => l.ledgerPush,
      LedgerKind.powerPurchase => l.ledgerPower,
      LedgerKind.marketBuy || LedgerKind.marketSell => l.ledgerTrade,
      LedgerKind.marketPayout => l.ledgerMarketPayout,
      LedgerKind.adReward => l.ledgerAd,
    };

IconData ledgerIcon(LedgerKind k) => switch (k) {
      LedgerKind.welcomeBonus => Icons.card_giftcard,
      LedgerKind.deposit => Icons.south_west,
      LedgerKind.withdrawal => Icons.north_east,
      LedgerKind.bet => Icons.casino_outlined,
      LedgerKind.double => Icons.exposure_plus_2,
      LedgerKind.split => Icons.call_split,
      LedgerKind.insurance => Icons.shield_outlined,
      LedgerKind.payout => Icons.emoji_events_outlined,
      LedgerKind.refund => Icons.undo,
      LedgerKind.powerPurchase => Icons.bolt,
      LedgerKind.marketBuy || LedgerKind.marketSell => Icons.show_chart,
      LedgerKind.marketPayout => Icons.savings_outlined,
      LedgerKind.adReward => Icons.ondemand_video,
    };

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = context.palette;
    final wallet = ref.watch(walletProvider);
    final ledger = ref.watch(ledgerProvider);
    final user = ref.watch(authStateProvider).value;
    final now = ref.watch(clockProvider)();
    final kycOk = user?.kycStatus == KycStatus.verified;

    return Scaffold(
      appBar: AppBar(title: Text(l.walletTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 0), child: SimulationBanner()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AsyncBody(
              value: wallet,
              builder: (w) => _BalanceCard(wallet: w, kycOk: kycOk),
            ),
          ),
          if (!kycOk)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Panel(
                onTap: () => context.push('/kyc'),
                child: Row(
                  children: [
                    Icon(Icons.verified_user_outlined, color: p.warning),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.walletKycNeeded)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          SectionHeader(l.walletHistory, icon: Icons.receipt_long),
          AsyncBody(
            value: ledger,
            builder: (entries) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < entries.length; i++) ...[
                      if (i > 0) const Divider(indent: 56),
                      _LedgerRow(entry: entries[i], now: now),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet, required this.kycOk});
  final WalletSnapshot wallet;
  final bool kycOk;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.surfaceRaised, p.surface],
        ),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.walletBalance, style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              context.money(wallet.balanceCents),
              key: const Key('wallet-balance'),
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Stat(label: l.walletInPlay, value: context.money(wallet.lockedCents))),
              Expanded(
                child: _Stat(
                  label: l.walletDepositLimit,
                  value: '${context.money(wallet.depositedTodayCents, compact: true)} / ${context.money(wallet.depositLimitCents, compact: true)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('wallet-deposit'),
                  onPressed: kycOk ? () => showPaymentSheet(context, PaymentMode.deposit) : null,
                  icon: const Icon(Icons.add),
                  label: Text(l.deposit),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('wallet-withdraw'),
                  onPressed: kycOk ? () => showPaymentSheet(context, PaymentMode.withdraw) : null,
                  style: OutlinedButton.styleFrom(foregroundColor: cs.onSurface),
                  icon: const Icon(Icons.north_east),
                  label: Text(l.withdraw),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.palette.textMuted, fontSize: 11.5)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.now});
  final LedgerEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final positive = entry.amountCents > 0;
    final color = entry.amountCents == 0 ? p.textMuted : (positive ? p.win : Theme.of(context).colorScheme.onSurface);
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: p.surfaceRaised,
        child: Icon(ledgerIcon(entry.kind), size: 18, color: positive ? p.win : p.textMuted),
      ),
      title: Text(ledgerLabel(l, entry.kind), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [?entry.detail, relativeTime(context, entry.at, now)].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(context.money(entry.amountCents, signed: true), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          Text(context.money(entry.balanceAfterCents), style: TextStyle(color: p.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
