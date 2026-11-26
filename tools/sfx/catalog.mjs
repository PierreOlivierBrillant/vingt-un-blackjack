// Catalogue d'un groupe de sons (Sprint 2) : un fichier tools/sfx/games/<groupe>.mjs par jeu (+ romance).
//
//   import * as D from '../dsp.mjs';
//   import * as I from '../instruments.mjs';
//   import { catalog, HI, LO } from '../catalog.mjs';
//   export const { SOUNDS, def } = catalog('roulette');
//   def('roulette_ball_tick', { sr: HI, dur: 0.18, peak: -6, cat: 'Roulette', use: '…' }, (c) => I.woodblock(c.sr, c.r));
//
// Règles vérifiées ici (et par generate.mjs --check, et par app/test/unit/sound_test.dart) :
//  - chaque nom commence par '<groupe>_' et ne contient que [a-z0-9_] ;
//  - les boucles (loop: true) sont en 22 050 Hz (LO) : c'est ce qui tient dans le quota ;
//  - sr ∈ {HI, LO}, dur > 0, peak ≤ 0 dBFS.
// Le rendu reçoit { sr, dur, r } où r est un PRNG dont la graine dérive du nom (rendu déterministe,
// indépendant de l'ordre). Le poids d'un son ≈ sr × dur × 2 octets : surveillez le quota du groupe
// (tools/sfx/quotas.json).
export const HI = 32000; // cloches, pièces, brillance
export const LO = 22050; // percussions graves, cuivres sourds, ambiance, BOUCLES

const NAME = /^[a-z0-9_]+$/;

/** Crée le catalogue du groupe [group] : `def(name, meta, render)` y ajoute un son. */
export function catalog(group) {
  if (!NAME.test(group)) throw new Error(`nom de groupe invalide : ${group}`);
  const SOUNDS = [];
  function def(name, meta, render) {
    if (!NAME.test(name) || !name.startsWith(`${group}_`)) {
      throw new Error(`${name} : un son du groupe ${group} doit s'appeler ${group}_<nom> ([a-z0-9_])`);
    }
    if (meta.sr !== HI && meta.sr !== LO) throw new Error(`${name} : sr doit valoir ${HI} ou ${LO}`);
    if (!(meta.dur > 0)) throw new Error(`${name} : dur doit être > 0`);
    if (!(meta.peak <= 0)) throw new Error(`${name} : peak doit être ≤ 0 dBFS`);
    if (meta.loop && meta.sr !== LO) throw new Error(`${name} : une boucle doit être en mono ${LO} Hz`);
    if (typeof meta.use !== 'string' || !meta.use) throw new Error(`${name} : « use » (usage prévu) est obligatoire`);
    if (typeof render !== 'function') throw new Error(`${name} : fonction de rendu manquante`);
    SOUNDS.push({ name, loop: false, limit: 0, cat: group, ...meta, group, render });
  }
  return { SOUNDS, def };
}
