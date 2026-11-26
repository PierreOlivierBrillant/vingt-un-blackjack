/// What the app needs to know about ONE game wherever it shows it (lobby
/// selector, `/table/:id`, shop, markets, profile, ledger, fairness…).
///
/// Registry: `kGames` (`registry.dart`), one [GameUi] per [GameId]. Each
/// Sprint 2 game's entry is defined in ITS folder
/// (`lib/features/games/<jeu>/<jeu>_game.dart`), so a game implementer never
/// edits a shared file: screens, rules, sounds, market icons/questions,
/// profile counters and fairness checks all hang off this object.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/sfx.dart';
import '../../domain/fairness.dart';
import '../../domain/game_table.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../stage/stage_geometry.dart';

typedef L10nText = String Function(AppLocalizations l);

/// Builds the table screen of a table id (`?code=` → [privateCode]).
typedef GameScreenBuilder = Widget Function(String tableId, String? privateCode);

/// Local re-computation of a finished round's fairness proof.
typedef RoundVerifier = FairnessVerdict Function(GameRound round);

/// One line of the profile statistics (label, value).
typedef StatLine = (String label, String value);

@immutable
class GameUi {
  const GameUi({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.screen,
    required this.rules,
    this.playable = false,
    this.sign,
    this.cardMedallion = '21',
    this.geometry,
    this.sounds = const [],
    this.marketIcon,
    this.marketQuestion,
    this.roundSummary,
    this.verifyRound = verifyRoundCommit,
    this.statLines,
    this.pickBuyIn,
    this.routes = const [],
  });

  final GameId id;

  /// Display name ("Roulette").
  final L10nText name;

  /// One line under the name in the lobby selector / hero.
  final L10nText tagline;
  final IconData icon;

  /// Neon of the room, selector glow, chips of the markets filter.
  final Color accent;

  /// `/table/:id` of this game (blackjack: the Sprint 1 `TableScreen`).
  final GameScreenBuilder screen;

  /// Body of the rules sheet (scrollable column content).
  final WidgetBuilder rules;

  /// false = "coming soon": shown in the selector with a ribbon, its live
  /// tables can be WATCHED, but quick play / private tables are disabled.
  /// The game's implementer flips it to true when its table plays.
  final bool playable;

  /// Neon sign of the room (`CasinoBackdrop`), default the game name.
  final String? sign;

  /// Text of the card-back medallion at this game's tables ("21").
  final String cardMedallion;

  /// Logical layout of the stage (null for blackjack, which has its own).
  final StageGeometry? geometry;

  /// Every sound of the game's group (`tools/sfx/games/<jeu>.mjs`), checked
  /// by `test/unit/sound_test.dart`; one-shots are preloaded at the table.
  final List<GameSfx> sounds;

  /// Icon of a market card of this game (null kind = unknown to the client).
  final IconData Function(MarketKind? kind)? marketIcon;

  /// Localized question of a market of this game; null → the server text.
  final String? Function(AppLocalizations l, Market market)? marketQuestion;

  /// One-line summary of a finished round for the history sheet ("17 rouge").
  final String? Function(AppLocalizations l, GameRound round)? roundSummary;

  /// Fairness check of a finished round (default: commitment only).
  final RoundVerifier verifyRound;

  /// Extra profile lines from `gameStats[game].counters`.
  final List<StatLine> Function(AppLocalizations l, GameStats stats)? statLines;

  /// Hold'em: asks the buy-in before joining (null = cancelled). Called by
  /// the lobby with the tier's limits (`limits.extra`); null for bet-board games.
  final Future<int?> Function(BuildContext context, String stakeTier)? pickBuyIn;

  /// Extra root-level routes of the game (e.g. a demo), pushed above the tabs.
  final List<RouteBase> routes;

  String signText(AppLocalizations l) => sign ?? name(l).toUpperCase();

  /// Powers usable at this game's tables (`POWER_GAME`), shop order.
  List<PowerType> get powers => [for (final p in PowerType.values) if (p.game == id) p];
}

/// Default [RoundVerifier]: SHA-256(seed) must equal the published
/// commitment; card games with `remainingBefore`/`dealt` are re-dealt too.
FairnessVerdict verifyRoundCommit(GameRound round) {
  final f = round.fairness;
  if (f.seed.isEmpty || sha256Hex(f.seed) != f.commit.toLowerCase()) return FairnessVerdict.badCommit;
  final remaining = f.remainingBefore, dealt = f.dealt;
  if (remaining != null && dealt != null && remaining.isNotEmpty) {
    return verifyFairness(commit: f.commit, seed: f.seed, remainingBefore: remaining, dealt: dealt, decks: f.decks ?? 1);
  }
  return FairnessVerdict.verified;
}

/// Whether [round]'s verification covered the draw itself (not only the commitment).
bool verifiesDraw(GameRound round) => (round.fairness.dealt?.isNotEmpty ?? false);
