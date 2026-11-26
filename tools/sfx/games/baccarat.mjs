// Sons du BACCARAT (groupe « baccarat », quota dans ../quotas.json). PROPRIÉTAIRE : implémenteur baccarat.
// Mode d'emploi : ../catalog.mjs. Régénérer : node tools/sfx/generate.mjs --group baccarat
// Côté Dart : app/lib/features/games/baccarat/baccarat_sounds.dart (GameSfx('baccarat_…', ms)).
// 12 sons, ≈ 0,62 Mio sur 0,85 : sortie du sabot, squeeze, révélation, 3e carte en travers, brûlage,
// nouveau sabot, carte de coupe, gagnants Joueur / Banquier, égalité, naturel, paire.
import * as D from '../dsp.mjs';
import * as I from '../instruments.mjs';
import { catalog, HI, LO } from '../catalog.mjs';

export const { SOUNDS, def } = catalog('baccarat');

const mix = (c) => new D.Mix(c.sr, c.dur);
const verb = (x, c, o) => D.reverb(x, c.sr, o);

def('baccarat_card_pitch', { sr: HI, dur: 0.3, peak: -7, cat: 'Baccarat', use: 'Inès tire une carte du sabot et la glisse face cachée dans la case Joueur ou Banquier.' }, (c) => {
  const m = mix(c);
  m.add(I.cardSlide(c.sr, c.r, { dur: 0.06, slide: 0.04, bright: 1.3, tap: 0, f0: 2400 }), 0, 0.35); // sortie du sabot
  m.add(I.cardSlide(c.sr, c.r, { dur: 0.24, slide: 0.16, bright: 0.9, tap: 0.5, f0: 1500 }), 0.05, 1);
  return m.out;
});

def('baccarat_card_squeeze', { sr: HI, dur: 0.6, peak: -8, cat: 'Baccarat', use: 'Squeeze : la carte est pliée lentement par un coin avant d\'être révélée (frottement du carton).' }, (c) =>
  I.cardSlide(c.sr, c.r, { dur: c.dur, slide: 0.5, bright: 0.35, tap: 0, f0: 900 }),
);

def('baccarat_card_reveal', { sr: HI, dur: 0.28, peak: -6, cat: 'Baccarat', use: 'Fin du squeeze : la carte se redresse et claque sur le tapis, face visible.' }, (c) => {
  const m = mix(c);
  m.add(I.cardFlip(c.sr, c.r, { dur: 0.16, f: 2100, gap: 0.03 }), 0, 1);
  m.add(I.feltThump(c.sr, c.r, { dur: 0.1, f: 140 }), 0.07, 0.5);
  return m.out;
});

def('baccarat_card_sideways', { sr: HI, dur: 0.36, peak: -7, cat: 'Baccarat', use: 'Troisième carte posée en travers : glissement plus long et petit pivot sur le feutre.' }, (c) => {
  const m = mix(c);
  m.add(I.cardSlide(c.sr, c.r, { dur: 0.26, slide: 0.2, bright: 0.8, tap: 0.3, f0: 1350 }), 0, 1);
  m.add(I.cardSlide(c.sr, c.r, { dur: 0.1, slide: 0.06, bright: 0.6, tap: 0.6, f0: 1900 }), 0.24, 0.55); // pivot
  return m.out;
});

def('baccarat_burn', { sr: HI, dur: 0.9, peak: -7, cat: 'Baccarat', use: 'Brûlage : la première carte est montrée puis des cartes filent face cachée vers la défausse.' }, (c) => {
  const m = mix(c);
  m.add(I.cardFlip(c.sr, c.r, { f: 1900 }), 0, 0.8);
  const times = Array.from({ length: 9 }, (_, k) => 0.28 + k * 0.055);
  m.add(I.cardClicks(c.sr, c.r, c.dur, times, { lp: 7000, f: 2600 }), 0, 0.7);
  m.add(I.knock(c.sr, c.r, { f0: 250 }), 0.8, 0.35);
  return m.out;
});

def('baccarat_shoe_shuffle', { sr: LO, dur: 1.6, peak: -6, cat: 'Baccarat', use: 'Nouveau sabot : huit jeux mélangés à la main puis glissés dans le sabot.' }, (c) => {
  const m = mix(c);
  const riffle = Array.from({ length: 60 }, (_, k) => 0.05 + 0.75 * Math.pow(k / 60, 0.85));
  m.add(I.cardClicks(c.sr, c.r, c.dur, riffle, { lp: 6000 }), 0, 0.85);
  const fl = D.bp(D.white(c.sr, 0.5, c.r), c.sr, 2400, 0.8);
  D.mulEnv(fl, c.sr, D.envLin([[0, 0], [0.06, 1], [0.4, 0.7], [0.5, 0]]));
  m.add(fl, 0.85, 0.12);
  m.add(I.knock(c.sr, c.r, { f0: 170, dur: 0.2 }), 1.32, 0.8); // le paquet entre dans le sabot
  m.add(I.knock(c.sr, c.r, { f0: 150, dur: 0.2 }), 1.42, 0.5);
  return m.out;
});

def('baccarat_cut_card', { sr: HI, dur: 0.45, peak: -8, cat: 'Baccarat', use: 'La carte de coupe sort du sabot : dernier coup du sabot (petit claquement de plastique).' }, (c) => {
  const m = mix(c);
  m.add(I.woodblock(c.sr, c.r, { f: 2600, dur: 0.08 }), 0, 0.7);
  m.add(I.chime(c.sr, 'E6', { dur: 0.35, decay: 0.25, index: 1.1 }), 0.04, 0.35);
  return verb(m.out, c, { room: 0.6, wet: 0.08 });
});

def('baccarat_win_player', { sr: HI, dur: 1.1, peak: -6, cat: 'Baccarat', use: 'Annonce « Joueur gagne » : arpège clair ascendant (bleu).' }, (c) => {
  const m = mix(c);
  m.add(I.arp(c.sr, ['G5', 'B5', 'D6', 'G6'], 0.09, { decay: 0.55, dur: 0.9 }), 0, 0.8);
  m.add(I.chipClink(c.sr, c.r, { f0: 3400 }), 0.32, 0.25);
  return verb(m.out, c, { room: 0.75, wet: 0.14 });
});

def('baccarat_win_banker', { sr: HI, dur: 1.1, peak: -6, cat: 'Baccarat', use: 'Annonce « Banquier gagne » : arpège plus grave et rond (rouge).' }, (c) => {
  const m = mix(c);
  m.add(I.arp(c.sr, ['C5', 'E5', 'G5', 'C6'], 0.1, { decay: 0.6, dur: 0.95, ratio: 2.5, index: 1.4 }), 0, 0.85);
  m.add(I.chipClink(c.sr, c.r, { f0: 2900 }), 0.36, 0.25);
  return verb(m.out, c, { room: 0.78, wet: 0.14 });
});

def('baccarat_tie', { sr: HI, dur: 1.4, peak: -5, cat: 'Baccarat', use: 'Égalité : trois coups de cloche (l\'égalité paie 8 pour 1, Joueur et Banquier rendus).' }, (c) => {
  const m = mix(c);
  [0, 0.2, 0.4].forEach((t, i) => m.add(I.bell(c.sr, 'A5', c.r, { dur: 0.9, decay: 0.7, strike: 0.4 + 0.1 * i }), t, 0.6));
  m.add(I.sparkle(c.sr, c.r, 0.7, { density: 18 }), 0.45, 0.35);
  return verb(m.out, c, { room: 0.82, wet: 0.16 });
});

def('baccarat_natural', { sr: HI, dur: 1.0, peak: -6, cat: 'Baccarat', use: 'Naturel (8 ou 9 en deux cartes) : scintillement et accord brillant.' }, (c) => {
  const m = mix(c);
  m.add(I.chime(c.sr, 'D6', { dur: 0.8, decay: 0.6, index: 1.6 }), 0, 0.6);
  m.add(I.chime(c.sr, 'A6', { dur: 0.7, decay: 0.5, index: 1.2 }), 0.08, 0.45);
  m.add(I.sparkle(c.sr, c.r, 0.9, { density: 30 }), 0.02, 0.5);
  return verb(m.out, c, { room: 0.8, wet: 0.15 });
});

def('baccarat_pair', { sr: HI, dur: 0.8, peak: -7, cat: 'Baccarat', use: 'Paire Joueur ou Banquier (11 pour 1) : « shing » métallique.' }, (c) =>
  I.shing(c.sr, c.r, { dur: c.dur, f0: 3200 }),
);
