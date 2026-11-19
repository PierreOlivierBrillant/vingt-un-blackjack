import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ids.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

/// Friends: username search, suggestions, requests received / sent, list
/// with online status and "watch their table".
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _search = TextEditingController();
  List<PlayerProfile> _results = const [];
  String? _searchError;
  Timer? _debounce;
  int _searchGen = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final gen = ++_searchGen;
    final l = context.l10n;
    try {
      final r = await ref.read(friendsRepositoryProvider).search(q);
      if (mounted && gen == _searchGen) {
        setState(() {
          _results = r;
          _searchError = null;
        });
      }
    } on Object catch (e) {
      if (mounted && gen == _searchGen) setState(() => _searchError = localizeError(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final friends = ref.watch(friendsProvider);
    final allRequests = ref.watch(friendRequestsProvider).value ?? const <FriendRequest>[];
    final incoming = allRequests.where((r) => r.incoming).toList();
    final outgoing = allRequests.where((r) => !r.incoming).toList();
    final friendIds = {for (final f in friends.value ?? const <Friend>[]) f.uid};
    final pendingIds = {for (final r in allRequests) r.incoming ? r.fromUid : r.toUid};
    final suggestions = [
      for (final s in ref.watch(friendSuggestionsProvider).value ?? const <PlayerProfile>[])
        if (!friendIds.contains(s.uid) && !pendingIds.contains(s.uid)) s,
    ];
    final repo = ref.read(friendsRepositoryProvider);
    final now = ref.watch(clockProvider)();
    Future<void> guarded(Future<void> Function() action, {String? success}) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
        if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
      } on Object catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(localizeError(l, e))));
      }
    }

    Widget addButton(PlayerProfile f) => FilledButton.tonal(
          key: Key('friend-add-${f.uid}'),
          onPressed: friendIds.contains(f.uid) || pendingIds.contains(f.uid)
              ? null
              : () => guarded(
                    () => repo.sendRequest(toUid: f.uid, idempotencyKey: newIdempotencyKey()),
                    success: l.friendsRequestSent(f.username),
                  ),
          child: Text(l.friendsAdd),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.friendsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              key: const Key('friends-search'),
              controller: _search,
              onChanged: _onSearch,
              autocorrect: false,
              decoration: InputDecoration(hintText: l.friendsSearchHint, prefixIcon: const Icon(Icons.search)),
            ),
          ),
          if (_searchError != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: InlineError(_searchError!)),
          for (final f in _results)
            ListTile(
              leading: AppAvatar(name: f.username, hue: f.avatarHue, online: f.onlineAt(now)),
              title: Text(f.username),
              subtitle: Align(alignment: Alignment.centerLeft, child: TierBadge(f.rankTier)),
              trailing: addButton(f),
            ),
          if (incoming.isNotEmpty) ...[
            SectionHeader(l.friendsRequests(incoming.length), icon: Icons.mail_outline),
            for (final r in incoming)
              ListTile(
                leading: AppAvatar(name: r.fromUsername, hue: r.avatarHue),
                title: Text(r.fromUsername, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(l.friendsWantsToAdd),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('friend-decline-${r.fromUid}'),
                      tooltip: l.decline,
                      onPressed: () => guarded(() => repo.respond(r.fromUid, accept: false, idempotencyKey: newIdempotencyKey())),
                      icon: Icon(Icons.close, color: p.loss),
                    ),
                    IconButton.filled(
                      key: Key('friend-accept-${r.fromUid}'),
                      tooltip: l.accept,
                      onPressed: () => guarded(
                        () => repo.respond(r.fromUid, accept: true, idempotencyKey: newIdempotencyKey()),
                        success: l.friendsAccepted(r.fromUsername),
                      ),
                      icon: const Icon(Icons.check),
                    ),
                  ],
                ),
              ),
          ],
          SectionHeader(l.friendsList, icon: Icons.people_outline),
          AsyncBody(
            value: friends,
            isEmpty: (list) => list.isEmpty,
            empty: EmptyState(icon: Icons.person_search_outlined, text: l.friendsEmpty),
            builder: (list) => Column(
              children: [
                for (final f in list)
                  ListTile(
                    key: Key('friend-${f.uid}'),
                    leading: AppAvatar(name: f.username, hue: f.avatarHue, online: f.online),
                    title: Row(
                      children: [
                        Flexible(child: Text(f.username, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 6),
                        TierBadge(f.tier),
                      ],
                    ),
                    subtitle: Text(
                      f.tableName != null ? l.friendsAtTable(f.tableName!) : (f.online ? l.online : l.offline),
                      style: TextStyle(color: f.online ? p.win : p.textMuted),
                    ),
                    onLongPress: () => _confirmRemove(f, guarded),
                    trailing: f.tableId == null
                        ? IconButton(
                            key: Key('friend-remove-${f.uid}'),
                            tooltip: l.friendsRemove,
                            onPressed: () => _confirmRemove(f, guarded),
                            icon: Icon(Icons.person_remove_outlined, color: p.textMuted),
                          )
                        : OutlinedButton.icon(
                            key: Key('friend-watch-${f.uid}'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10)),
                            onPressed: () => context.push('/table/${f.tableId}'),
                            icon: const Icon(Icons.visibility_outlined, size: 18),
                            label: Text(l.watch),
                          ),
                  ),
              ],
            ),
          ),
          if (outgoing.isNotEmpty) ...[
            SectionHeader(l.friendsSent, icon: Icons.outgoing_mail),
            for (final r in outgoing)
              ListTile(
                leading: AppAvatar(name: r.toUsername, hue: stableHash(r.toUsername) % 360),
                title: Text(r.toUsername),
                subtitle: Text(l.friendsPending, style: TextStyle(color: p.textMuted)),
              ),
          ],
          if (suggestions.isNotEmpty) ...[
            SectionHeader(l.friendsSuggestions, icon: Icons.auto_awesome_outlined),
            for (final s in suggestions)
              ListTile(
                leading: AppAvatar(name: s.username, hue: s.avatarHue, online: s.onlineAt(now)),
                title: Text(s.username),
                subtitle: Align(alignment: Alignment.centerLeft, child: TierBadge(s.rankTier)),
                trailing: addButton(s),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(Friend f, Future<void> Function(Future<void> Function(), {String? success}) guarded) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.friendsRemove),
        content: Text(f.username),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.back)),
          FilledButton(key: const Key('friend-remove-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(l.friendsRemove)),
        ],
      ),
    );
    if (ok == true && mounted) {
      await guarded(
        () => ref.read(friendsRepositoryProvider).remove(f.uid, idempotencyKey: newIdempotencyKey()),
        success: l.friendsRemoved(f.username),
      );
    }
  }
}
