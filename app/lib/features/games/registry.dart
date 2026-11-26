/// `kGames`: the casino's games, in lobby order. Each entry lives in its
/// game's folder (`<jeu>/<jeu>_game.dart`): a game implementer edits ONLY
/// that folder, never this file.
library;

import 'package:flutter/widgets.dart';

import '../../domain/games.dart';
import 'baccarat/baccarat_game.dart';
import 'blackjack_game.dart';
import 'craps/craps_game.dart';
import 'game_ui.dart';
import 'holdem/holdem_game.dart';
import 'roulette/roulette_game.dart';

export 'game_ui.dart';

/// One [GameUi] per [GameId], in [GameId.values] order.
final Map<GameId, GameUi> kGames = Map.unmodifiable({
  GameId.blackjack: blackjackGame,
  GameId.roulette: rouletteGame,
  GameId.baccarat: baccaratGame,
  GameId.holdem: holdemGame,
  GameId.craps: crapsGame,
});

GameUi gameUi(GameId game) => kGames[game]!;

/// `/table/:id`: the screen of the table's game (from the id prefix).
Widget tableScreenFor(String tableId, {String? privateCode}) => gameUi(gameOfTableId(tableId)).screen(tableId, privateCode);
