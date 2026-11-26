#!/usr/bin/env node
// Générateur de la banque de sons de Vingt-Un (100 % procédural, déterministe).
//
//   node tools/sfx/generate.mjs                 régénère tout + MANIFEST.md + MANIFEST.<groupe>.md
//   node tools/sfx/generate.mjs --only bust,ui_tap
//   node tools/sfx/generate.mjs --group roulette   seulement les sons d'un groupe (répétable : --group a,b)
//   node tools/sfx/generate.mjs --check         vérifie les fichiers présents (et leur reproductibilité),
//                                               les quotas par groupe et le budget total (quotas.json)
//   node tools/sfx/generate.mjs --list          liste les noms
//
// Groupes (Sprint 2) : « core » = les 83 sons du Sprint 1 (./sounds.mjs, figés : ils ne doivent pas
// changer d'un octet) ; puis un fichier par jeu et pour le Rendez-vous dans ./games/<groupe>.mjs (voir
// ./catalog.mjs), chacun avec son quota (./quotas.json) et son manifeste app/assets/sfx/MANIFEST.<groupe>.md.
// Un implémenteur de jeu ne touche QUE son ./games/<groupe>.mjs : ce générateur n'a pas à changer.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as D from './dsp.mjs';
import { SOUNDS } from './sounds.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT = path.join(ROOT, 'app', 'assets', 'sfx');
const MIB = 1024 * 1024;
const QUOTAS = JSON.parse(fs.readFileSync(path.join(HERE, 'quotas.json'), 'utf8'));
const MAX_BYTES = QUOTAS.totalMiB * MIB;

/** Groupes du Sprint 2, dans l'ordre de quotas.json (sans « core »). */
export const GROUPS = Object.keys(QUOTAS.groups).filter((g) => g !== 'core');
const GROUP_SOUNDS = {};
for (const g of GROUPS) {
  const mod = await import(new URL(`./games/${g}.mjs`, import.meta.url).href);
  if (!Array.isArray(mod.SOUNDS)) throw new Error(`games/${g}.mjs doit exporter SOUNDS (voir catalog.mjs)`);
  for (const s of mod.SOUNDS) {
    if (s.group !== g) throw new Error(`games/${g}.mjs : ${s.name} n'a pas été déclaré par catalog('${g}')`);
  }
  GROUP_SOUNDS[g] = mod.SOUNDS;
}
/** Tous les sons : core puis chaque groupe. */
export const ALL_SOUNDS = [...SOUNDS, ...GROUPS.flatMap((g) => GROUP_SOUNDS[g])];
const groupOf = (s) => s.group ?? 'core';
{
  const sum = Object.values(QUOTAS.groups).reduce((a, b) => a + b, 0);
  if (Math.abs(sum - QUOTAS.totalMiB) > 1e-9) throw new Error(`quotas.json : la somme des quotas (${sum}) ≠ totalMiB (${QUOTAS.totalMiB})`);
}

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
  for (const g of GROUPS) groupManifest(g);
}

/** MANIFEST.<groupe>.md : même tableau que MANIFEST.md, plus le quota du groupe. */
function groupManifest(g) {
  const list = GROUP_SOUNDS[g];
  let total = 0;
  const lines = [];
  lines.push(`# Banque de sons — groupe « ${g} »`, '');
  lines.push('> Fichier généré par `node tools/sfx/generate.mjs` — ne pas éditer à la main.', '');
  lines.push(`Source : \`tools/sfx/games/${g}.mjs\` (mode d'emploi : \`tools/sfx/catalog.mjs\`). Mêmes conventions que`);
  lines.push('`MANIFEST.md` (WAV PCM 16 bits mono, 32 000 ou 22 050 Hz) ; les **boucles** sont en 22 050 Hz.', '');
  lines.push('| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |');
  lines.push('|---|---:|---:|---:|:---:|---|');
  for (const s of list) {
    const f = path.join(OUT, `${s.name}.wav`);
    if (fs.existsSync(f)) total += fs.statSync(f).size;
    lines.push(`| \`${s.name}.wav\` | ${s.dur.toFixed(2)} s | ${s.sr} Hz | ${s.peak} dBFS | ${s.loop ? 'oui' : '—'} | ${s.use} |`);
  }
  lines.push('');
  lines.push(`Total : ${list.length} fichier(s), ${(total / MIB).toFixed(2)} Mio sur un quota de ${QUOTAS.groups[g]} Mio.`, '');
  fs.writeFileSync(path.join(OUT, `MANIFEST.${g}.md`), lines.join('\n'));
}

// ------------------------------------------------------------------ CLI
function parseArgs(argv) {
  const o = { only: null, groups: null, check: false, list: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--check') o.check = true;
    else if (a === '--list') o.list = true;
    else if (a === '--only') o.only = (o.only ?? []).concat(argv[++i].split(','));
    else if (a.startsWith('--only=')) o.only = (o.only ?? []).concat(a.slice(7).split(','));
    else if (a === '--group') o.groups = (o.groups ?? []).concat(argv[++i].split(','));
    else if (a.startsWith('--group=')) o.groups = (o.groups ?? []).concat(a.slice(8).split(','));
    else throw new Error(`argument inconnu : ${a}`);
  }
  return o;
}

/** Octets par groupe des fichiers présents ; renvoie les lignes d'échec (quotas). */
function checkBudget() {
  const fails = [];
  const used = {};
  for (const s of ALL_SOUNDS) {
    const f = path.join(OUT, `${s.name}.wav`);
    used[groupOf(s)] = (used[groupOf(s)] ?? 0) + (fs.existsSync(f) ? fs.statSync(f).size : 0);
  }
  for (const [g, quota] of Object.entries(QUOTAS.groups)) {
    const u = used[g] ?? 0;
    console.log(`  ${g.padEnd(10)} ${(u / MIB).toFixed(2)} / ${quota} Mio`);
    if (u > quota * MIB) fails.push(`le groupe ${g} dépasse son quota (${(u / MIB).toFixed(2)} > ${quota} Mio)`);
  }
  return fails;
}

function main() {
  const opt = parseArgs(process.argv.slice(2));
  const names = new Set(ALL_SOUNDS.map((s) => s.name));
  if (names.size !== ALL_SOUNDS.length) throw new Error('noms en double dans le catalogue');
  if (opt.only) for (const n of opt.only) if (!names.has(n)) throw new Error(`son inconnu : ${n}`);
  if (opt.groups) for (const g of opt.groups) if (g !== 'core' && !GROUPS.includes(g)) throw new Error(`groupe inconnu : ${g}`);
  let sel = opt.only ? ALL_SOUNDS.filter((s) => opt.only.includes(s.name)) : ALL_SOUNDS;
  if (opt.groups) sel = sel.filter((s) => opt.groups.includes(groupOf(s)));
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
    console.log(`\n${sel.length} sons vérifiés, ${bad} en échec, ${warned} avec avertissement ; poids total du dossier : ${(all / 1024 / 1024).toFixed(2)} Mio (max ${MAX_BYTES / 1024 / 1024}).`);
    if (all > MAX_BYTES) console.log(`ÉCHEC : le dossier dépasse ${MAX_BYTES / 1024 / 1024} Mio`);
    const quotaFails = checkBudget();
    for (const f of quotaFails) console.log(`ÉCHEC : ${f}`);
    process.exitCode = bad || orphans.length || all > MAX_BYTES || quotaFails.length ? 1 : 0;
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
