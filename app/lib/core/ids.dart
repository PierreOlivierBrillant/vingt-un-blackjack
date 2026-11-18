import 'dart:math';

final _rng = Random.secure();

/// Random 128-bit hex key sent with every mutating callable so the server can
/// de-duplicate retries.
String newIdempotencyKey() =>
    List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// Stable (cross-run) 32-bit FNV-1a hash, used to seed deterministic fake
/// data. `String.hashCode` is not guaranteed stable.
int stableHash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}
