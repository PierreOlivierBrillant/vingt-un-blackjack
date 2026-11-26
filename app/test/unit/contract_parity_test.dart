// Cross-language contract (Sprint 2): firebase/functions/test/golden/contract.json
// is written by the backend test test/unit/contract.test.ts from the real
// TypeScript constants; every Dart mirror must match it exactly.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/data/server_errors.dart';
import 'package:vingtun/domain/backend_constants.dart';
import 'package:vingtun/domain/cosmetics.dart';
import 'package:vingtun/domain/game_table.dart';
import 'package:vingtun/domain/games.dart';
import 'package:vingtun/domain/models.dart';

Map<String, Object?> loadContract() {
  // `flutter test` runs from app/.
  final f = File('../firebase/functions/test/golden/contract.json');
  return jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
}

List<String> _strings(Object? v) => [for (final x in v! as List) x as String];

void main() {
  final c = loadContract();

  test('kernel constants mirror GAME_PHASES, GAME_TIMING, caps and GAME_RANK_POINTS', () {
    expect(GamePhase.values.map((p) => p.name).toList(), _strings(c['gamePhases']));
    expect(c['gameTiming'], {
      'bettingMs': GameTiming.bettingMs,
      'decisionMs': GameTiming.decisionMs,
      'settledMs': GameTiming.settledMs,
      'botMinMs': GameTiming.botMinMs,
      'botMaxMs': GameTiming.botMaxMs,
    });
    expect(c['gameMissedRoundsLimit'], GameTiming.missedRoundsLimit);
    expect(c['gameEventsCap'], GameTiming.eventsCap);
    expect(c['gameRankPoints'], {'bigWin': GameRankPoints.bigWin, 'win': GameRankPoints.win, 'lose': GameRankPoints.lose, 'none': 0});
    expect(c['rankPointsDailyCapPerGame'], GameRankPoints.dailyCapPerGame);
  });

  test('ServerReason mirrors ERROR_REASONS (same order)', () {
    expect(ServerReason.values.map((r) => r.name).toList(), _strings(c['errorReasons']));
  });

  test('PowerType mirrors POWER_IDS, POWER_GAME and prices', () {
    expect(PowerType.values.map((p) => p.name).toList(), _strings(c['powerIds']));
    final game = c['powerGame']! as Map<String, Object?>;
    final prices = c['powerPricesCents']! as Map<String, Object?>;
    for (final p in PowerType.values) {
      expect(p.game.wire, game[p.name], reason: p.name);
      expect(p.priceCents, prices[p.name], reason: p.name);
    }
  });

  test('MarketKind mirrors MARKET_KINDS, series kinds and liquidity', () {
    expect(MarketKind.values.map((k) => k.name).toList(), _strings(c['marketKinds']));
    expect(MarketKind.values.where((k) => k.isSeries).map((k) => k.name).toSet(), _strings(c['seriesMarketKinds']).toSet());
    final b = c['marketLiquidity']! as Map<String, Object?>;
    for (final k in MarketKind.values) {
      expect(Backend.marketLiquidity[k], (b[k.name]! as num).toDouble(), reason: k.name);
    }
  });

  test('LedgerKind mirrors LEDGER_TYPES', () {
    expect(LedgerKind.values.map((k) => k.name).toList(), _strings(c['ledgerTypes']));
  });

  test('GameId mirrors ALL_GAMES, prefixes and seats', () {
    expect(GameId.values.map((g) => g.wire).toList(), _strings(c['games']));
    final prefix = c['gamePrefix']! as Map<String, Object?>;
    final seats = c['gameSeats']! as Map<String, Object?>;
    final dealer = c['dealerOf']! as Map<String, Object?>;
    for (final g in GameId.values) {
      expect(g.dealerCharacterId, dealer[g.wire], reason: g.wire);
      if (!g.isKernel) continue;
      expect(g.prefix, prefix[g.wire], reason: g.wire);
      expect(g.seats, seats[g.wire], reason: g.wire);
      expect(gameOfTableId('${g.prefix}-abc'), g);
    }
    expect(gameOfTableId('sim-01'), GameId.blackjack);
    expect(gameOfTableId('AbCdEf123'), GameId.blackjack);
  });

  test('cosmetics and characters mirror the TypeScript catalog', () {
    expect(kCharacterIds, _strings(c['characters']));
    final cat = c['cosmetics']! as Map<String, Object?>;
    expect(kCosmetics.keys.toSet(), cat.keys.toSet());
    for (final e in kCosmetics.entries) {
      final ts = cat[e.key]! as Map<String, Object?>;
      expect(e.value.slot.name, ts['slot'], reason: e.key);
      expect(e.value.free, ts['free'], reason: e.key);
    }
  });
}
