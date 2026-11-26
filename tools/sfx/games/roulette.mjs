// Sons de la ROULETTE (groupe « roulette », quota dans ../quotas.json). PROPRIÉTAIRE : implémenteur roulette.
// Mode d'emploi : ../catalog.mjs. Régénérer : node tools/sfx/generate.mjs --group roulette
// (puis --check). Côté Dart, déclarer chaque son dans app/lib/features/games/roulette/roulette_sounds.dart
// (GameSfx('roulette_…', durée en ms, …)) : le test app/test/unit/sound_test.dart vérifie la correspondance.
// Idées (PLAN_SPRINT2.md) : cylindre qui tourne (boucle 22 kHz), bille qui roule puis rebondit sur les
// frettes, « Rien ne va plus », râteau, dolly posé sur le numéro gagnant.
import * as I from '../instruments.mjs';
import { catalog, HI } from '../catalog.mjs';

export const { SOUNDS, def } = catalog('roulette');

// Exemple : la bille frappe une frette (à jouer en rafale décroissante quand elle se pose).
def('roulette_ball_tick', { sr: HI, dur: 0.16, peak: -8, cat: 'Roulette', use: 'Exemple : la bille heurte une frette du cylindre (tic métallique court).' }, (c) =>
  I.chipClink(c.sr, c.r, { f0: 3600, dur: c.dur, tight: 0.6, rattle: 0.3 }),
);
