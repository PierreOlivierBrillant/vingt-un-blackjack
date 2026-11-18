import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/card_style.dart';
import '../../domain/cards.dart';
import '../../l10n/gen/app_localizations.dart';
import '../cards/card_painters.dart';

String faceName(AppLocalizations l, CardFaceStyle f) => switch (f) {
      CardFaceStyle.classic => l.faceClassic,
      CardFaceStyle.fourColor => l.faceFourColor,
      CardFaceStyle.neon => l.faceNeon,
    };

String backName(AppLocalizations l, CardBackDesign b) => switch (b) {
      CardBackDesign.lattice => l.backLattice,
      CardBackDesign.stripes => l.backStripes,
      CardBackDesign.chevron => l.backChevron,
      CardBackDesign.dots => l.backDots,
      CardBackDesign.sunburst => l.backSunburst,
    };

String feltName(AppLocalizations l, FeltColor f) => switch (f) {
      FeltColor.green => l.feltGreen,
      FeltColor.navy => l.feltNavy,
      FeltColor.crimson => l.feltCrimson,
      FeltColor.purple => l.feltPurple,
      FeltColor.charcoal => l.feltCharcoal,
    };

class CustomizeScreen extends ConsumerStatefulWidget {
  const CustomizeScreen({super.key});

  @override
  ConsumerState<CustomizeScreen> createState() => _CustomizeScreenState();
}

class _CustomizeScreenState extends ConsumerState<CustomizeScreen> {
  CardStyle? _draft;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final equipped = ref.watch(equippedStyleProvider).value ?? const CardStyle();
    final style = _draft ?? equipped;
    final dirty = _draft != null && _draft != equipped;
    void set(CardStyle s) => setState(() => _draft = s);

    return Scaffold(
      appBar: AppBar(title: Text(l.customizeTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(padding: const EdgeInsets.all(16), child: CardStylePreview(style: style)),
          SectionHeader(l.customizeFaces, icon: Icons.style),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in CardFaceStyle.values)
                  ChoiceChip(
                    key: Key('face-${f.name}'),
                    label: Text(faceName(l, f)),
                    selected: style.face == f,
                    onSelected: (_) => set(style.copyWith(face: f)),
                  ),
              ],
            ),
          ),
          SectionHeader(l.customizeBacks, icon: Icons.grid_on),
          SizedBox(
            height: 112,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: CardBackDesign.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final b = CardBackDesign.values[i];
                final selected = style.back == b;
                return GestureDetector(
                  key: Key('back-${b.name}'),
                  onTap: () => set(style.copyWith(back: b)),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: PlayingCardView(card: null, faceUp: false, style: style.copyWith(back: b), width: 54),
                      ),
                      const SizedBox(height: 2),
                      Text(backName(l, b), style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                );
              },
            ),
          ),
          SectionHeader(l.customizeBackColor, icon: Icons.palette_outlined),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < kCardBackColors.length; i++)
                  _Swatch(
                    key: Key('color-$i'),
                    color: kCardBackColors[i],
                    selected: style.backColorIndex == i,
                    onTap: () => set(style.copyWith(backColorIndex: i)),
                  ),
              ],
            ),
          ),
          SectionHeader(l.customizeFelt, icon: Icons.table_bar_outlined),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final f in FeltColor.values)
                  Tooltip(
                    message: feltName(l, f),
                    child: _Swatch(
                      key: Key('felt-${f.name}'),
                      color: f.light,
                      selected: style.felt == f,
                      onTap: () => set(style.copyWith(felt: f)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            key: const Key('customize-save'),
            onPressed: dirty
                ? () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await ref.read(cosmeticsRepositoryProvider).equip(style, idempotencyKey: newIdempotencyKey());
                    setState(() => _draft = null);
                    messenger.showSnackBar(SnackBar(content: Text(l.customizeSaved)));
                  }
                : null,
            icon: const Icon(Icons.check),
            label: Text(dirty ? l.customizeEquip : l.customizeEquipped),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({super.key, required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : context.palette.border, width: selected ? 3 : 1),
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
      ),
    );
  }
}

/// Live preview: a fan of faces + a back on the chosen felt.
class CardStylePreview extends StatelessWidget {
  const CardStylePreview({super.key, required this.style});
  final CardStyle style;

  static const _hand = [
    PlayingCard(Rank.ace, Suit.spades),
    PlayingCard(Rank.king, Suit.hearts),
    PlayingCard(Rank.queen, Suit.diamonds),
    PlayingCard(Rank.seven, Suit.clubs),
  ];

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.7,
      child: Container(
        key: const Key('style-preview'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: RadialGradient(colors: [style.felt.light, style.felt.dark], radius: 0.9),
          border: Border.all(color: const Color(0xFF3A2115), width: 6),
        ),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth * 0.17;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < _hand.length; i++)
                Transform.translate(
                  offset: Offset((i - 1.5) * w * 0.62 - w * 0.55, (i - 1.5).abs() * 6),
                  child: Transform.rotate(
                    angle: (i - 1.5) * 0.14,
                    child: PlayingCardView(card: _hand[i], style: style, width: w),
                  ),
                ),
              Transform.translate(
                offset: Offset(box.maxWidth * 0.3, 0),
                child: Transform.rotate(
                  angle: 0.12,
                  child: PlayingCardView(card: null, faceUp: false, style: style, width: w),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
