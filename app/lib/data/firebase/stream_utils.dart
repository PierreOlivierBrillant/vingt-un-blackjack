/// Small stream combinators (no rxdart dependency). Pure Dart, unit-tested.
library;

import 'dart:async';

/// For each value of [source], listens to `project(value)` and forwards its
/// events, cancelling the previous inner stream (rx `switchMap`). Errors of
/// both streams are forwarded without closing the result. Done when
/// [source] is done and the current inner stream is done.
Stream<R> switchMap<T, R>(Stream<T> source, Stream<R> Function(T value) project) {
  late final StreamController<R> out;
  StreamSubscription<T>? outer;
  StreamSubscription<R>? inner;
  var outerDone = false;
  var innerDone = true;

  void maybeClose() {
    if (outerDone && innerDone && !out.isClosed) unawaited(out.close());
  }

  out = StreamController<R>(
    onListen: () {
      outer = source.listen(
        (v) {
          final previous = inner;
          if (previous != null) unawaited(previous.cancel());
          innerDone = false;
          inner = project(v).listen(out.add, onError: out.addError, onDone: () {
            innerDone = true;
            maybeClose();
          });
        },
        onError: out.addError,
        onDone: () {
          outerDone = true;
          maybeClose();
        },
      );
    },
    onPause: () {
      outer?.pause();
      inner?.pause();
    },
    onResume: () {
      outer?.resume();
      inner?.resume();
    },
    onCancel: () async {
      await inner?.cancel();
      await outer?.cancel();
    },
  );
  return out.stream;
}

/// Emits the list of the latest values of [streams] once every stream has
/// emitted, then on each change. An empty list emits `[]` once and closes.
Stream<List<T>> combineLatestList<T>(List<Stream<T>> streams) {
  if (streams.isEmpty) return Stream.value(<T>[]);
  late final StreamController<List<T>> out;
  final subs = <StreamSubscription<T>>[];
  final values = List<T?>.filled(streams.length, null);
  final has = List<bool>.filled(streams.length, false);
  var done = 0;
  out = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < streams.length; i++) {
        subs.add(streams[i].listen(
          (v) {
            values[i] = v;
            has[i] = true;
            if (has.every((h) => h)) out.add(List<T>.from(values));
          },
          onError: out.addError,
          onDone: () {
            if (++done == streams.length && !out.isClosed) unawaited(out.close());
          },
        ));
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return out.stream;
}

/// Emits immediately, then every [period] (for time-dependent views such as
/// the 120 s "online" rule).
Stream<int> ticker(Duration period) async* {
  var i = 0;
  yield i;
  yield* Stream.periodic(period, (_) => ++i);
}

/// Splits [items] into chunks of at most [size] (Firestore `whereIn` ≤ 10).
List<List<T>> chunked<T>(List<T> items, [int size = 10]) => [
      for (var i = 0; i < items.length; i += size) items.sublist(i, i + size > items.length ? items.length : i + size),
    ];
