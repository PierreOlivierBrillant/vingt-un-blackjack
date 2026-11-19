/// Client-side "provably fair" verifier — exact port of
/// `firebase/functions/src/engine/fair.ts` + `rng.ts` (`seededRng`) +
/// `cards.ts` (`canonicalSort`, `buildShoe`), so a player can check a finished
/// hand without trusting the server:
///  1. `SHA-256(seed)` (hex of the UTF-8 seed string) equals the commitment
///     published before the hand;
///  2. the dealt cards are the prefix of `fairDealOrder(remainingBefore, seed)`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _ranks = 'A23456789TJQK';
const _suits = 'SHDC';

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// Canonical order: rank index, then suit index (wire codes, `T` = ten).
int compareWireCards(String a, String b) {
  final ra = _ranks.indexOf(a[0]);
  final rb = _ranks.indexOf(b[0]);
  if (ra != rb) return ra - rb;
  return _suits.indexOf(a[1]) - _suits.indexOf(b[1]);
}

List<String> buildWireShoe(int decks) => [
      for (var d = 0; d < decks; d++)
        for (final s in _suits.split(''))
          for (final r in _ranks.split('')) '$r$s',
    ];

/// SHA-256 counter-mode DRBG: block_i = SHA-256(seed + ":" + i), 32-bit
/// big-endian words, rejection sampling (no modulo bias).
class SeededRng {
  SeededRng(this.seed);
  final String seed;
  int _counter = 0;
  Uint8List _block = Uint8List(0);
  int _offset = 32;

  int _nextU32() {
    if (_offset >= 32) {
      _block = Uint8List.fromList(sha256.convert(utf8.encode('$seed:$_counter')).bytes);
      _counter++;
      _offset = 0;
    }
    final v = ByteData.sublistView(_block).getUint32(_offset);
    _offset += 4;
    return v;
  }

  /// Uniform integer in `[0, n)`, `1 <= n <= 2^32`.
  int nextInt(int n) {
    if (n < 1 || n > 0x100000000) throw RangeError('bad bound $n');
    if (n == 1) return 0;
    final limit = (0x100000000 ~/ n) * n;
    while (true) {
      final x = _nextU32();
      if (x < limit) return x % n;
    }
  }
}

/// In-place Fisher-Yates (Durstenfeld), same index sequence as the server.
List<T> shuffleInPlace<T>(List<T> a, SeededRng rng) {
  for (var i = a.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

List<String> fairDealOrder(List<String> remaining, String seed, {int decks = 6}) {
  final main = shuffleInPlace([...remaining]..sort(compareWireCards), SeededRng(seed));
  final refill = shuffleInPlace(buildWireShoe(decks), SeededRng('$seed:refill'));
  return [...main, ...refill];
}

enum FairnessVerdict { verified, badCommit, badOrder }

/// Verifies one hand's proof (`HandHistoryDoc.fairness`).
FairnessVerdict verifyFairness({
  required String commit,
  required String seed,
  required List<String> remainingBefore,
  required List<String> dealt,
  int decks = 6,
}) {
  if (sha256Hex(seed) != commit.toLowerCase()) return FairnessVerdict.badCommit;
  final order = fairDealOrder(remainingBefore, seed, decks: decks);
  if (dealt.length > order.length) return FairnessVerdict.badOrder;
  for (var i = 0; i < dealt.length; i++) {
    if (order[i] != dealt[i]) return FairnessVerdict.badOrder;
  }
  return FairnessVerdict.verified;
}
