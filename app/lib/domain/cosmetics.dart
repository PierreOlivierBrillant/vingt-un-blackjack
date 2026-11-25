/// Mirror of `firebase/functions/src/shared/cosmetics.ts` (Sprint 2). Free
/// items are the Sprint 1 card backs / faces / felts; exclusive ones are
/// unlocked by the Rendez-vous meta (`users/{uid}/unlocks/{id}`). A test
/// checks these ids against the TypeScript catalog.
library;

enum CosmeticSlot { cardBack, cardFace, felt, title }

/// Characters of the Rendez-vous meta (`CHARACTER_IDS`), in order.
const kCharacterIds = ['lucas', 'camille', 'ines', 'alex', 'marco', 'jade', 'theo', 'nora', 'hugo'];

/// The croupiers among [kCharacterIds] (`DEALER_CHARACTER_IDS`).
const kDealerCharacterIds = ['lucas', 'camille', 'ines', 'alex', 'marco'];

const kFreeCardBacks = ['classicBlue', 'classicRed', 'midnight', 'emerald', 'neonGrid', 'goldFiligree'];
const kFreeCardFaces = ['classic', 'fourColor', 'neon'];
const kFreeFelts = ['green', 'blue', 'red', 'purple', 'black'];

final kExclusiveCardBacks = List<String>.unmodifiable([for (final c in kCharacterIds) 'rv_${c}_back', 'duo_back']);
final kExclusiveFelts = List<String>.unmodifiable([for (final c in kCharacterIds) 'rv_${c}_felt', 'duo_felt']);
final kTitleIds = List<String>.unmodifiable([for (final c in kCharacterIds) 'rv_${c}_title', 'duo_title']);

class CosmeticInfo {
  const CosmeticInfo(this.slot, {required this.free});
  final CosmeticSlot slot;
  final bool free;
}

/// `COSMETICS`: id → slot and whether it is free.
final Map<String, CosmeticInfo> kCosmetics = Map.unmodifiable({
  for (final id in kFreeCardBacks) id: const CosmeticInfo(CosmeticSlot.cardBack, free: true),
  for (final id in kFreeCardFaces) id: const CosmeticInfo(CosmeticSlot.cardFace, free: true),
  for (final id in kFreeFelts) id: const CosmeticInfo(CosmeticSlot.felt, free: true),
  for (final id in kExclusiveCardBacks) id: const CosmeticInfo(CosmeticSlot.cardBack, free: false),
  for (final id in kExclusiveFelts) id: const CosmeticInfo(CosmeticSlot.felt, free: false),
  for (final id in kTitleIds) id: const CosmeticInfo(CosmeticSlot.title, free: false),
});

/// Character of an exclusive cosmetic id (`rv_<char>_<slot>`), else null.
String? characterOfCosmetic(String id) {
  final m = RegExp(r'^rv_([a-z]+)_(back|felt|title)$').firstMatch(id);
  return m?.group(1);
}
