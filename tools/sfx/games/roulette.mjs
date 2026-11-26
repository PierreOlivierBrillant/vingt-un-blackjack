// Sons de la ROULETTE (groupe « roulette », quota dans ../quotas.json). PROPRIÉTAIRE : implémenteur roulette.
// Mode d'emploi : ../catalog.mjs. Régénérer : node tools/sfx/generate.mjs --group roulette
// (puis --check). Côté Dart, chaque son est déclaré dans app/lib/features/games/roulette/roulette_sounds.dart
// (GameSfx('roulette_…', durée en ms, …)) : le test app/test/unit/sound_test.dart vérifie la correspondance.
// 12 sons (~0,6 Mio sur 1,25) : la boucle de la bille qui roule (22 kHz mono), le lancer, les frettes, la
// chute dans la case, « Faites vos jeux » / « Rien ne va plus », les jetons, le dolly, le râteau, le paiement,
// le plein gagnant et le zéro.
import * as D from '../dsp.mjs';
import * as I from '../instruments.mjs';
import { catalog, HI, LO } from '../catalog.mjs';

export const { SOUNDS, def } = catalog('roulette');

const TAU = D.TAU;
const mix = (c) => new D.Mix(c.sr, c.dur);

// La bille frappe une frette (en rafale décroissante quand elle se pose).
def('roulette_ball_tick', { sr: HI, dur: 0.16, peak: -8, cat: 'Roulette', use: 'La bille heurte une frette du cylindre (tic métallique court), en rafale pendant les rebonds.' }, (c) =>
  I.chipClink(c.sr, c.r, { f0: 3600, dur: c.dur, tight: 0.6, rattle: 0.3 }),
);

// La bille roule sur la piste en bois : grondement filtré modulé à la vitesse de la bille (période 2 s).
def('roulette_spin_loop', { sr: LO, dur: 2.0, loop: true, xfade: 0.3, peak: -9, cat: 'Roulette', use: 'Bille qui roule sur la piste du cylindre, BOUCLABLE (2 s) : grondement boisé + léger sifflement, pendant le lancer.' }, (c) => {
  const { sr, r } = c;
  return D.makeLoop(sr, 2.0, 0.3, (T) => {
    const m = new D.Mix(sr, T);
    const rumble = D.lp(D.pink(sr, T, r), sr, 420, 0.9);
    D.mulEnv(rumble, sr, (t) => 0.75 + 0.25 * Math.sin(TAU * 2 * t));
    m.add(rumble, 0, 1);
    const hiss = D.bp(D.white(sr, T, r), sr, 2600, 1.4);
    D.mulEnv(hiss, sr, (t) => 0.16 + 0.1 * Math.sin(TAU * 2 * t + 1.3));
    m.add(hiss, 0, 1);
    m.add(D.osc(sr, T, { f: 55, type: 'sine', amp: 0.18 }), 0, 1);
    return D.dcBlock(m.out, sr);
  }, { preroll: 0.3 });
});

// Le croupier lance la bille : petit coup de doigt + souffle qui s'éloigne.
def('roulette_ball_launch', { sr: HI, dur: 0.5, peak: -6, cat: 'Roulette', use: 'Lancer de la bille par la croupière (pichenette + souffle rapide).' }, (c) => {
  const m = mix(c);
  m.add(I.knock(c.sr, c.r, { f0: 900, dur: 0.06 }), 0, 0.6);
  m.add(I.whoosh(c.sr, c.r, { dur: 0.45, f0: 2600, f1: 900, f2: 500, peakAt: 0.2, q: 1.4 }), 0.02, 0.9);
  return m.out;
});

// La bille tombe dans la case : quelques chocs rapprochés de plus en plus faibles, puis elle se cale.
def('roulette_ball_drop', { sr: HI, dur: 0.7, peak: -5, cat: 'Roulette', use: 'La bille tombe et se cale dans la case gagnante (cliquetis décroissant).' }, (c) => {
  const m = mix(c);
  const times = [0, 0.09, 0.16, 0.22, 0.27, 0.31, 0.345];
  times.forEach((t, k) => m.add(I.chipClink(c.sr, c.r, { f0: 3000 + 500 * (k % 3), dur: 0.12, tight: 0.8, rattle: 0.2 }), t, 1 - k * 0.12));
  m.add(I.feltThump(c.sr, c.r, { dur: 0.1, f: 260 }), 0.36, 0.5);
  return m.out;
});

// « Faites vos jeux » : carillon montant.
def('roulette_place_bets', { sr: HI, dur: 0.9, peak: -8, cat: 'Roulette', use: '« Faites vos jeux » : carillon montant à l\'ouverture des mises.' }, (c) =>
  I.arp(c.sr, D.notes('C6 E6 G6'), 0.12, { decay: 0.55, dur: c.dur, ratio: 3, index: 1.4 }),
);

// « Rien ne va plus » : ding-dong descendant.
def('roulette_no_more_bets', { sr: HI, dur: 1.2, peak: -6, cat: 'Roulette', use: '« Rien ne va plus » : ding-dong descendant au tirage.' }, (c) => {
  const m = mix(c);
  m.add(I.chime(c.sr, D.hz('A5'), { dur: 0.9, decay: 0.8, ratio: 3.5, index: 1.6 }), 0, 0.9);
  m.add(I.chime(c.sr, D.hz('F5'), { dur: 0.9, decay: 0.9, ratio: 3.5, index: 1.6 }), 0.28, 0.9);
  return D.reverb(m.out, c.sr, { room: 0.7, wet: 0.15 });
});

// Un jeton posé sur le tapis.
def('roulette_chip_place', { sr: HI, dur: 0.18, peak: -9, cat: 'Roulette', use: 'Un jeton posé sur le tapis (tap sur une case).' }, (c) => {
  const m = mix(c);
  m.add(I.feltThump(c.sr, c.r, { dur: 0.08, f: 180 }), 0, 0.7);
  m.add(I.chipClink(c.sr, c.r, { f0: 2400, dur: 0.15, tight: 1, rattle: 0.5 }), 0.005, 0.8);
  return m.out;
});

// Le dolly (marqueur en cristal) posé sur le numéro gagnant.
def('roulette_dolly', { sr: HI, dur: 0.35, peak: -7, cat: 'Roulette', use: 'Le dolly posé sur le numéro gagnant (choc sourd + tintement cristallin).' }, (c) => {
  const m = mix(c);
  m.add(I.knock(c.sr, c.r, { f0: 240, dur: 0.12 }), 0, 0.8);
  m.add(I.chime(c.sr, D.hz('E7'), { dur: 0.3, decay: 0.25, ratio: 2.7, index: 0.8 }), 0.01, 0.4);
  return m.out;
});

// Le râteau ramasse les jetons perdants.
def('roulette_rake', { sr: LO, dur: 0.8, peak: -7, cat: 'Roulette', use: 'Le râteau ramasse les jetons perdants (frottement sur le feutre + jetons qui s\'entrechoquent).' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  const slide = D.bp(D.pink(sr, 0.7, r), sr, 900, 0.8);
  D.mulEnv(slide, sr, D.envLin([[0, 0], [0.08, 1], [0.55, 0.8], [0.7, 0]]));
  m.add(slide, 0, 0.9);
  for (let t = 0.15; t < 0.65; t += r.range(0.05, 0.09)) m.add(I.chipClink(sr, r, { f0: r.range(1800, 2600), dur: 0.1, tight: 1, rattle: 0.4 }), t, r.range(0.25, 0.45));
  return m.out;
});

// Le paiement : jetons empilés puis poussés vers le gagnant.
def('roulette_payout', { sr: HI, dur: 0.6, peak: -7, cat: 'Roulette', use: 'Paiement d\'un gagnant : jetons comptés et poussés vers sa place.' }, (c) => {
  const m = mix(c);
  for (let k = 0; k < 6; k++) m.add(I.chipClink(c.sr, c.r, { f0: 2200 + 160 * k, dur: 0.14, tight: 0.9, rattle: 0.6 }), 0.06 * k, 0.75);
  m.add(I.feltThump(c.sr, c.r, { dur: 0.1, f: 150 }), 0.4, 0.5);
  return m.out;
});

// Plein gagnant (35 contre 1) : arpège de cloches + paillettes.
def('roulette_straight_win', { sr: HI, dur: 1.8, peak: -3, limit: 2, cat: 'Roulette', use: 'Plein gagnant (35:1) : arpège de cloches, paillettes et pluie de jetons.' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.arp(sr, D.notes('G5 C6 E6 G6 C7'), 0.09, { decay: 0.8, dur: 1.4, ratio: 3.5, index: 1.8 }), 0, 0.8);
  m.add(I.sparkle(sr, r, 1.3, { density: 26, lo: 3000, hi: 7000, env: (t) => Math.exp(-t / 0.7) }), 0.25, 0.35);
  m.add(I.coinShower(sr, r, 1.0, { density: 22, env: (t) => Math.exp(-t / 0.5), gain: 0.5 }), 0.45, 0.6);
  return D.reverb(m.out, sr, { room: 0.78, wet: 0.16 });
});

// Le zéro sort : coup grave et cloche.
def('roulette_zero', { sr: HI, dur: 1.2, peak: -5, cat: 'Roulette', use: 'Le zéro sort : coup de timbale grave et cloche (les chances simples perdent, sauf bouclier).' }, (c) => {
  const { sr, r } = c;
  const m = mix(c);
  m.add(I.timpani(sr, r, D.hz('D2'), { dur: 1.1, decay: 0.9 }), 0, 0.9);
  m.add(I.bell(sr, D.hz('D5'), r, { dur: 1.1, decay: 1.0, bright: 0.8 }), 0.02, 0.5);
  return m.out;
});
