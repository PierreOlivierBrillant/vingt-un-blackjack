/// Mirror of the server-enforced constants of
/// `firebase/functions/src/shared/types.ts` (section "Constants"). The server
/// is authoritative; the client only displays / pre-validates with these.
library;

import 'models.dart' show MarketKind, PowerType, RankTier;

abstract final class Backend {
  static const seatsPerTable = 5;
  static const decksPerShoe = 6;
  static const shoeSize = 312;
  static const cutCardRemaining = 78;
  static const maxHandsPerSeat = 4;

  /// `STAKE_TIERS` in order.
  static const stakeTiers = ['low', 'mid', 'high'];

  /// `STAKE_TIER_LIMITS`: tier id → (minBetCents, maxBetCents).
  static const stakeTierLimits = <String, (int, int)>{
    'low': (100, 10000),
    'mid': (500, 50000),
    'high': (2500, 250000),
  };

  // TIMING (ms).
  static const bettingMs = 20000;
  static const decisionMs = 20000;
  static const insuranceMs = 20000;
  static const settledMs = 6000;

  /// Call `pokeTable` when `now > deadline + pokeGraceMs` and nothing changed.
  /// Must exceed the server's DECISION_GRACE_MS (2 500 ms, human decisions):
  /// poking earlier is a no-op.
  static const decisionGraceMs = 2500;
  static const pokeGraceMs = decisionGraceMs + 500;

  /// `RANK_TIER_THRESHOLDS` (minimum rankPoints per tier).
  static const rankTierThresholds = <RankTier, int>{
    RankTier.bronze: 0,
    RankTier.silver: 500,
    RankTier.gold: 1500,
    RankTier.platinum: 3500,
    RankTier.diamond: 7000,
  };

  /// `RANK_POINTS` per settled seat-hand.
  static const rankPointsBlackjack = 15;
  static const rankPointsWin = 10;
  static const rankPointsPush = 2;
  static const rankPointsLose = -4;

  static const welcomeBonusCents = 100000;
  static const depositMinCents = 500;
  static const depositMaxCents = 100000;
  static const depositDailyCapCents = 500000;
  static const withdrawMinCents = 500;
  static const withdrawMaxCents = 500000;
  static const kycReviewMs = 3000;
  static const kycMinAgeYears = 18;

  /// `POWER_PRICES_CENTS`.
  static const powerPricesCents = <PowerType, int>{
    PowerType.freeSplit: 2000,
    PowerType.freeDouble: 2500,
    PowerType.freeInsurance: 1000,
    PowerType.peek: 3000,
    PowerType.secondChance: 4000,
  };
  static const powerMaxQuantityPerPurchase = 10;
  static const powerMaxInventory = 99;

  static const adRewardCents = 500;
  static const adRewardDailyMax = 10;
  static const adRewardCooldownMs = 30000;

  static const marketSharePayoutCents = 100;
  static const marketMaxSharesPerTrade = 1000;

  /// `MARKET_LIQUIDITY` (LMSR b, in shares).
  static const marketLiquidity = <MarketKind, double>{
    MarketKind.dealerBust: 60,
    MarketKind.playerWins: 60,
    MarketKind.natural: 60,
    MarketKind.shoeDealerBustRate: 200,
  };
  static const shoeBustRateThreshold = 0.28;

  /// A profile is "online" if `now - lastSeenAtMs < onlineWindow`.
  static const onlineWindow = Duration(milliseconds: 120000);

  /// Avatar ids "avatar01".."avatar24".
  static final avatarIds = List<String>.unmodifiable(
    List.generate(24, (i) => 'avatar${(i + 1).toString().padLeft(2, '0')}'),
  );

  /// Username rule of `completeProfile`: 3..16 chars [A-Za-z0-9_].
  static final usernamePattern = RegExp(r'^[A-Za-z0-9_]{3,16}$');

  /// Private table code: 6 chars [A-Z0-9] (case-insensitive).
  static final tableCodePattern = RegExp(r'^[A-Za-z0-9]{6}$');
}

/// Tier for [rankPoints] per `RANK_TIER_THRESHOLDS`.
RankTier rankTierForPoints(int rankPoints) {
  var tier = RankTier.bronze;
  for (final e in Backend.rankTierThresholds.entries) {
    if (rankPoints >= e.value) tier = e.key;
  }
  return tier;
}
