import 'package:flutter/foundation.dart';

enum Suit {
  spades('♠'),
  hearts('♥'),
  diamonds('♦'),
  clubs('♣');

  const Suit(this.symbol);
  final String symbol;
  bool get isRed => this == hearts || this == diamonds;
}

enum Rank {
  ace('A', 11),
  two('2', 2),
  three('3', 3),
  four('4', 4),
  five('5', 5),
  six('6', 6),
  seven('7', 7),
  eight('8', 8),
  nine('9', 9),
  ten('10', 10),
  jack('J', 10),
  queen('Q', 10),
  king('K', 10);

  const Rank(this.label, this.value);
  final String label;

  /// Blackjack value (ace counted as 11, see [handTotal]).
  final int value;
  bool get isFace => this == jack || this == queen || this == king;
}

@immutable
class PlayingCard {
  const PlayingCard(this.rank, this.suit);

  /// Parses the compact wire format used by the backend: `"AS"`, `"10H"`,
  /// `"QD"`, `"7C"`.
  factory PlayingCard.parse(String code) {
    final c = code.trim().toUpperCase();
    if (c.length < 2) throw FormatException('bad card', code);
    final suit = switch (c[c.length - 1]) {
      'S' => Suit.spades,
      'H' => Suit.hearts,
      'D' => Suit.diamonds,
      'C' => Suit.clubs,
      _ => throw FormatException('bad suit', code),
    };
    final r = c.substring(0, c.length - 1);
    final rank = Rank.values.firstWhere(
      (x) => x.label == r || (r == 'T' && x == Rank.ten),
      orElse: () => throw FormatException('bad rank', code),
    );
    return PlayingCard(rank, suit);
  }

  final Rank rank;
  final Suit suit;

  String get code => '${rank.label}${suit.name[0].toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);

  @override
  String toString() => code;
}

@immutable
class HandTotal {
  const HandTotal(this.total, {required this.soft});
  final int total;
  final bool soft;
  bool get isBust => total > 21;
}

/// Display-only hand total (the server is authoritative). Aces count 11 while
/// that does not bust the hand.
HandTotal handTotal(Iterable<PlayingCard> cards) {
  var total = 0;
  var aces = 0;
  for (final c in cards) {
    total += c.rank.value;
    if (c.rank == Rank.ace) aces++;
  }
  while (total > 21 && aces > 0) {
    total -= 10;
    aces--;
  }
  return HandTotal(total, soft: aces > 0);
}

bool isNaturalBlackjack(List<PlayingCard> cards) =>
    cards.length == 2 && handTotal(cards).total == 21;
