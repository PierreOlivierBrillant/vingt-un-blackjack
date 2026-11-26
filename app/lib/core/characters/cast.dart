/// The 9 characters of the Rendez-vous meta (`CHARACTER_IDS` of
/// `firebase/functions/src/shared/romance.ts`, mirrored by `kCharacterIds`):
/// 5 croupiers (one per game, `DEALER_OF`) and 4 regulars of the casino.
/// Every character is an adult (24–38), written PG-13 (PLAN_SPRINT2.md).
///
/// Looks only: names are proper nouns (same in every language); roles and
/// story texts are localized by the Rendez-vous part of the app.
/// Lucas is today's blackjack croupier (`dealer_painters.dart`); his spec
/// matches that look so phase D can move his head onto [CharacterPainter].
library;

import 'package:flutter/painting.dart';

import '../../domain/games.dart';
import 'character_spec.dart';

abstract final class Cast {
  static const lucas = CharacterSpec(
    id: 'lucas',
    name: 'Lucas',
    age: 32,
    pronoun: CharacterPronoun.he,
    role: CharacterRole.dealer,
    skin: Color(0xFFE2AE8A),
    hair: Color(0xFF2B1D16),
    hairStyle: HairStyle.sidePart,
    eyes: Color(0xFF3B2A1E),
    outfit: Outfit.dealerVest,
    outfitPrimary: Color(0xFF14202B),
    outfitSecondary: Color(0xFFF4F4F2),
    outfitAccent: Color(0xFFB3123A),
    accessories: {Accessory.bowTie, Accessory.nameTag},
    lips: Color(0xFF8C3B2E),
    medallionColor: Color(0xFF0B6B3A),
  );

  static const camille = CharacterSpec(
    id: 'camille',
    name: 'Camille',
    age: 27,
    pronoun: CharacterPronoun.she,
    role: CharacterRole.dealer,
    skin: Color(0xFFF1C7A8),
    hair: Color(0xFF8E3B1F),
    hairStyle: HairStyle.ponytail,
    eyes: Color(0xFF2F6B4F),
    outfit: Outfit.dealerDress,
    outfitPrimary: Color(0xFF0E5A3A),
    outfitSecondary: Color(0xFFF6F1E7),
    outfitAccent: Color(0xFFE0C068),
    accessories: {Accessory.earrings, Accessory.nameTag},
    lips: Color(0xFFC0505A),
    freckles: true,
    faceWidth: 0.95,
    medallionColor: Color(0xFF7A1424),
  );

  static const ines = CharacterSpec(
    id: 'ines',
    name: 'Inès',
    age: 30,
    pronoun: CharacterPronoun.she,
    role: CharacterRole.dealer,
    skin: Color(0xFFB9825E),
    hair: Color(0xFF16100D),
    hairStyle: HairStyle.bun,
    eyes: Color(0xFF2A1A12),
    outfit: Outfit.dealerVest,
    outfitPrimary: Color(0xFF1B1B22),
    outfitSecondary: Color(0xFFF3EEE4),
    outfitAccent: Color(0xFFD9B55A),
    accessories: {Accessory.necklace, Accessory.earrings, Accessory.nameTag},
    lips: Color(0xFF9E3C46),
    faceWidth: 0.94,
    medallionColor: Color(0xFF3B2A12),
  );

  static const alex = CharacterSpec(
    id: 'alex',
    name: 'Alex',
    age: 29,
    pronoun: CharacterPronoun.they,
    role: CharacterRole.dealer,
    skin: Color(0xFFD6A27C),
    hair: Color(0xFF2E3F7A),
    hairStyle: HairStyle.undercut,
    eyes: Color(0xFF3A2F26),
    outfit: Outfit.dealerVest,
    outfitPrimary: Color(0xFF3A2463),
    outfitSecondary: Color(0xFFEDEFF5),
    outfitAccent: Color(0xFF8FD3FF),
    accessories: {Accessory.glasses, Accessory.necktie, Accessory.nameTag},
    lips: Color(0xFFA35A50),
    medallionColor: Color(0xFF151A2E),
  );

  static const marco = CharacterSpec(
    id: 'marco',
    name: 'Marco',
    age: 36,
    pronoun: CharacterPronoun.he,
    role: CharacterRole.dealer,
    skin: Color(0xFFCB8F66),
    hair: Color(0xFF1E1612),
    hairStyle: HairStyle.buzz,
    eyes: Color(0xFF3A2516),
    outfit: Outfit.dealerVest,
    outfitPrimary: Color(0xFF8A1C1C),
    outfitSecondary: Color(0xFFF7F4EE),
    outfitAccent: Color(0xFF111111),
    accessories: {Accessory.bowTie, Accessory.nameTag},
    lips: Color(0xFF8E4A3A),
    facialHair: FacialHair.stubble,
    faceWidth: 1.08,
    medallionColor: Color(0xFF6B4410),
  );

  static const jade = CharacterSpec(
    id: 'jade',
    name: 'Jade',
    age: 26,
    pronoun: CharacterPronoun.she,
    role: CharacterRole.regular,
    skin: Color(0xFFEDC9A6),
    hair: Color(0xFF111418),
    hairStyle: HairStyle.bob,
    eyes: Color(0xFF2B2018),
    outfit: Outfit.bartender,
    outfitPrimary: Color(0xFF22262B),
    outfitSecondary: Color(0xFF2F8F83),
    outfitAccent: Color(0xFFE8C66A),
    accessories: {Accessory.flower, Accessory.earrings},
    lips: Color(0xFFC2475E),
    faceWidth: 0.92,
    medallionColor: Color(0xFF0F5E57),
  );

  static const theo = CharacterSpec(
    id: 'theo',
    name: 'Théo',
    age: 33,
    pronoun: CharacterPronoun.he,
    role: CharacterRole.regular,
    skin: Color(0xFFF0CDB1),
    hair: Color(0xFFB98A4E),
    hairStyle: HairStyle.long,
    eyes: Color(0xFF3E6A8A),
    outfit: Outfit.tuxedo,
    outfitPrimary: Color(0xFF15161A),
    outfitSecondary: Color(0xFFF7F7F5),
    outfitAccent: Color(0xFF15161A),
    accessories: {Accessory.bowTie},
    lips: Color(0xFFB06A5E),
    faceWidth: 0.97,
    medallionColor: Color(0xFF2B2140),
  );

  static const nora = CharacterSpec(
    id: 'nora',
    name: 'Nora',
    age: 31,
    pronoun: CharacterPronoun.she,
    role: CharacterRole.regular,
    skin: Color(0xFF8D5B3E),
    hair: Color(0xFF1A110C),
    hairStyle: HairStyle.curly,
    eyes: Color(0xFF2A1A10),
    outfit: Outfit.magician,
    outfitPrimary: Color(0xFF4A1E6B),
    outfitSecondary: Color(0xFF14101A),
    outfitAccent: Color(0xFFE8C66A),
    accessories: {Accessory.topHat, Accessory.earrings},
    lips: Color(0xFF8E3046),
    medallionColor: Color(0xFF241238),
  );

  static const hugo = CharacterSpec(
    id: 'hugo',
    name: 'Hugo',
    age: 38,
    pronoun: CharacterPronoun.he,
    role: CharacterRole.regular,
    skin: Color(0xFFE6B996),
    hair: Color(0xFF5B5550),
    hairStyle: HairStyle.sidePart,
    eyes: Color(0xFF4A5A3A),
    outfit: Outfit.concierge,
    outfitPrimary: Color(0xFF1A2844),
    outfitSecondary: Color(0xFFF2F2EE),
    outfitAccent: Color(0xFFB8913A),
    accessories: {Accessory.necktie, Accessory.nameTag, Accessory.glasses},
    lips: Color(0xFF9A5A4C),
    facialHair: FacialHair.moustache,
    faceWidth: 1.04,
    medallionColor: Color(0xFF1A2844),
  );

  /// In `CHARACTER_IDS` order.
  static const all = <CharacterSpec>[lucas, camille, ines, alex, marco, jade, theo, nora, hugo];

  static final Map<String, CharacterSpec> byId = {for (final c in all) c.id: c};

  /// Character [id], or a neutral stand-in for an unknown id (never throws).
  static CharacterSpec of(String id) => byId[id] ?? _unknown(id);

  /// The croupier of [game] (`DEALER_OF`).
  static CharacterSpec dealerOf(GameId game) => of(game.dealerCharacterId);

  static CharacterSpec _unknown(String id) => CharacterSpec(
        id: id,
        name: id,
        age: 30,
        pronoun: CharacterPronoun.they,
        role: CharacterRole.player,
        skin: const Color(0xFFD9A884),
        hair: const Color(0xFF3A2A20),
        hairStyle: HairStyle.curly,
        eyes: const Color(0xFF3A2A20),
        outfit: Outfit.casual,
        outfitPrimary: const Color(0xFF34495E),
        outfitSecondary: const Color(0xFFECF0F1),
      );
}
