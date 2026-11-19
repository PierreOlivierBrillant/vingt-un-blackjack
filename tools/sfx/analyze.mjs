#!/usr/bin/env node
// Analyse spectrale/temporelle des WAV générés, pour vérifier « à l'œil » qu'un son ressemble à ce qu'il prétend être.
//   node tools/sfx/analyze.mjs friend_request coin_single bust ...
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as D from './dsp.mjs';

const OUT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'app', 'assets', 'sfx');

function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const a = (-2 * Math.PI) / len, wr = Math.cos(a), wi = Math.sin(a);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const ur = re[i + k], ui = im[i + k];
        const vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci;
        const vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
        re[i + k] = ur + vr; im[i + k] = ui + vi;
        re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
        const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
      }
    }
  }
}

/** Spectre de puissance moyen (Welch, Hann) sur [a, b) échantillons. */
function spectrum(x, a, b, n = 4096) {
  const pw = new Float64Array(n / 2);
  let frames = 0;
  for (let s = a; s < Math.max(a + 1, b - n / 2); s += n / 2) {
    const re = new Float64Array(n), im = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      const v = s + i < b && s + i < x.length ? x[s + i] : 0;
      re[i] = v * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (n - 1)));
    }
    fft(re, im);
    for (let k = 0; k < n / 2; k++) pw[k] += re[k] * re[k] + im[k] * im[k];
    frames++;
  }
  for (let k = 0; k < n / 2; k++) pw[k] /= frames;
  return pw;
}

function stats(pw, sr, n) {
  let tot = 0, cen = 0, lg = 0, ar = 0, cnt = 0;
  const edges = [0, 250, 1000, 2500, 6000, 1e9];
  const bands = new Float64Array(edges.length - 1);
  for (let k = 1; k < pw.length; k++) {
    const f = (k * sr) / n;
    tot += pw[k];
    cen += f * pw[k];
    for (let b = 0; b < bands.length; b++) if (f >= edges[b] && f < edges[b + 1]) bands[b] += pw[k];
    if (f > 100 && f < Math.min(10000, sr / 2)) { lg += Math.log(pw[k] + 1e-20); ar += pw[k]; cnt++; }
  }
  return { centroid: cen / tot, bands: [...bands].map((v) => (100 * v) / tot), flatness: Math.exp(lg / cnt) / (ar / cnt) };
}

function peaks(pw, sr, n, count = 6, minHz = 60) {
  const max = Math.max(...pw);
  const res = [];
  for (let k = 2; k < pw.length - 2; k++) {
    const f = (k * sr) / n;
    if (f < minHz) continue;
    if (pw[k] > pw[k - 1] && pw[k] >= pw[k + 1] && pw[k] > pw[k - 2] && pw[k] >= pw[k + 2] && pw[k] > max * 1e-4) {
      const a = Math.log(pw[k - 1] + 1e-30), b = Math.log(pw[k] + 1e-30), c = Math.log(pw[k + 1] + 1e-30);
      const d = (0.5 * (a - c)) / (a - 2 * b + c);
      res.push({ k, f: ((k + d) * sr) / n, db: 10 * Math.log10(pw[k] / max) });
    }
  }
  res.sort((p, q) => q.db - p.db);
  const kept = [];
  for (const p of res) if (kept.every((q) => Math.abs(q.f - p.f) > 25)) kept.push(p);
  return kept.slice(0, count).sort((p, q) => p.f - q.f);
}

function envelope(x, sr, hop = 0.005) {
  const H = Math.round(hop * sr);
  const e = [];
  for (let i = 0; i + H <= x.length; i += H) e.push(D.rms(x, i, i + H));
  return e;
}

function pitchTrack(x, sr, times) {
  const W = Math.round(0.04 * sr);
  return times.map((t) => {
    const s = Math.round(t * sr);
    if (s + 2 * W > x.length) return null;
    let best = 0, bestLag = 0, e0 = 0;
    for (let i = 0; i < W; i++) e0 += x[s + i] * x[s + i];
    for (let lag = Math.round(sr / 1500); lag < Math.round(sr / 60); lag++) {
      let c = 0, e1 = 0;
      for (let i = 0; i < W; i++) { c += x[s + i] * x[s + i + lag]; e1 += x[s + i + lag] * x[s + i + lag]; }
      const v = c / Math.sqrt(e0 * e1 + 1e-12);
      if (v > best) { best = v; bestLag = lag; }
    }
    return best > 0.6 ? { t, f: sr / bestLag, clarity: best } : { t, f: null, clarity: best };
  });
}

function modRate(env, hop) {
  const n = 1 << Math.ceil(Math.log2(env.length));
  const m = env.reduce((a, b) => a + b, 0) / env.length;
  const re = new Float64Array(n), im = new Float64Array(n);
  env.forEach((v, i) => (re[i] = v - m));
  fft(re, im);
  let best = 0, bk = 0;
  for (let k = 1; k < n / 2; k++) {
    const f = k / (n * hop);
    if (f < 3 || f > 45) continue;
    const p = re[k] * re[k] + im[k] * im[k];
    if (p > best) { best = p; bk = k; }
  }
  return bk / (n * hop);
}

function analyze(name) {
  const w = D.decodeWav(fs.readFileSync(path.join(OUT, `${name}.wav`)));
  const x = w.data, sr = w.sr, N = x.length;
  const n = 4096;
  const all = stats(spectrum(x, 0, N, n), sr, n);
  const hop = 0.005;
  const env = envelope(x, sr, hop);
  const eMax = Math.max(...env);
  const iPk = env.indexOf(eMax);
  const i10 = env.findIndex((v) => v >= 0.1 * eMax), i90 = env.findIndex((v) => v >= 0.9 * eMax);
  let iDec = env.length - 1;
  for (let i = iPk; i < env.length; i++) if (env[i] < eMax * D.db(-30)) { iDec = i; break; }
  const lines = [];
  lines.push(`■ ${name}  (${(N / sr).toFixed(2)} s, ${sr} Hz)`);
  lines.push(`  centroïde ${Math.round(all.centroid)} Hz · planéité ${all.flatness.toFixed(3)} · bandes % [<250 | 250-1k | 1-2.5k | 2.5-6k | >6k] = ${all.bands.map((v) => v.toFixed(0)).join(' | ')}`);
  lines.push(`  attaque 10→90 % : ${((i90 - i10) * hop * 1000).toFixed(0)} ms · crête d'enveloppe à ${(iPk * hop).toFixed(2)} s · −30 dB atteint ${((iDec - iPk) * hop).toFixed(2)} s après · modulation d'enveloppe dominante ${modRate(env, hop).toFixed(1)} Hz`);
  const a = Math.round(iPk * hop * sr);
  const early = spectrum(x, a, a + Math.round(0.12 * sr), 8192);
  const pk = peaks(early, sr, 8192, 7);
  const lateA = a + Math.round(0.4 * sr);
  if (lateA + 0.12 * sr < N) {
    const late = spectrum(x, lateA, lateA + Math.round(0.12 * sr), 8192);
    const eMaxP = Math.max(...early);
    const f0 = pk.length ? pk[0].f : 1;
    lines.push('  partiels (fenêtre initiale) → niveau 0,4 s plus tard :');
    lines.push('   ' + pk.map((p) => {
      const lv = 10 * Math.log10((late[p.k] + late[p.k - 1] + late[p.k + 1]) / 3 / eMaxP);
      return `${Math.round(p.f)} Hz (×${(p.f / f0).toFixed(2)}) ${p.db.toFixed(0)}→${lv.toFixed(0)} dB`;
    }).join(' · '));
  } else {
    lines.push('  pics spectraux : ' + pk.map((p) => `${Math.round(p.f)} Hz (${p.db.toFixed(0)} dB)`).join(' · '));
  }
  const T = N / sr;
  const times = Array.from({ length: 8 }, (_, i) => (i + 0.5) * (T / 8));
  const pt = pitchTrack(x, sr, times);
  lines.push('  hauteur (autocorr.) : ' + pt.filter(Boolean).map((p) => `${p.t.toFixed(2)}s:${p.f ? Math.round(p.f) + 'Hz' : '—'}`).join(' '));
  return lines.join('\n');
}

const names = process.argv.slice(2);
if (!names.length) { console.log('usage : node tools/sfx/analyze.mjs <nom> [<nom> ...]'); process.exit(1); }
for (const n of names) console.log(analyze(n) + '\n');
