#!/usr/bin/env node
// Générateur de la banque de sons de Vingt-Un (100 % procédural, déterministe).
//
//   node tools/sfx/generate.mjs                 régénère tout + MANIFEST.md
//   node tools/sfx/generate.mjs --only bust,ui_tap
//   node tools/sfx/generate.mjs --check         vérifie les fichiers présents (et leur reproductibilité)
//   node tools/sfx/generate.mjs --list          liste les noms
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as D from './dsp.mjs';
import { SOUNDS } from './sounds.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT = path.join(ROOT, 'app', 'assets', 'sfx');
const MAX_BYTES = 6 * 1024 * 1024;

// ------------------------------------------------------------------ rendu
export function renderSound(def) {
  const r = D.makeRng(D.hashSeed(def.name));
  const raw = def.render({ sr: def.sr, dur: def.dur, r });
  const N = D.len(def.sr, def.dur);
  let y = new Float64Array(N);
  y.set(raw.length > N ? raw.subarray(0, N) : raw);
  for (let i = 0; i < N; i++) if (!Number.isFinite(y[i])) throw new Error(`${def.name}: valeur non finie à l'échantillon ${i}`);
  if (def.loop) {
    D.normalize(y, def.peak); // gain scalaire seulement : la continuité de boucle est préservée
  } else {
    y = D.dcBlock(y, def.sr);
    if (def.limit) {
      D.normalize(y, 0);
      y = D.softClip(D.scale(y, D.db(def.limit)), 0.6);
    }
    D.fades(y, def.sr, 0.0008, def.fadeOut ?? D.clamp(def.dur * 0.08, 0.008, 0.25));
    D.normalize(y, def.peak); // après les fondus : la crête atteint exactement la cible
  }
  if (D.peak(y) === 0) throw new Error(`${def.name}: silence`);
  return y;
}

// ------------------------------------------------------------------ vérification
function percentile(arr, p) {
  const a = Float64Array.from(arr).sort();
  return a[Math.min(a.length - 1, Math.floor(p * a.length))];
}

export function checkSound(def, { reproduce = true } = {}) {
  const file = path.join(OUT, `${def.name}.wav`);
  const errs = [];
  const warns = [];
  if (!fs.existsSync(file)) return { name: def.name, errs: ['fichier absent'], warns, info: {} };
  const bytes = fs.readFileSync(file);
  const w = D.decodeWav(bytes);
  errs.push(...w.errors);
  const info = { bytes: bytes.length };
  if (!w.data) return { name: def.name, errs, warns, info };
  const x = w.data, raw = w.raw, N = x.length;
  if (w.sr !== def.sr) errs.push(`fréquence ${w.sr} ≠ ${def.sr}`);
  const expected = D.len(def.sr, def.dur);
  info.dur = N / w.sr;
  if (N !== expected) errs.push(`durée ${N} éch. ≠ ${expected} attendus`);
  let pk = 0, clip = 0;
  for (let i = 0; i < N; i++) {
    const a = Math.abs(raw[i]);
    if (a > pk) pk = a;
    if (a >= 32767) clip++;
  }
  info.peakDb = D.toDb(pk / 32767);
  info.rmsDb = D.toDb(D.rms(x));
  if (clip > 0) errs.push(`${clip} échantillon(s) écrêté(s)`);
  if (info.peakDb > 0) errs.push(`crête ${info.peakDb.toFixed(2)} dBFS > 0`);
  if (info.peakDb > def.peak + 0.05) errs.push(`crête ${info.peakDb.toFixed(2)} dBFS > cible ${def.peak}`);
  if (!(info.rmsDb > -60)) errs.push(`RMS trop faible (${info.rmsDb.toFixed(1)} dBFS)`);
  if (def.loop) {
    const dx = new Float64Array(N - 1);
    for (let i = 1; i < N; i++) dx[i - 1] = Math.abs(x[i] - x[i - 1]);
    const jump = Math.abs(x[0] - x[N - 1]);
    const ref = percentile(dx, 0.999);
    info.loopJump = jump;
    info.loopRef = ref;
    if (jump > Math.max(1.5 * ref, 0.002)) errs.push(`discontinuité de boucle ${jump.toFixed(4)} (p99.9 interne ${ref.toFixed(4)})`);
    // l'énergie autour du point de bouclage doit être comparable au reste (pas de trou ni de bosse)
    const W = Math.round(0.05 * w.sr);
    const seam = Math.sqrt((D.rms(x, N - W, N) ** 2 + D.rms(x, 0, W) ** 2) / 2);
    const ratio = D.toDb(seam / D.rms(x));
    info.seamDb = ratio;
    if (Math.abs(ratio) > 6) warns.push(`niveau à la jointure ${ratio.toFixed(1)} dB vs moyenne`);
  } else {
    if (Math.abs(raw[0]) > 16 || Math.abs(raw[N - 1]) > 16) errs.push(`début/fin non nuls (${raw[0]}, ${raw[N - 1]})`);
    const W = Math.round(0.002 * w.sr);
    const head = D.peak(x.subarray(0, Math.round(0.0002 * w.sr))), tail = D.peak(x.subarray(N - W));
    if (head > D.db(-12)) errs.push(`attaque sans fondu (${D.toDb(head).toFixed(1)} dBFS dans les 0,2 premières ms)`);
    if (tail > 0.01) errs.push(`fin abrupte : ${D.toDb(tail).toFixed(1)} dBFS dans les 2 dernières ms`);
    const tailRms = D.toDb(D.rms(x, N - Math.round(0.03 * w.sr), N));
    if (tailRms > -40) warns.push(`queue encore audible à la coupe (${tailRms.toFixed(1)} dBFS sur 30 ms)`);
  }
  if (reproduce) {
    const again = D.encodeWav(renderSound(def), def.sr); // lève une erreur si NaN/Infinity
    info.reproducible = Buffer.compare(again, bytes) === 0;
    if (!info.reproducible) errs.push('le rendu actuel diffère du fichier (régénérer ?)');
  }
  return { name: def.name, errs, warns, info };
}

// ------------------------------------------------------------------ manifeste
function manifest() {
  const cats = [...new Set(SOUNDS.map((s) => s.cat))];
  let total = 0;
  const lines = [];
  lines.push('# Banque de sons — Vingt-Un', '');
  lines.push('> Fichier généré par `node tools/sfx/generate.mjs` — ne pas éditer à la main.', '');
  lines.push('Tous les sons sont **100 % synthétisés** (aucun échantillon externe) par `tools/sfx/` : additif, FM, bruit filtré,');
  lines.push('enveloppes, réverbération Schroeder/Freeverb, écho, saturation douce. Rendu déterministe (graine dérivée du nom).', '');
  lines.push('Format : WAV PCM 16 bits mono, 32 000 Hz (sons brillants : cloches, pièces) ou 22 050 Hz (graves, ambiance).');
  lines.push('Crêtes : −1 dBFS pour les gros effets, −3 à −6 dBFS pour les sons de jeu, −8 à −12 dBFS pour l\'interface.');
  lines.push('Les variantes `_1.._n` sont à tirer au hasard pour éviter la répétition.');
  lines.push('Les sons **bouclables** ont une jointure fondue enchaînée : les jouer en `ReleaseMode.loop` sans fondu supplémentaire.', '');
  for (const cat of cats) {
    lines.push(`## ${cat}`, '');
    lines.push('| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |');
    lines.push('|---|---:|---:|---:|:---:|---|');
    for (const s of SOUNDS.filter((x) => x.cat === cat)) {
      const f = path.join(OUT, `${s.name}.wav`);
      if (fs.existsSync(f)) total += fs.statSync(f).size;
      lines.push(`| \`${s.name}.wav\` | ${s.dur.toFixed(2)} s | ${s.sr} Hz | ${s.peak} dBFS | ${s.loop ? 'oui' : '—'} | ${s.use} |`);
    }
    lines.push('');
  }
  lines.push(`Total : ${SOUNDS.length} fichiers, ${(total / 1024 / 1024).toFixed(2)} Mio.`, '');
  fs.writeFileSync(path.join(OUT, 'MANIFEST.md'), lines.join('\n'));
}

// ------------------------------------------------------------------ CLI
function parseArgs(argv) {
  const o = { only: null, check: false, list: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--check') o.check = true;
    else if (a === '--list') o.list = true;
    else if (a === '--only') o.only = (o.only ?? []).concat(argv[++i].split(','));
    else if (a.startsWith('--only=')) o.only = (o.only ?? []).concat(a.slice(7).split(','));
    else throw new Error(`argument inconnu : ${a}`);
  }
  return o;
}

function main() {
  const opt = parseArgs(process.argv.slice(2));
  const names = new Set(SOUNDS.map((s) => s.name));
  if (names.size !== SOUNDS.length) throw new Error('noms en double dans le catalogue');
  if (opt.only) for (const n of opt.only) if (!names.has(n)) throw new Error(`son inconnu : ${n}`);
  const sel = opt.only ? SOUNDS.filter((s) => opt.only.includes(s.name)) : SOUNDS;
  if (opt.list) {
    for (const s of sel) console.log(`${s.name}\t${s.dur}s\t${s.sr}Hz${s.loop ? '\tloop' : ''}`);
    return;
  }
  fs.mkdirSync(OUT, { recursive: true });
  if (opt.check) {
    let bad = 0, warned = 0, total = 0;
    for (const s of sel) {
      const res = checkSound(s);
      total += res.info.bytes ?? 0;
      const i = res.info;
      const meta = i.dur != null ? `${i.dur.toFixed(3)}s crête ${i.peakDb.toFixed(2)} dBFS RMS ${i.rmsDb.toFixed(1)} dBFS${s.loop ? ` boucle saut=${i.loopJump.toFixed(4)} jointure ${i.seamDb.toFixed(1)} dB` : ''}` : '';
      const status = res.errs.length ? 'ÉCHEC' : res.warns.length ? 'OK*  ' : 'OK   ';
      if (res.errs.length) bad++;
      if (res.warns.length) warned++;
      console.log(`${status} ${s.name.padEnd(24)} ${meta}`);
      for (const e of res.errs) console.log(`        ✗ ${e}`);
      for (const w of res.warns) console.log(`        ! ${w}`);
    }
    const all = fs.readdirSync(OUT).filter((f) => f.endsWith('.wav')).reduce((a, f) => a + fs.statSync(path.join(OUT, f)).size, 0);
    const orphans = fs.readdirSync(OUT).filter((f) => f.endsWith('.wav') && !names.has(f.slice(0, -4)));
    for (const o of orphans) console.log(`ÉCHEC fichier orphelin hors catalogue : ${o}`);
    console.log(`\n${sel.length} sons vérifiés, ${bad} en échec, ${warned} avec avertissement ; poids total du dossier : ${(all / 1024 / 1024).toFixed(2)} Mio (max 6).`);
    if (all > MAX_BYTES) console.log('ÉCHEC : le dossier dépasse 6 Mio');
    process.exitCode = bad || orphans.length || all > MAX_BYTES ? 1 : 0;
    return;
  }
  const t0 = Date.now();
  for (const s of sel) {
    const t = Date.now();
    const y = renderSound(s);
    fs.writeFileSync(path.join(OUT, `${s.name}.wav`), D.encodeWav(y, s.sr));
    console.log(`${s.name.padEnd(24)} ${s.dur.toFixed(2)}s ${s.sr}Hz  (${Date.now() - t} ms)`);
  }
  manifest();
  console.log(`\n${sel.length} sons écrits dans ${path.relative(ROOT, OUT)} en ${((Date.now() - t0) / 1000).toFixed(1)} s ; MANIFEST.md à jour.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
