// Primitives DSP pour la banque de sons procédurale de Vingt-Un.
// Aucune dépendance externe : Node pur, calcul en Float64, sortie WAV PCM 16 bits mono.

export const TAU = 2 * Math.PI;
export const P = (v) => (typeof v === 'function' ? v : () => v);
export const db = (d) => Math.pow(10, d / 20);
export const toDb = (a) => (a <= 0 ? -Infinity : 20 * Math.log10(a));
export const clamp = (x, lo, hi) => (x < lo ? lo : x > hi ? hi : x);
export const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
export const len = (sr, dur) => Math.max(1, Math.round(sr * dur));
export const buf = (sr, dur) => new Float64Array(len(sr, dur));

const NOTE_IDX = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
/** 'C#5', 'Bb3', 'A4' -> Hz. Un nombre est renvoyé tel quel. */
export function hz(n) {
  if (typeof n === 'number') return n;
  const m = /^([A-G])([#b]?)(-?\d)$/.exec(n);
  if (!m) throw new Error(`note invalide: ${n}`);
  const s = NOTE_IDX[m[1]] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0);
  return mtof(12 * (Number(m[3]) + 1) + s);
}
export const notes = (str) => str.trim().split(/\s+/).map(hz);

// ---------------------------------------------------------------- PRNG
export function hashSeed(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** mulberry32 : déterministe, rapide, suffisant pour l'audio. */
export function makeRng(seed) {
  let a = seed >>> 0;
  const r = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  r.range = (lo, hi) => lo + (hi - lo) * r();
  r.int = (lo, hi) => Math.floor(lo + (hi - lo + 1) * r());
  r.pick = (arr) => arr[Math.floor(r() * arr.length)];
  r.sign = () => (r() < 0.5 ? -1 : 1);
  r.fork = (k) => makeRng((Math.imul(seed ^ 0x9e3779b9, 31) + hashSeed(String(k))) >>> 0);
  return r;
}

// ---------------------------------------------------------------- buffers
export function addAt(dst, src, sr, t = 0, gain = 1) {
  const off = Math.round(t * sr);
  const n = Math.min(src.length, dst.length - off);
  for (let i = Math.max(0, -off); i < n; i++) dst[off + i] += src[i] * gain;
  return dst;
}
export function scale(x, g) {
  for (let i = 0; i < x.length; i++) x[i] *= g;
  return x;
}
export function mulEnv(x, sr, env) {
  for (let i = 0; i < x.length; i++) x[i] *= env(i / sr);
  return x;
}
export function sum(...arrs) {
  const n = Math.max(...arrs.map((a) => a.length));
  const out = new Float64Array(n);
  for (const a of arrs) for (let i = 0; i < a.length; i++) out[i] += a[i];
  return out;
}
export function peak(x) {
  let p = 0;
  for (let i = 0; i < x.length; i++) {
    const a = Math.abs(x[i]);
    if (a > p) p = a;
  }
  return p;
}
export function rms(x, from = 0, to = x.length) {
  let s = 0;
  for (let i = from; i < to; i++) s += x[i] * x[i];
  return Math.sqrt(s / Math.max(1, to - from));
}
export function reverse(x) {
  const out = new Float64Array(x.length);
  for (let i = 0; i < x.length; i++) out[i] = x[x.length - 1 - i];
  return out;
}
export class Mix {
  constructor(sr, dur) {
    this.sr = sr;
    this.out = buf(sr, dur);
  }
  add(src, t = 0, g = 1) {
    addAt(this.out, src, this.sr, t, g);
    return this;
  }
}

// ---------------------------------------------------------------- envelopes (fonctions du temps)
/** Attaque linéaire puis décroissance exponentielle ; `d` = temps pour -60 dB. */
export const envAD = (a, d) => (t) => (t < a ? t / a : Math.exp((-6.9 * (t - a)) / d));
/** Points [[t, v], ...] interpolés linéairement. */
export const envLin = (pts) => (t) => {
  if (t <= pts[0][0]) return pts[0][1];
  for (let i = 1; i < pts.length; i++) {
    if (t <= pts[i][0]) {
      const [t0, v0] = pts[i - 1];
      const [t1, v1] = pts[i];
      return v0 + ((v1 - v0) * (t - t0)) / Math.max(1e-9, t1 - t0);
    }
  }
  return pts[pts.length - 1][1];
};
/** ADSR : relâchement à partir de `hold`. */
export const envADSR = (a, d, s, r, hold) => (t) => {
  let v;
  if (t < a) v = t / a;
  else if (t < a + d) v = 1 - ((1 - s) * (t - a)) / d;
  else v = s;
  if (t > hold) v *= Math.max(0, 1 - (t - hold) / r);
  return v;
};
/** Interpolation exponentielle de fréquence entre points [[t, f], ...]. */
export const glide = (pts) => (t) => {
  if (t <= pts[0][0]) return pts[0][1];
  for (let i = 1; i < pts.length; i++) {
    if (t <= pts[i][0]) {
      const [t0, f0] = pts[i - 1];
      const [t1, f1] = pts[i];
      const u = (t - t0) / Math.max(1e-9, t1 - t0);
      return f0 * Math.pow(f1 / f0, u);
    }
  }
  return pts[pts.length - 1][1];
};

// ---------------------------------------------------------------- oscillateurs
function blep(t, dt) {
  if (t < dt) {
    t /= dt;
    return t + t - t * t - 1;
  }
  if (t > 1 - dt) {
    t = (t - 1) / dt;
    return t * t + t + t + 1;
  }
  return 0;
}

/**
 * Oscillateur à fréquence variable (sine | tri | saw | square, anti-repliement polyBLEP).
 * f, amp : nombre ou fonction du temps. vib : profondeur relative (0.01 = 1 %).
 */
export function osc(sr, dur, { f, type = 'sine', amp = 1, phase = 0, vib = 0, vibRate = 5.5, vibDelay = 0, pw = 0.5 }) {
  const F = P(f);
  const A = P(amp);
  const out = buf(sr, dur);
  let ph = phase - Math.floor(phase);
  for (let i = 0; i < out.length; i++) {
    const t = i / sr;
    let fr = F(t);
    if (vib) fr *= 1 + vib * Math.sin(TAU * vibRate * t) * clamp((t - vibDelay) / 0.15, 0, 1);
    const dt = clamp(fr / sr, 0, 0.5);
    let s;
    if (type === 'sine') s = Math.sin(TAU * ph);
    else if (type === 'tri') s = 4 * Math.abs(ph - 0.5) - 1;
    else if (type === 'saw') s = 2 * ph - 1 - blep(ph, dt);
    else s = (ph < pw ? 1 : -1) + blep(ph, dt) - blep((ph + 1 - pw) % 1, dt);
    out[i] = s * A(t);
    ph += dt;
    ph -= Math.floor(ph);
  }
  return out;
}

/**
 * Somme de partiels sinusoïdaux amortis : [{ f, a, d (T60 s), ph?, att? }].
 * `bend(t)` multiplie toutes les fréquences (glissando global).
 */
export function partials(sr, dur, list, { bend = null } = {}) {
  const out = buf(sr, dur);
  const n = out.length;
  for (const p of list) {
    if (p.f >= sr * 0.47 || p.a === 0) continue;
    const k = Math.exp(-6.9 / (p.d * sr));
    const attN = Math.max(1, Math.round((p.att ?? 0.0006) * sr));
    let e = p.a;
    let ph = p.ph ?? 0;
    const inc = p.f / sr;
    for (let i = 0; i < n; i++) {
      const fr = bend ? inc * bend(i / sr) : inc;
      const a = i < attN ? i / attN : 1;
      out[i] += Math.sin(TAU * ph) * e * a;
      ph += fr;
      if (ph > 1) ph -= 1;
      e *= k;
      if (e < 1e-6 * p.a && i > attN) break;
    }
  }
  return out;
}

// ---------------------------------------------------------------- bruits
export function white(sr, dur, r) {
  const out = buf(sr, dur);
  for (let i = 0; i < out.length; i++) out[i] = r() * 2 - 1;
  return out;
}
/** Bruit rose (filtre de Paul Kellet). */
export function pink(sr, dur, r) {
  const out = buf(sr, dur);
  let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
  for (let i = 0; i < out.length; i++) {
    const w = r() * 2 - 1;
    b0 = 0.99886 * b0 + w * 0.0555179;
    b1 = 0.99332 * b1 + w * 0.0750759;
    b2 = 0.969 * b2 + w * 0.153852;
    b3 = 0.8665 * b3 + w * 0.3104856;
    b4 = 0.55 * b4 + w * 0.5329522;
    b5 = -0.7616 * b5 - w * 0.016898;
    out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11;
    b6 = w * 0.115926;
  }
  return out;
}
/** Bruit lent (valeurs aléatoires lissées), normalisé en RMS ≈ 1 : modulation de grain. */
export function smoothNoise(sr, dur, r, rate) {
  const x = lp(lp(white(sr, dur, r), sr, rate), sr, rate);
  const g = rms(x) || 1;
  return scale(x, 1 / g);
}

// ---------------------------------------------------------------- filtres
/**
 * Filtre à variables d'état TPT (Zavalishin) : stable sous modulation rapide.
 * mode : lp | hp | bp (crête unitaire) | notch. cutoff : nombre ou fonction du temps.
 */
export function svf(x, sr, cutoff, q = 0.707, mode = 'lp') {
  const k = 1 / q;
  const out = new Float64Array(x.length);
  const isFn = typeof cutoff === 'function';
  let ic1 = 0, ic2 = 0, a1 = 0, a2 = 0, a3 = 0;
  const coef = (fc) => {
    fc = clamp(fc, 10, sr * 0.47);
    const g = Math.tan((Math.PI * fc) / sr);
    a1 = 1 / (1 + g * (g + k));
    a2 = g * a1;
    a3 = g * a2;
  };
  if (!isFn) coef(cutoff);
  const m = mode === 'lp' ? 0 : mode === 'hp' ? 1 : mode === 'bp' ? 2 : 3;
  for (let i = 0; i < x.length; i++) {
    if (isFn && (i & 7) === 0) coef(cutoff(i / sr));
    const v0 = x[i];
    const v3 = v0 - ic2;
    const v1 = a1 * ic1 + a2 * v3;
    const v2 = ic2 + a2 * ic1 + a3 * v3;
    ic1 = 2 * v1 - ic1;
    ic2 = 2 * v2 - ic2;
    out[i] = m === 0 ? v2 : m === 1 ? v0 - k * v1 - v2 : m === 2 ? v1 * k : v0 - k * v1;
  }
  return out;
}
export const lp = (x, sr, f, q = 0.707) => svf(x, sr, f, q, 'lp');
export const hp = (x, sr, f, q = 0.707) => svf(x, sr, f, q, 'hp');
export const bp = (x, sr, f, q = 1) => svf(x, sr, f, q, 'bp');

/** Suppression de la composante continue (passe-haut 1 pôle ~20 Hz). */
export function dcBlock(x, sr, fc = 20) {
  const R = 1 - (TAU * fc) / sr;
  const out = new Float64Array(x.length);
  let x1 = 0, y1 = 0;
  for (let i = 0; i < x.length; i++) {
    const y = x[i] - x1 + R * y1;
    x1 = x[i];
    y1 = y;
    out[i] = y;
  }
  return out;
}

// ---------------------------------------------------------------- effets
/**
 * Réverbération de Schroeder/Freeverb : 8 filtres en peigne amortis en parallèle + 4 passe-tout en série.
 * room = rétroaction des peignes (0.7–0.97), damp = amortissement des aigus (0–0.6).
 */
export function reverb(x, sr, { room = 0.84, damp = 0.25, wet = 0.25, dry = 1, pre = 0.008 } = {}) {
  const s = sr / 44100;
  const combT = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map((d) => Math.round(d * s));
  const apT = [556, 441, 341, 225].map((d) => Math.round(d * s));
  const n = x.length;
  const w = new Float64Array(n);
  const preN = Math.round(pre * sr);
  for (const d of combT) {
    const cb = new Float64Array(d);
    let idx = 0, fs = 0;
    for (let i = 0; i < n; i++) {
      const inp = i >= preN ? x[i - preN] * 0.015 : 0;
      const o = cb[idx];
      fs = o * (1 - damp) + fs * damp;
      cb[idx] = inp + fs * room;
      if (++idx >= d) idx = 0;
      w[i] += o;
    }
  }
  for (const d of apT) {
    const b = new Float64Array(d);
    let idx = 0;
    for (let i = 0; i < n; i++) {
      const bo = b[idx];
      const o = -w[i] + bo;
      b[idx] = w[i] + bo * 0.5;
      if (++idx >= d) idx = 0;
      w[i] = o;
    }
  }
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) out[i] = x[i] * dry + w[i] * 3 * wet;
  return out;
}

/** Écho à rétroaction avec passe-bas dans la boucle. */
export function echo(x, sr, { time = 0.22, fb = 0.35, wet = 0.3, lpHz = 4500 } = {}) {
  const d = Math.max(1, Math.round(time * sr));
  const line = new Float64Array(d);
  const out = new Float64Array(x.length);
  const c = Math.exp((-TAU * lpHz) / sr);
  let idx = 0, z = 0;
  for (let i = 0; i < x.length; i++) {
    const o = line[idx];
    z = o * (1 - c) + z * c;
    line[idx] = x[i] + z * fb;
    if (++idx >= d) idx = 0;
    out[i] = x[i] + o * wet;
  }
  return out;
}

/** Saturation douce : linéaire sous `thr`, courbe tanh au-dessus, sortie bornée par 1. */
export function softClip(x, thr = 0.7) {
  const out = new Float64Array(x.length);
  const k = 1 - thr;
  for (let i = 0; i < x.length; i++) {
    const a = Math.abs(x[i]);
    out[i] = a <= thr ? x[i] : Math.sign(x[i]) * (thr + k * Math.tanh((a - thr) / k));
  }
  return out;
}
export function drive(x, amount = 2) {
  const n = Math.tanh(amount);
  const out = new Float64Array(x.length);
  for (let i = 0; i < x.length; i++) out[i] = Math.tanh(x[i] * amount) / n;
  return out;
}
export function normalize(x, dBFS) {
  const p = peak(x);
  if (p > 0) scale(x, db(dBFS) / p);
  return x;
}
/** Fondus en cosinus surélevé. */
export function fades(x, sr, inS = 0.001, outS = 0.02) {
  const ni = Math.min(x.length, Math.round(inS * sr));
  const no = Math.min(x.length, Math.round(outS * sr));
  for (let i = 0; i < ni; i++) x[i] *= 0.5 - 0.5 * Math.cos((Math.PI * i) / ni);
  for (let i = 0; i < no; i++) x[x.length - 1 - i] *= 0.5 - 0.5 * Math.cos((Math.PI * i) / no);
  if (x.length) {
    x[0] = 0;
    x[x.length - 1] = 0;
  }
  return x;
}
/** Lecture à vitesse variable (rate < 0 = à l'envers), interpolation linéaire. */
export function varispeed(x, sr, rate, dur, start = 0) {
  const R = P(rate);
  const out = buf(sr, dur);
  let pos = start * sr;
  for (let i = 0; i < out.length; i++) {
    const i0 = Math.floor(pos);
    const fr = pos - i0;
    const a = i0 >= 0 && i0 < x.length ? x[i0] : 0;
    const b = i0 + 1 >= 0 && i0 + 1 < x.length ? x[i0 + 1] : 0;
    out[i] = a + (b - a) * fr;
    pos += R(i / sr);
  }
  return out;
}

/**
 * Fabrique une boucle sans couture : on rend `preroll + loop + xfade`, puis la queue
 * [loop, loop+xfade) est fondue enchaînée sur le début. Le dernier échantillon précède
 * donc exactement le premier dans le signal source -> continuité parfaite au rebouclage.
 */
export function makeLoop(sr, loopDur, xfDur, render, { preroll = 0, mode = 'power' } = {}) {
  const raw = render(preroll + loopDur + xfDur + 0.01);
  const L = len(sr, loopDur);
  const X = len(sr, xfDur);
  const p0 = Math.round(preroll * sr);
  const out = new Float64Array(L);
  for (let i = 0; i < L; i++) out[i] = raw[p0 + i];
  for (let i = 0; i < X; i++) {
    const u = i / X;
    const gi = mode === 'power' ? Math.sin((u * Math.PI) / 2) : u;
    const go = mode === 'power' ? Math.cos((u * Math.PI) / 2) : 1 - u;
    out[i] = raw[p0 + i] * gi + raw[p0 + L + i] * go;
  }
  return out;
}

// ---------------------------------------------------------------- WAV
export function encodeWav(x, sr) {
  const n = x.length;
  const b = Buffer.alloc(44 + n * 2);
  b.write('RIFF', 0, 'ascii');
  b.writeUInt32LE(36 + n * 2, 4);
  b.write('WAVE', 8, 'ascii');
  b.write('fmt ', 12, 'ascii');
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20); // PCM
  b.writeUInt16LE(1, 22); // mono
  b.writeUInt32LE(sr, 24);
  b.writeUInt32LE(sr * 2, 28);
  b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34);
  b.write('data', 36, 'ascii');
  b.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const v = Math.round(clamp(x[i], -1, 1) * 32767);
    b.writeInt16LE(v, 44 + i * 2);
  }
  return b;
}

/** Décode un WAV PCM ; renvoie { ok, errors, sr, channels, bits, format, data(Float64, -1..1), raw(Int16) }. */
export function decodeWav(b) {
  const errors = [];
  const res = { errors, sr: 0, channels: 0, bits: 0, format: 0, data: null, raw: null };
  if (b.length < 44) {
    errors.push('fichier trop court');
    return res;
  }
  if (b.toString('ascii', 0, 4) !== 'RIFF') errors.push('pas de RIFF');
  if (b.toString('ascii', 8, 12) !== 'WAVE') errors.push('pas de WAVE');
  if (b.readUInt32LE(4) !== b.length - 8) errors.push(`taille RIFF incohérente (${b.readUInt32LE(4)} vs ${b.length - 8})`);
  let off = 12;
  let dataOff = -1, dataLen = 0, gotFmt = false;
  while (off + 8 <= b.length) {
    const id = b.toString('ascii', off, off + 4);
    const sz = b.readUInt32LE(off + 4);
    if (id === 'fmt ') {
      gotFmt = true;
      res.format = b.readUInt16LE(off + 8);
      res.channels = b.readUInt16LE(off + 10);
      res.sr = b.readUInt32LE(off + 12);
      const byteRate = b.readUInt32LE(off + 16);
      const align = b.readUInt16LE(off + 20);
      res.bits = b.readUInt16LE(off + 22);
      if (byteRate !== (res.sr * res.channels * res.bits) / 8) errors.push('byteRate incohérent');
      if (align !== (res.channels * res.bits) / 8) errors.push('blockAlign incohérent');
    } else if (id === 'data') {
      dataOff = off + 8;
      dataLen = sz;
    }
    off += 8 + sz + (sz & 1);
  }
  if (!gotFmt) errors.push('chunk fmt absent');
  if (dataOff < 0) errors.push('chunk data absent');
  if (res.format !== 1) errors.push(`format ${res.format} ≠ PCM`);
  if (res.channels !== 1) errors.push(`${res.channels} canaux ≠ mono`);
  if (res.bits !== 16) errors.push(`${res.bits} bits ≠ 16`);
  if (dataOff >= 0) {
    if (dataOff + dataLen > b.length) errors.push('chunk data tronqué');
    const n = Math.floor(Math.min(dataLen, b.length - dataOff) / 2);
    res.raw = new Int16Array(n);
    res.data = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      const v = b.readInt16LE(dataOff + i * 2);
      res.raw[i] = v;
      res.data[i] = v / 32767;
    }
  }
  return res;
}
