/// Mirror of `firebase/functions/src/shared/games/common.ts` (Sprint 2): the
/// casino's games and how a table id tells which game it belongs to.
library;

/// Every game of the casino. [wire] is the backend `AnyGame` value.
enum GameId {
  blackjack('blackjack', prefix: null, seats: 5),
  roulette('roulette', prefix: 'rl', seats: 7),
  baccarat('baccarat', prefix: 'bc', seats: 7),
  holdem('holdem', prefix: 'ho', seats: 6),
  craps('craps', prefix: 'cr', seats: 8);

  const GameId(this.wire, {required this.prefix, required this.seats});

  final String wire;

  /// Table id prefix (`rl-…`); null for blackjack (its ids never contain a dash).
  final String? prefix;

  /// `GAME_SEATS` (blackjack: `SEATS_PER_TABLE`).
  final int seats;

  /// Kernel-driven game (stored in `gameTables`), i.e. everything but blackjack.
  bool get isKernel => this != GameId.blackjack;

  /// The croupier character of this game's tables (`DEALER_OF`).
  String get dealerCharacterId => switch (this) {
        GameId.blackjack => 'lucas',
        GameId.roulette => 'camille',
        GameId.baccarat => 'ines',
        GameId.holdem => 'alex',
        GameId.craps => 'marco',
      };

  static GameId? fromWire(Object? v) {
    for (final g in values) {
      if (g.wire == v) return g;
    }
    return null;
  }
}

final _prefix = RegExp(r'^(rl|bc|ho|cr)-');

/// `gameOfTableId`: the game a table id belongs to.
GameId gameOfTableId(String tableId) {
  final m = _prefix.firstMatch(tableId);
  if (m == null) return GameId.blackjack;
  return GameId.values.firstWhere((g) => g.prefix == m.group(1));
}
