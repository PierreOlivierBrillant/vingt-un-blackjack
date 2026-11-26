import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/error_messages.dart';
import '../settings/settings_controller.dart';
import 'app_sound_events.dart';
import 'sfx.dart';
import 'sound_service.dart';

/// Raw audio output. Muted by default (tests, headless runs); `main()`
/// overrides it with [AudioplayersSoundService]. Tests override it with a
/// [RecordingSoundService] to assert which sounds fire.
final soundBackendProvider = Provider<SoundService>((ref) => const MutedSoundService());

/// What the app plays through: the backend behind the anti-fatigue
/// [SoundGovernor], kept in sync with the settings (levels, master switch).
final soundProvider = Provider<SoundService>((ref) {
  final governor = SoundGovernor(ref.watch(soundBackendProvider));
  ref.listen<AppSettings>(settingsProvider, (_, s) => governor.setLevels(s.soundLevels), fireImmediately: true);
  return governor;
});

/// Random source for sound variants (overridable for deterministic tests).
final sfxRandomProvider = Provider<math.Random>((ref) => math.Random());

/// Haptic patterns, gated by the "vibrations" setting.
enum Haptic { selection, light, medium, heavy, celebration }

class Haptics {
  Haptics(this._enabled);
  final bool Function() _enabled;

  /// Every pattern fired (tests).
  final fired = <Haptic>[];

  void call(Haptic h) {
    if (!_enabled()) return;
    fired.add(h);
    if (fired.length > 64) fired.removeRange(0, 32);
    switch (h) {
      case Haptic.selection:
        HapticFeedback.selectionClick();
      case Haptic.light:
        HapticFeedback.lightImpact();
      case Haptic.medium:
        HapticFeedback.mediumImpact();
      case Haptic.heavy:
        HapticFeedback.heavyImpact();
      case Haptic.celebration:
        // Heavy thump + a longer buzz (no timers: safe in tests).
        HapticFeedback.heavyImpact();
        HapticFeedback.vibrate();
    }
  }
}

final hapticsProvider = Provider<Haptics>((ref) => Haptics(() => ref.read(settingsProvider).hapticsOn));

/// Where the casino room tone should be heard, and how loud (relative):
/// [volume] for the room (crowd, chips), [slotsVolume] for the distant slot
/// machines layered under it (loudest in the lobby: the casino floor).
enum AmbienceZone {
  lobby(0.55, 0.9),
  table(1.0, 0.35);

  const AmbienceZone(this.volume, this.slotsVolume);
  final double volume;
  final double slotsVolume;
}

/// Ref-counted ambience: screens enter/leave zones, the most recent zone
/// still entered wins; nothing entered → silence.
class AmbienceController {
  AmbienceController(this._sound);
  final SoundService _sound;
  final _stack = <(int, AmbienceZone)>[];
  var _next = 0;
  var _introPlayed = false;

  AmbienceZone? get current => _stack.isEmpty ? null : _stack.last.$2;

  /// Returns a token for [leave]. The first time the casino floor (lobby)
  /// opens in this app session, the "welcome to Las Vegas" jingle plays.
  int enter(AmbienceZone zone) {
    final token = _next++;
    _stack.add((token, zone));
    _apply();
    if (zone == AmbienceZone.lobby && !_introPlayed) {
      _introPlayed = true;
      _sound.play(Sfx.vegasIntro);
    }
    return token;
  }

  void leave(int token) {
    _stack.removeWhere((e) => e.$1 == token);
    _apply();
  }

  void _apply() {
    final z = current;
    if (z == null) {
      _sound.stopLoop(SoundChannel.ambience);
      _sound.stopLoop(SoundChannel.slots);
    } else {
      _sound.startLoop(SoundChannel.ambience, Sfx.ambienceCasinoLoop, volume: z.volume);
      _sound.startLoop(SoundChannel.slots, Sfx.ambienceSlotsLoop, volume: z.slotsVolume);
    }
  }
}

/// Recognises taps among raw pointer events (short, still presses), so that
/// EVERY tap in the app clicks like a casino chip, whatever widget got it.
class TapDetector {
  TapDetector(this.onTap);
  final void Function() onTap;
  final _downs = <int, (Offset, Duration)>{};

  static const maxMove = 18.0;
  static const maxPress = Duration(milliseconds: 450);

  void handle(PointerEvent e) {
    switch (e) {
      case PointerDownEvent():
        _downs[e.pointer] = (e.position, e.timeStamp);
      case PointerUpEvent():
        final d = _downs.remove(e.pointer);
        if (d != null && (e.position - d.$1).distance <= maxMove && e.timeStamp - d.$2 <= maxPress) onTap();
      case PointerCancelEvent():
        _downs.remove(e.pointer);
      default:
        break;
    }
  }
}

final ambienceProvider = Provider<AmbienceController>((ref) => AmbienceController(ref.watch(soundProvider)));

/// Sonar loop while [search] runs, then the "found" sting (or nothing on
/// failure: the error message brings its own sound).
Future<T> withMatchmakingSounds<T>(SoundService sound, Future<T> Function() search) async {
  sound.startLoop(SoundChannel.matchmaking, Sfx.matchmakingSearch, volume: 0.8);
  try {
    final r = await search();
    sound.stopLoop(SoundChannel.matchmaking);
    sound.play(Sfx.matchmakingFound);
    return r;
  } catch (_) {
    sound.stopLoop(SoundChannel.matchmaking);
    rethrow;
  }
}

/// Shortcuts for widgets.
extension SfxWidgetRef on WidgetRef {
  void sfx(SoundCue s, {double volume = 1}) => read(soundProvider).play(s, volume: volume);
}

extension SfxContext on BuildContext {
  /// Plays [s] from anywhere below the ProviderScope (no-op otherwise).
  void sfx(SoundCue s, {double volume = 1}) {
    try {
      ProviderScope.containerOf(this, listen: false).read(soundProvider).play(s, volume: volume);
    } on Object {
      // No ProviderScope (isolated widget tests): silent.
    }
  }
}

/// Keeps a zone of ambience on while this widget is mounted.
class AmbienceScope extends ConsumerStatefulWidget {
  const AmbienceScope({super.key, required this.zone, required this.child});
  final AmbienceZone zone;
  final Widget child;

  @override
  ConsumerState<AmbienceScope> createState() => _AmbienceScopeState();
}

class _AmbienceScopeState extends ConsumerState<AmbienceScope> {
  late final AmbienceController _ambience;
  late final int _token;

  @override
  void initState() {
    super.initState();
    _ambience = ref.read(ambienceProvider);
    _token = _ambience.enter(widget.zone);
  }

  @override
  void dispose() {
    _ambience.leave(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Pauses every sound while the app is in the background.
class AudioLifecycle extends ConsumerStatefulWidget {
  const AudioLifecycle({super.key, required this.child, this.dataEvents = true});
  final Widget child;

  /// Listen to the user's data streams for [AppSoundEvents].
  final bool dataEvents;

  @override
  ConsumerState<AudioLifecycle> createState() => _AudioLifecycleState();
}

class _AudioLifecycleState extends ConsumerState<AudioLifecycle> {
  late final AppLifecycleListener _listener;
  late final TapDetector _taps;
  bool _suspended = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: _onState);
    final sound = ref.read(soundProvider);
    // Las Vegas: every tap anywhere clicks like a chip (screens add their own sound on top).
    _taps = TapDetector(() => sound.play(Sfx.uiChipTap, volume: 0.7));
    GestureBinding.instance.pointerRouter.addGlobalRoute(_taps.handle);
    // Every error message shown to the user gets the "bonk".
    ErrorFeedback.hook = () => sound.play(Sfx.uiError);
    // Data-driven sounds (deposits, KYC, friends, markets, rank...).
    if (widget.dataEvents) ref.listenManual(appSoundEventsProvider, (_, _) {}, fireImmediately: true);
    // Decode the interface + table sounds early (low-latency pool).
    Future<void>.microtask(() async {
      await sound.preload(kUiSfx);
      await sound.preload(kTableSfx);
    });
  }

  void _onState(AppLifecycleState s) {
    final sound = ref.read(soundProvider);
    final background = s == AppLifecycleState.paused || s == AppLifecycleState.hidden || s == AppLifecycleState.detached;
    if (background && !_suspended) {
      _suspended = true;
      sound.suspend();
    } else if (s == AppLifecycleState.resumed && _suspended) {
      _suspended = false;
      sound.resume();
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_taps.handle);
    ErrorFeedback.hook = null;
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
