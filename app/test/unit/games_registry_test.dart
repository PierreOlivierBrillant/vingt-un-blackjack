// kGames registry: one entry per game (lobby order), screens chosen by the
// table id prefix, market questions / icons for every kind, powers grouped
// by POWER_GAME, cast and croupiers.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/characters/cast.dart';
import 'package:vingtun/core/characters/character_spec.dart';
import 'package:vingtun/domain/cosmetics.dart';
import 'package:vingtun/domain/games.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/features/games/baccarat/baccarat_screen.dart';
import 'package:vingtun/features/games/craps/craps_screen.dart';
import 'package:vingtun/features/games/holdem/holdem_buy_in.dart';
import 'package:vingtun/features/games/holdem/holdem_screen.dart';
import 'package:vingtun/features/games/registry.dart';
import 'package:vingtun/features/games/roulette/roulette_screen.dart';
import 'package:vingtun/features/table/table_screen.dart';
import 'package:vingtun/l10n/gen/app_localizations.dart';

import '../helpers.dart';

void main() {
  test('one entry per GameId, in GameId order, each pointing at its own game', () {
    expect(kGames.keys.toList(), GameId.values);
    for (final e in kGames.entries) {
      expect(e.value.id, e.key);
    }
    expect(gameUi(GameId.blackjack).playable, isTrue);
    expect(gameUi(GameId.blackjack).cardMedallion, '21');
    expect(gameUi(GameId.blackjack).geometry, isNull);
    for (final g in GameId.values.where((g) => g.isKernel)) {
      expect(gameUi(g).geometry!.seatCount, g.seats, reason: g.wire);
      expect(gameUi(g).sounds.every((s) => s.file.startsWith('${g.wire}_')), isTrue, reason: g.wire);
    }
  });

  test('/table/:id builds the screen of the id prefix (blackjack keeps TableScreen)', () {
    Type of(String id) => tableScreenFor(id).runtimeType;
    expect(of('sim-01'), TableScreen);
    expect(of('AbCdEf123'), TableScreen);
    expect(of('rl-sim-01'), RouletteScreen);
    expect(of('bc-x'), BaccaratScreen);
    expect(of('ho-x'), HoldemScreen);
    expect(of('cr-x'), CrapsScreen);
    final w = tableScreenFor('rl-p-r1000', privateCode: 'RL1000') as RouletteScreen;
    expect((w.tableId, w.privateCode), ('rl-p-r1000', 'RL1000'));
  });

  test('every market kind has a localized question and an icon from its game', () {
    for (final locale in const [Locale('fr'), Locale('en')]) {
      final l = lookupAppLocalizations(locale);
      for (final k in MarketKind.values) {
        final m = Market(id: 'm', kind: k, tableId: '${k.game.prefix ?? 'tbl'}-1', tableName: 'T', status: MarketStatus.open, priceYes: 0.5, subjectUsername: 'Ada');
        final ui = gameUi(m.gameOf);
        expect(m.gameOf, k.game);
        expect(ui.marketQuestion!(l, m), isNotEmpty, reason: '${k.name} ($locale)');
        expect(ui.marketIcon!(k), isNotNull);
      }
    }
  });

  test('powers grouped by POWER_GAME: every power in exactly one game, none in hold\'em', () {
    final grouped = [for (final ui in kGames.values) ...ui.powers];
    expect(grouped.toSet(), PowerType.values.toSet());
    expect(grouped.length, PowerType.values.length);
    expect(gameUi(GameId.holdem).powers, isEmpty);
    expect(gameUi(GameId.roulette).powers, [PowerType.zeroShield]);
  });

  test('l10n: names, taglines and rules of every game in both languages', () {
    for (final locale in const [Locale('fr'), Locale('en')]) {
      final l = lookupAppLocalizations(locale);
      for (final ui in kGames.values) {
        expect(ui.name(l), isNotEmpty);
        expect(ui.tagline(l), isNotEmpty);
        expect(ui.signText(l), isNotEmpty);
      }
    }
  });

  testWidgets('rules sheets of every game render (FR)', (tester) async {
    for (final ui in kGames.values) {
      await pumpScreen(tester, Builder(builder: (context) => SingleChildScrollView(child: ui.rules(context))));
      expect(tester.takeException(), isNull, reason: ui.id.wire);
    }
  });

  test("hold'em buy-in range: 40 to 100 big blinds per tier", () {
    expect(holdemBuyInRange('low'), (8000, 20000));
    expect(holdemBuyInRange('mid'), (40000, 100000));
    expect(holdemBuyInRange('high'), (200000, 500000));
  });

  group('cast', () {
    test('mirrors CHARACTER_IDS, croupiers match DEALER_OF, everyone an adult (24–38)', () {
      expect([for (final c in Cast.all) c.id], kCharacterIds);
      expect([for (final c in Cast.all) if (c.role == CharacterRole.dealer) c.id], kDealerCharacterIds);
      for (final g in GameId.values) {
        expect(Cast.dealerOf(g).id, g.dealerCharacterId);
      }
      for (final c in Cast.all) {
        expect(c.age, inInclusiveRange(24, 38), reason: c.id);
        expect(c.name, isNotEmpty);
      }
      expect(Cast.of('alex').pronoun, CharacterPronoun.they);
      expect(Cast.of('nobody').role, CharacterRole.player, reason: 'unknown ids never throw');
    });

    test('the look vocabulary: 8 hairstyles, 8 expressions, every outfit and hairstyle used by the cast or available', () {
      expect(HairStyle.values.length, 8);
      expect(CharacterExpression.values.length, 8);
      expect({for (final c in Cast.all) c.id}.length, 9);
      expect({for (final c in Cast.all) c.hairStyle}.length, greaterThanOrEqualTo(7));
    });
  });
}
