// Sons du TEXAS HOLD'EM (groupe « holdem », quota dans ../quotas.json). PROPRIÉTAIRE : implémenteur hold'em.
// Mode d'emploi : ../catalog.mjs. Régénérer : node tools/sfx/generate.mjs --group holdem
// Côté Dart : app/lib/features/games/holdem/holdem_sounds.dart (GameSfx('holdem_…', ms)).
// Idées : pitch d'une carte, brûlage, check (deux tapes sur le feutre), mises poussées au pot, tapis.
import * as I from '../instruments.mjs';
import { catalog, HI } from '../catalog.mjs';

export const { SOUNDS, def } = catalog('holdem');

// Exemple : « parole » — deux tapes du bout des doigts sur le feutre.
def('holdem_check_knock', { sr: HI, dur: 0.32, peak: -8, cat: 'Hold\'em', use: 'Exemple : un joueur dit « parole » en tapant deux fois sur la table.' }, (c) => {
  const out = new Float64Array(Math.round(c.sr * c.dur));
  const add = (x, t, g) => { const o = Math.round(t * c.sr); for (let i = 0; i < x.length && o + i < out.length; i++) out[o + i] += x[i] * g; };
  add(I.knock(c.sr, c.r, { f0: 210, dur: 0.14 }), 0, 1);
  add(I.knock(c.sr, c.r, { f0: 200, dur: 0.14 }), 0.13, 0.8);
  return out;
});
