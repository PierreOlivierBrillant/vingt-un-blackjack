// Sons du BACCARAT (groupe « baccarat », quota dans ../quotas.json). PROPRIÉTAIRE : implémenteur baccarat.
// Mode d'emploi : ../catalog.mjs. Régénérer : node tools/sfx/generate.mjs --group baccarat
// Côté Dart : app/lib/features/games/baccarat/baccarat_sounds.dart (GameSfx('baccarat_…', ms)).
// Idées : sortie du sabot, 3e carte posée en travers, squeeze (carte pliée lentement), annonce du gagnant.
import * as I from '../instruments.mjs';
import { catalog, HI } from '../catalog.mjs';

export const { SOUNDS, def } = catalog('baccarat');

// Exemple : une carte qu'on plie lentement (squeeze).
def('baccarat_card_squeeze', { sr: HI, dur: 0.6, peak: -8, cat: 'Baccarat', use: 'Exemple : squeeze, la carte est pliée lentement avant d\'être révélée.' }, (c) =>
  I.cardSlide(c.sr, c.r, { dur: c.dur, slide: 0.5, bright: 0.35, tap: 0, f0: 900 }),
);
