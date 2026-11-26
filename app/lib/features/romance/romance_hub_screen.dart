/// The "Rendez-vous" tab (EMPTY HUB of phase A). OWNER: Rendez-vous implementer.
///
/// Today: the 9 characters of `core/characters/cast.dart` (croupiers and
/// regulars) as medallions, everyone "Inconnu·e", and the (disabled)
/// player-to-player dating card. TO PROVIDE (PLAN_SPRINT2.md « Méta
/// Rendez-vous »): affinity per character from `romance{op:'sync'}`
/// (folds table play), the visual-novel engine (scenes from
/// `assets/story/`, choices replayed by the server), gifts, dates, the
/// "Souvenirs" gallery, rewards; "Rencontres" (discover, matches, preset
/// lines) when `config/features.dating` is on. Your sub-pages go in
/// `romance_routes.dart` (mounted under `/romance` by the router); your
/// sounds in `romance_sounds.dart`; the table slot in `dealer_meta.dart`;
/// your texts in `l10n/parts/romance.*.arb`.
library;

import 'package:flutter/material.dart';

import '../../core/characters/cast.dart';
import '../../core/characters/character_spec.dart';
import '../../core/characters/character_view.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../l10n/gen/app_localizations.dart';

/// Role line of a cast member (localized).
String romanceRoleOf(AppLocalizations l, String id) => switch (id) {
      'lucas' => l.romanceRoleLucas,
      'camille' => l.romanceRoleCamille,
      'ines' => l.romanceRoleInes,
      'alex' => l.romanceRoleAlex,
      'marco' => l.romanceRoleMarco,
      'jade' => l.romanceRoleJade,
      'theo' => l.romanceRoleTheo,
      'nora' => l.romanceRoleNora,
      'hugo' => l.romanceRoleHugo,
      _ => id,
    };

class RomanceHubScreen extends StatelessWidget {
  const RomanceHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final dealers = Cast.all.where((c) => c.role == CharacterRole.dealer).toList();
    final regulars = Cast.all.where((c) => c.role == CharacterRole.regular).toList();
    return Scaffold(
      appBar: AppBar(title: Text(l.romanceHubTitle), actions: const [BalancePill()]),
      body: ListView(
        key: const Key('romance-hub'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l.romanceHubIntro, style: TextStyle(color: p.textMuted)),
          ),
          SectionHeader(l.romanceDealers, icon: Icons.style_outlined),
          _CastGrid(cast: dealers),
          SectionHeader(l.romanceRegulars, icon: Icons.local_bar_outlined),
          _CastGrid(cast: regulars),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Panel(
              key: const Key('romance-dating'),
              child: Row(
                children: [
                  Icon(Icons.favorite_border, color: p.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.romanceDatingTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(l.romanceDatingBody, style: TextStyle(color: p.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(l.romanceHubSoon, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _CastGrid extends StatelessWidget {
  const _CastGrid({required this.cast});
  final List<CharacterSpec> cast;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 520 ? 4 : 3;
        final w = (box.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in cast)
              SizedBox(
                width: w,
                child: Panel(
                  key: Key('character-${c.id}'),
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                  child: Column(
                    children: [
                      CharacterPortrait(spec: c, size: w * 0.62),
                      const SizedBox(height: 6),
                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        romanceRoleOf(l, c.id),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: p.surfaceSunken, borderRadius: BorderRadius.circular(6)),
                        child: Text(l.romanceTierStranger, style: TextStyle(color: p.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}
