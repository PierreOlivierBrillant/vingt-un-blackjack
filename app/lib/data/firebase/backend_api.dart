/// Firestore paths, query parameters and callable payloads of
/// `firebase/functions/src/shared/types.ts`, as pure functions so the exact
/// shapes are unit-tested without Firebase. Callable schemas are strict:
/// optional fields are OMITTED (never sent as null) and `requestId` is added
/// by `CallableClient`.
library;

import '../../domain/card_style.dart';
import '../../domain/game_table.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/table_state.dart';

abstract final class FirestorePaths {
  static const profiles = 'profiles';
  static const tables = 'tables';

  /// Sprint 2: kernel-driven tables (`shared/games/common.ts`).
  static const gameTables = 'gameTables';
  static String gameTable(String id) => 'gameTables/$id';
  static String gameBets(String tableId) => 'gameTables/$tableId/bets';
  static String gameBet(String tableId, String uid) => 'gameTables/$tableId/bets/$uid';
  static String gameHole(String tableId, String uid) => 'gameTables/$tableId/holes/$uid';
  static String gameRounds(String tableId) => 'gameTables/$tableId/rounds';

  /// Public document of ANY table id (blackjack `tables/…`, others `gameTables/…`).
  static String anyTable(String id) => gameOfTableId(id).isKernel ? gameTable(id) : table(id);
  static const markets = 'markets';
  static const feed = 'feed';
  static const friendRequests = 'friendRequests';
  static const friendships = 'friendships';

  static String profile(String uid) => 'profiles/$uid';
  static String userSettings(String uid) => 'users/$uid';
  static String wallet(String uid) => 'users/$uid/private/wallet';
  static String kyc(String uid) => 'users/$uid/private/kyc';
  static String suggestions(String uid) => 'users/$uid/private/suggestions';
  static String ads(String uid) => 'users/$uid/private/ads';
  static String ledger(String uid) => 'users/$uid/ledger';
  static String inventory(String uid) => 'users/$uid/inventory';
  static String positions(String uid) => 'users/$uid/positions';
  static String table(String id) => 'tables/$id';
  static String peek(String tableId, String uid) => 'tables/$tableId/peeks/$uid';
  static String hands(String tableId) => 'tables/$tableId/hands';
  static String market(String id) => 'markets/$id';
  static String trades(String marketId) => 'markets/$marketId/trades';
  static String priceHistory(String marketId) => 'markets/$marketId/priceHistory';
}

/// Query limits used by the repositories.
abstract final class QueryLimits {
  static const lobbyTables = 50;
  static const feed = 20;
  static const leaderboard = 50;
  static const openMarkets = 50;
  static const tableMarkets = 30;
  static const priceHistory = 300;
  static const search = 20;

  /// Firestore `whereIn` maximum per query.
  static const whereIn = 10;
}

/// Prefix-search bounds on `usernameLower`: `[lower, upper)`; null when the
/// prefix is empty.
(String, String)? usernamePrefixRange(String prefix) {
  final q = prefix.trim().toLowerCase();
  if (q.isEmpty) return null;
  return (q, '$q');
}

abstract final class Payloads {
  static Map<String, Object?> completeProfile({required String username, required String avatar, String? language}) =>
      {'username': username, 'avatar': avatar, 'language': ?language};

  static Map<String, Object?> submitKyc(KycSubmission s) => s.toRequest();
  static Map<String, Object?> submitKycRefresh() => {'refresh': true};

  static Map<String, Object?> deposit(int amountCents, PaymentMethod method) =>
      {'amountCents': amountCents, 'method': method.name};
  static Map<String, Object?> withdraw(int amountCents, PaymentMethod method) =>
      {'amountCents': amountCents, 'method': method.name};

  /// `stakeTier` is required by the schema even for joinCode (ignored there).
  static Map<String, Object?> joinMatchmaking(MatchMode mode, String stakeTier, String? code) => {
        'mode': mode.name,
        'stakeTier': stakeTier,
        if (mode == MatchMode.joinCode && code != null) 'code': code.trim().toUpperCase(),
      };

  static Map<String, Object?> leaveTable(String tableId) => {'tableId': tableId};
  static Map<String, Object?> pokeTable(String tableId) => {'tableId': tableId};

  static Map<String, Object?> placeBet(String tableId, int handNumber, int amountCents) =>
      {'tableId': tableId, 'handNumber': handNumber, 'amountCents': amountCents};

  static Map<String, Object?> act(
    String tableId,
    int handNumber,
    PlayerAction action, {
    int? handIndex,
    int? amountCents,
    PowerType? power,
  }) =>
      {
        'tableId': tableId,
        'handNumber': handNumber,
        'action': action.name,
        'handIndex': ?handIndex,
        'amountCents': ?amountCents,
        'power': ?power?.name,
      };

  static Map<String, Object?> buyPower(PowerType power, int quantity) => {'powerId': power.name, 'quantity': quantity};

  // ------------------------------------------------ Sprint 2: game tables --

  /// `GameJoinRequest`: [stakeTier] always sent (ignored for joinCode),
  /// [code] only for joinCode, [buyInCents] only when given (hold'em).
  static Map<String, Object?> gameJoin(GameId game, GameJoinMode mode, String stakeTier, {String? code, int? buyInCents}) {
    if (!game.isKernel) throw ArgumentError('gameJoin is for kernel-driven games, not ${game.wire}');
    return {
      'game': game.wire,
      'mode': mode.name,
      'stakeTier': stakeTier,
      if (mode == GameJoinMode.joinCode && code != null) 'code': code.trim().toUpperCase(),
      'buyInCents': ?buyInCents,
    };
  }

  static Map<String, Object?> gameLeave(String tableId) => {'tableId': tableId};
  static Map<String, Object?> gamePoke(String tableId) => {'tableId': tableId};

  /// `GameActionRequest`: [action] must carry its `type` (kernel or game action).
  static Map<String, Object?> gameAction(String tableId, int round, Map<String, Object?> action) {
    if (action['type'] is! String) throw ArgumentError('a game action needs a "type"');
    return {'tableId': tableId, 'round': round, 'action': action};
  }

  /// Kernel `setBets`: the WHOLE desired board (spotId → cents), power optional.
  static Map<String, Object?> setBetsAction(Map<String, int> bets, {PowerType? power}) =>
      {'type': 'setBets', 'bets': {for (final e in bets.entries) if (e.value > 0) e.key: e.value}, 'power': ?power?.name};

  static Map<String, Object?> tradeShares(
    String marketId,
    Outcome side,
    int shares, {
    required bool buy,
    int? maxCostCents,
    int? minProceedsCents,
  }) =>
      {
        'marketId': marketId,
        'side': side.name,
        'direction': buy ? 'buy' : 'sell',
        'shares': shares,
        if (buy) 'maxCostCents': ?maxCostCents,
        if (!buy) 'minProceedsCents': ?minProceedsCents,
      };

  /// Exactly one of [toUid] / [toUsername].
  static Map<String, Object?> friendRequest({String? toUid, String? toUsername}) {
    if ((toUid == null) == (toUsername == null)) {
      throw ArgumentError('friendRequest needs exactly one of toUid / toUsername');
    }
    return toUid != null ? {'toUid': toUid} : {'toUsername': toUsername!.trim()};
  }

  static Map<String, Object?> respondFriend(String fromUid, {required bool accept}) =>
      {'fromUid': fromUid, 'accept': accept};
  static Map<String, Object?> removeFriend(String friendUid) => {'friendUid': friendUid};
  static Map<String, Object?> claimAdReward(String adId) => {'adId': adId};
  static Map<String, Object?> equipCardStyle(CardStyle style) => style.toWire();

  /// Whitelisted direct write of `users/{uid}` (merge).
  static Map<String, Object?> userSettings({ThemePreference? theme, String? language, required DateTime now}) => {
        'theme': ?theme?.name,
        if (language == 'fr' || language == 'en') 'language': language,
        'updatedAtMs': now.millisecondsSinceEpoch,
      };
}
