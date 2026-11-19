import 'package:flutter/foundation.dart';

import 'sfx.dart';

/// Long-running sounds, one at a time per channel.
enum SoundChannel {
  /// Casino room tone (lobby + table).
  ambience,

  /// Sonar loop while matchmaking.
  matchmaking,

  /// Snare roll while the dealer draws.
  suspense,
}

/// Output levels (0..1) and the master switch.
@immutable
class SoundLevels {
  const SoundLevels({this.effects = 0.9, this.ambience = 0.45, this.muted = false});
  final double effects;
  final double ambience;
  final bool muted;

  double forChannel(SoundChannel c) => muted ? 0 : (c == SoundChannel.ambience ? ambience : effects);

  @override
  bool operator ==(Object other) =>
      other is SoundLevels && other.effects == effects && other.ambience == ambience && other.muted == muted;
  @override
  int get hashCode => Object.hash(effects, ambience, muted);
  @override
  String toString() => 'SoundLevels(fx $effects, amb $ambience${muted ? ', muted' : ''})';
}

/// Audio output, injected through Riverpod (`soundBackendProvider`).
///
/// Implementations must never throw from [play] / loop calls: a missing or
/// broken audio device simply plays nothing.
abstract interface class SoundService {
  /// Decodes these sounds ahead of time (low-latency playback later).
  Future<void> preload(Iterable<Sfx> sounds);

  /// Fire-and-forget one-shot. [volume] is relative (multiplied by the
  /// effects level); [rate] changes speed/pitch slightly when supported.
  void play(Sfx sfx, {double volume = 1, double rate = 1});

  /// Starts (or replaces) the loop of [channel]. Same sound → no restart.
  void startLoop(SoundChannel channel, Sfx sfx, {double volume = 1});

  void stopLoop(SoundChannel channel);

  void setLevels(SoundLevels levels);

  /// App went to the background: silence everything, remember the loops.
  void suspend();

  /// App back in the foreground: restart the remembered loops.
  void resume();

  Future<void> dispose();
}

/// Plays nothing (default backend: tests, platforms without audio).
class MutedSoundService implements SoundService {
  const MutedSoundService();
  @override
  Future<void> preload(Iterable<Sfx> sounds) async {}
  @override
  void play(Sfx sfx, {double volume = 1, double rate = 1}) {}
  @override
  void startLoop(SoundChannel channel, Sfx sfx, {double volume = 1}) {}
  @override
  void stopLoop(SoundChannel channel) {}
  @override
  void setLevels(SoundLevels levels) {}
  @override
  void suspend() {}
  @override
  void resume() {}
  @override
  Future<void> dispose() async {}
}

@immutable
class PlayedSound {
  const PlayedSound(this.sfx, this.volume, this.rate);
  final Sfx sfx;
  final double volume;
  final double rate;
  @override
  String toString() => '${sfx.name}${volume == 1 ? '' : '@${volume.toStringAsFixed(2)}'}';
}

/// Records everything (tests, debugging).
class RecordingSoundService implements SoundService {
  final played = <PlayedSound>[];
  final preloaded = <Sfx>{};
  final loops = <SoundChannel, Sfx>{};

  /// Every loop ever started, in order (`channel:sfx`, `channel:stop`).
  final loopLog = <String>[];
  SoundLevels levels = const SoundLevels();
  bool suspended = false;
  bool disposed = false;

  List<Sfx> get sounds => [for (final p in played) p.sfx];
  bool playedAny(Iterable<Sfx> s) => sounds.any(s.contains);
  int count(Sfx s) => sounds.where((x) => x == s).length;
  void clear() {
    played.clear();
    loopLog.clear();
  }

  @override
  Future<void> preload(Iterable<Sfx> sounds) async => preloaded.addAll(sounds);
  @override
  void play(Sfx sfx, {double volume = 1, double rate = 1}) => played.add(PlayedSound(sfx, volume, rate));
  @override
  void startLoop(SoundChannel channel, Sfx sfx, {double volume = 1}) {
    if (loops[channel] == sfx) return;
    loops[channel] = sfx;
    loopLog.add('${channel.name}:${sfx.name}');
  }

  @override
  void stopLoop(SoundChannel channel) {
    if (loops.remove(channel) != null) loopLog.add('${channel.name}:stop');
  }

  @override
  void setLevels(SoundLevels levels) => this.levels = levels;
  @override
  void suspend() => suspended = true;
  @override
  void resume() => suspended = false;
  @override
  Future<void> dispose() async => disposed = true;
}

/// Anti-fatigue decorator in front of the real output:
///  * per-sound (or per variant group) minimum interval ([Sfx.cooldownMs]);
///  * no pile of fanfares: while a jackpot rings, lesser fanfares are
///    dropped; at most [maxFanfares] fanfares / jackpots ring together (a
///    fanfare "rings" for 70 % of its length, the tail may overlap);
///  * a cap on simultaneous voices: beyond [maxVoices], only fanfares pass;
///  * everything is dropped while muted or suspended (loops are kept and
///    resumed by the backend).
class SoundGovernor implements SoundService {
  SoundGovernor(this.inner, {DateTime Function()? now, this.maxVoices = 10, this.maxFanfares = 2})
      : _now = now ?? DateTime.now;

  final SoundService inner;
  final DateTime Function() _now;
  final int maxVoices;
  final int maxFanfares;

  final _lastByGroup = <String, DateTime>{};
  final _voices = <DateTime>[]; // end times of the one-shots still ringing
  final _fanfares = <(DateTime, Sfx)>[]; // ringing fanfares (70 % end)
  SoundLevels _levels = const SoundLevels();
  bool _suspended = false;

  SoundLevels get levels => _levels;
  bool get suspended => _suspended;

  /// Number of sounds dropped by the rules above (diagnostics/tests).
  int dropped = 0;

  @override
  Future<void> preload(Iterable<Sfx> sounds) => inner.preload(sounds);

  @override
  void play(Sfx sfx, {double volume = 1, double rate = 1}) {
    if (_levels.muted || _suspended || _levels.effects <= 0 || volume <= 0) return;
    assert(!sfx.loop, '${sfx.name} is a loop: use startLoop');
    final now = _now();
    final last = _lastByGroup[sfx.group];
    if (last != null && now.difference(last).inMilliseconds < sfx.cooldownMs) {
      dropped++;
      return;
    }
    final big = sfx.tier.index >= SfxTier.fanfare.index;
    if (big) {
      _fanfares.removeWhere((f) => !f.$1.isAfter(now));
      final top = _fanfares.fold<int>(-1, (m, f) => f.$2.tier.index > m ? f.$2.tier.index : m);
      // Same fanfare still ringing, lesser than a jackpot, or no free slot.
      if (_fanfares.any((f) => f.$2 == sfx) || sfx.tier.index < top || _fanfares.length >= maxFanfares) {
        dropped++;
        return;
      }
    }
    _voices.removeWhere((e) => !e.isAfter(now));
    if (!big && _voices.length >= maxVoices) {
      dropped++;
      return;
    }
    _lastByGroup[sfx.group] = now;
    _voices.add(now.add(sfx.duration));
    if (big) _fanfares.add((now.add(Duration(milliseconds: (sfx.durationMs * 0.7).round())), sfx));
    inner.play(sfx, volume: volume.clamp(0.0, 1.0), rate: rate);
  }

  @override
  void startLoop(SoundChannel channel, Sfx sfx, {double volume = 1}) => inner.startLoop(channel, sfx, volume: volume);

  @override
  void stopLoop(SoundChannel channel) => inner.stopLoop(channel);

  @override
  void setLevels(SoundLevels levels) {
    _levels = levels;
    inner.setLevels(levels);
  }

  @override
  void suspend() {
    _suspended = true;
    inner.suspend();
  }

  @override
  void resume() {
    _suspended = false;
    inner.resume();
  }

  @override
  Future<void> dispose() => inner.dispose();
}
