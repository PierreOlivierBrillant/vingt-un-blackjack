import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Fixed, public test values. They are display-only: the fields are
/// read-only and NOTHING from them is sent to the server (only amount +
/// method + idempotency key travel).
abstract final class SimulatedPaymentDetails {
  static const cardNumber = '4242 4242 4242 4242';
  static const cardExpiry = '12/34';
  static const cardCvc = '•••';
  static const cryptoAddress = 'sim1q-vingtun-0000-test-only';
  static const iban = 'FR76 0000 0000 0000 0000 SIMU';
}

enum PaymentMode { deposit, withdraw }


Future<void> showPaymentSheet(BuildContext context, PaymentMode mode) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PaymentSheet(mode: mode),
    );

class PaymentSheet extends ConsumerStatefulWidget {
  const PaymentSheet({super.key, required this.mode});
  final PaymentMode mode;

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  PaymentMethod _method = PaymentMethod.card;
  final _amount = TextEditingController(text: '50');
  bool _busy = false;
  String? _error;

  /// One key per sheet: a double tap or a retry is de-duplicated server-side.
  final _idempotencyKey = newIdempotencyKey();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final l = context.l10n;
    final cents = parseCents(_amount.text);
    if (cents == null || cents < 100) {
      setState(() => _error = l.paymentAmountInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(walletRepositoryProvider);
    try {
      if (widget.mode == PaymentMode.deposit) {
        await repo.deposit(amountCents: cents, method: _method, idempotencyKey: _idempotencyKey);
      } else {
        await repo.withdraw(amountCents: cents, method: _method, idempotencyKey: _idempotencyKey);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final text = widget.mode == PaymentMode.deposit
          ? l.depositDone(context.money(cents))
          : l.withdrawDone(context.money(cents));
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = localizeError(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final deposit = widget.mode == PaymentMode.deposit;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(deposit ? l.deposit : l.withdraw, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SimulationBanner(text: l.paymentSimulationBanner),
            const SizedBox(height: 14),
            SegmentedButton<PaymentMethod>(
              segments: [
                ButtonSegment(value: PaymentMethod.card, label: Text(l.methodCard), icon: const Icon(Icons.credit_card)),
                ButtonSegment(value: PaymentMethod.crypto, label: Text(l.methodCrypto), icon: const Icon(Icons.currency_bitcoin)),
                ButtonSegment(value: PaymentMethod.bankTransfer, label: Text(l.methodBank), icon: const Icon(Icons.account_balance)),
              ],
              selected: {_method},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 14),
            ..._methodFields(l),
            const SizedBox(height: 14),
            TextField(
              key: const Key('payment-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l.amount,
                suffixText: '\$',
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final v in const [10, 50, 100, 500])
                  ActionChip(
                    label: Text(context.money(v * 100, compact: true)),
                    onPressed: () => setState(() => _amount.text = '$v'),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: p.loss, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('payment-confirm'),
              onPressed: _busy ? null : _confirm,
              child: Text(deposit ? l.depositConfirm : l.withdrawConfirm),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _methodFields(AppLocalizations l) {
    InputDecoration deco(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.lock, size: 16),
          helperText: l.paymentTestValue,
        );
    return switch (_method) {
      PaymentMethod.card => [
          TextFormField(
            key: const Key('payment-card-number'),
            initialValue: SimulatedPaymentDetails.cardNumber,
            readOnly: true,
            enableInteractiveSelection: false,
            decoration: deco(l.cardNumber, Icons.credit_card),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: SimulatedPaymentDetails.cardExpiry,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  decoration: InputDecoration(labelText: l.cardExpiry, prefixIcon: const Icon(Icons.event)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: SimulatedPaymentDetails.cardCvc,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  decoration: InputDecoration(labelText: l.cardCvc, prefixIcon: const Icon(Icons.password)),
                ),
              ),
            ],
          ),
        ],
      PaymentMethod.crypto => [
          TextFormField(
            initialValue: SimulatedPaymentDetails.cryptoAddress,
            readOnly: true,
            enableInteractiveSelection: false,
            decoration: deco(l.cryptoAddress, Icons.qr_code_2),
          ),
        ],
      PaymentMethod.bankTransfer => [
          TextFormField(
            initialValue: SimulatedPaymentDetails.iban,
            readOnly: true,
            enableInteractiveSelection: false,
            decoration: deco(l.iban, Icons.account_balance),
          ),
        ],
    };
  }
}
