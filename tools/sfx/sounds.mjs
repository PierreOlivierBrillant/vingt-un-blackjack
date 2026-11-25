// Catalogue de la banque de sons : nom, format, crête cible, usage, fonction de rendu.
// Chaque rendu reçoit { sr, dur, r } (r = PRNG à graine dérivée du nom -> indépendant de l'ordre).
import * as D from './dsp.mjs';
import * as I from './instruments.mjs';

const HI = 32000; // cloches, pièces, brillance
const LO = 22050; // percussions graves, cuivres sourds, ambiance

export const SOUNDS = [];
/**
 * meta : sr, dur (s), peak (dBFS), cat, use, loop?, xfade?, limit? (dB de pré-gain dans le saturateur),
 *        fadeOut? (s). render(c) -> Float64Array.
 */
function def(name, meta, render) {
  SOUNDS.push({ name, loop: false, limit: 0, ...meta, render });
}
const mix = (c) => new D.Mix(c.sr, c.dur);
const verb = (x, c, o) => D.reverb(x, c.sr, o);
const TAU = D.TAU;

// =================================================================== CARTES
const DEALS = [
  { slide: 0.15, bright: 1.0, f0: 1500 },
  { slide: 0.17, bright: 0.8, f0: 1750 },
  { slide: 0.13, bright: 1.2, f0: 1400 },
  { slide: 0.19, bright: 0.9, f0: 1600 },
];
DEALS.forEach((p, i) =>
  def(`card_deal_${i + 1}`, { sr: HI, dur: 0.28, peak: -6, cat: 'Cartes', use: `Distribution d'une carte : glissement sur le feutre + petit choc (variante ${i + 1}/4, à tirer au hasard).` },
    (c) => I.cardSlide(c.sr, c.r, { dur: c.dur, ...p })),
);
[{ f: 2200, gap: 0.035 }, { f: 1850, gap: 0.028 }].forEach((p, i) =>
  def(`card_flip_${i + 1}`, { sr: HI, dur: 0.16, peak: -6, cat: 'Cartes', use: `Retournement d'une carte face visible (variante ${i + 1}/2).` },
    (c) => I.cardFlip(c.sr, c.r, { dur: c.dur, ...p })),
);
def('card_reveal_hole', { sr: HI, dur: 1.7, peak: -1, limit: 3, cat: 'Cartes', use: 'Retournement dramatique de la carte cachée du croupier : mini-roulement + montée, claquement, accord de cuivres, timbale, paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.snareRoll(sr, r, 0.78, { rate: 24, amp: (t) => 0.15 + 0.7 * (t / 0.75) }), 0, 0.45);
  m.add(I.riser(sr, r, { dur: 0.75, f0: 150, f1: 620 }), 0, 0.3);
  m.add(I.cardFlip(sr, r, { f: 2000 }), 0.72, 1.0);
  m.add(I.timpani(sr, r, 'D2', { dur: 0.95 }), 0.76, 0.9);
  m.add(I.fanfare(sr, r, [[0, 'D3 A3 D4 F#4 A4', 0.3]], { bright: 1.2, tail: 0.1 }), 0.76, 0.75);
  m.add(I.crash(sr, r, { dur: 0.9, decay: 0.85 }), 0.76, 0.25);
  m.add(I.sparkle(sr, r, 0.9, { density: 25 }), 0.78, 0.6);
  return verb(m.out, c, { room: 0.82, wet: 0.18 });
});
def('shuffle_riffle', { sr: HI, dur: 1.35, peak: -5, cat: 'Cartes', use: 'Mélange en queue d\'aronde : fermeture du pouce, crépitement des 52 cartes, cascade du pont, tapotement pour égaliser le paquet.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.knock(sr, r, { f0: 280 }), 0, 0.4);
  const riffle = Array.from({ length: 52 }, (_, k) => 0.1 + 0.6 * Math.pow(k / 52, 0.8));
  m.add(I.cardClicks(sr, r, c.dur, riffle), 0, 0.9);
  const fl = D.bp(D.white(sr, 0.65, r), sr, 3000, 0.8);
  D.mulEnv(fl, sr, D.envLin([[0, 0], [0.05, 1], [0.55, 0.8], [0.65, 0]]));
  m.add(fl, 0.08, 0.12);
  const bridge = Array.from({ length: 40 }, (_, k) => 0.82 + 0.3 * Math.pow(k / 40, 1.3));
  m.add(I.cardClicks(sr, r, c.dur, bridge, { lp: 5000, f: 2400 }), 0, 0.6);
  m.add(I.knock(sr, r, { f0: 260 }), 1.2, 0.25);
  m.add(I.knock(sr, r, { f0: 250 }), 1.26, 0.2);
  return m.out;
});
def('shuffle_bridge', { sr: HI, dur: 0.95, peak: -5, cat: 'Cartes', use: 'Pont (cascade des cartes qui retombent) puis égalisation du paquet.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.whoosh(sr, r, { dur: 0.12, f0: 800, f1: 2500, f2: 1500 }), 0, 0.15);
  const t = Array.from({ length: 52 }, (_, k) => 0.1 + 0.52 * Math.pow(k / 52, 1.4));
  m.add(I.cardClicks(sr, r, c.dur, t, { lp: 6500, f: 2600 }), 0, 1);
  const fl = D.bp(D.white(sr, 0.55, r), sr, 2200, 0.7);
  D.mulEnv(fl, sr, D.envLin([[0, 0], [0.04, 1], [0.5, 0.3], [0.55, 0]]));
  m.add(fl, 0.1, 0.1);
  m.add(I.knock(sr, r, { f0: 255 }), 0.72, 0.25);
  m.add(I.knock(sr, r, { f0: 245 }), 0.8, 0.2);
  return m.out;
});
def('cards_collect', { sr: HI, dur: 0.9, peak: -6, cat: 'Cartes', use: 'Ramassage des cartes en fin de main : glissements superposés puis paquet tapoté.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  [0, 0.09, 0.17, 0.25].forEach((t, i) => m.add(I.cardSlide(sr, r, { dur: 0.2, slide: 0.11, f0: 1300 + i * 150, tap: 0.25 }), t, 0.8));
  m.add(I.knock(sr, r, { f0: 240 }), 0.55, 0.6);
  m.add(I.knock(sr, r, { f0: 230 }), 0.64, 0.5);
  return m.out;
});

// =================================================================== JETONS
[2300, 2600, 2050, 2850].forEach((f0, i) =>
  def(`chip_clink_${i + 1}`, { sr: HI, dur: 0.2, peak: -6, cat: 'Jetons', use: `Choc de deux jetons d'argile (variante ${i + 1}/4, à tirer au hasard).` },
    (c) => I.chipClink(c.sr, c.r, { f0, dur: c.dur })),
);
def('chip_stack', { sr: HI, dur: 0.55, peak: -5, cat: 'Jetons', use: 'Empilement rapide de 5 jetons.' }, (c) => {
  const m = mix(c);
  m.add(I.feltThump(c.sr, c.r, { f: 140 }), 0, 0.4);
  [0, 0.06, 0.115, 0.165, 0.21].forEach((t, k) => m.add(I.chipClink(c.sr, c.r, { f0: 2200 + k * 90 }), t, 0.6 + k * 0.08));
  return m.out;
});
def('chip_bet_place', { sr: HI, dur: 0.3, peak: -5, cat: 'Jetons', use: 'Pose d\'une mise sur le tapis.' }, (c) => {
  const m = mix(c);
  m.add(I.feltThump(c.sr, c.r, { f: 130 }), 0, 1);
  m.add(I.chipClink(c.sr, c.r, { tight: 0.7 }), 0.003, 0.7);
  m.add(I.chipClink(c.sr, c.r, { tight: 0.5, rattle: 0 }), 0.032, 0.25);
  return m.out;
});
def('chips_push_win', { sr: HI, dur: 1.15, peak: -3, cat: 'Jetons', use: 'Le croupier pousse la pile de gains vers le joueur : frottement sur le feutre + cliquetis.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const n = D.sum(D.lp(D.white(sr, 0.8, r), sr, 900), D.scale(D.bp(D.white(sr, 0.8, r), sr, 2200, 1), 0.5));
  const g = D.smoothNoise(sr, 0.8, r, 60);
  const e = D.envLin([[0, 0], [0.06, 1], [0.6, 0.8], [0.8, 0]]);
  for (let i = 0; i < n.length; i++) n[i] *= (0.6 + 0.5 * Math.abs(g[i])) * e(i / sr);
  m.add(n, 0, 0.5);
  for (let k = 0; k < 22; k++) m.add(I.chipClink(sr, r, { f0: r.range(2000, 3000) }), 0.05 + 0.8 * Math.pow(r(), 0.8), r.range(0.3, 0.7));
  for (let k = 0; k < 4; k++) m.add(I.chipClink(sr, r), 0.8 + k * 0.025, 0.6);
  return verb(m.out, c, { room: 0.7, wet: 0.1 });
});
def('chips_rake_lose', { sr: HI, dur: 1.0, peak: -4, cat: 'Jetons', use: 'Le râteau du croupier ramasse la mise perdue : raclement descendant + jetons qui s\'éloignent.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const n = D.svf(D.white(sr, 0.75, r), sr, D.glide([[0, 1500], [0.75, 650]]), 1.2, 'bp');
  const g = D.smoothNoise(sr, 0.75, r, 90);
  const e = D.envLin([[0, 0], [0.04, 1], [0.55, 0.7], [0.75, 0]]);
  for (let i = 0; i < n.length; i++) n[i] *= (0.4 + 0.8 * Math.abs(g[i])) * e(i / sr);
  m.add(n, 0, 0.7);
  for (let k = 0; k < 12; k++) {
    const t = 0.03 + 0.65 * (k / 12) + r.range(0, 0.04);
    m.add(I.chipClink(sr, r, { f0: 2300 - k * 50 }), t, 0.5 * (1 - k / 16));
  }
  return verb(m.out, c, { room: 0.7, wet: 0.1 });
});
def('chip_allin', { sr: HI, dur: 1.8, peak: -1, limit: 3, cat: 'Jetons', use: 'Tapis ! Avalanche de jetons poussés d\'un coup, grosse caisse, timbale, coup de cuivres, cymbale.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.kick(sr, r, { f0: 42, decay: 0.6 }), 0, 0.9);
  m.add(I.timpani(sr, r, 'C2', { dur: 1.6 }), 0, 0.7);
  m.add(I.fanfare(sr, r, [[0, 'C3 G3 C4 E4 G4', 0.28]], { bright: 1.3, tail: 0.2 }), 0.02, 0.6);
  m.add(I.crash(sr, r, { dur: 1.7, decay: 1.5 }), 0, 0.3);
  for (let k = 0; k < 45; k++) {
    const t = 1.0 * Math.pow(r(), 1.8);
    m.add(I.chipClink(sr, r), t, 0.45 * (1 - t * 0.6));
  }
  const drag = D.lp(D.white(sr, 0.9, r), sr, 1200);
  D.mulEnv(drag, sr, D.envLin([[0, 0], [0.03, 1], [0.9, 0]]));
  m.add(drag, 0, 0.3);
  return verb(m.out, c, { room: 0.8, wet: 0.15 });
});

// =================================================================== ACTIONS
def('action_hit', { sr: HI, dur: 0.25, peak: -6, cat: 'Actions', use: 'Tirer (« carte ! ») : tapotement du doigt sur le feutre + petit claquement.' }, (c) => {
  const m = mix(c);
  m.add(I.knock(c.sr, c.r, { f0: 320 }), 0, 0.8);
  m.add(I.cardFlip(c.sr, c.r, { f: 2600, gap: 0.02 }), 0.02, 0.45);
  m.add(I.pop(c.sr, c.r, { f0: 1400, f1: 800 }), 0, 0.2);
  return m.out;
});
def('action_stand', { sr: LO, dur: 0.4, peak: -5, cat: 'Actions', use: 'Rester : double toc-toc sur la table.' }, (c) => {
  const m = mix(c);
  m.add(I.knock(c.sr, c.r, { f0: 175 }), 0, 1);
  m.add(I.knock(c.sr, c.r, { f0: 165 }), 0.13, 0.85);
  return m.out;
});
def('action_double', { sr: HI, dur: 1.35, peak: -2, limit: 3, cat: 'Actions', use: 'Doubler : coup de tambour + montée + coup de cuivres.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.kick(sr, r), 0, 0.8);
  m.add(I.snare(sr, r), 0, 0.5);
  m.add(I.riser(sr, r, { dur: 0.7, f0: 220, f1: 880 }), 0.05, 0.4);
  m.add(I.fanfare(sr, r, [[0, 'G4 D5 G5', 0.22]], { bright: 1.3, tail: 0.1 }), 0.75, 0.7);
  m.add(I.chime(sr, 'G6', { decay: 0.4, dur: 0.4 }), 0.75, 0.25);
  m.add(I.crash(sr, r, { dur: 0.4, decay: 0.4 }), 0.75, 0.2);
  return verb(m.out, c, { room: 0.78, wet: 0.12 });
});
def('action_split', { sr: HI, dur: 0.85, peak: -3, cat: 'Actions', use: 'Séparer : lame tranchante « shhing » puis deux cartes qui s\'écartent.' }, (c) => {
  const m = mix(c);
  m.add(I.shing(c.sr, c.r, { dur: 0.75 }), 0, 1);
  m.add(I.cardSlide(c.sr, c.r, { bright: 1.2, slide: 0.13, tap: 0.4 }), 0.1, 0.6);
  m.add(I.cardSlide(c.sr, c.r, { f0: 1300, slide: 0.15, tap: 0.4 }), 0.2, 0.6);
  return m.out;
});
def('action_surrender', { sr: LO, dur: 1.0, peak: -10, cat: 'Actions', use: 'Abandon : sifflet à coulisse qui dégringole (drapeau blanc comique).' }, (c) => {
  const m = mix(c);
  m.add(I.slideWhistle(c.sr, c.r, D.glide([[0, 1400], [0.1, 1450], [0.85, 330]]), 0.9), 0, 0.9);
  m.add(I.whoosh(c.sr, c.r, { dur: 0.6, f0: 2000, f1: 1200, f2: 300, peakAt: 0.2 }), 0.05, 0.15);
  return m.out;
});
def('action_insurance', { sr: HI, dur: 1.0, peak: -4, cat: 'Actions', use: 'Assurance : choc sourd protecteur + carillon « bouclier ».' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.kick(sr, r, { f0: 55, f1: 110, decay: 0.3, click: 0.1 }), 0, 0.6);
  m.add(I.arp(sr, 'E5 B5 E6', 0.05, { decay: 0.6 }), 0.02, 0.6);
  m.add(I.pad(sr, 'E4 B4 E5', 0.9, r, { att: 0.05, rel: 0.4, bright: 3000 }), 0, 0.35);
  m.add(I.bell(sr, 'E6', r, { dur: 0.9, decay: 0.8 }), 0.03, 0.3);
  return verb(m.out, c, { room: 0.8, wet: 0.15 });
});

// =================================================================== RÉSULTATS
def('win_small', { sr: HI, dur: 1.0, peak: -3, cat: 'Résultats', use: 'Petite victoire : arpège brillant + jetons + paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.arp(sr, 'C6 E6 G6', 0.07, { decay: 0.6 }), 0, 0.8);
  m.add(I.chipClink(sr, r), 0, 0.3);
  m.add(I.chipClink(sr, r), 0.04, 0.25);
  m.add(I.sparkle(sr, r, 0.7, { density: 20 }), 0.18, 0.5);
  return verb(m.out, c, { room: 0.75, wet: 0.12 });
});
def('win_medium', { sr: HI, dur: 1.8, peak: -1, limit: 2, cat: 'Résultats', use: 'Victoire moyenne : arpège sur deux octaves, cloches, pièces, paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.arp(sr, 'C5 E5 G5 C6 E6 G6', 0.06, { decay: 0.8 }), 0, 0.8);
  m.add(I.bell(sr, 'C6', r, { dur: 1.4, decay: 1.3 }), 0.36, 0.5);
  m.add(I.bell(sr, 'G6', r, { dur: 1.3, decay: 1.1 }), 0.38, 0.35);
  for (let k = 0; k < 8; k++) m.add(I.coin(sr, r), 0.35 + r() * 0.65, 0.35);
  m.add(I.sparkle(sr, r, 1.2, { density: 25 }), 0.4, 0.5);
  return verb(m.out, c, { room: 0.8, wet: 0.15 });
});
def('win_big', { sr: HI, dur: 3.0, peak: -1, limit: 3, cat: 'Résultats', use: 'Grosse victoire : fanfare « ta-ta-ta-taaa », timbale, cymbale, cloches, pluie de pièces.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const T = 0.42;
  m.add(I.fanfare(sr, r, [[0, 'G4 C5 E5', 0.11], [0.14, 'G4 C5 E5', 0.11], [0.28, 'G4 C5 E5', 0.11], [T, 'C4 G4 C5 E5 G5 C6', 1.4]], { bright: 1.2 }), 0, 0.85);
  m.add(I.timpani(sr, r, 'C2', { dur: 2 }), T, 0.7);
  m.add(I.kick(sr, r, { f0: 45 }), T, 0.6);
  m.add(I.crash(sr, r, { dur: 2.4, decay: 2 }), T, 0.3);
  m.add(I.bell(sr, 'C6', r, { dur: 2.2, decay: 2 }), T, 0.5);
  m.add(I.bell(sr, 'G6', r, { dur: 2.0, decay: 1.6 }), T + 0.08, 0.35);
  m.add(I.coinShower(sr, r, 2.5, { density: 35, env: D.envLin([[0, 1], [1.5, 0.8], [2.3, 0]]) }), T + 0.05, 0.6);
  m.add(I.sparkle(sr, r, 2.2, { density: 25, env: D.envLin([[0, 1], [2.2, 0]]) }), T, 0.45);
  return verb(m.out, c, { room: 0.85, wet: 0.18 });
});
def('blackjack_jackpot', { sr: HI, dur: 4.0, peak: -1, limit: 3, cat: 'Résultats', use: 'BLACKJACK ! Carillon de cloches, sirène de jackpot, cuivres, cascade de pièces, foule en délire.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.kick(sr, r, { f0: 38, decay: 0.8 }), 0, 0.8);
  m.add(I.crash(sr, r, { dur: 3, decay: 2.6 }), 0, 0.3);
  m.add(I.timpani(sr, r, 'C2', { dur: 2 }), 0, 0.7);
  m.add(I.fanfare(sr, r, [[0, 'C4 E4 G4 C5 E5', 0.8]], { bright: 1.3, tail: 0.2 }), 0, 0.7);
  const car = D.notes('C6 E6 G6 C7 G6 E6 C6 E6 G6 C7 E7 C7 G6 C7 E7 G7 E7 C7');
  car.forEach((f, k) => m.add(I.bell(sr, f, r, { dur: 1.4, decay: 1.1, strike: 0.2, bright: 1.3 }), 0.05 + k * 0.11, 0.42));
  m.add(I.siren(sr, { dur: 3.0, rate: 2.4 }), 0.3, 0.16);
  const T = 1.52;
  m.add(I.fanfare(sr, r, [[1.1, 'G4 C5 E5', 0.12], [1.24, 'A4 C5 F5', 0.12], [1.38, 'B4 D5 G5', 0.12], [T, 'C4 G4 C5 E5 G5 C6', 1.7]], { bright: 1.25 }), 0, 0.75);
  m.add(I.crash(sr, r, { dur: 2.4, decay: 2.2 }), T, 0.3);
  m.add(I.timpani(sr, r, 'C2', { dur: 2 }), T, 0.7);
  m.add(I.coinShower(sr, r, 3.6, { density: 60, env: D.envLin([[0, 0.4], [0.3, 1], [2.8, 0.9], [3.5, 0]]) }), 0.3, 0.85);
  m.add(I.crowd(sr, r, 3.7, { voices: 30, env: D.envLin([[0, 0], [0.4, 1], [3.0, 0.9], [3.7, 0]]) }), 0.3, 0.9);
  m.add(I.sparkle(sr, r, 3.5, { density: 30, env: D.envLin([[0, 1], [3.5, 0.2]]) }), 0.1, 0.55);
  return verb(m.out, c, { room: 0.86, wet: 0.16 });
});
def('push_tie', { sr: HI, dur: 0.8, peak: -6, cat: 'Résultats', use: 'Égalité : deux notes neutres identiques, discrètes.' }, (c) => {
  const m = mix(c);
  m.add(I.chime(c.sr, 'A5', { dur: 0.6, decay: 0.5, index: 1.2 }), 0, 0.8);
  m.add(I.chime(c.sr, 'A5', { dur: 0.64, decay: 0.6, index: 1.0 }), 0.16, 0.65);
  m.add(I.chipClink(c.sr, c.r), 0.0, 0.25);
  return verb(m.out, c, { room: 0.7, wet: 0.1 });
});
def('lose_hand', { sr: LO, dur: 1.2, peak: -8, cat: 'Résultats', use: 'Main perdue : « bwom-bwooomp » de trombone bouché, comique.' }, (c) =>
  I.trombone(c.sr, c.r, [[0, 'E3', 'E3', 0.22, 0.004], [0.26, 'Eb3', 'B2', 0.75, 0.02]]),
);
def('bust', { sr: LO, dur: 2.9, peak: -6, limit: 2, cat: 'Résultats', use: 'Sauté (>21) : buzzer de jeu télévisé puis trombone triste « wah-wah-wah-waaaah ».' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.buzzer(sr, { dur: 0.55, f: 105 }), 0, 0.8);
  m.add(I.kick(sr, r, { f0: 50, decay: 0.3 }), 0, 0.4);
  m.add(I.trombone(sr, r, [[0, 'Bb3', 'Bb3', 0.3], [0.34, 'A3', 'A3', 0.3], [0.68, 'Ab3', 'Ab3', 0.3], [1.02, 'G3', 'G3', 1.05, 0.03, 4.5]]), 0.62, 1);
  return m.out;
});
def('dealer_bust', { sr: LO, dur: 2.4, peak: -1, limit: 2, cat: 'Résultats', use: 'Le croupier saute : « ta-daa » de cuivres + foule qui acclame.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.crowd(sr, r, 2.4, { voices: 28, env: D.envLin([[0, 0], [0.2, 1], [1.6, 0.9], [2.4, 0]]) }), 0, 1);
  m.add(I.fanfare(sr, r, [[0.05, 'G4 B4 D5', 0.12], [0.2, 'C5 E5 G5 C6', 0.8]], { bright: 1.1 }), 0, 0.6);
  m.add(I.crash(sr, r, { dur: 1.8, decay: 1.6 }), 0.2, 0.25);
  return m.out;
});
def('dealer_blackjack', { sr: LO, dur: 2.8, peak: -1, limit: 2, cat: 'Résultats', use: 'Blackjack du croupier : « dun-dun-DUNNN » dramatique (accord diminué, timbales).' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.fanfare(sr, r, [[0, 'D3 A3 D4', 0.18], [0.3, 'D3 A3 D4', 0.18], [0.6, 'C#3 G3 Bb3 E4', 1.5]], { bright: 0.8, vib: 0.01 }), 0, 0.8);
  m.add(I.timpani(sr, r, 'D2', { dur: 0.6 }), 0, 0.8);
  m.add(I.timpani(sr, r, 'D2', { dur: 0.6 }), 0.3, 0.8);
  m.add(I.timpaniRoll(sr, r, 'A1', 1.2, { amp: (t) => 1 - t / 1.3 }), 0.6, 0.7);
  m.add(I.kick(sr, r, { f0: 40, decay: 0.8 }), 0.6, 0.6);
  m.add(I.crash(sr, r, { dur: 2.1, decay: 2 }), 0.6, 0.25);
  return verb(m.out, c, { room: 0.9, wet: 0.28, damp: 0.4 });
});
def('win_streak_3', { sr: HI, dur: 1.6, peak: -1, limit: 2, cat: 'Résultats', use: 'Série de 3 victoires : montée « combo » 8-bit + coup de cuivres + pièces.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.blips(sr, 'C5 E5 G5 C6 E6 G6 C7', 0.045), 0, 0.8);
  m.add(I.fanfare(sr, r, [[0, 'C5 E5 G5', 0.35]], { bright: 1.2, tail: 0.2 }), 0.34, 0.7);
  m.add(I.chime(sr, 'C7', { decay: 0.8 }), 0.34, 0.3);
  for (let k = 0; k < 3; k++) m.add(I.coin(sr, r), 0.4 + k * 0.09, 0.4);
  m.add(I.sparkle(sr, r, 1.0, { density: 25 }), 0.35, 0.45);
  return verb(m.out, c, { room: 0.8, wet: 0.15 });
});
def('win_streak_5', { sr: HI, dur: 2.8, peak: -1, limit: 3, cat: 'Résultats', use: 'Série de 5 victoires : double montée 8-bit, sirène, fanfare, foule, pièces.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.blips(sr, 'C4 E4 G4 C5 E5 G5 C6 E6 G6 C7', 0.04), 0, 0.8);
  m.add(I.siren(sr, { dur: 1.4, rate: 3 }), 0.42, 0.18);
  m.add(I.fanfare(sr, r, [[0.42, 'G4 C5 E5', 0.1], [0.55, 'G4 C5 E5', 0.1], [0.68, 'C5 E5 G5 C6', 1.2]], { bright: 1.25 }), 0, 0.8);
  m.add(I.crash(sr, r, { dur: 2, decay: 1.8 }), 0.68, 0.3);
  m.add(I.kick(sr, r, { f0: 45 }), 0.68, 0.6);
  m.add(I.crowd(sr, r, 2.1, { voices: 24, env: D.envLin([[0, 0], [0.3, 1], [1.5, 0.8], [2.1, 0]]) }), 0.6, 0.7);
  m.add(I.coinShower(sr, r, 1.9, { density: 40, env: D.envLin([[0, 1], [1.2, 0.7], [1.8, 0]]) }), 0.7, 0.55);
  return verb(m.out, c, { room: 0.82, wet: 0.15 });
});

// =================================================================== TENSION
def('drumroll_short', { sr: LO, dur: 1.8, peak: -2, limit: 2, cat: 'Tension', use: 'Roulement de caisse claire en crescendo terminé par grosse caisse + cymbale.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.snareRoll(sr, r, 1.5, { rate: 26, end: 1.45, amp: (t) => 0.25 + 0.75 * Math.pow(t / 1.45, 1.5) }), 0, 0.9);
  m.add(I.kick(sr, r, { f0: 45 }), 1.45, 0.8);
  m.add(I.snare(sr, r, { decay: 0.25 }), 1.45, 0.7);
  m.add(I.crash(sr, r, { dur: 0.35, decay: 0.9 }), 1.45, 0.35);
  return verb(m.out, c, { room: 0.75, wet: 0.12 });
});
def('drumroll_long', { sr: LO, dur: 2.0, loop: true, xfade: 0.25, peak: -4, cat: 'Tension', use: 'Roulement de caisse claire continu, BOUCLABLE (attente du tirage du croupier, suspense).' }, (c) =>
  D.makeLoop(c.sr, 2.0, 0.25, (T) => D.dcBlock(D.reverb(I.snareRoll(c.sr, c.r, T, { rate: 24, amp: (t) => 0.8 + 0.2 * Math.sin(TAU * 0.5 * t) }), c.sr, { room: 0.72, wet: 0.1 }), c.sr), { preroll: 0.4 }),
);
def('timer_tick', { sr: HI, dur: 0.12, peak: -8, cat: 'Tension', use: 'Tic du compte à rebours (temps de décision).' }, (c) => I.woodblock(c.sr, c.r, { f: 1500, dur: c.dur }));
def('timer_urgent', { sr: HI, dur: 0.32, peak: -5, cat: 'Tension', use: 'Tic urgent des dernières secondes : double tic aigu + bip.' }, (c) => {
  const m = mix(c);
  m.add(I.woodblock(c.sr, c.r, { f: 2000 }), 0, 1);
  m.add(I.woodblock(c.sr, c.r, { f: 2400 }), 0.08, 0.9);
  m.add(I.blips(c.sr, 'A6', 0.1, { len: 0.08 }), 0.15, 1.6);
  return m.out;
});
def('timeout', { sr: LO, dur: 1.3, peak: -2, cat: 'Tension', use: 'Temps écoulé : tonalité qui chute + buzzer + timbale grave.' }, (c) => {
  const m = mix(c);
  m.add(I.zap(c.sr, { f0: 880, f1: 220, dur: 0.5, type: 'square' }), 0, 0.5);
  m.add(I.buzzer(c.sr, { dur: 0.4, f: 98 }), 0.45, 0.7);
  m.add(I.timpani(c.sr, c.r, 'G1', { dur: 0.85, decay: 0.8 }), 0.45, 0.8);
  return m.out;
});

// =================================================================== ARGENT
def('cash_register_kaching', { sr: HI, dur: 1.6, peak: -1, limit: 2, cat: 'Argent', use: 'Dépôt : caisse enregistreuse « ka-ching » (mécanisme, tiroir, clochette, pièces).' }, (c) => I.kaching(c.sr, c.r, { dur: c.dur }));
def('coin_shower', { sr: HI, dur: 2.6, peak: -1, limit: 2, cat: 'Argent', use: 'Pluie de pièces (2,6 s) : gros gain, bonus.' }, (c) => {
  const m = mix(c);
  m.add(I.coinShower(c.sr, c.r, 2.6, { density: 55, env: D.envLin([[0, 0.3], [0.15, 1], [1.6, 0.8], [2.4, 0]]) }), 0, 1);
  m.add(I.sparkle(c.sr, c.r, 2.0, { density: 10, env: D.envLin([[0, 1], [2, 0]]) }), 0.1, 0.25);
  return m.out;
});
def('coin_single', { sr: HI, dur: 0.6, peak: -4, cat: 'Argent', use: 'Une pièce qui tombe et rebondit.' }, (c) => I.coin(c.sr, c.r, { f0: 3400, bounces: 2, decay: 0.3, dur: c.dur }));
def('withdraw_whoosh', { sr: HI, dur: 0.9, peak: -3, cat: 'Argent', use: 'Retrait : souffle + billets qui s\'envolent + petit arpège descendant.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.whoosh(sr, r, { dur: 0.6, f0: 250, f1: 4200, f2: 900 }), 0, 0.8);
  const fl = D.bp(D.white(sr, 0.5, r), sr, 2500, 1.5);
  const g = D.smoothNoise(sr, 0.5, r, 30);
  for (let i = 0; i < fl.length; i++) fl[i] *= Math.max(0, Math.sin((TAU * 24 * i) / sr + g[i])) * Math.sin((Math.PI * i) / fl.length);
  m.add(fl, 0.1, 0.4);
  m.add(I.arp(sr, 'G6 D6 G5', 0.08, { decay: 0.4 }), 0.35, 0.4);
  return verb(m.out, c, { room: 0.75, wet: 0.12 });
});
def('welcome_bonus', { sr: HI, dur: 2.8, peak: -1, limit: 3, cat: 'Argent', use: 'Bonus de bienvenue : fanfare montante, cloches, cymbale, pluie de pièces, paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const T = 0.39;
  m.add(I.fanfare(sr, r, [[0, 'C5 E5 G5', 0.1], [0.13, 'D5 F5 A5', 0.1], [0.26, 'E5 G5 B5', 0.1], [T, 'C4 G4 C5 E5 G5 C6', 1.3]], { bright: 1.2 }), 0, 0.8);
  m.add(I.bell(sr, 'C6', r, { dur: 2, decay: 1.8 }), T, 0.45);
  m.add(I.bell(sr, 'E6', r, { dur: 2, decay: 1.6 }), T + 0.06, 0.35);
  m.add(I.crash(sr, r, { dur: 2, decay: 1.8 }), T, 0.28);
  m.add(I.kick(sr, r, { f0: 45 }), T, 0.5);
  m.add(I.coinShower(sr, r, 2.3, { density: 40, env: D.envLin([[0, 1], [1.4, 0.7], [2.2, 0]]) }), T + 0.02, 0.55);
  m.add(I.sparkle(sr, r, 2.4, { density: 25, env: D.envLin([[0, 1], [2.4, 0]]) }), 0.2, 0.4);
  return verb(m.out, c, { room: 0.85, wet: 0.16 });
});

// =================================================================== POUVOIRS
def('power_free_split', { sr: HI, dur: 1.3, peak: -1, limit: 2, cat: 'Pouvoirs', use: 'Pouvoir « séparation gratuite » : double lame, rayons divergents, cartes, paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.shing(sr, r, { f0: 3200, dur: 0.9 }), 0, 0.9);
  m.add(I.shing(sr, r, { f0: 2600, dur: 0.9 }), 0.12, 0.6);
  m.add(I.zap(sr, { f0: 400, f1: 3000, dur: 0.3, type: 'sine' }), 0.05, 0.3);
  m.add(I.zap(sr, { f0: 3000, f1: 400, dur: 0.3, type: 'sine' }), 0.05, 0.3);
  m.add(I.cardSlide(sr, r, { tap: 0.3 }), 0.2, 0.5);
  m.add(I.cardSlide(sr, r, { f0: 1300, tap: 0.3 }), 0.28, 0.5);
  m.add(I.sparkle(sr, r, 1.1, { density: 30 }), 0.15, 0.5);
  return m.out;
});
def('power_free_double', { sr: HI, dur: 1.3, peak: -1, limit: 2, cat: 'Pouvoirs', use: 'Pouvoir « double gratuit » : montée 8-bit sur 3 octaves + double coup de grosse caisse « ×2 » + cuivres.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.blips(sr, 'C4 E4 G4 C5 E5 G5 C6 E6 G6 C7', 0.03), 0, 0.8);
  m.add(I.kick(sr, r), 0.32, 0.7);
  m.add(I.kick(sr, r, { f0: 55 }), 0.44, 0.7);
  m.add(I.fanfare(sr, r, [[0, 'C4 G4 C5 E5', 0.1], [0.12, 'C4 G4 C5 E5 G5', 0.35]], { bright: 1.3, tail: 0.2 }), 0.32, 0.7);
  m.add(I.zap(sr, { f0: 300, f1: 2400, dur: 0.25, type: 'square' }), 0.3, 0.15);
  m.add(I.sparkle(sr, r, 0.8, { density: 25 }), 0.45, 0.4);
  return verb(m.out, c, { room: 0.78, wet: 0.13 });
});
def('power_free_insurance', { sr: HI, dur: 1.6, peak: -2, cat: 'Pouvoirs', use: 'Pouvoir « assurance gratuite » : bouclier qui s\'active (vrombissement grave + nappe lumineuse + carillons).' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const v = D.sum(D.osc(sr, 1.4, { f: D.glide([[0, 70], [0.4, 110], [1.4, 105]]) }), D.scale(D.osc(sr, 1.4, { f: D.glide([[0, 140], [0.4, 220], [1.4, 210]]), type: 'tri' }), 0.4));
  D.mulEnv(v, sr, D.envLin([[0, 0], [0.25, 1], [0.9, 0.7], [1.4, 0]]));
  m.add(v, 0, 0.6);
  m.add(I.pad(sr, 'E4 B4 E5 G#5', 1.5, r, { att: 0.15, rel: 0.6, bright: 3500 }), 0, 0.45);
  m.add(I.chime(sr, 'E6', { decay: 1.0 }), 0.15, 0.4);
  m.add(I.chime(sr, 'B6', { decay: 0.9 }), 0.22, 0.3);
  m.add(I.sparkle(sr, r, 1.3, { density: 20, lo: 3000 }), 0.2, 0.4);
  return verb(m.out, c, { room: 0.85, wet: 0.2 });
});
def('power_peek', { sr: HI, dur: 1.8, peak: -3, cat: 'Pouvoirs', use: 'Pouvoir « coup d\'œil » : mystérieux (thérémine, glissando par tons entiers, bourdon grave).' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const th = D.osc(sr, 1.7, { f: D.glide([[0, D.hz('E5')], [0.5, D.hz('B5')], [1.0, D.hz('G5')], [1.6, D.hz('D#5')]]), vib: 0.025, vibRate: 6.5 });
  D.mulEnv(th, sr, D.envLin([[0, 0], [0.2, 1], [1.3, 0.8], [1.7, 0]]));
  m.add(th, 0, 0.35);
  m.add(I.arp(sr, 'C7 Bb6 Ab6 F#6 E6 D6 C6 Bb5', 0.05, { decay: 0.8, ratio: 2, index: 1 }), 0.05, 0.5);
  m.add(I.pad(sr, 'E2 B2', 1.7, r, { type: 'tri', bright: 800, att: 0.3, rel: 0.5 }), 0, 0.5);
  return D.echo(verb(m.out, c, { room: 0.9, wet: 0.3 }), sr, { time: 0.19, fb: 0.35, wet: 0.25 });
});
def('power_second_chance', { sr: HI, dur: 1.8, peak: -2, cat: 'Pouvoirs', use: 'Pouvoir « seconde chance » : rembobinage (son joué à l\'envers en décélérant, effet bande) puis redémarrage lumineux.' }, (c) => {
  const { sr, r } = c;
  const src = new D.Mix(sr, 1.6);
  src.add(I.arp(sr, 'C5 E5 G5 C6 E6', 0.08, { decay: 0.8 }), 0, 0.7);
  src.add(I.pad(sr, 'C4 E4 G4', 1.5, r, { att: 0.1, rel: 0.4 }), 0, 0.4);
  src.add(I.crash(sr, r, { dur: 1.5, decay: 1.2 }), 0, 0.2);
  const s = verb(src.out, c, { room: 0.8, wet: 0.2 });
  const rew = D.varispeed(s, sr, (t) => -(3 - 2 * (t / 0.8)) * (1 + 0.08 * Math.sin(TAU * 11 * t)), 0.82, 1.6);
  D.mulEnv(rew, sr, (t) => (0.75 + 0.25 * Math.sin(TAU * 12 * t)) * Math.min(1, t / 0.03) * Math.min(1, (0.82 - t) / 0.04));
  const m = mix(c);
  m.add(rew, 0, 1);
  m.add(I.whoosh(sr, r, { dur: 0.35, f0: 400, f1: 5000, f2: 3000, peakAt: 0.8 }), 0.6, 0.4);
  m.add(I.arp(sr, 'C5 G5 C6 E6', 0.05, { decay: 0.7 }), 0.85, 0.7);
  m.add(I.bell(sr, 'C6', r, { dur: 0.9, decay: 0.9 }), 1.0, 0.35);
  return m.out;
});
def('power_buy', { sr: HI, dur: 1.2, peak: -2, limit: 2, cat: 'Pouvoirs', use: 'Achat d\'un pouvoir : ka-ching court + montée + paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.kaching(sr, r, { dur: 1.1 }), 0, 0.9);
  m.add(I.blips(sr, 'G5 C6 E6', 0.05), 0, 0.4);
  m.add(I.sparkle(sr, r, 0.9, { density: 25 }), 0.15, 0.4);
  return m.out;
});

// =================================================================== PROGRESSION
def('rank_up', { sr: HI, dur: 3.4, peak: -1, limit: 3, cat: 'Progression', use: 'Montée de rang : roulement de timbales, grande fanfare I-IV-V-I, cymbales, cloches, pièces.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.timpaniRoll(sr, r, 'C2', 0.5, { amp: (t) => 0.3 + 1.4 * t }), 0, 0.6);
  m.add(I.fanfare(sr, r, [[0.5, 'G4 C5 E5', 0.12], [0.64, 'G4 C5 E5', 0.12], [0.78, 'G4 C5 E5', 0.12], [0.92, 'A4 C5 F5', 0.3], [1.24, 'B4 D5 G5', 0.3], [1.56, 'C4 G4 C5 E5 G5 C6', 1.4]], { bright: 1.25 }), 0, 0.85);
  m.add(I.crash(sr, r, { dur: 1, decay: 1 }), 0.5, 0.2);
  m.add(I.crash(sr, r, { dur: 1.8, decay: 1.8 }), 1.56, 0.3);
  m.add(I.kick(sr, r, { f0: 42 }), 1.56, 0.6);
  m.add(I.timpani(sr, r, 'C2', { dur: 1.8 }), 1.56, 0.7);
  m.add(I.bell(sr, 'C6', r, { dur: 1.8, decay: 1.7 }), 1.56, 0.45);
  m.add(I.bell(sr, 'G6', r, { dur: 1.7, decay: 1.4 }), 1.62, 0.35);
  m.add(I.sparkle(sr, r, 1.8, { density: 28, env: D.envLin([[0, 1], [1.8, 0]]) }), 1.56, 0.45);
  m.add(I.coinShower(sr, r, 1.6, { density: 20, env: D.envLin([[0, 1], [1.5, 0]]) }), 1.6, 0.4);
  return verb(m.out, c, { room: 0.86, wet: 0.18 });
});
def('leaderboard_climb', { sr: HI, dur: 1.5, peak: -3, cat: 'Progression', use: 'Remontée au classement : gamme montante + souffle ascendant + cloche.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.arp(sr, 'C5 D5 E5 F5 G5 A5 B5 C6', 0.075, { decay: 0.5 }), 0, 0.8);
  m.add(I.whoosh(sr, r, { dur: 0.65, f0: 300, f1: 6000, f2: 4000, peakAt: 0.9 }), 0, 0.25);
  m.add(I.bell(sr, 'C6', r, { dur: 0.9, decay: 0.9 }), 0.6, 0.5);
  m.add(I.sparkle(sr, r, 0.7, { density: 20 }), 0.62, 0.4);
  return verb(m.out, c, { room: 0.8, wet: 0.14 });
});
def('kyc_verified', { sr: HI, dur: 1.1, peak: -3, cat: 'Progression', use: 'Identité vérifiée : coup de tampon + deux notes « validé » + paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.kick(sr, r, { f0: 70, f1: 180, decay: 0.2, click: 0.5 }), 0, 0.5);
  m.add(I.feltThump(sr, r, { f: 160 }), 0, 0.6);
  m.add(I.chime(sr, 'G5', { decay: 0.6, dur: 0.7 }), 0.12, 0.6);
  m.add(I.chime(sr, 'C6', { decay: 0.8, dur: 0.85 }), 0.24, 0.7);
  m.add(I.sparkle(sr, r, 0.6, { density: 20 }), 0.25, 0.4);
  return verb(m.out, c, { room: 0.75, wet: 0.12 });
});
def('achievement', { sr: HI, dur: 1.9, peak: -2, cat: 'Progression', use: 'Succès débloqué : arpège, cloche, nappe, paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.arp(sr, 'C5 G5 C6 E6', 0.07, { decay: 0.7 }), 0, 0.7);
  m.add(I.bell(sr, 'C6', r, { dur: 1.5, decay: 1.4 }), 0.28, 0.45);
  m.add(I.chime(sr, 'G6', { decay: 1.0 }), 0.28, 0.35);
  m.add(I.pad(sr, 'C5 E5 G5', 1.5, r, { type: 'tri', att: 0.1, rel: 0.6, bright: 4000 }), 0.2, 0.3);
  m.add(I.sparkle(sr, r, 1.5, { density: 25, env: D.envLin([[0, 1], [1.5, 0]]) }), 0.28, 0.45);
  return verb(m.out, c, { room: 0.84, wet: 0.16 });
});

// =================================================================== MARCHÉS
def('trade_buy', { sr: HI, dur: 0.45, peak: -5, cat: 'Marchés', use: 'Achat d\'une position : « bloop » montant + pièce.' }, (c) => {
  const m = mix(c);
  m.add(I.bloop(c.sr, { f0: 500, f1: 1000, dur: 0.12, fm: 1 }), 0, 0.8);
  m.add(I.coin(c.sr, c.r, { bounces: 1, dur: 0.35 }), 0.08, 0.5);
  return m.out;
});
def('trade_sell', { sr: HI, dur: 0.5, peak: -5, cat: 'Marchés', use: 'Vente d\'une position : « bloop » descendant + jeton + clochette.' }, (c) => {
  const m = mix(c);
  m.add(I.bloop(c.sr, { f0: 1000, f1: 500, dur: 0.12, fm: 1 }), 0, 0.8);
  m.add(I.chipClink(c.sr, c.r), 0.07, 0.4);
  m.add(I.bell(c.sr, 'A6', c.r, { dur: 0.4, decay: 0.4 }), 0.1, 0.3);
  return m.out;
});
def('market_resolved_win', { sr: HI, dur: 1.6, peak: -2, limit: 2, cat: 'Marchés', use: 'Marché résolu en votre faveur : mini-fanfare + pièces + cloche.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.fanfare(sr, r, [[0, 'G4 C5 E5', 0.1], [0.14, 'C5 E5 G5 C6', 0.7]], { bright: 1.2 }), 0, 0.8);
  m.add(I.bell(sr, 'C6', r, { dur: 1.3, decay: 1.2 }), 0.14, 0.4);
  for (let k = 0; k < 6; k++) m.add(I.coin(sr, r), 0.15 + r() * 0.6, 0.35);
  m.add(I.sparkle(sr, r, 1.2, { density: 20 }), 0.14, 0.4);
  return verb(m.out, c, { room: 0.8, wet: 0.14 });
});
def('market_resolved_lose', { sr: LO, dur: 1.3, peak: -6, cat: 'Marchés', use: 'Marché résolu en votre défaveur : trois accords de cuivres sourds qui descendent chromatiquement.' }, (c) => {
  const m = mix(c);
  m.add(I.fanfare(c.sr, c.r, [[0, 'E4 G4', 0.2], [0.25, 'Eb4 Gb4', 0.2], [0.5, 'D4 F4', 0.45]], { bright: 0.35, vib: 0.012 }), 0, 1);
  m.add(I.feltThump(c.sr, c.r, { f: 80, dur: 0.2 }), 0.5, 0.5);
  return m.out;
});
def('price_tick_up', { sr: HI, dur: 0.09, peak: -12, fadeOut: 0.01, cat: 'Marchés', use: 'Cote qui monte (micro-blip, très fréquent).' }, (c) => I.bloop(c.sr, { f0: 1400, f1: 1900, dur: 0.07 }));
def('price_tick_down', { sr: HI, dur: 0.09, peak: -12, fadeOut: 0.01, cat: 'Marchés', use: 'Cote qui baisse (micro-blip, très fréquent).' }, (c) => I.bloop(c.sr, { f0: 1100, f1: 800, dur: 0.07 }));

// =================================================================== SOCIAL / PUBS
def('friend_request', { sr: HI, dur: 0.95, peak: -4, cat: 'Social', use: 'Demande d\'ami reçue : sonnette « ding-dong ».' }, (c) => {
  const m = mix(c);
  m.add(I.bell(c.sr, 'E6', c.r, { dur: 0.9, decay: 0.9 }), 0, 0.9);
  m.add(I.bell(c.sr, 'C6', c.r, { dur: 0.75, decay: 1.0 }), 0.2, 0.9);
  return m.out;
});
def('friend_accept', { sr: HI, dur: 0.9, peak: -4, cat: 'Social', use: 'Ami accepté : arpège joyeux + paillettes.' }, (c) => {
  const m = mix(c);
  m.add(I.arp(c.sr, 'C6 E6 G6 C7', 0.06, { decay: 0.5 }), 0, 0.8);
  m.add(I.sparkle(c.sr, c.r, 0.6, { density: 20 }), 0.2, 0.5);
  return verb(m.out, c, { room: 0.75, wet: 0.12 });
});
def('ad_reward', { sr: HI, dur: 1.5, peak: -2, limit: 2, cat: 'Social', use: 'Récompense après une pub : montée + pièces + clochette + paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.blips(sr, 'C6 E6 G6', 0.05), 0, 0.5);
  for (let k = 0; k < 6; k++) m.add(I.coin(sr, r), 0.05 + r() * 0.4, 0.4);
  m.add(I.bell(sr, 'G6', r, { dur: 1.2, decay: 1.1 }), 0.2, 0.5);
  m.add(I.sparkle(sr, r, 1.2, { density: 25 }), 0.2, 0.45);
  return verb(m.out, c, { room: 0.8, wet: 0.14 });
});
def('ad_interstitial_sting', { sr: HI, dur: 1.2, peak: -2, limit: 2, cat: 'Social', use: 'Jingle d\'entrée d\'une pub interstitielle : souffle + coup de cuivres + cymbale.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.whoosh(sr, r, { dur: 0.3, f0: 300, f1: 5000, f2: 2000, peakAt: 0.9 }), 0, 0.6);
  m.add(I.fanfare(sr, r, [[0, 'Bb3 F4 Bb4 D5 F5', 0.35]], { bright: 1.3, tail: 0.3 }), 0.28, 0.8);
  m.add(I.kick(sr, r), 0.28, 0.6);
  m.add(I.crash(sr, r, { dur: 0.9, decay: 0.8 }), 0.28, 0.25);
  return verb(m.out, c, { room: 0.8, wet: 0.13 });
});

// =================================================================== INTERFACE
def('ui_tap', { sr: HI, dur: 0.06, peak: -12, fadeOut: 0.008, cat: 'Interface', use: 'Appui sur un bouton (très fréquent, discret).' }, (c) => I.pop(c.sr, c.r, { dur: c.dur }));
def('ui_chip_tap', { sr: HI, dur: 0.12, peak: -9, cat: 'Interface', use: 'Appui n\'importe où dans l\'appli (très fréquent) : petit clic net de jeton en céramique + soupçon de scintillement.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.chipClink(sr, r, { f0: 3300, tight: 0.45, rattle: 0, dur: c.dur }), 0, 1);
  m.add(I.chime(sr, 'E7', { dur: 0.1, decay: 0.08, ratio: 2, index: 0.4, partial2: 0.05 }), 0.008, 0.07);
  m.add(I.chime(sr, 'B7', { dur: 0.08, decay: 0.07, ratio: 2, index: 0.3, partial2: 0.03 }), 0.03, 0.045);
  return m.out;
});
def('ui_toggle', { sr: HI, dur: 0.1, peak: -12, fadeOut: 0.01, cat: 'Interface', use: 'Interrupteur / case à cocher.' }, (c) => {
  const m = mix(c);
  m.add(I.pop(c.sr, c.r, { f0: 1500, f1: 900 }), 0, 1);
  m.add(I.pop(c.sr, c.r, { f0: 1000, f1: 600 }), 0.035, 0.7);
  return m.out;
});
def('ui_error', { sr: LO, dur: 0.35, peak: -11, cat: 'Interface', use: 'Erreur / action impossible : double « bonk » grave.' }, (c) => {
  const m = mix(c);
  [[0, 233], [0.15, 196]].forEach(([t, f]) => {
    const b = D.lp(D.osc(c.sr, 0.14, { f, type: 'square', amp: (x) => Math.min(1, x / 0.003) * Math.exp(-x / 0.05) }), c.sr, 1200);
    m.add(b, t, 1);
  });
  return m.out;
});
def('ui_success', { sr: HI, dur: 0.5, peak: -8, cat: 'Interface', use: 'Validation réussie : deux notes cristallines montantes.' }, (c) => {
  const m = mix(c);
  m.add(I.chime(c.sr, 'E6', { decay: 0.35, dur: 0.4 }), 0, 0.8);
  m.add(I.chime(c.sr, 'B6', { decay: 0.4, dur: 0.43 }), 0.07, 0.8);
  return m.out;
});
def('nav_swoosh', { sr: HI, dur: 0.3, peak: -10, cat: 'Interface', use: 'Changement d\'écran / glissement de panneau.' }, (c) => I.whoosh(c.sr, c.r, { dur: 0.28, f0: 500, f1: 3200, f2: 1500, peakAt: 0.45, q: 1 }));
def('matchmaking_search', { sr: HI, dur: 2.4, loop: true, xfade: 0.3, peak: -8, cat: 'Interface', use: 'Recherche d\'une table, BOUCLABLE : pings type sonar + nappe douce (période 2,4 s).' }, (c) => {
  const { sr } = c;
  // Tout est strictement périodique (période 2,4 s, fréquences de nappe multiples de 1/2,4 Hz) -> fondu linéaire.
  const render = (T) => {
    const m = new D.Mix(sr, T);
    const seq = ['E5', 'B5', 'A5', 'B5'];
    for (let t = 0.3, k = 0; t < T; t += 0.6, k++) m.add(I.chime(sr, seq[k % 4], { decay: 0.5, dur: 0.55, ratio: 2, index: 1.2 }), t, 0.5);
    const padF = [395 / 2.4, 593 / 2.4];
    for (const f of padF) m.add(D.osc(sr, T, { f, type: 'tri', amp: (t) => 0.12 * (0.6 + 0.4 * Math.sin((TAU * t) / 2.4)) }), 0, 1);
    return D.dcBlock(D.echo(m.out, sr, { time: 0.15, fb: 0.4, wet: 0.35 }), sr);
  };
  return D.makeLoop(sr, 2.4, 0.3, render, { preroll: 2.4, mode: 'linear' });
});
def('matchmaking_found', { sr: HI, dur: 1.2, peak: -3, cat: 'Interface', use: 'Table trouvée : arpège montant + coup de cuivres + paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.arp(sr, 'E5 G#5 B5 E6', 0.05, { decay: 0.6 }), 0, 0.7);
  m.add(I.fanfare(sr, r, [[0, 'E4 B4 E5 G#5', 0.3]], { bright: 1.1, tail: 0.2 }), 0.22, 0.6);
  m.add(I.kick(sr, r, { decay: 0.3 }), 0.22, 0.4);
  m.add(I.sparkle(sr, r, 0.8, { density: 20 }), 0.25, 0.4);
  return verb(m.out, c, { room: 0.8, wet: 0.13 });
});
def('seat_join', { sr: HI, dur: 0.6, peak: -6, cat: 'Interface', use: 'Un joueur s\'assoit à la table : jeton posé + petit carillon.' }, (c) => {
  const m = mix(c);
  m.add(I.feltThump(c.sr, c.r), 0, 0.6);
  m.add(I.chipClink(c.sr, c.r), 0, 0.5);
  m.add(I.chime(c.sr, 'A5', { decay: 0.4, dur: 0.45 }), 0.05, 0.5);
  m.add(I.chime(c.sr, 'E6', { decay: 0.4, dur: 0.45 }), 0.12, 0.5);
  return m.out;
});

// =================================================================== AMBIANCE
def('ambience_casino_loop', { sr: LO, dur: 10.0, loop: true, xfade: 2.0, peak: -6, cat: 'Ambiance', use: 'Fond sonore de casino, BOUCLABLE (10 s) : brouhaha de foule, machines à sous lointaines, pièces et jetons, réverbération de grande salle.' }, (c) => {
  const { sr, r } = c;
  const render = (T) => {
    const m = new D.Mix(sr, T);
    // Brouhaha : 28 « causeurs » voisés, syllabes 3-6 Hz, voyelles changeantes, prises de parole/pauses.
    const vowels = [[730, 1090], [530, 1840], [570, 840], [300, 2200], [660, 1700], [440, 1020]];
    const babble = D.buf(sr, T);
    for (let v = 0; v < 28; v++) {
      const f0 = r.range(95, 240);
      const rate = r.range(3, 6);
      const nSyl = Math.ceil(T * rate) + 2;
      const vw = Array.from({ length: nSyl }, () => r.pick(vowels));
      const talk = [];
      for (let t = -r.range(0, 3); t < T; ) { const on = r.range(1.2, 4); talk.push([t, t + on]); t += on + r.range(0.4, 2.2); }
      const speaking = (t) => { for (const [a, b] of talk) if (t >= a && t < b) return Math.min(1, (t - a) / 0.1, (b - t) / 0.1); return 0; };
      const drift = D.smoothNoise(sr, T, r, 2);
      const src = D.osc(sr, T, { f: (t) => f0 * (1 + 0.06 * drift[Math.min(drift.length - 1, Math.round(t * sr))]), type: 'saw', phase: r() });
      const syl = (t) => vw[Math.min(nSyl - 1, Math.floor(t * rate))];
      const y = D.sum(D.svf(src, sr, (t) => syl(t)[0], 5, 'bp'), D.scale(D.svf(src, sr, (t) => syl(t)[1], 7, 'bp'), 0.5));
      D.mulEnv(y, sr, (t) => speaking(t) * Math.pow(Math.sin(Math.PI * ((t * rate) % 1)), 2));
      D.addAt(babble, y, sr, 0, r.range(0.3, 1));
    }
    m.add(D.lp(babble, sr, 2400), 0, 0.32);
    m.add(D.lp(D.pink(sr, T, r), sr, 350), 0, 0.25);
    // Machines à sous lointaines : petits jingles 8-bit / carillons.
    const pent = D.notes('C5 D5 E5 G5 A5 C6 D6 E6 G6 A6');
    for (let t = r.range(0.2, 0.8); t < T - 0.3; t += r.range(0.7, 1.8)) {
      const k = r.int(3, 6), st = r.int(0, 4), step = r.range(0.06, 0.1);
      const seq = Array.from({ length: k }, (_, i) => pent[Math.min(pent.length - 1, st + i * r.int(1, 2))]);
      const j = r() < 0.5 ? I.blips(sr, seq, step, { len: step * 0.8 }) : I.arp(sr, seq, step, { decay: 0.4 });
      m.add(D.lp(j, sr, 3500), t, r.range(0.12, 0.25));
    }
    // Pièces qui tombent dans un bac, jetons.
    for (let t = r.range(0.5, 2); t < T - 0.5; t += r.range(2, 4)) m.add(I.coinShower(sr, r, 0.8, { density: 25, room: false }), t, 0.1);
    for (let t = r.range(0, 0.5); t < T; t += r.range(0.3, 1.2)) m.add(I.chipClink(sr, r), t, r.range(0.04, 0.1));
    return D.dcBlock(D.reverb(m.out, sr, { room: 0.88, damp: 0.45, wet: 0.35 }), sr);
  };
  return D.makeLoop(sr, 10.0, 2.0, render, { preroll: 1.0 });
});
def('slot_reel_spin', { sr: LO, dur: 1.0, loop: true, xfade: 0.12, peak: -6, cat: 'Ambiance', use: 'Rouleaux de machine à sous qui tournent, BOUCLABLE : cliquet 20 Hz + ronronnement moteur.' }, (c) => {
  const { sr, r } = c;
  const noisy = D.makeLoop(sr, 1.0, 0.12, (T) => {
    const m = new D.Mix(sr, T);
    for (let t = 0; t < T; t += 0.05) {
      const cl = D.bp(D.white(sr, 0.012, r), sr, r.range(2200, 2800), 2);
      D.mulEnv(cl, sr, (x) => Math.exp(-x / 0.002));
      m.add(cl, t, r.range(0.6, 0.9));
      m.add(D.partials(sr, 0.04, [{ f: 1800, a: 0.15, d: 0.03 }]), t, 1);
    }
    const whir = D.bp(D.white(sr, T, r), sr, 700, 2);
    m.add(whir, 0, 0.25);
    return D.dcBlock(m.out, sr);
  }, { preroll: 0.1 });
  // Partie périodique (fréquences entières sur 1 s) ajoutée après : boucle naturellement.
  // Le filtre a un transitoire initial : on prend la 2e seconde d'un rendu de 2 s (régime établi).
  const humLong = D.lp(D.osc(sr, 2.0, { f: 150, type: 'saw' }), sr, 600);
  const L = noisy.length;
  for (let i = 0; i < L; i++) noisy[i] += humLong[L + i] * 0.06;
  return noisy;
});
def('slot_reel_stop', { sr: HI, dur: 0.5, peak: -4, cat: 'Ambiance', use: 'Arrêt d\'un rouleau de machine à sous : « clonk » + cliquet + petite clochette.' }, (c) => {
  const m = mix(c);
  m.add(I.knock(c.sr, c.r, { f0: 120 }), 0, 1);
  m.add(I.chipClink(c.sr, c.r, { f0: 1800, tight: 0.6 }), 0.01, 0.5);
  m.add(I.bell(c.sr, 'C7', c.r, { dur: 0.45, decay: 0.4 }), 0.03, 0.25);
  return m.out;
});
def('ambience_slots_loop', { sr: LO, dur: 8.0, loop: true, xfade: 1.5, peak: -14, cat: 'Ambiance', use: 'Salle des machines à sous au loin, BOUCLABLE (8 s), couche discrète à jouer sous ambience_casino_loop : petits jingles épars, carillons, rouleaux qui s\'arrêtent, pièces, ronronnement grave.' }, (c) => {
  const { sr, r } = c;
  const render = (T) => {
    const m = new D.Mix(sr, T);
    const pent = D.notes('C5 D5 E5 G5 A5 C6 D6 E6 G6 A6 C7');
    // Jingles de machines lointaines : arpèges / blips 8-bit / trilles, rares, bas et filtrés (distance).
    for (let t = r.range(0.1, 0.6); t < T - 0.4; t += r.range(1.1, 2.4)) {
      const n = r.int(3, 6), st = r.int(0, 4), step = r.range(0.055, 0.09);
      const seq = Array.from({ length: n }, (_, i) => pent[Math.min(pent.length - 1, st + i * r.int(1, 2))]);
      if (r() < 0.25) seq.reverse();
      const kind = r();
      const j = kind < 0.4 ? I.blips(sr, seq, step, { len: step * 0.7 })
        : kind < 0.85 ? I.arp(sr, seq, step, { decay: 0.45 })
          : I.arp(sr, [seq[0], seq[n - 1], seq[0], seq[n - 1]], 0.07, { decay: 0.3 });
      m.add(D.lp(j, sr, r.range(2200, 3200)), t, r.range(0.08, 0.18));
    }
    // Carillons isolés.
    for (let t = r.range(0.5, 1.5); t < T - 0.5; t += r.range(1.8, 3.5)) m.add(D.lp(I.chime(sr, r.pick(pent), { decay: 0.8, dur: 1.0, ratio: 2, index: 1 }), sr, 3000), t, r.range(0.05, 0.1));
    // Rouleaux qui tournent puis s'arrêtent, quelque part dans la salle.
    for (let t = r.range(0.3, 1.5); t < T - 1; t += r.range(2.2, 3.8)) {
      const d = r.range(0.4, 0.9), rate = r.range(17, 22);
      m.add(D.lp(mechClicks(sr, r, d + 0.1, clickTimes(0, d, () => rate), { f: 2300, ringA: 0.08 }), sr, 2500), t, r.range(0.035, 0.06));
      m.add(D.lp(I.knock(sr, r, { f0: 120 }), sr, 1500), t + d, r.range(0.06, 0.1));
    }
    // Une pièce ou une petite poignée de pièces de temps en temps.
    for (let t = r.range(1, 2.5); t < T - 0.8; t += r.range(2.5, 4.5)) {
      const x = r() < 0.5 ? I.coin(sr, r, { dur: 0.5 }) : I.coinShower(sr, r, 0.7, { density: 18, room: false });
      m.add(D.lp(x, sr, 4000), t, r.range(0.05, 0.09));
    }
    // Ronronnement grave des machines + air de la salle.
    m.add(D.lp(D.pink(sr, T, r), sr, 220), 0, 0.16);
    m.add(D.bp(D.pink(sr, T, r), sr, 900, 0.6), 0, 0.03);
    return D.dcBlock(D.reverb(m.out, sr, { room: 0.9, damp: 0.5, wet: 0.45 }), sr);
  };
  const y = D.makeLoop(sr, 8.0, 1.5, render, { preroll: 1.0 });
  // Bourdon électrique strictement périodique (nombre entier de cycles sur 8 s), ajouté après la boucle.
  const g = D.peak(y) * 0.025;
  for (let i = 0; i < y.length; i++) {
    const t = i / sr;
    y[i] += g * (Math.sin(TAU * 60 * t) + 0.6 * Math.sin(TAU * 120 * t + 0.4) + 0.3 * Math.sin(TAU * 180 * t + 1.1)) * (0.85 + 0.15 * Math.sin((TAU * t) / 4));
  }
  return y;
});

// =================================================================== LAS VEGAS
/** Cliquetis mécanique (cliquet de levier, rouleaux) : clic de bruit filtré + petite résonance métallique à chaque instant. */
function mechClicks(sr, r, dur, times, { f = 2500, q = 2, ring = 1800, ringA = 0.15, decay = 0.002, gain = 1 } = {}) {
  const out = D.buf(sr, dur);
  for (const t of times) {
    if (t < 0 || t >= dur) continue;
    const g = r.range(0.6, 1);
    const cl = D.bp(D.white(sr, 0.012, r), sr, f * r.range(0.85, 1.15), q);
    D.mulEnv(cl, sr, (x) => Math.exp(-x / decay));
    D.addAt(out, cl, sr, t, g);
    if (ringA) D.addAt(out, D.partials(sr, 0.05, [{ f: ring * r.range(0.97, 1.03), a: ringA, d: 0.035, ph: r() }]), sr, t, g);
  }
  return D.scale(out, gain);
}
/** Instants d'un train de clics de cadence rate(t) (Hz) entre t0 et t1. */
function clickTimes(t0, t1, rate) {
  const ts = [];
  for (let t = t0; t < t1; t += 1 / rate(t)) ts.push(t);
  return ts;
}
/** Sonnerie mécanique de jackpot : le marteau alterne entre deux timbres à ~12 coups/s. amp(t) relatif à `start`. */
function jackpotBells(sr, r, dur, { rate = 12, pitches = ['G6', 'E6'], start = 0, end = dur, decay = 0.55, amp = () => 1 } = {}) {
  const out = D.buf(sr, dur);
  const fs = pitches.map(D.hz);
  let k = 0;
  for (let t = start; t < end; t += 1 / rate, k++) {
    const tt = Math.max(0, t + r.range(-0.004, 0.004));
    const g = amp(tt - start) * r.range(0.8, 1) * (k % 2 ? 0.85 : 1);
    const bd = Math.min(decay * 1.4, dur - tt);
    if (g <= 0.01 || bd < 0.02) continue;
    D.addAt(out, I.bell(sr, fs[k % fs.length], r, { dur: bd, decay, bright: 1.35, strike: 0.7, detune: 0.0025 }), sr, tt, g * 0.5);
  }
  return out;
}
/** Pièces qui dégringolent dans un bac métallique : pièces + résonance du bac + bruissement du tas. */
function coinTray(sr, r, dur, { density = 30, env = () => 1, gain = 1 } = {}) {
  const out = D.buf(sr, dur);
  const tray = [410, 980, 1630, 2310, 3070, 3920];
  const n = Math.round(density * dur);
  for (let k = 0; k < n; k++) {
    const t = r() * (dur - 0.12);
    const g = env(t);
    if (g <= 0.01 || r() > g) continue;
    const cd = Math.min(0.5, dur - t);
    D.addAt(out, I.coin(sr, r, { f0: r.range(2300, 4200), dur: cd, gain: r.range(0.4, 1) }), sr, t, 0.5);
    const ring = D.partials(sr, cd, tray.map((f, i) => ({ f: f * r.range(0.99, 1.01), a: r.range(0.4, 1) / (1 + i * 0.6), d: r.range(0.15, 0.35) / (1 + i * 0.3), ph: r() })));
    D.addAt(out, ring, sr, t, 0.06 * r.range(0.5, 1));
  }
  const rustle = D.bp(D.white(sr, dur, r), sr, 4800, 0.8);
  const grain = D.smoothNoise(sr, dur, r, 35);
  for (let i = 0; i < rustle.length; i++) rustle[i] *= Math.abs(grain[i]) * env(i / sr) * 0.07;
  D.addAt(out, rustle, sr);
  return D.scale(out, gain);
}
/** « Ouais ! » collectif : voix voisées dont les formants glissent de [é] vers [a], hauteur d'exclamation (montée puis retombée). */
function yeah(sr, r, dur, { voices = 12 } = {}) {
  const out = D.buf(sr, dur);
  for (let v = 0; v < voices; v++) {
    const f0 = r.range(115, 300);
    const on = r.range(0, 0.08);
    const vd = Math.min(dur - on, r.range(0.35, 0.6));
    const k = (f0 > 200 ? 1.15 : 1) * r.range(0.95, 1.05);
    const src = D.osc(sr, vd, { f: D.glide([[0, f0 * 0.88], [0.1, f0 * 1.18], [vd, f0 * 0.92]]), type: 'saw', vib: 0.01, vibRate: r.range(5, 7), phase: r() });
    const br = D.white(sr, vd, r);
    for (let i = 0; i < src.length; i++) src[i] += br[i] * 0.3;
    const F1 = D.glide([[0.03, 400 * k], [0.16, 780 * k]]);
    const F2 = D.glide([[0.03, 2050 * k], [0.16, 1250 * k]]);
    const y = D.sum(D.svf(src, sr, F1, 5, 'bp'), D.scale(D.svf(src, sr, F2, 7, 'bp'), 0.55));
    const rl = r.range(0.15, 0.3);
    D.mulEnv(y, sr, (t) => Math.min(1, t / 0.025) * Math.min(1, Math.max(0, vd - t) / rl));
    D.addAt(out, y, sr, on, r.range(0.5, 1) * 0.35);
  }
  return D.reverb(out, sr, { room: 0.78, damp: 0.35, wet: 0.2 });
}

def('vegas_intro', { sr: HI, dur: 3.2, peak: -1, limit: 3, cat: 'Las Vegas', use: '« Bienvenue à Las Vegas » à l\'arrivée dans le hall : levier de machine à sous (cliquet), rouleaux qui tournent, trois arrêts « clonk » (1,0 / 1,25 / 1,5 s), puis sonnerie de jackpot, « ta-da » de cuivres, pluie de pièces, foule en liesse, paillettes.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  // Levier : cliquet qui accélère + grincement du bras, butée en fin de course.
  const lever = Array.from({ length: 9 }, (_, k) => 0.02 + 0.22 * Math.pow(k / 9, 0.8));
  m.add(mechClicks(sr, r, 0.4, lever, { f: 3200, q: 2.5, ring: 2100, ringA: 0.25, decay: 0.0015 }), 0, 1.4);
  const creak = D.svf(D.white(sr, 0.24, r), sr, D.glide([[0, 500], [0.24, 1400]]), 4, 'bp');
  D.mulEnv(creak, sr, (t) => Math.sin(Math.PI * Math.min(1, t / 0.24)));
  m.add(creak, 0.02, 0.25);
  m.add(I.knock(sr, r, { f0: 150 }), 0.26, 1.0);
  m.add(I.feltThump(sr, r, { f: 85, dur: 0.14 }), 0.26, 0.7);
  // Trois rouleaux : cliquet ~20 Hz chacun, démarrage progressif, léger ralenti, arrêt à 1,0 / 1,25 / 1,5 s.
  [1.0, 1.25, 1.5].forEach((S, j) => {
    const rmax = 18 + j * 1.7;
    const ts = clickTimes(0.29 + j * 0.012, S - 0.02, (t) => rmax * (0.35 + 0.65 * D.clamp((t - 0.29) / 0.18, 0, 1)) * (1 - 0.35 * D.clamp((t - (S - 0.12)) / 0.12, 0, 1)));
    m.add(mechClicks(sr, r, c.dur, ts, { f: 2400 + j * 250 }), 0, 0.8);
    const whir = D.bp(D.white(sr, S - 0.29, r), sr, 650 + j * 120, 2);
    D.mulEnv(whir, sr, D.envLin([[0, 0], [0.15, 1], [S - 0.31, 0.9], [S - 0.29, 0]]));
    m.add(whir, 0.29, 0.3);
    // Arrêt : « clonk » + cliquet + clochette montante (do-mi-sol) pour l'anticipation.
    m.add(I.knock(sr, r, { f0: 120 }), S, 1.3);
    m.add(I.chipClink(sr, r, { f0: 1800, tight: 0.6 }), S + 0.01, 0.6);
    m.add(I.bell(sr, ['C6', 'E6', 'G6'][j], r, { dur: 0.6, decay: 0.5, strike: 0.4 }), S + 0.02, 0.5);
  });
  m.add(I.riser(sr, r, { dur: 1.2, f0: 180, f1: 700 }), 0.32, 0.22);
  // JACKPOT : sonnerie, « ta-da », grosse caisse, cymbale, pièces, foule, paillettes.
  const J = 1.58, T = 1.72;
  m.add(jackpotBells(sr, r, 1.62, { rate: 12, end: 1.2, amp: D.envLin([[0, 0.8], [0.15, 1], [0.9, 0.85], [1.2, 0.5]]) }), J, 0.5);
  m.add(I.fanfare(sr, r, [[0, 'G4 C5 E5', 0.1], [T - J, 'C4 G4 C5 E5 G5 C6', 1.05]], { bright: 1.3 }), J, 0.8);
  m.add(I.kick(sr, r, { f0: 42, decay: 0.6 }), T, 0.7);
  m.add(I.crash(sr, r, { dur: 1.48, decay: 1.6 }), T, 0.28);
  m.add(I.timpani(sr, r, 'C2', { dur: 1.48 }), T, 0.55);
  m.add(I.siren(sr, { dur: 1.2, rate: 2.6 }), T + 0.05, 0.08);
  m.add(coinTray(sr, r, 1.46, { density: 45, env: D.envLin([[0, 0.5], [0.15, 1], [0.9, 0.8], [1.35, 0]]) }), T + 0.02, 0.7);
  m.add(I.crowd(sr, r, 1.45, { voices: 26, whistles: 2, claps: 45, env: D.envLin([[0, 0], [0.18, 1], [0.95, 0.85], [1.4, 0]]) }), T + 0.03, 0.75);
  m.add(I.sparkle(sr, r, 1.45, { density: 32, env: D.envLin([[0, 1], [1.4, 0.1]]) }), T - 0.05, 0.5);
  return verb(m.out, c, { room: 0.85, wet: 0.16 });
});
def('slot_jackpot_bells', { sr: HI, dur: 2.6, peak: -2, cat: 'Las Vegas', use: 'Paiement d\'une machine à sous : sonnerie mécanique de jackpot à deux timbres (~12 coups/s) + pièces qui dégringolent dans le bac métallique, puis extinction.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(jackpotBells(sr, r, c.dur, { rate: 12, end: 1.95, amp: D.envLin([[0, 0.85], [0.12, 1], [1.5, 0.9], [1.95, 0.55]]) }), 0, 0.8);
  m.add(I.bell(sr, 'G6', r, { dur: 0.6, decay: 1.0, bright: 1.35, strike: 0.7, detune: 0.0025 }), 2.0, 0.22); // dernier coup : la cloche résonne librement
  m.add(coinTray(sr, r, 2.5, { density: 55, env: D.envLin([[0, 0.3], [0.2, 1], [1.6, 0.85], [2.3, 0]]) }), 0.08, 0.6);
  return verb(m.out, c, { room: 0.78, damp: 0.3, wet: 0.12 });
});
def('crowd_cheer', { sr: LO, dur: 1.8, peak: -3, cat: 'Las Vegas', use: 'La table acclame : « ouais ! » collectif, applaudissements et un sifflet.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(yeah(sr, r, 0.7, { voices: 14 }), 0, 1.0);
  m.add(I.crowd(sr, r, c.dur, { voices: 24, whistles: 1, claps: 70, rise: 0.25, env: D.envLin([[0, 0], [0.07, 1], [0.55, 0.95], [1.3, 0.3], [1.55, 0]]) }), 0, 1);
  return m.out;
});
def('crowd_ooh', { sr: LO, dur: 1.4, peak: -5, cat: 'Las Vegas', use: 'La table compatit : « ooooh » qui retombe (joueur qui saute, blackjack du croupier).' }, (c) => {
  const { sr, r } = c;
  const out = D.buf(sr, c.dur);
  // Voix voisées désaccordées sur les formants de [o] -> [ou] (≈ 400 / 800 Hz), hauteur qui retombe.
  // Chaque voix a sa voyelle, sa dérive de hauteur et son entrée : une foule, pas un chœur.
  for (let v = 0; v < 22; v++) {
    const f0 = r.range(100, 280);
    const on = r.range(0, 0.16);
    const vd = c.dur - on - r.range(0.05, 0.25);
    const k = (f0 > 190 ? 1.12 : 1) * r.range(0.92, 1.08);
    const fall = r.range(0.78, 0.9);
    const drift = D.smoothNoise(sr, vd, r, 3);
    const contour = D.glide([[0, f0 * 0.95], [r.range(0.1, 0.2), f0 * 1.02], [vd, f0 * fall]]);
    const src = D.osc(sr, vd, { f: (t) => contour(t) * (1 + 0.012 * drift[Math.min(drift.length - 1, Math.round(t * sr))]), type: 'saw', vib: r.range(0.004, 0.012), vibRate: r.range(4, 6.5), vibDelay: 0.2, phase: r() });
    const br = D.white(sr, vd, r);
    for (let i = 0; i < src.length; i++) src[i] += br[i] * r.range(0.12, 0.2);
    const a1 = r.range(400, 520) * k, a2 = r.range(780, 920) * k; // [o] / [ɔ]
    const F1 = D.glide([[0, a1], [vd, a1 * r.range(0.75, 0.85)]]); // ... qui se ferme en [ou]
    const F2 = D.glide([[0, a2], [vd, a2 * r.range(0.82, 0.9)]]);
    const y = D.sum(D.svf(src, sr, F1, 6, 'bp'), D.scale(D.svf(src, sr, F2, 7, 'bp'), 0.45));
    const at = r.range(0.1, 0.2), rl = r.range(0.35, 0.55);
    D.mulEnv(y, sr, (t) => Math.pow(Math.min(1, t / at), 1.5) * (1 - 0.35 * D.clamp((t - at) / (vd - at), 0, 1)) * Math.min(1, Math.max(0, vd - t) / rl));
    D.addAt(out, y, sr, on, r.range(0.4, 1) * 0.26);
  }
  // Souffle : bruit rose dans les mêmes formants + un peu d'air.
  const pk = D.pink(sr, c.dur, r);
  const breath = D.sum(D.bp(pk, sr, 420, 3), D.scale(D.bp(pk, sr, 820, 3), 0.6), D.scale(D.bp(pk, sr, 2600, 1.5), 0.12));
  D.mulEnv(breath, sr, D.envLin([[0, 0], [0.2, 1], [0.8, 0.65], [1.25, 0]]));
  D.addAt(out, breath, sr, 0, 0.25);
  return D.lp(verb(out, c, { room: 0.82, damp: 0.4, wet: 0.24 }), sr, 3200);
});
