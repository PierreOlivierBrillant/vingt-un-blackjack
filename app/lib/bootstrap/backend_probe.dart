import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_config.dart';

enum BackendService { auth, firestore, functions }

@immutable
class ProbeResult {
  const ProbeResult(this.service, {required this.ok, this.latency, this.error});

  final BackendService service;
  final bool ok;
  final Duration? latency;
  final String? error;
}

/// Checks that the emulators answer on a host. Abstract so tests (and the
/// widget tests of the "Serveur" screen) never touch the network.
abstract interface class BackendProbe {
  Future<List<ProbeResult>> probe(BackendConfig config);
}

/// Plain HTTP GET on each emulator root. Any HTTP status counts as "up":
/// only a refused/timed-out connection means the service is unreachable.
class HttpBackendProbe implements BackendProbe {
  HttpBackendProbe({this.timeout = const Duration(seconds: 3)});

  final Duration timeout;

  @override
  Future<List<ProbeResult>> probe(BackendConfig config) {
    final targets = {
      BackendService.auth: config.authUri,
      BackendService.firestore: config.firestoreUri,
      BackendService.functions: config.functionsUri,
    };
    return Future.wait(targets.entries.map((e) => _one(e.key, e.value)));
  }

  Future<ProbeResult> _one(BackendService service, Uri uri) async {
    final client = HttpClient()..connectionTimeout = timeout;
    final watch = Stopwatch()..start();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return ProbeResult(service, ok: true, latency: watch.elapsed);
    } on Object catch (e) {
      return ProbeResult(service, ok: false, error: e.runtimeType.toString());
    } finally {
      client.close(force: true);
    }
  }
}

final backendProbeProvider = Provider<BackendProbe>((ref) => HttpBackendProbe());
