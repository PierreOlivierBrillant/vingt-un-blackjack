import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/backend_config.dart';
import '../../bootstrap/backend_probe.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';

/// "Serveur": choose the host running the Firebase emulators (classroom
/// teacher's LAN IP, or 10.0.2.2 for the local machine), test it, save it.
class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  late final TextEditingController _host;
  final _form = GlobalKey<FormState>();
  bool _testing = false;
  List<ProbeResult>? _results;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: ref.read(backendConfigProvider).host);
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _results = null;
    });
    final results = await ref
        .read(backendProbeProvider)
        .probe(BackendConfig(host: _host.text.trim(), isCustom: true));
    if (mounted) {
      setState(() {
        _testing = false;
        _results = results;
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await ref.read(backendConfigProvider.notifier).setHost(_host.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.serverSaved)));
    }
  }

  Future<void> _reset() async {
    await ref.read(backendConfigProvider.notifier).resetToDefault();
    _host.text = ref.read(backendConfigProvider).host;
    setState(() => _results = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final config = ref.watch(backendConfigProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(l.serverTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l.serverIntro, style: TextStyle(color: p.textMuted)),
            const SizedBox(height: 16),
            Form(
              key: _form,
              child: TextFormField(
                key: const Key('server-host'),
                controller: _host,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.serverHostLabel,
                  hintText: '192.168.1.20',
                  prefixIcon: const Icon(Icons.dns_outlined),
                ),
                validator: (v) => isValidBackendHost(v ?? '') ? null : l.serverHostInvalid,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              config.isCustom ? l.serverCurrentCustom(config.host) : l.serverCurrentDefault(config.host),
              style: TextStyle(color: p.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('server-test'),
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check),
                    label: Text(l.serverTest),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('server-save'),
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l.save),
                  ),
                ),
              ],
            ),
            TextButton(onPressed: _reset, child: Text(l.serverReset(kDefaultBackendHost))),
            if (_results != null) ...[
              const SizedBox(height: 8),
              Panel(
                child: Column(
                  children: [
                    for (final r in _results!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          r.ok ? Icons.check_circle : Icons.cancel,
                          color: r.ok ? p.win : p.loss,
                        ),
                        title: Text(switch (r.service) {
                          BackendService.auth => 'Auth · ${EmulatorPorts.auth}',
                          BackendService.firestore => 'Firestore · ${EmulatorPorts.firestore}',
                          BackendService.functions => 'Functions · ${EmulatorPorts.functions}',
                        }),
                        trailing: Text(
                          r.ok ? '${r.latency?.inMilliseconds ?? 0} ms' : l.serverUnreachable,
                          style: TextStyle(color: r.ok ? p.win : p.loss, fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      _results!.every((r) => r.ok) ? l.serverAllOk : l.serverSomeDown,
                      style: TextStyle(color: p.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(l.serverHelpTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(l.serverHelpBody, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
