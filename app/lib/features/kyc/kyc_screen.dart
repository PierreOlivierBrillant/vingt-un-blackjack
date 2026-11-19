import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ids.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

enum _Step { form, scanning, review }

/// Simulated identity check. No photo is taken and no document leaves the
/// device: the "scan" is an animation; ONLY document type + birth date are
/// submitted (callable `submitKyc`; the name field stays on the device), and
/// the server refuses minors.
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key, this.scanDuration = const Duration(milliseconds: 3600)});
  final Duration scanDuration;

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> with SingleTickerProviderStateMixin {
  final _name = TextEditingController();
  IdDocumentType _doc = IdDocumentType.idCard;
  DateTime? _birth;
  _Step _step = _Step.form;
  KycStatus? _result;
  late final AnimationController _scan;
  String? _error;
  final _idempotencyKey = newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(vsync: this, duration: widget.scanDuration);
  }

  @override
  void dispose() {
    _scan.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _start() async {
    final l = context.l10n;
    if (_name.text.trim().length < 3 || _birth == null) {
      setState(() => _error = l.kycFormIncomplete);
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.scanning;
    });
    await _scan.forward(from: 0);
    if (!mounted) return;
    setState(() => _step = _Step.review);
    try {
      final state = await ref.read(kycRepositoryProvider).submit(
            KycSubmission(documentType: _doc, birthDate: _birth!),
            idempotencyKey: _idempotencyKey,
          );
      if (mounted) setState(() => _result = state.status);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _step = _Step.form;
          _error = localizeError(l, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.kycTitle)),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_step) {
            _Step.form => _form(context),
            _Step.scanning => _scanning(context),
            _Step.review => _review(context),
          },
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return ListView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.all(16),
      children: [
        SimulationBanner(text: l.kycSimulationBanner),
        const SizedBox(height: 16),
        Text(l.kycIntro, style: TextStyle(color: p.textMuted)),
        const SizedBox(height: 16),
        Text(l.kycDocType, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<IdDocumentType>(
          segments: [
            ButtonSegment(value: IdDocumentType.idCard, label: Text(l.kycIdCard)),
            ButtonSegment(value: IdDocumentType.passport, label: Text(l.kycPassport)),
            ButtonSegment(value: IdDocumentType.driverLicense, label: Text(l.kycLicense)),
          ],
          selected: {_doc},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _doc = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l.kycFullName, prefixIcon: const Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickBirth,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(labelText: l.kycBirthDate, prefixIcon: const Icon(Icons.cake_outlined)),
            child: Text(_birth == null ? l.kycChooseDate : DateFormat.yMMMd(context.lang).format(_birth!)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: p.loss, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('kyc-start'),
          onPressed: _start,
          icon: const Icon(Icons.document_scanner_outlined),
          label: Text(l.kycStartScan),
        ),
      ],
    );
  }

  Widget _scanning(BuildContext context) {
    final l = context.l10n;
    final steps = [l.kycStepEdges, l.kycStepMrz, l.kycStepFace, l.kycStepAge];
    return Padding(
      key: const ValueKey('scan'),
      padding: const EdgeInsets.all(20),
      child: AnimatedBuilder(
        animation: _scan,
        builder: (context, _) {
          final t = _scan.value;
          final current = (t * steps.length).floor().clamp(0, steps.length - 1);
          return Column(
            children: [
              Text(l.kycScanning, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 1.586, // ID-1 card format
                child: CustomPaint(painter: _ScanPainter(t, Theme.of(context).colorScheme.primary, context.palette)),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(value: t, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 16),
              for (var i = 0; i < steps.length; i++)
                ListTile(
                  dense: true,
                  leading: i < current || t >= 1
                      ? Icon(Icons.check_circle, color: context.palette.win)
                      : i == current
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.radio_button_unchecked, color: context.palette.textMuted),
                  title: Text(steps[i]),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _review(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    // The callable answers "pending"; the final decision arrives later on
    // `users/{uid}/private/kyc` (refresh scheduled by the repository).
    final live = ref.watch(kycStatusProvider).value;
    final r = live == KycStatus.verified || live == KycStatus.rejected ? live : _result;
    final (icon, color, title, body) = switch (r) {
      null || KycStatus.pending || KycStatus.none => (Icons.hourglass_top, p.warning, l.kycPending, l.kycPendingBody),
      KycStatus.verified => (Icons.verified, p.win, l.kycVerified, l.kycVerifiedBody),
      KycStatus.rejected => (Icons.block, p.loss, l.kycRejected, l.kycRejectedBody),
    };
    return Center(
      key: const ValueKey('review'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: color),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
            const SizedBox(height: 24),
            if (r == KycStatus.verified)
              FilledButton(onPressed: () => context.go('/wallet'), child: Text(l.kycGoToWallet)),
            if (r == KycStatus.rejected)
              OutlinedButton(onPressed: () => setState(() => _step = _Step.form), child: Text(l.back)),
            if (r == null || r == KycStatus.pending) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.t, this.accent, this.p);
  final double t;
  final Color accent;
  final AppPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    canvas.drawRRect(r, Paint()..color = p.surfaceRaised);
    // Generic ID silhouette (no real document is captured).
    final photo = Rect.fromLTWH(size.width * 0.06, size.height * 0.18, size.width * 0.26, size.height * 0.56);
    canvas.drawRRect(RRect.fromRectAndRadius(photo, const Radius.circular(8)), Paint()..color = p.border);
    canvas.drawCircle(photo.center - Offset(0, photo.height * 0.12), photo.width * 0.22, Paint()..color = p.textMuted.withValues(alpha: 0.5));
    canvas.drawOval(
      Rect.fromCenter(center: photo.bottomCenter - Offset(0, photo.height * 0.12), width: photo.width * 0.7, height: photo.height * 0.4),
      Paint()..color = p.textMuted.withValues(alpha: 0.5),
    );
    final line = Paint()..color = p.border;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.24 + i * 0.13);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.38, y, size.width * (0.5 - i * 0.07), size.height * 0.06), const Radius.circular(3)),
        line,
      );
    }
    // MRZ lines.
    for (var i = 0; i < 2; i++) {
      canvas.drawRect(Rect.fromLTWH(size.width * 0.06, size.height * (0.82 + i * 0.07), size.width * 0.88, size.height * 0.035), line);
    }
    // Corner brackets.
    final bracket = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const k = 26.0;
    for (final c in [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)]) {
      final sx = c.dx == 0 ? 1.0 : -1.0, sy = c.dy == 0 ? 1.0 : -1.0;
      canvas.drawLine(c + Offset(6 * sx, 6 * sy), c + Offset((6 + k) * sx, 6 * sy), bracket);
      canvas.drawLine(c + Offset(6 * sx, 6 * sy), c + Offset(6 * sx, (6 + k) * sy), bracket);
    }
    // Sweeping laser line with glow.
    final phase = (t * 3) % 1;
    final y = size.height * (phase < 0.5 ? phase * 2 : 2 - phase * 2);
    canvas.drawRect(
      Rect.fromLTWH(0, y - 18, size.width, 36),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0), accent.withValues(alpha: 0.35), accent.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, y - 18, size.width, 36)),
    );
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()
      ..color = accent
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.t != t;
}
