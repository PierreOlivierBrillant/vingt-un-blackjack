import 'dart:async';

/// Minimal behaviour-subject: replays the current value to each listener,
/// then every change.
class Live<T> {
  Live(this._value);
  T _value;
  final _ctrl = StreamController<T>.broadcast();

  T get value => _value;
  set value(T v) {
    _value = v;
    if (!_ctrl.isClosed) _ctrl.add(v);
  }

  Stream<T> get stream async* {
    yield _value;
    yield* _ctrl.stream;
  }

  Future<void> close() => _ctrl.close();
}
