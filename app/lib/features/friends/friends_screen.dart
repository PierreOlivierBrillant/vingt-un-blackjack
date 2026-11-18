import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ids.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/error_messages.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _search = TextEditingController();
  List<PlayerProfile> _results = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _onSearch(String q) async {
    final r = await ref.read(friendsRepositoryProvider).search(q);
    if (mounted) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final friends = ref.watch(friendsProvider);
    final requests = (ref.watch(friendRequestsProvider).value ?? const <FriendRequest>[]).where((r) => r.incoming).toList();
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
              decoration: InputDecoration(hintText: l.friendsSearchHint, prefixIcon: const Icon(Icons.search)),
            ),
          ),
          for (final f in _results)
            ListTile(
              leading: AppAvatar(name: f.username, hue: f.avatarHue, online: f.onlineAt(now)),
              title: Text(f.username),
              subtitle: Align(alignment: Alignment.centerLeft, child: TierBadge(f.rankTier)),
              trailing: FilledButton.tonal(
                onPressed: () => guarded(
                  () => repo.sendRequest(toUid: f.uid, idempotencyKey: newIdempotencyKey()),
                  success: l.friendsRequestSent(f.username),
                ),
                child: Text(l.friendsAdd),
              ),
            ),
          if (requests.isNotEmpty) ...[
            SectionHeader(l.friendsRequests(requests.length), icon: Icons.mail_outline),
            for (final r in requests)
              ListTile(
                leading: AppAvatar(name: r.fromUsername, hue: r.avatarHue),
                title: Text(r.fromUsername, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(l.friendsWantsToAdd),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l.decline,
                      onPressed: () => guarded(() => repo.respond(r.fromUid, accept: false, idempotencyKey: newIdempotencyKey())),
                      icon: Icon(Icons.close, color: p.loss),
                    ),
                    IconButton.filled(
                      tooltip: l.accept,
                      onPressed: () => guarded(() => repo.respond(r.fromUid, accept: true, idempotencyKey: newIdempotencyKey())),
                      icon: const Icon(Icons.check),
                    ),
                  ],
                ),
              ),
          ],
          SectionHeader(l.friendsList, icon: Icons.people_outline),
          AsyncBody(
            value: friends,
            builder: (list) => Column(
              children: [
                for (final f in list)
                  ListTile(
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
                    trailing: f.tableId == null
                        ? null
                        : OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 10)),
                            onPressed: () => context.push('/table/${f.tableId}'),
                            icon: const Icon(Icons.visibility_outlined, size: 18),
                            label: Text(l.watch),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
