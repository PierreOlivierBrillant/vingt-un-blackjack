// Instruments de synthèse : chaque fonction renvoie un Float64Array (mono, -1..1 approximativement).
// Les paramètres aléatoires passent toujours par le PRNG `r` fourni -> rendu déterministe.
import * as D from './dsp.mjs';

const { TAU, hz } = D;

// ================================================================ métal : cloches, carillons, pièces
// Partiels d'une cloche d'église (hum, prime, tierce mineure, quinte, nominal, ...) : inharmoniques.
const BELL = [
  [0.5, 0.3, 1.5], [1, 1, 1], [1.183, 0.55, 0.75], [1.506, 0.35, 0.65], [2.0, 0.5, 0.55],
  [2.514, 0.28, 0.42], [2.662, 0.22, 0.38], [3.011, 0.2, 0.3], [4.166, 0.14, 0.22],
  [5.433, 0.1, 0.16], [6.796, 0.07, 0.12], [8.215, 0.05, 0.09],
];
/** Cloche additive : chaque partiel est doublé (léger désaccord -> battements), les aigus meurent plus vite. */
export function bell(sr, f0, r, { dur = 2.5, decay = 2.2, bright = 1, gain = 1, detune = 0.0016, strike = 0.3 } = {}) {
  f0 = hz(f0);
  const list = [];
  for (const [ratio, a, ds] of BELL) {
    const amp = a * (ratio > 3 ? bright : 1) * 0.5;
    const ph = r(); // paire en phase au coup : attaque franche, puis battement lent
    list.push({ f: f0 * ratio * (1 + detune), a: amp, d: decay * ds, ph });
    list.push({ f: f0 * ratio * (1 - detune), a: amp, d: decay * ds * 0.92, ph });
  }
  const out = D.partials(sr, dur, list);
  if (strike) {
    const n = D.bp(D.white(sr, 0.03, r), sr, Math.min(f0 * 4, sr * 0.4), 1.2);
    D.mulEnv(n, sr, (t) => Math.exp(-t / 0.004));
    D.addAt(out, n, sr, 0, strike);
  }
  return D.scale(out, gain * 0.45);
}

/** Carillon FM « verre/cristal » : rapport modulant inharmonique, indice qui décroît (attaque brillante). */
export function chime(sr, f, { dur = 1.2, decay = 0.9, ratio = 3.5, index = 2.2, gain = 1, att = 0.0015, partial2 = 0.25 } = {}) {
  f = hz(f);
  const out = D.buf(sr, dur);
  const idx0 = index * Math.min(1, 2200 / f);
  for (let i = 0; i < out.length; i++) {
    const t = i / sr;
    const e = Math.exp((-6.9 * t) / decay) * Math.min(1, t / att);
    const ix = idx0 * Math.exp((-6.9 * t) / (decay * 0.35));
    const s = Math.sin(TAU * f * t + ix * Math.sin(TAU * f * ratio * t));
    const s2 = 2 * f * 1.002 < sr * 0.45 ? Math.sin(TAU * 2.002 * f * t) * partial2 * Math.exp((-6.9 * t) / (decay * 0.5)) : 0;
    out[i] = (s + s2) * e * gain;
  }
  return out;
}

/** Pièce métallique : modes de plaque circulaire, rebonds successifs plus faibles. */
export function coin(sr, r, { f0, decay, gain = 1, bounces, dur = 0.6 } = {}) {
  f0 = f0 ?? r.range(2600, 4300);
  decay = decay ?? r.range(0.15, 0.4);
  bounces = bounces ?? r.int(1, 3);
  const modes = [1, 1.59, 2.14, 2.3, 2.65, 2.92, 3.5, 4.13];
  const out = D.buf(sr, dur);
  let t = 0, g = 1;
  for (let b = 0; b <= bounces && t < dur - 0.04; b++) {
    const list = modes.map((m, k) => ({
      f: f0 * m * (1 + r.range(-0.004, 0.004)),
      a: r.range(0.35, 1) / (1 + k * 0.35),
      d: (decay * (b === 0 ? 1 : 0.6) * 1.2) / (1 + k * 0.45),
      ph: r(),
    }));
    D.addAt(out, D.partials(sr, dur - t, list), sr, t, g * 0.22);
    const click = D.hp(D.white(sr, 0.004, r), sr, 4500);
    D.mulEnv(click, sr, (x) => Math.exp(-x / 0.0007));
    D.addAt(out, click, sr, t, g * 0.5);
    t += r.range(0.03, 0.08) * (1 + b * 0.5);
    g *= r.range(0.3, 0.55);
  }
  return D.scale(out, gain);
}

/** Cascade/pluie de pièces : densité suivant `env`, + bruissement de tas. */
export function coinShower(sr, r, dur, { density = 40, env = () => 1, gain = 1, lo = 2400, hi = 4800, room = true } = {}) {
  const out = D.buf(sr, dur);
  const n = Math.round(density * dur);
  for (let k = 0; k < n; k++) {
    const t = r() * (dur - 0.15);
    const g = env(t);
    if (g <= 0.01 || r() > g) continue;
    D.addAt(out, coin(sr, r, { f0: r.range(lo, hi), dur: Math.min(0.6, dur - t), gain: r.range(0.4, 1) }), sr, t, 0.55);
  }
  const rustle = D.bp(D.white(sr, dur, r), sr, 5500, 0.7);
  const grain = D.smoothNoise(sr, dur, r, 40);
  for (let i = 0; i < rustle.length; i++) rustle[i] *= Math.abs(grain[i]) * env(i / sr) * 0.08;
  D.addAt(out, rustle, sr);
  const res = room ? D.reverb(out, sr, { room: 0.78, damp: 0.3, wet: 0.18 }) : out;
  return D.scale(res, gain);
}

/** Jeton d'argile : clic sec + quelques modes courts, petit cliquetis secondaire. */
export function chipClink(sr, r, { f0, gain = 1, dur = 0.2, tight = 1, rattle = 0.8 } = {}) {
  f0 = f0 ?? r.range(2100, 3000);
  const out = D.buf(sr, dur);
  const hit = (t, g) => {
    const amps = [1, 0.7, 0.5, 0.35, 0.25];
    const list = [1, 1.52, 2.27, 2.98, 3.6].map((m, k) => ({
      f: f0 * m * r.range(0.99, 1.01), a: amps[k] * r.range(0.6, 1), d: (r.range(0.05, 0.1) / (1 + k * 0.3)) * tight, ph: r(),
    }));
    D.addAt(out, D.partials(sr, dur - t, list), sr, t, g * 0.3);
    const click = D.hp(D.white(sr, 0.006, r), sr, 2500);
    D.mulEnv(click, sr, (x) => Math.exp(-x / 0.0009));
    D.addAt(out, click, sr, t, g * 0.55);
    const body = D.bp(D.white(sr, 0.02, r), sr, 900, 2);
    D.mulEnv(body, sr, (x) => Math.exp(-x / 0.004));
    D.addAt(out, body, sr, t, g * 0.4);
  };
  hit(0, 1);
  if (r() < rattle) hit(r.range(0.008, 0.025), r.range(0.2, 0.45));
  return D.scale(out, gain);
}

/** Choc mat d'un objet posé sur le feutre. */
export function feltThump(sr, r, { dur = 0.12, f = 120, gain = 1 } = {}) {
  const t1 = D.osc(sr, dur, { f: (t) => f * (1 + 0.6 * Math.exp(-t / 0.008)), amp: (t) => Math.exp(-t / 0.018) });
  const n = D.lp(D.white(sr, dur, r), sr, 1100);
  D.mulEnv(n, sr, (t) => Math.exp(-t / 0.007));
  return D.scale(D.sum(t1, D.scale(n, 0.8)), gain);
}

/** Coup de phalange / bois sur la table. */
export function knock(sr, r, { f0 = 190, gain = 1, dur = 0.16 } = {}) {
  const list = [
    { f: f0, a: 1, d: 0.09 }, { f: f0 * 2.31, a: 0.5, d: 0.05 },
    { f: f0 * 3.9, a: 0.3, d: 0.03 }, { f: f0 * 5.3, a: 0.18, d: 0.02 },
  ];
  const out = D.partials(sr, dur, list);
  const n = D.lp(D.white(sr, 0.01, r), sr, 3000);
  D.mulEnv(n, sr, (t) => Math.exp(-t / 0.0025));
  D.addAt(out, n, sr, 0, 0.7);
  return D.scale(out, gain * 0.6);
}

/** Bloc de bois (tic-tac). */
export function woodblock(sr, r, { f = 1500, gain = 1, dur = 0.1 } = {}) {
  const out = D.partials(sr, dur, [{ f, a: 1, d: 0.05 }, { f: f * 2.08, a: 0.35, d: 0.03 }, { f: f * 3.4, a: 0.15, d: 0.02 }]);
  const n = D.hp(D.white(sr, 0.006, r), sr, 3000);
  D.mulEnv(n, sr, (t) => Math.exp(-t / 0.0008));
  D.addAt(out, n, sr, 0, 0.4);
  return D.scale(out, gain);
}

// ================================================================ cartes
/** Glissement d'une carte : bruit à grain (friction) filtré en bande montante + petit choc final. */
export function cardSlide(sr, r, { dur = 0.26, slide = 0.16, gain = 1, bright = 1, tap = 0.6, f0 = 1600 } = {}) {
  const out = D.buf(sr, dur);
  const n = D.sum(D.white(sr, slide, r), D.scale(D.pink(sr, slide, r), 1.5));
  const grain = D.smoothNoise(sr, slide, r, 220);
  for (let i = 0; i < n.length; i++) n[i] *= 0.5 + 0.9 * Math.abs(grain[i]);
  const s = D.svf(n, sr, (t) => f0 + 3200 * bright * (t / slide), 0.8, 'bp');
  const air = D.hp(D.white(sr, slide, r), sr, 6000);
  const env = D.envLin([[0, 0], [0.02, 1], [slide * 0.7, 0.75], [slide, 0]]);
  for (let i = 0; i < s.length; i++) s[i] = (s[i] + air[i] * 0.12) * env(i / sr);
  D.addAt(out, s, sr, 0, 1);
  if (tap) D.addAt(out, feltThump(sr, r, { f: r.range(150, 190), dur: Math.min(0.1, dur - slide + 0.01) }), sr, slide - 0.012, tap * 0.5);
  return D.scale(out, gain);
}

/** Retournement : deux claquements d'air rapprochés + souffle. */
export function cardFlip(sr, r, { dur = 0.16, gain = 1, f = 2200, gap = 0.035 } = {}) {
  const out = D.buf(sr, dur);
  const flap = (t, ff, g) => {
    const n = D.bp(D.white(sr, 0.05, r), sr, ff, 1.3);
    D.mulEnv(n, sr, (x) => Math.min(1, x / 0.002) * Math.exp(-x / 0.012));
    D.addAt(out, n, sr, t, g);
  };
  flap(0, f, 1);
  flap(gap, f * 1.3, 0.75);
  const w = D.svf(D.white(sr, 0.07, r), sr, (t) => 900 + 3000 * (t / 0.07), 0.8, 'bp');
  D.mulEnv(w, sr, (t) => Math.sin(Math.PI * Math.min(1, t / 0.07)));
  D.addAt(out, w, sr, 0.005, 0.25);
  const snap = D.hp(D.white(sr, 0.004, r), sr, 5000);
  D.mulEnv(snap, sr, (x) => Math.exp(-x / 0.0006));
  D.addAt(out, snap, sr, gap + 0.012, 0.5);
  return D.scale(out, gain);
}

/** Série de micro-clics de tranches de cartes (riffle / pont). times[] en secondes. */
export function cardClicks(sr, r, dur, times, { lp = 9000, gain = 1, f = 3200 } = {}) {
  const out = D.buf(sr, dur);
  for (const t of times) {
    const c = D.bp(D.white(sr, 0.006, r), sr, f * r.range(0.75, 1.3), 1.1);
    D.mulEnv(c, sr, (x) => Math.exp(-x / 0.0012));
    D.addAt(out, c, sr, t, r.range(0.5, 1));
  }
  return D.scale(D.lp(out, sr, lp), gain);
}

// ================================================================ percussions
export function kick(sr, r, { dur = 0.5, f0 = 48, f1 = 150, decay = 0.4, click = 0.3, gain = 1 } = {}) {
  const o = D.osc(sr, dur, { f: (t) => f0 + (f1 - f0) * Math.exp(-t / 0.035), amp: (t) => Math.min(1, t / 0.001) * Math.exp((-6.9 * t) / decay) });
  const c = D.lp(D.white(sr, 0.01, r), sr, 4000);
  D.mulEnv(c, sr, (t) => Math.exp(-t / 0.0015));
  D.addAt(o, c, sr, 0, click);
  return D.scale(D.drive(o, 1.4), gain);
}

export function snare(sr, r, { dur = 0.25, tone = 185, decay = 0.17, gain = 1, snappy = 1 } = {}) {
  const tn = D.osc(sr, dur, { f: (t) => tone * (1 + 0.4 * Math.exp(-t / 0.01)), amp: (t) => Math.exp((-6.9 * t) / 0.09) });
  const t2 = D.osc(sr, dur, { f: tone * 1.62, amp: (t) => 0.4 * Math.exp((-6.9 * t) / 0.06) });
  let n = D.hp(D.white(sr, dur, r), sr, 1500);
  n = D.lp(n, sr, Math.min(9500, sr * 0.45));
  D.mulEnv(n, sr, (t) => Math.min(1, t / 0.0008) * Math.exp((-6.9 * t) / decay));
  return D.scale(D.sum(D.scale(tn, 0.5), D.scale(t2, 0.5), D.scale(n, 0.9 * snappy)), gain);
}

/** Roulement de caisse claire : coups alternés main gauche/droite, amplitude `amp(t)`. */
export function snareRoll(sr, r, dur, { rate = 22, amp = () => 1, tone = 190, start = 0, end = dur, decay = 0.11 } = {}) {
  const out = D.buf(sr, dur);
  const step = 1 / rate;
  let k = 0;
  for (let t = start; t < end; t += step, k++) {
    const tt = Math.max(0, t + r.range(-0.08, 0.08) * step);
    const g = amp(tt) * r.range(0.8, 1) * (k % 2 ? 0.88 : 1);
    if (g <= 0) continue;
    D.addAt(out, snare(sr, r, { dur: 0.18, tone: tone * r.range(0.97, 1.03), decay, snappy: 1.1 }), sr, tt, g * 0.6);
  }
  return out;
}

export function timpani(sr, r, f0, { dur = 2, decay = 1.6, gain = 1 } = {}) {
  f0 = hz(f0);
  const R = [1, 1.504, 1.742, 2.0, 2.245, 2.494];
  const A = [1, 0.5, 0.35, 0.3, 0.2, 0.15];
  const Dd = [1, 0.7, 0.6, 0.5, 0.4, 0.35];
  const out = D.partials(sr, dur, R.map((x, i) => ({ f: f0 * x, a: A[i], d: decay * Dd[i], ph: r() })), { bend: (t) => 1 + 0.03 * Math.exp(-t / 0.04) });
  const m = D.lp(D.white(sr, 0.05, r), sr, 700);
  D.mulEnv(m, sr, (t) => Math.exp(-t / 0.01));
  D.addAt(out, m, sr, 0, 0.8);
  return D.scale(out, gain * 0.5);
}

/** Roulement de timbale. */
export function timpaniRoll(sr, r, f0, dur, { rate = 16, amp = () => 1 } = {}) {
  const out = D.buf(sr, dur + 1.2);
  for (let t = 0; t < dur; t += 1 / rate) D.addAt(out, timpani(sr, r, f0, { dur: 1.2, decay: 1 }), sr, t, amp(t) * r.range(0.7, 1) * 0.35);
  return out;
}

/** Cymbale crash : bruit aigu + métal à la 808 (carrés inharmoniques) filtré. */
export function crash(sr, r, { dur = 2.5, decay = 2, gain = 1 } = {}) {
  let n = D.hp(D.white(sr, dur, r), sr, 3500);
  D.mulEnv(n, sr, (t) => Math.min(1, t / 0.0015) * Math.exp((-6.9 * t) / decay));
  const freqs = [205.3, 304.4, 369.6, 522.7, 540, 800].map((f) => f * 1.7);
  const m = D.buf(sr, dur);
  for (const f of freqs) D.addAt(m, D.osc(sr, dur, { f, type: 'square', phase: r() }), sr, 0, 1 / 6);
  let mm = D.bp(m, sr, Math.min(7500, sr * 0.38), 0.7);
  D.mulEnv(mm, sr, (t) => Math.exp((-6.9 * t) / (decay * 0.55)));
  const out = D.sum(D.scale(n, 0.7), D.scale(mm, 0.7));
  return D.scale(out, gain);
}

// ================================================================ cuivres, trombone, voix
/** Note de cuivre synthétique : 3 dents de scie désaccordées, « scoop » d'attaque, filtre qui s'ouvre (blat). */
export function brassNote(sr, f, r, { dur = 0.6, gain = 1, bright = 1, vib = 0.006, rel = 0.12, att = 0.025, scoop = 0.025, voices = 3 } = {}) {
  f = hz(f);
  const total = dur + rel;
  const det = voices === 1 ? [0] : voices === 2 ? [-0.004, 0.004] : [-0.0065, 0, 0.0055];
  const raw = D.buf(sr, total);
  for (const d of det) D.addAt(raw, D.osc(sr, total, { f: (t) => f * (1 + d) * (1 - scoop * Math.exp(-t / 0.03)), type: 'saw', vib, vibDelay: 0.22, vibRate: 5.3, phase: r() }), sr, 0, 1 / det.length);
  const fc = (t) => {
    const a = att * 2;
    const e = t < a ? t / a : 0.55 + 0.45 * Math.exp(-(t - a) / 0.15);
    const rl = t > dur ? Math.max(0, 1 - (t - dur) / rel) : 1;
    return f * (1.2 + 7 * bright * e * (0.4 + 0.6 * rl));
  };
  const y = D.svf(raw, sr, fc, 0.9, 'lp');
  D.mulEnv(y, sr, D.envADSR(att, 0.12, 0.82, rel, dur));
  return D.scale(D.drive(y, 1.6), gain);
}

/** Séquence de fanfare : [[t, 'C4 E4 G4', dur, gain?], ...]. */
export function fanfare(sr, r, seq, { bright = 1, rel = 0.18, vib = 0.006, gain = 1, tail = 0.6 } = {}) {
  const end = Math.max(...seq.map(([t, , d]) => t + d)) + rel + tail;
  const out = D.buf(sr, end);
  for (const [t, chord, d, g = 1] of seq) {
    const ns = D.notes(chord);
    for (const f of ns) D.addAt(out, brassNote(sr, f, r, { dur: d, bright, rel, vib }), sr, t, g / Math.sqrt(ns.length));
  }
  return D.scale(out, gain);
}

/** Trombone bouché « wah » : notes [[t, from, to, dur, vibDepth]]. */
export function trombone(sr, r, seq, { gain = 1, wahRate = 0 } = {}) {
  const end = Math.max(...seq.map(([t, , , d]) => t + d)) + 0.25;
  const out = D.buf(sr, end);
  for (const [t, a, b, d, vib = 0.004, wr = wahRate] of seq) {
    const f0 = hz(a), f1 = hz(b);
    const total = d + 0.12;
    const fFn = (x) => f0 * Math.pow(f1 / f0, Math.min(1, x / d)) * (1 - 0.03 * Math.exp(-x / 0.03));
    const src = D.sum(
      D.osc(sr, total, { f: fFn, type: 'saw', vib, vibRate: 5, vibDelay: 0.15, phase: r() }),
      D.osc(sr, total, { f: (x) => fFn(x) * 1.004, type: 'saw', vib, vibRate: 5, vibDelay: 0.15, phase: r() }),
    );
    const wah = (x) => {
      const u = Math.min(1, x / d);
      let w = Math.pow(Math.sin(Math.PI * Math.min(1, u * 1.15)), 0.7);
      if (wr) w *= 0.55 + 0.45 * Math.cos(TAU * wr * Math.max(0, x - 0.25));
      return 300 + 1500 * w;
    };
    const y = D.svf(src, sr, wah, 2.6, 'lp');
    D.mulEnv(y, sr, D.envADSR(0.03, 0.1, 0.85, 0.1, d));
    D.addAt(out, D.drive(y, 1.5), sr, t, 0.6);
  }
  return D.scale(out, gain);
}

/** Buzzer de jeu télévisé : carrés graves désaccordés, saturés. */
export function buzzer(sr, { dur = 0.6, f = 110, gain = 1 } = {}) {
  const x = D.sum(
    D.osc(sr, dur, { f, type: 'square' }),
    D.osc(sr, dur, { f: f * 1.06, type: 'saw' }),
    D.scale(D.osc(sr, dur, { f: f * 2.01, type: 'square' }), 0.3),
  );
  for (let i = 0; i < x.length; i++) x[i] *= 1 + 0.25 * Math.sin((TAU * 31 * i) / sr);
  let y = D.drive(x, 3);
  y = D.lp(y, sr, 2600, 0.9);
  D.mulEnv(y, sr, D.envADSR(0.004, 0.05, 0.9, 0.03, dur - 0.03));
  return D.scale(y, gain);
}

/** Sirène de jackpot « whoop » tournante. */
export function siren(sr, { dur = 2, rate = 2.2, lo = 650, hi = 1300, gain = 1 } = {}) {
  const f = (t) => lo + (hi - lo) * (0.5 - 0.5 * Math.cos(TAU * rate * t));
  const x = D.sum(D.scale(D.osc(sr, dur, { f, type: 'square' }), 0.5), D.osc(sr, dur, { f, type: 'tri' }));
  const y = D.lp(x, sr, 3800);
  D.mulEnv(y, sr, (t) => Math.min(1, t / 0.04) * Math.min(1, (dur - t) / 0.12) * (0.85 + 0.15 * Math.sin(TAU * 9 * t)));
  return D.scale(y, gain);
}

/** Foule qui acclame : voix voisées (dents de scie + formants de voyelles) + sifflets + applaudissements. */
export function crowd(sr, r, dur, { voices = 26, env = () => 1, whistles = 2, claps = 40, rise = 0.15, gain = 1, wet = 0.22 } = {}) {
  const out = D.buf(sr, dur);
  const vowels = [[730, 1090], [530, 1840], [570, 840], [660, 1700], [490, 1350], [800, 1200]];
  for (let v = 0; v < voices; v++) {
    const f0 = r.range(110, 330);
    const on = r.range(0, Math.min(0.3, dur * 0.15));
    const vd = r.range(dur * 0.55, dur - on);
    const [F1, F2] = r.pick(vowels).map((x) => x * (f0 > 200 ? 1.15 : 1) * r.range(0.95, 1.05));
    const wob = r.range(3, 7);
    const src = D.osc(sr, vd, { f: (t) => f0 * (1 + rise * Math.min(1, t / 0.35)) * (1 + 0.03 * Math.sin(TAU * wob * 0.3 * t)), type: 'saw', vib: 0.012, vibRate: r.range(4.5, 7), phase: r() });
    const br = D.white(sr, vd, r);
    for (let i = 0; i < src.length; i++) src[i] += br[i] * 0.25;
    const y = D.sum(D.bp(src, sr, F1, 5), D.scale(D.bp(src, sr, F2, 7), 0.6));
    const at = r.range(0.06, 0.2), rl = r.range(0.25, 0.6), ph = r() * TAU;
    D.mulEnv(y, sr, (t) => Math.min(1, t / at) * Math.min(1, Math.max(0, vd - t) / rl) * (0.75 + 0.25 * Math.sin(TAU * wob * t + ph)));
    D.addAt(out, y, sr, on, r.range(0.4, 1) * 0.35);
  }
  const bed = D.bp(D.pink(sr, dur, r), sr, 1200, 0.5);
  D.addAt(out, bed, sr, 0, 0.25);
  for (let w = 0; w < whistles; w++) {
    const t0 = r.range(0.1, Math.max(0.15, dur * 0.5));
    const wd = r.range(0.4, 0.7);
    const fa = r.range(1800, 2300), fb = fa * r.range(1.2, 1.4);
    const s = D.osc(sr, wd, { f: D.glide([[0, fa], [wd * 0.3, fb], [wd * 0.75, fb], [wd, fa * 0.9]]), vib: 0.01, vibRate: 7 });
    D.mulEnv(s, sr, D.envLin([[0, 0], [0.05, 1], [wd - 0.08, 0.8], [wd, 0]]));
    D.addAt(out, s, sr, t0, 0.12);
  }
  for (let c = 0; c < claps; c++) {
    const t = r.range(0.05, dur - 0.1);
    if (r() > env(t)) continue;
    const n = D.bp(D.white(sr, 0.04, r), sr, r.range(1000, 2200), 1.2);
    D.mulEnv(n, sr, (x) => Math.exp(-x / 0.008));
    D.addAt(out, n, sr, t, r.range(0.15, 0.35));
  }
  D.mulEnv(out, sr, env);
  return D.scale(D.reverb(out, sr, { room: 0.8, damp: 0.35, wet }), gain);
}

// ================================================================ souffles, montées, synthés
/** Souffle : bruit dans un passe-bande balayé f0 -> f1 (au pic) -> f2. */
export function whoosh(sr, r, { dur = 0.5, f0 = 400, f1 = 3500, f2 = 800, peakAt = 0.55, q = 1.2, gain = 1 } = {}) {
  const tp = dur * peakAt;
  const n = D.sum(D.white(sr, dur, r), D.scale(D.pink(sr, dur, r), 2));
  const y = D.svf(n, sr, D.glide([[0, f0], [tp, f1], [dur, f2]]), q, 'bp');
  D.mulEnv(y, sr, (t) => (t < tp ? Math.pow(t / tp, 1.6) : Math.pow(Math.max(0, (dur - t) / (dur - tp)), 1.3)));
  return D.scale(y, gain);
}

/** Montée (riser) : dent de scie qui grimpe + bruit en passe-haut qui s'ouvre. */
export function riser(sr, r, { dur = 0.8, f0 = 200, f1 = 900, gain = 1 } = {}) {
  const s = D.sum(
    D.osc(sr, dur, { f: D.glide([[0, f0], [dur, f1]]), type: 'saw' }),
    D.osc(sr, dur, { f: D.glide([[0, f0 * 1.01], [dur, f1 * 1.01]]), type: 'saw', phase: 0.3 }),
  );
  const sf = D.svf(s, sr, D.glide([[0, 600], [dur, 6000]]), 1.5, 'lp');
  const n = D.svf(D.white(sr, dur, r), sr, D.glide([[0, 800], [dur, 9000]]), 1, 'bp');
  const out = D.sum(D.scale(sf, 0.4), D.scale(n, 0.5));
  D.mulEnv(out, sr, (t) => Math.pow(t / dur, 1.5));
  return D.scale(out, gain);
}

/** Paillettes : pings aigus aléatoires sur une gamme pentatonique, avec écho. */
export function sparkle(sr, r, dur, { density = 30, lo = 2000, hi = 6000, gain = 1, env = () => 1, decay = 0.25 } = {}) {
  const out = D.buf(sr, dur);
  const scale = [];
  for (let m = 60; m < 120; m++) if ([0, 2, 4, 7, 9].includes(m % 12)) { const f = D.mtof(m); if (f >= lo && f <= Math.min(hi, sr * 0.3)) scale.push(f); }
  const n = Math.round(density * dur);
  for (let k = 0; k < n; k++) {
    const t = r() * (dur - 0.1);
    const g = env(t);
    if (g <= 0.02) continue;
    const f = r.pick(scale);
    D.addAt(out, chime(sr, f, { dur: Math.min(0.5, dur - t), decay: decay * r.range(0.6, 1.4), ratio: 2.0, index: 0.8, partial2: 0.1 }), sr, t, g * r.range(0.3, 1) * 0.3);
  }
  return D.scale(D.echo(out, sr, { time: 0.11, fb: 0.4, wet: 0.35, lpHz: 7000 }), gain);
}

/** Arpège de carillons. */
export function arp(sr, list, step, { decay = 0.7, gain = 1, dur, ratio = 3.5, index = 1.8, start = 0 } = {}) {
  const fs = typeof list === 'string' ? D.notes(list) : list.map(hz);
  const total = dur ?? start + fs.length * step + decay + 0.1;
  const out = D.buf(sr, total);
  fs.forEach((f, i) => D.addAt(out, chime(sr, f, { dur: Math.max(0.05, Math.min(decay * 1.2, total - start - i * step)), decay, ratio, index }), sr, start + i * step, 0.5));
  return D.scale(out, gain);
}

/** Notes carrées 8-bit (montée de bonus). */
export function blips(sr, list, step, { len = 0.07, gain = 1, pw = 0.25, total } = {}) {
  const fs = typeof list === 'string' ? D.notes(list) : list.map(hz);
  const out = D.buf(sr, total ?? fs.length * step + len + 0.05);
  fs.forEach((f, i) => {
    const b = D.osc(sr, len, { f, type: 'square', pw });
    D.mulEnv(b, sr, (t) => Math.min(1, t / 0.002) * Math.min(1, (len - t) / 0.01));
    D.addAt(out, D.lp(b, sr, 6000), sr, i * step, 0.3);
  });
  return D.scale(out, gain);
}

/** « Bloop » sinusoïdal avec glissando (interface, marchés). */
export function bloop(sr, { f0 = 600, f1 = 1200, dur = 0.12, gain = 1, fm = 0 } = {}) {
  const fFn = D.glide([[0, f0], [dur * 0.7, f1], [dur, f1]]);
  const out = D.buf(sr, dur);
  let ph = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / sr;
    const f = fFn(t);
    ph += f / sr;
    const s = Math.sin(TAU * ph + fm * Math.sin(TAU * ph * 2) * Math.exp(-t / 0.03));
    out[i] = s * Math.min(1, t / 0.003) * Math.pow(Math.max(0, 1 - t / dur), 1.5);
  }
  return D.scale(out, gain);
}

/** Petit « pop » d'interface. */
export function pop(sr, r, { f0 = 1150, f1 = 650, dur = 0.055, gain = 1 } = {}) {
  const o = D.osc(sr, dur, { f: (t) => f1 + (f0 - f1) * Math.exp(-t / 0.008), amp: (t) => Math.min(1, t / 0.0015) * Math.exp(-t / 0.012) });
  const c = D.hp(D.white(sr, 0.003, r), sr, 4000);
  D.mulEnv(c, sr, (t) => Math.exp(-t / 0.0005));
  D.addAt(o, c, sr, 0, 0.15);
  return D.scale(o, gain);
}

/** Rayon / zap : glissando exponentiel. */
export function zap(sr, { f0 = 3000, f1 = 200, dur = 0.18, gain = 1, type = 'saw' } = {}) {
  const x = D.osc(sr, dur, { f: D.glide([[0, f0], [dur, f1]]), type, amp: (t) => Math.min(1, t / 0.002) * Math.pow(1 - t / dur, 1.2) });
  return D.scale(D.lp(x, sr, 7000), gain);
}

/** Sifflet à coulisse. */
export function slideWhistle(sr, r, fFn, dur, { gain = 1, vib = 0.012 } = {}) {
  const x = D.sum(D.osc(sr, dur, { f: fFn, vib, vibRate: 6, vibDelay: 0.05 }), D.scale(D.osc(sr, dur, { f: (t) => fFn(t) * 2, vib, vibRate: 6 }), 0.12));
  const n = D.bp(D.white(sr, dur, r), sr, 2500, 0.8);
  for (let i = 0; i < x.length; i++) x[i] += n[i] * 0.05;
  D.mulEnv(x, sr, D.envLin([[0, 0], [0.04, 1], [dur * 0.8, 0.9], [dur, 0]]));
  return D.scale(x, gain);
}

/** Nappe chorus (accord tenu, attaque lente). */
export function pad(sr, chord, dur, r, { att = 0.25, rel = 0.5, bright = 2500, gain = 1, type = 'saw' } = {}) {
  const fs = D.notes(chord);
  const out = D.buf(sr, dur);
  for (const f of fs) for (const d of [-0.007, 0, 0.006]) D.addAt(out, D.osc(sr, dur, { f: f * (1 + d), type, phase: r(), vib: 0.003, vibRate: r.range(0.3, 0.8) }), sr, 0, 1 / (3 * fs.length));
  const y = D.lp(out, sr, bright, 0.7);
  D.mulEnv(y, sr, (t) => Math.min(1, t / att) * Math.min(1, Math.max(0, dur - t) / rel));
  return D.scale(y, gain);
}

/** Lame métallique « shhing » : partiels aigus inharmoniques qui montent + bruit balayé. */
export function shing(sr, r, { dur = 0.7, gain = 1, f0 = 2900 } = {}) {
  const list = [1, 1.37, 1.81, 2.23, 2.71].map((m, k) => ({ f: f0 * m, a: 1 / (1 + k * 0.5), d: 0.6 / (1 + k * 0.3), ph: r(), att: 0.01 }));
  const ring = D.partials(sr, dur, list, { bend: (t) => 1 + 0.03 * Math.min(1, t / 0.15) });
  const sw = D.svf(D.white(sr, 0.25, r), sr, D.glide([[0, 2000], [0.25, 11000]]), 1.5, 'bp');
  D.mulEnv(sw, sr, (t) => Math.sin(Math.PI * Math.min(1, t / 0.25)));
  const out = D.sum(D.scale(ring, 0.25), D.scale(sw, 0.6));
  return D.scale(D.reverb(out, sr, { room: 0.7, wet: 0.15 }), gain);
}

/** Caisse enregistreuse « ka-ching » : mécanisme (cliquetis + choc), tiroir, puis clochette double + pièces. */
export function kaching(sr, r, { dur = 1.6, gain = 1 } = {}) {
  const m = new D.Mix(sr, dur);
  [0, 0.022, 0.045].forEach((t, i) => m.add(chipClink(sr, r, { f0: 1800 + i * 300, tight: 0.5, rattle: 0 }), t, 0.5));
  m.add(feltThump(sr, r, { f: 90, dur: 0.15 }), 0.06, 0.9);
  const drawer = D.bp(D.white(sr, 0.12, r), sr, 1200, 0.9);
  D.mulEnv(drawer, sr, D.envLin([[0, 0], [0.01, 1], [0.12, 0]]));
  m.add(drawer, 0.06, 0.4);
  m.add(bell(sr, 2093, r, { dur: dur - 0.12, decay: 1.4, bright: 1.3, strike: 0.5 }), 0.12, 0.9);
  m.add(bell(sr, 2637, r, { dur: dur - 0.16, decay: 1.2, bright: 1.2, strike: 0.4 }), 0.16, 0.7);
  for (let k = 0; k < 4; k++) m.add(coin(sr, r, { dur: 0.5 }), 0.14 + r.range(0, 0.3), 0.35);
  return D.scale(D.reverb(m.out, sr, { room: 0.75, wet: 0.12 }), gain);
}
