#!/usr/bin/env node
// Vérifie qu'un chantier du Sprint 2 ne modifie que les fichiers de son périmètre (tools/sprint2/owners.json).
//
//   node tools/sprint2/check_owners.mjs <chantier>              compare HEAD + copie de travail à la base (sprint-2)
//   node tools/sprint2/check_owners.mjs <chantier> --base <ref> autre base (ex. origin/sprint-2)
//   node tools/sprint2/check_owners.mjs <chantier> --files a b  vérifie une liste explicite (tests, hooks)
//   node tools/sprint2/check_owners.mjs --list                  liste les chantiers
//
// Fichiers considérés : ceux qui diffèrent entre merge-base(base, HEAD) et la copie de travail, plus les fichiers
// non suivis (hors .gitignore). Code de sortie 1 si un fichier est hors périmètre, 2 en cas d'erreur d'usage.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OWNERS = JSON.parse(fs.readFileSync(path.join(HERE, 'owners.json'), 'utf8'));

/** Glob → RegExp : `**` (dossiers quelconques, y compris aucun), `*` (hors '/'), `?` (un caractère hors '/'). */
export function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') {
        i++;
        if (glob[i + 1] === '/') {
          i++;
          re += '(?:.*/)?';
        } else {
          re += '.*';
        }
      } else {
        re += '[^/]*';
      }
    } else if (c === '?') {
      re += '[^/]';
    } else {
      re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
    }
  }
  return new RegExp(`^${re}$`);
}

const matchesAny = (file, globs) => globs.some((g) => globToRegExp(g).test(file));

/** Classe chaque fichier : 'ok' (allow), 'generated', ou un motif de refus. */
export function classify(chantier, files, owners = OWNERS) {
  const c = owners.chantiers[chantier];
  if (!c) throw new Error(`chantier inconnu : ${chantier}`);
  return files.map((file) => {
    if (matchesAny(file, owners.deny)) return { file, verdict: 'refusé (fichier réservé à la phase D)' };
    // Un 'allow' explicite du chantier l'emporte sur 'lead' (ex. a1 peut compléter le contrat, en ajout seulement).
    if (matchesAny(file, c.allow)) return { file, verdict: 'ok' };
    if (matchesAny(file, owners.lead)) return { file, verdict: 'refusé (contrat/plan réservé à la session principale)' };
    if (matchesAny(file, owners.generated)) return { file, verdict: 'generated' };
    return { file, verdict: 'refusé (hors périmètre)' };
  });
}

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function changedFiles(base) {
  const mb = git(['merge-base', base, 'HEAD']).trim();
  const lines = [
    ...git(['diff', '--name-only', '--no-renames', mb]).split('\n'),
    ...git(['ls-files', '--others', '--exclude-standard']).split('\n'),
  ];
  return [...new Set(lines.map((l) => l.trim().replace(/\\/g, '/')).filter(Boolean))].sort();
}

function main(argv) {
  if (argv.includes('--list')) {
    for (const [name, c] of Object.entries(OWNERS.chantiers)) console.log(`${name.padEnd(10)} ${c.description}`);
    return 0;
  }
  const chantier = argv[0];
  if (!chantier || chantier.startsWith('-')) {
    console.error('usage : node tools/sprint2/check_owners.mjs <chantier> [--base <ref>] [--files f1 f2 …] | --list');
    return 2;
  }
  if (!OWNERS.chantiers[chantier]) {
    console.error(`chantier inconnu : ${chantier} (connus : ${Object.keys(OWNERS.chantiers).join(', ')})`);
    return 2;
  }
  let files;
  const fi = argv.indexOf('--files');
  if (fi >= 0) {
    files = argv.slice(fi + 1).map((f) => f.replace(/\\/g, '/'));
  } else {
    const bi = argv.indexOf('--base');
    const base = bi >= 0 ? argv[bi + 1] : OWNERS.base;
    const root = git(['rev-parse', '--show-toplevel']).trim();
    process.chdir(root);
    files = changedFiles(base);
  }
  const res = classify(chantier, files);
  const bad = res.filter((r) => r.verdict.startsWith('refusé'));
  const gen = res.filter((r) => r.verdict === 'generated');
  for (const r of bad) console.log(`✗ ${r.file} — ${r.verdict}`);
  if (gen.length) console.log(`(fichiers dérivés modifiés, régénérés à la fusion : ${gen.length})`);
  console.log(`${chantier} : ${res.length} fichier(s) modifié(s), ${bad.length} hors périmètre.`);
  return bad.length ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
