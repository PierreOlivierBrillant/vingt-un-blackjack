// Sons du TEXAS HOLD'EM (groupe « holdem », quota dans ../quotas.json). PROPRIÉTAIRE : implémenteur hold'em.
// Mode d'emploi : ../catalog.mjs. Régénérer : node tools/sfx/generate.mjs --group holdem (puis --check).
// Côté Dart : app/lib/features/games/holdem/holdem_sounds.dart (GameSfx('holdem_…', ms)), joués par la
// scène (holdem_stage.dart) : pitch des cartes, brûlage, flop/turn/river retournés, parole, mises poussées,
// ramassage des mises au pot, tapis, main couchée, abattage, pot poussé au gagnant, « à vous ».
import * as D from '../dsp.mjs';
import * as I from '../instruments.mjs';
import { catalog, HI } from '../catalog.mjs';

export const { SOUNDS, def } = catalog('holdem');

const mix = (c) => new D.Mix(c.sr, c.dur);

// « Parole » : deux tapes du bout des doigts sur le feutre.
def('holdem_check_knock', { sr: HI, dur: 0.32, peak: -8, cat: 'Hold\'em', use: 'Un joueur dit « parole » en tapant deux fois sur la table.' }, (c) => {
  const out = new Float64Array(Math.round(c.sr * c.dur));
  const add = (x, t, g) => { const o = Math.round(t * c.sr); for (let i = 0; i < x.length && o + i < out.length; i++) out[o + i] += x[i] * g; };
  add(I.knock(c.sr, c.r, { f0: 210, dur: 0.14 }), 0, 1);
  add(I.knock(c.sr, c.r, { f0: 200, dur: 0.14 }), 0.13, 0.8);
  return out;
});

// Carte lancée par le croupier vers un siège : glissement court et vif, petit choc à l'arrivée.
def('holdem_card_pitch', { sr: HI, dur: 0.2, peak: -9, cat: 'Hold\'em', use: 'Pitch d\'une carte (cartes privées, cartes du tableau qui quittent le paquet).' }, (c) =>
  I.cardSlide(c.sr, c.r, { dur: c.dur, slide: 0.12, f0: 1800, bright: 1.15, tap: 0.45 }),
);

// Carte brûlée : glissement plus feutré, posée face cachée sur la pile.
def('holdem_card_burn', { sr: HI, dur: 0.24, peak: -11, cat: 'Hold\'em', use: 'Le croupier brûle une carte avant le flop, la turn ou la river.' }, (c) => {
  const m = mix(c);
  m.add(I.cardSlide(c.sr, c.r, { dur: 0.22, slide: 0.15, f0: 1100, bright: 0.6, tap: 0.7 }), 0, 1);
  return m.out;
});

// Cartes du tableau retournées (flop, turn, river).
def('holdem_board_flip', { sr: HI, dur: 0.22, peak: -8, cat: 'Hold\'em', use: 'Retournement des cartes du tableau ou de vos cartes privées.' }, (c) => {
  const m = mix(c);
  m.add(I.cardFlip(c.sr, c.r, { dur: 0.16, f: 2400 }), 0, 1);
  m.add(I.feltThump(c.sr, c.r, { f: 170, dur: 0.06 }), 0.07, 0.35);
  return m.out;
});

// Mise poussée devant le joueur : quelques jetons qui s'entrechoquent.
def('holdem_chips_bet', { sr: HI, dur: 0.34, peak: -7, cat: 'Hold\'em', use: 'Blind, mise, relance ou suivi : jetons poussés devant le joueur.' }, (c) => {
  const m = mix(c);
  for (let k = 0; k < 5; k++) m.add(I.chipClink(c.sr, c.r, { f0: c.r.range(2100, 2900), dur: 0.16 }), 0.02 + k * c.r.range(0.03, 0.05), c.r.range(0.45, 0.8));
  m.add(I.feltThump(c.sr, c.r, { f: 140, dur: 0.07 }), 0, 0.3);
  return m.out;
});

// Ramassage des mises au pot : frottement sur le feutre + cliquetis groupés.
def('holdem_chips_collect', { sr: HI, dur: 0.6, peak: -6, cat: 'Hold\'em', use: 'Fin d\'un tour d\'enchères : le croupier rassemble les mises dans le pot.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const n = D.lp(D.white(sr, 0.42, r), sr, 1000);
  D.mulEnv(n, sr, D.envLin([[0, 0], [0.04, 1], [0.32, 0.7], [0.42, 0]]));
  m.add(n, 0, 0.35);
  for (let k = 0; k < 12; k++) m.add(I.chipClink(sr, r, { dur: 0.16 }), 0.04 + 0.4 * Math.pow(r(), 0.9), r.range(0.3, 0.6));
  for (let k = 0; k < 3; k++) m.add(I.chipClink(sr, r, { dur: 0.16 }), 0.42 + k * 0.03, 0.55);
  return m.out;
});

// Tapis : avalanche de jetons poussés d'un coup, coup sourd et petit éclat de cuivres.
def('holdem_all_in', { sr: HI, dur: 0.95, peak: -3, cat: 'Hold\'em', use: 'Un joueur fait tapis.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.kick(sr, r, { dur: 0.45, f0: 46, decay: 0.35 }), 0, 0.8);
  m.add(I.brassNote(sr, 196, r, { dur: 0.45, gain: 0.5, bright: 1.2 }), 0.03, 0.35);
  m.add(I.brassNote(sr, 293.66, r, { dur: 0.45, gain: 0.4, bright: 1.2 }), 0.03, 0.3);
  for (let k = 0; k < 26; k++) {
    const t = 0.55 * Math.pow(r(), 1.6);
    m.add(I.chipClink(sr, r, { dur: 0.16 }), t, 0.45 * (1 - t));
  }
  const drag = D.lp(D.white(sr, 0.5, r), sr, 1100);
  D.mulEnv(drag, sr, D.envLin([[0, 0], [0.03, 1], [0.5, 0]]));
  m.add(drag, 0, 0.3);
  return m.out;
});

// Main couchée : deux cartes jetées vers le croupier.
def('holdem_fold', { sr: HI, dur: 0.26, peak: -11, cat: 'Hold\'em', use: 'Un joueur se couche : ses cartes glissent vers le croupier.' }, (c) => {
  const m = mix(c);
  m.add(I.cardSlide(c.sr, c.r, { dur: 0.2, slide: 0.12, f0: 1200, bright: 0.7, tap: 0.3 }), 0, 0.9);
  m.add(I.cardSlide(c.sr, c.r, { dur: 0.18, slide: 0.1, f0: 1350, bright: 0.7, tap: 0.25 }), 0.05, 0.7);
  return m.out;
});

// Abattage : les cartes se retournent ensemble, petit arpège de surprise.
def('holdem_showdown', { sr: HI, dur: 0.7, peak: -6, cat: 'Hold\'em', use: 'Abattage : les mains encore en jeu sont retournées.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.cardFlip(sr, r, { dur: 0.16, f: 2300 }), 0, 0.9);
  m.add(I.cardFlip(sr, r, { dur: 0.16, f: 2600 }), 0.06, 0.8);
  m.add(I.arp(sr, 'E5 G5 B5', 0.07, { decay: 0.4, gain: 0.35, dur: 0.56 }), 0.12, 1);
  return m.out;
});

// Le pot poussé au gagnant.
def('holdem_pot_win', { sr: HI, dur: 0.75, peak: -5, cat: 'Hold\'em', use: 'Le croupier pousse le pot (ou un pot annexe) vers le gagnant.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const n = D.sum(D.lp(D.white(sr, 0.5, r), sr, 900), D.scale(D.bp(D.white(sr, 0.5, r), sr, 2200, 1), 0.4));
  D.mulEnv(n, sr, D.envLin([[0, 0], [0.05, 1], [0.38, 0.8], [0.5, 0]]));
  m.add(n, 0, 0.4);
  for (let k = 0; k < 14; k++) m.add(I.chipClink(sr, r, { dur: 0.16 }), 0.04 + 0.5 * Math.pow(r(), 0.8), r.range(0.3, 0.65));
  m.add(I.chime(sr, D.hz('G5'), { dur: 0.5, decay: 0.35, gain: 0.25 }), 0.18, 1);
  return m.out;
});

// C'est à vous : double ping discret.
def('holdem_your_turn', { sr: HI, dur: 0.36, peak: -12, cat: 'Hold\'em', use: 'C\'est à vous de parler.' }, (c) => {
  const m = mix(c);
  m.add(I.chime(c.sr, D.hz('A5'), { dur: 0.2, decay: 0.12, gain: 0.8 }), 0, 1);
  m.add(I.chime(c.sr, D.hz('E6'), { dur: 0.2, decay: 0.12, gain: 0.7 }), 0.12, 1);
  return m.out;
});
