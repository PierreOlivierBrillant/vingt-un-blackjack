import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sfx.dart';
import 'sound_service.dart';

/// [SoundService] on top of `audioplayers`.
///
/// * One-shots use low-latency players (Android `SoundPool`): each sound gets
///   a small ring of pre-decoded players, so the same sound can overlap
///   itself and many different sounds ring at once (polyphony).
/// * Loops (ambience, matchmaking sonar, drum roll) use media players in
///   `ReleaseMode.loop` (the WAVs have cross-faded seams).
/// * Audio focus is never requested: the app mixes with whatever else plays
///   and never pauses its own sounds.
/// Every platform error is swallowed (logged in debug): no sound, no crash.
class AudioplayersSoundService implements SoundService {
  AudioplayersSoundService();

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient, options: const {AVAudioSessionOptions.mixWithOthers}),
  );

  final _pools = <Sfx, _Pool>{};
  final _loops = <SoundChannel, _Loop>{};
  SoundLevels _levels = const SoundLevels();
  bool _suspended = false;
  bool _disposed = false;
  Future<void>? _init;

  Future<void> _ensureInit() => _init ??= () async {
        try {
          await AudioPlayer.global.setAudioContext(_context);
        } on Object catch (e) {
          _log('global context', e);
        }
      }();

  static int _ringSize(Sfx s) {
    if (s.group != s.file) return 2; // variants: each one twice
    return switch (s) {
      Sfx.chipBetPlace || Sfx.chipStack || Sfx.coinSingle || Sfx.uiTap || Sfx.timerTick || Sfx.timerUrgent => 3,
      Sfx.actionHit || Sfx.chipsPushWin || Sfx.chipsRakeLose || Sfx.priceTickUp || Sfx.priceTickDown => 2,
      _ => 1,
    };
  }

  _Pool _pool(Sfx sfx) => _pools.putIfAbsent(sfx, () {
        final pool = _Pool(sfx, _ringSize(sfx));
        pool.ready = _ensureInit().then((_) => pool.load()).catchError((Object e) => _log('load ${sfx.file}', e));
        return pool;
      });

  @override
  Future<void> preload(Iterable<Sfx> sounds) async {
    if (_disposed) return;
    await Future.wait([for (final s in sounds) if (!s.loop) _pool(s).ready]);
  }

  @override
  void play(Sfx sfx, {double volume = 1, double rate = 1}) {
    if (_disposed || _suspended || _levels.muted) return;
    final v = (volume * _levels.effects).clamp(0.0, 1.0);
    if (v <= 0) return;
    final pool = _pool(sfx);
    unawaited(pool.ready.then((_) => pool.play(v, rate)).catchError((Object e) => _log('play ${sfx.file}', e)));
  }

  @override
  void startLoop(SoundChannel channel, Sfx sfx, {double volume = 1}) {
    if (_disposed) return;
    final current = _loops[channel];
    if (current != null && current.sfx == sfx) {
      current.volume = volume;
      unawaited(_apply(channel, current));
      return;
    }
    if (current != null) unawaited(current.dispose());
    final loop = _Loop(sfx, volume);
    _loops[channel] = loop;
    unawaited(_ensureInit().then((_) => loop.load()).then((_) => _apply(channel, loop)).catchError((Object e) => _log('loop ${sfx.file}', e)));
  }

  @override
  void stopLoop(SoundChannel channel) {
    final loop = _loops.remove(channel);
    if (loop != null) unawaited(loop.dispose());
  }

  Future<void> _apply(SoundChannel channel, _Loop loop) async {
    if (_loops[channel] != loop) return;
    final v = (loop.volume * _levels.forChannel(channel)).clamp(0.0, 1.0);
    try {
      if (_suspended || v <= 0) {
        await loop.pause();
      } else {
        await loop.play(v);
      }
    } on Object catch (e) {
      _log('loop ${loop.sfx.file}', e);
    }
  }

  void _applyAll() {
    _loops.forEach((c, l) => unawaited(_apply(c, l)));
  }

  @override
  void setLevels(SoundLevels levels) {
    if (levels == _levels) return;
    _levels = levels;
    _applyAll();
  }

  @override
  void suspend() {
    _suspended = true;
    _applyAll();
    for (final p in _pools.values) {
      unawaited(p.stopAll());
    }
  }

  @override
  void resume() {
    _suspended = false;
    _applyAll();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final l in _loops.values) {
      await l.dispose();
    }
    _loops.clear();
    for (final p in _pools.values) {
      await p.dispose();
    }
    _pools.clear();
  }

  static void _log(String what, Object e) {
    if (kDebugMode) debugPrint('[sound] $what failed: $e');
  }
}

class _Pool {
  _Pool(this.sfx, this.size);
  final Sfx sfx;
  final int size;
  final _players = <AudioPlayer>[];
  final _volumes = <double>[];
  final _rates = <double>[];
  late Future<void> ready;
  var _next = 0;

  Future<void> load() async {
    for (var i = 0; i < size; i++) {
      final p = AudioPlayer();
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(AssetSource(sfx.audioplayersPath));
      _players.add(p);
      _volumes.add(-1);
      _rates.add(1);
    }
  }

  Future<void> play(double volume, double rate) async {
    if (_players.isEmpty) return;
    final i = _next;
    _next = (_next + 1) % _players.length;
    final p = _players[i];
    await p.stop();
    if (_volumes[i] != volume) {
      _volumes[i] = volume;
      await p.setVolume(volume);
    }
    if (_rates[i] != rate) {
      _rates[i] = rate;
      await p.setPlaybackRate(rate);
    }
    await p.resume();
  }

  Future<void> stopAll() async {
    for (final p in _players) {
      try {
        await p.stop();
      } on Object {
        // ignore
      }
    }
  }

  Future<void> dispose() async {
    for (final p in _players) {
      try {
        await p.dispose();
      } on Object {
        // ignore
      }
    }
    _players.clear();
  }
}

class _Loop {
  _Loop(this.sfx, this.volume);
  final Sfx sfx;
  double volume;
  AudioPlayer? _player;
  bool _playing = false;
  bool _disposed = false;

  Future<void> load() async {
    final p = AudioPlayer();
    _player = p;
    await p.setPlayerMode(PlayerMode.mediaPlayer);
    await p.setReleaseMode(ReleaseMode.loop);
    await p.setSource(AssetSource(sfx.audioplayersPath));
    if (_disposed) await p.dispose();
  }

  Future<void> play(double v) async {
    final p = _player;
    if (p == null || _disposed) return;
    await p.setVolume(v);
    if (!_playing) {
      _playing = true;
      await p.resume();
    }
  }

  Future<void> pause() async {
    final p = _player;
    if (p == null || _disposed || !_playing) return;
    _playing = false;
    await p.pause();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.stop();
        await p.dispose();
      } on Object {
        // ignore
      }
    }
  }
}
