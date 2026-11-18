/// Leaderboards and friends on `profiles`, `friendships`, `friendRequests`.
library;

import '../../domain/models.dart';
import '../../domain/wire.dart';
import '../repositories.dart';
import 'backend_api.dart';
import 'firebase_context.dart';
import 'firebase_errors.dart';
import 'stream_utils.dart';

/// Friend uids of [uid] from `friendships` where uids array-contains me.
Stream<List<Friendship>> _friendships(FirebaseContext ctx, String uid) => ctx
    .queryDocs(ctx.col(FirestorePaths.friendships).where('uids', arrayContains: uid))
    .map((docs) => [for (final (_, d) in docs) Friendship.fromDoc(d)]);

/// Ranks profiles for [scope] (pure; unit-tested).
List<LeaderboardEntry> rankProfiles(
  List<PlayerProfile> profiles,
  LeaderboardScope scope, {
  required String? myUid,
  required String currentWeekId,
  int limit = QueryLimits.leaderboard,
}) {
  int score(PlayerProfile p) =>
      scope == LeaderboardScope.weekly ? (p.weekId == currentWeekId ? p.weeklyPoints : 0) : p.rankPoints;
  final sorted = [...profiles]..sort((a, b) {
      final c = score(b).compareTo(score(a));
      return c != 0 ? c : a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });
  return [
    for (final (i, p) in sorted.take(limit).indexed)
      LeaderboardEntry.fromProfile(p, rank: i + 1, scope: scope, myUid: myUid, currentWeekId: currentWeekId),
  ];
}

class FirebaseLeaderboardRepository implements LeaderboardRepository {
  FirebaseLeaderboardRepository(this._ctx);
  final FirebaseContext _ctx;

  @override
  Stream<List<LeaderboardEntry>> watch(LeaderboardScope scope, {int limit = QueryLimits.leaderboard}) =>
      _ctx.perUser((uid) {
        final week = isoWeekId(_ctx.now());
        final profiles = _ctx.col(FirestorePaths.profiles);
        Stream<List<PlayerProfile>> source;
        switch (scope) {
          case LeaderboardScope.global:
            source = _ctx
                .queryDocs(profiles.orderBy('rankPoints', descending: true).limit(limit))
                .map((docs) => [for (final (id, d) in docs) PlayerProfile.fromDoc(d, id: id)]);
          case LeaderboardScope.weekly:
            source = _ctx
                .queryDocs(profiles.where('weekId', isEqualTo: week).orderBy('weeklyPoints', descending: true).limit(limit))
                .map((docs) => [for (final (id, d) in docs) PlayerProfile.fromDoc(d, id: id)]);
          case LeaderboardScope.friends:
            source = switchMap(
              _friendships(_ctx, uid),
              (fs) => _ctx.profilesOf([uid, for (final f in fs) ?f.otherUid(uid)]),
            );
        }
        return source.map((ps) => rankProfiles(ps, scope, myUid: uid, currentWeekId: week, limit: limit));
      }, const []);
}

class FirebaseFriendsRepository implements FriendsRepository {
  FirebaseFriendsRepository(this._ctx);
  final FirebaseContext _ctx;

  /// How often the 120 s "online" flags are re-evaluated.
  static const onlineRefresh = Duration(seconds: 30);

  @override
  Stream<List<Friend>> watchFriends() => _ctx.perUser(
        (uid) => switchMap(_friendships(_ctx, uid), (List<Friendship> fs) {
          final since = {for (final f in fs) ?f.otherUid(uid): f.since};
          return switchMap(_ctx.profilesOf(since.keys.toList()), (List<PlayerProfile> ps) async* {
            final names = await _ctx.tableNames.getAll(ps.map((p) => p.currentTableId).nonNulls);
            yield* ticker(onlineRefresh).map((_) {
              final now = _ctx.now();
              final friends = [
                for (final p in ps)
                  Friend.fromProfile(p, now: now, since: since[p.uid], tableName: names[p.currentTableId]),
              ]..sort((a, b) {
                  if (a.online != b.online) return a.online ? -1 : 1;
                  return a.username.toLowerCase().compareTo(b.username.toLowerCase());
                });
              return friends;
            });
          });
        }),
        const [],
      );

  @override
  Stream<List<FriendRequest>> watchRequests() => _ctx.perUser((uid) {
        Stream<List<FriendRequest>> q(String field) => _ctx
            .queryDocs(_ctx.col(FirestorePaths.friendRequests).where(field, isEqualTo: uid))
            .map((docs) => [for (final (_, d) in docs) FriendRequest.fromDoc(d, myUid: uid)]);
        return combineLatestList([q('toUid'), q('fromUid')]).map((l) {
          final all = [...l[0], ...l[1]]
            ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          return all;
        });
      }, const []);

  @override
  Stream<List<PlayerProfile>> watchSuggestions() => _ctx.perUser(
        (uid) => switchMap(
          _ctx.docData(FirestorePaths.suggestions(uid)).map((d) => d == null ? const <String>[] : FriendSuggestions.fromDoc(d).uids),
          (List<String> uids) => _ctx.profilesOf(uids),
        ),
        const [],
      );

  @override
  Future<List<PlayerProfile>> search(String usernamePrefix, {int limit = QueryLimits.search}) async {
    final range = usernamePrefixRange(usernamePrefix);
    if (range == null) return const [];
    final me = _ctx.uid;
    try {
      final snap = await _ctx
          .col(FirestorePaths.profiles)
          .where('usernameLower', isGreaterThanOrEqualTo: range.$1)
          .where('usernameLower', isLessThan: range.$2)
          .orderBy('usernameLower')
          .limit(limit + 1)
          .get();
      return [
        for (final d in snap.docs)
          if (d.id != me) PlayerProfile.fromDoc(jsonOf(d.data()), id: d.id),
      ].take(limit).toList();
    } on Object catch (e) {
      throw toRepositoryException(e);
    }
  }

  @override
  Future<FriendRequestOutcome> sendRequest({String? toUid, String? toUsername, required String idempotencyKey}) async =>
      FriendRequestOutcome.fromResponse(await _ctx.call(
          'friendRequest', Payloads.friendRequest(toUid: toUid, toUsername: toUsername),
          idempotencyKey: idempotencyKey));

  @override
  Future<bool> respond(String fromUid, {required bool accept, required String idempotencyKey}) async {
    final r = await _ctx.call('respondFriend', Payloads.respondFriend(fromUid, accept: accept), idempotencyKey: idempotencyKey);
    return r['status'] == 'accepted';
  }

  @override
  Future<void> remove(String friendUid, {required String idempotencyKey}) =>
      _ctx.call('removeFriend', Payloads.removeFriend(friendUid), idempotencyKey: idempotencyKey);
}
