/// App-wide sounds driven by the DATA (not by buttons): whatever caused a
/// deposit, a KYC approval, a friend request or a market payout — this
/// device, the server, another player — the sound plays when the change
/// reaches the client. The first value of every stream is a baseline (no
/// sound for history loaded at start-up).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/models.dart';
import 'sfx.dart';
import 'sound_providers.dart';
import 'sound_service.dart';

class AppSoundEvents {
  AppSoundEvents(this.sound);
  final SoundService sound;

  Set<String>? _ledgerIds;
  KycStatus? _kyc;
  Set<String>? _incoming;
  Set<String>? _friends;
  Map<String, PositionStatus>? _positions;
  RankTier? _tier;
  int? _rank;

  static Sfx? ledgerSfx(LedgerKind k) => switch (k) {
        LedgerKind.welcomeBonus => Sfx.welcomeBonus,
        LedgerKind.deposit => Sfx.cashRegisterKaching,
        LedgerKind.withdrawal => Sfx.withdrawWhoosh,
        LedgerKind.powerPurchase => Sfx.powerBuy,
        LedgerKind.marketBuy => Sfx.tradeBuy,
        LedgerKind.marketSell => Sfx.tradeSell,
        LedgerKind.marketPayout => Sfx.marketResolvedWin,
        LedgerKind.adReward => Sfx.adReward,
        // Table money moves are voiced by the table itself.
        LedgerKind.bet ||
        LedgerKind.double ||
        LedgerKind.split ||
        LedgerKind.insurance ||
        LedgerKind.payout ||
        LedgerKind.refund =>
          null,
      };

  void onLedger(List<LedgerEntry> entries) {
    final ids = {for (final e in entries) e.id};
    final known = _ledgerIds;
    _ledgerIds = ids;
    if (known == null) return;
    final fresh = entries.where((e) => !known.contains(e.id)).toList()..sort((a, b) => a.at.compareTo(b.at));
    for (final e in fresh) {
      final s = ledgerSfx(e.kind);
      if (s == null) continue;
      sound.play(s);
      // Big money in: the coin rain on top of the bell.
      if (e.kind == LedgerKind.deposit || e.kind == LedgerKind.welcomeBonus) sound.play(Sfx.coinShower, volume: 0.8);
    }
  }

  void onKyc(KycStatus status) {
    final before = _kyc;
    _kyc = status;
    if (before != null && before != KycStatus.verified && status == KycStatus.verified) sound.play(Sfx.kycVerified);
    if (before != null && before != KycStatus.rejected && status == KycStatus.rejected) sound.play(Sfx.uiError);
  }

  void onRequests(List<FriendRequest> requests) {
    final ids = {for (final r in requests) if (r.incoming) r.fromUid};
    final known = _incoming;
    _incoming = ids;
    if (known != null && ids.difference(known).isNotEmpty) sound.play(Sfx.friendRequest);
  }

  void onFriends(List<Friend> friends) {
    final ids = {for (final f in friends) f.uid};
    final known = _friends;
    _friends = ids;
    if (known != null && ids.difference(known).isNotEmpty) sound.play(Sfx.friendAccept);
  }

  void onPositions(List<MarketPosition> positions) {
    final now = {for (final p in positions) p.marketId: p.status};
    final known = _positions;
    _positions = now;
    if (known == null) return;
    for (final MapEntry(:key, :value) in now.entries) {
      final was = known[key];
      if (was == value || was == null && value == PositionStatus.open) continue;
      // Wins are voiced by the market payout ledger entry.
      if (value == PositionStatus.lost) sound.play(Sfx.marketResolvedLose);
    }
  }

  void onProfile(PlayerProfile? p) {
    if (p == null) return;
    final before = _tier;
    _tier = p.rankTier;
    if (before != null && p.rankTier.index > before.index) sound.play(Sfx.rankUp);
  }

  /// [rank] is 1-based, null when outside the board.
  void onLeaderboardRank(int? rank) {
    final before = _rank;
    _rank = rank;
    if (before != null && rank != null && rank < before) sound.play(Sfx.leaderboardClimb);
  }
}

/// Wires [AppSoundEvents] to the signed-in user's streams. Kept alive by
/// `AudioLifecycle` (listened for the whole app life).
final appSoundEventsProvider = Provider<AppSoundEvents>((ref) {
  final events = AppSoundEvents(ref.watch(soundProvider));
  final user = ref.watch(authStateProvider).value;
  if (user == null || !user.profileComplete) return events;
  ref.listen(ledgerProvider, (_, n) {
    if (n.value != null) events.onLedger(n.value!);
  }, fireImmediately: true);
  ref.listen(kycStatusProvider, (_, n) {
    if (n.value != null) events.onKyc(n.value!);
  }, fireImmediately: true);
  ref.listen(friendRequestsProvider, (_, n) {
    if (n.value != null) events.onRequests(n.value!);
  }, fireImmediately: true);
  ref.listen(friendsProvider, (_, n) {
    if (n.value != null) events.onFriends(n.value!);
  }, fireImmediately: true);
  ref.listen(positionsProvider, (_, n) {
    if (n.value != null) events.onPositions(n.value!);
  }, fireImmediately: true);
  ref.listen(profileProvider(user.uid), (_, n) => events.onProfile(n.value), fireImmediately: true);
  ref.listen(leaderboardProvider(LeaderboardScope.global), (_, n) {
    final list = n.value;
    if (list == null) return;
    final me = list.where((e) => e.uid == user.uid).firstOrNull;
    events.onLeaderboardRank(me?.rank);
  }, fireImmediately: true);
  return events;
});
