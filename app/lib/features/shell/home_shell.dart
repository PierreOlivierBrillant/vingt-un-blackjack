import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/sfx.dart';
import '../../core/audio/sound_providers.dart';
import '../../core/widgets.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: AmbienceScope(zone: AmbienceZone.lobby, child: shell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          if (i != shell.currentIndex) context.sfx(Sfx.navSwoosh);
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.casino_outlined), selectedIcon: const Icon(Icons.casino), label: l.navLobby),
          NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights), label: l.navMarkets),
          NavigationDestination(
            key: const Key('nav-romance'),
            icon: const Icon(Icons.favorite_border),
            selectedIcon: const Icon(Icons.favorite),
            label: l.navRomance,
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l.navWallet,
          ),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: l.navProfile),
        ],
      ),
    );
  }
}
