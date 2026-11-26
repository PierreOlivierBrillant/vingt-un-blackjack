// Sons du CRAPS (groupe « craps », quota dans ../quotas.json). PROPRIÉTAIRE : implémenteur craps.
// Mode d'emploi : ../catalog.mjs. Régénérer : node tools/sfx/generate.mjs --group craps
// Côté Dart : app/lib/features/games/craps/craps_sounds.dart (GameSfx('craps_…', ms)).
// Idées : dés secoués dans la main, rebonds sur le mur à pyramides, canne du stickman, palet ON/OFF.
import * as I from '../instruments.mjs';
import { catalog, HI } from '../catalog.mjs';

export const { SOUNDS, def } = catalog('craps');

// Exemple : deux dés secoués dans la main.
def('craps_dice_shake', { sr: HI, dur: 0.5, peak: -8, cat: 'Craps', use: 'Exemple : le lanceur secoue les deux dés dans sa main.' }, (c) => {
  const out = new Float64Array(Math.round(c.sr * c.dur));
  const add = (x, t, g) => { const o = Math.round(t * c.sr); for (let i = 0; i < x.length && o + i < out.length; i++) out[o + i] += x[i] * g; };
  for (let k = 0; k < 9; k++) {
    const t = 0.02 + k * 0.045 + c.r() * 0.012;
    add(I.woodblock(c.sr, c.r, { f: 2200 + c.r() * 900, dur: 0.05 }), t, 0.5 + 0.5 * c.r());
  }
  return out;
});
