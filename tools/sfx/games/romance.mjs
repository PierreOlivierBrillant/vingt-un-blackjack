// Sons du RENDEZ-VOUS (groupe « romance », quota dans ../quotas.json). PROPRIÉTAIRE : implémenteur Rendez-vous.
// Mode d'emploi : ../catalog.mjs. Régénérer : node tools/sfx/generate.mjs --group romance
// Côté Dart : app/lib/features/romance/romance_sounds.dart (GameSfx('romance_…', ms)).
// Idées : texte qui s'affiche (tic doux), choix validé, palier d'affinité, cadeau offert, ambiances de
// lieux en boucle (22 kHz !), fondu au noir de la finale.
import * as I from '../instruments.mjs';
import { catalog, HI } from '../catalog.mjs';

export const { SOUNDS, def } = catalog('romance');

// Exemple : l'affinité monte (petit carillon ascendant).
def('romance_heart_up', { sr: HI, dur: 0.9, peak: -8, cat: 'Rendez-vous', use: 'Exemple : l\'affinité avec un personnage augmente (carillon doux ascendant).' }, (c) =>
  I.arp(c.sr, 'E5 G#5 B5', 0.08, { decay: 0.6, dur: c.dur, ratio: 2.0, index: 0.9 }),
);
