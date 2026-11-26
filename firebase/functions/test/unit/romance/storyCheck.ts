/**
 * Content checks of the Rendez-vous story (src/romance/story/*.json): schema, graph without dead end,
 * FR/EN completeness, lengths, forbidden words, deltas, structure of a complete character.
 * `checkStory` returns the list of problems (empty = OK); content.test.ts asserts it is empty and
 * that every rule really fires on a broken copy.
 */
import { z } from 'zod';
import { COSMETICS } from '../../../src/shared/cosmetics';
import {
  CHARACTER_IDS, CHOICE_DELTA_MAX, CHOICE_DELTA_MIN, DEALER_CHARACTER_IDS, type CharacterId,
} from '../../../src/shared/romance';
import { POWER_IDS } from '../../../src/shared/types';
import {
  EXPRESSIONS, PLACES, type LocalText, type Story, type StoryScene,
} from '../../../src/romance/story';

export const MAX_LEN = { line: 280, choice: 90, title: 40, table: 90, dating: 90, bio: 220, gift: 40 } as const;

/** Best-path affinity budget per scene kind; worst path must stay ≥ WORST_PATH_MIN. */
export const DELTA_BUDGET = { smalltalk: 10, talk: 25, date: 35, finale: 40 } as const;
export const WORST_PATH_MIN = -15;

export const NODE_COUNT = { smalltalk: [3, 20], talk: [6, 40], date: [6, 48], finale: [6, 48] } as const;

/**
 * Word pattern with UNICODE word boundaries (JS `\b` treats « é », « œ » as non-letters, so « Vénus »
 * would match « nus » and « œil » would match « il »). `head` = whole-word start only (prefix match).
 */
const W = (body: string, opts: { prefix?: boolean } = {}): RegExp =>
  new RegExp(`(?<![\\p{L}\\p{N}_])(?:${body})${opts.prefix ? '' : '(?![\\p{L}\\p{N}_])'}`, 'iu');
const words = (list: string[]) => list.map((w) => (w.endsWith('*') ? W(w.slice(0, -1), { prefix: true }) : W(w)));

/** Words refused (per language, whole words, case-insensitive; `*` = prefix). PG-13: nothing sexual, vulgar, drunk or drugs. */
export const FORBIDDEN: Readonly<Record<'fr' | 'en', readonly RegExp[]>> = {
  fr: words([
    'sexe', 'sexuel*', 'sexy', 'nue?s?', 'nudité', 'déshabill*', 'seins?', 'fesses?', 'orgasm*', 'érotique*', 'porno*',
    'lingerie', 'putain', 'merde', 'connard*', 'salope*', 'putes?', 'bite', 'couilles?', 'ivres?', 'ivresse', 'bourré*',
    'saoul*', 'soûl*', 'drogue*', 'cocaïne', 'coucher avec', 'nuit ensemble',
  ]),
  en: words([
    'sex', 'sexual*', 'sexy', 'naked', 'nude', 'nudity', 'undress*', 'breasts?', 'boobs?', 'erotic*', 'porn*', 'fuck*',
    'shit', 'bitch*', 'slut*', 'whore*', 'dick', 'cock', 'drunk*', 'drugs?', 'cocaine', 'weed', 'bedroom', 'hook ?up*',
    'horny', 'aroused?', 'sleep together', 'spend the night',
  ]),
};

/** Kiss words: allowed only in finale scenes (at most a kiss, at the finale, then fade to black). */
export const KISS: Readonly<Record<'fr' | 'en', readonly RegExp[]>> = {
  fr: words(['embrass*', 'bisou*', 'baiser*']),
  en: words(['kiss*', 'smooch*']),
};

/** Alex uses « iel » / « they »: narration in Alex's scenes never uses gendered pronouns. */
export const GENDERED: Readonly<Record<'fr' | 'en', RegExp>> = {
  fr: W('il|elle|ils|elles'),
  en: W('he|she|him|her|his|hers|himself|herself'),
};

const localText = z.strictObject({ fr: z.string(), en: z.string() });
const expr = z.enum(EXPRESSIONS);
const choiceSchema = z.strictObject({
  id: z.string().regex(/^[a-z0-9_]{1,24}$/),
  text: localText,
  delta: z.number().int(),
  next: z.string(),
  if: z.strictObject({ minTier: z.number().int().min(0).max(5).optional(), seen: z.string().optional() }).optional(),
});
const nodeSchema = z.strictObject({
  who: z.union([z.enum(CHARACTER_IDS), z.literal('narrator')]),
  expr: expr.optional(),
  text: localText,
  next: z.string().optional(),
  choices: z.array(choiceSchema).optional(),
  end: z.literal(true).optional(),
  fade: z.literal(true).optional(),
});
export const sceneSchema = z.strictObject({
  id: z.string().regex(/^[a-z0-9_]{1,64}$/),
  character: z.enum(CHARACTER_IDS),
  kind: z.enum(['talk', 'smalltalk', 'date', 'finale']),
  minTier: z.number().int().min(0).max(5),
  requires: z.array(z.string()),
  reservationCents: z.number().int().positive().optional(),
  place: z.enum(PLACES),
  title: localText,
  start: z.string(),
  nodes: z.record(z.string().regex(/^[A-Za-z0-9_]{1,32}$/), nodeSchema),
});
const tableLinesSchema = z.strictObject({
  greet: z.record(z.string(), z.array(localText)),
  win: z.array(localText),
  bigWin: z.array(localText),
  lose: z.array(localText),
  push: z.array(localText),
});

function zodProblems(where: string, r: { success: boolean; error?: z.ZodError }): string[] {
  return r.success ? [] : (r.error?.issues ?? []).slice(0, 5).map((i) => `${where}: schema ${i.path.join('.')}: ${i.message}`);
}

/** Every localized text of the story with where it is and its length limit. */
interface TextSite { where: string; text: LocalText; max: number; scene?: StoryScene; narrator?: boolean }

function textSites(story: Story): TextSite[] {
  const out: TextSite[] = [];
  for (const [id, c] of Object.entries(story.characters)) out.push({ where: `characters.${id}.bio`, text: c.bio, max: MAX_LEN.bio });
  for (const g of story.gifts) out.push({ where: `gifts.${g.id}`, text: g.name, max: MAX_LEN.gift });
  for (const l of story.datingLines) out.push({ where: `dating_lines.${l.id}`, text: l.text, max: MAX_LEN.dating });
  for (const [c, t] of Object.entries(story.tableLines)) {
    if (!t) continue;
    for (const [tier, ls] of Object.entries(t.greet ?? {})) ls.forEach((x, i) => out.push({ where: `table_lines.${c}.greet.${tier}[${i}]`, text: x, max: MAX_LEN.table }));
    for (const k of ['win', 'bigWin', 'lose', 'push'] as const) (t[k] ?? []).forEach((x, i) => out.push({ where: `table_lines.${c}.${k}[${i}]`, text: x, max: MAX_LEN.table }));
  }
  for (const s of story.scenes) {
    out.push({ where: `${s.id}.title`, text: s.title, max: MAX_LEN.title, scene: s });
    for (const [nid, n] of Object.entries(s.nodes ?? {})) {
      out.push({ where: `${s.id}.${nid}`, text: n.text, max: MAX_LEN.line, scene: s, narrator: n.who === 'narrator' });
      for (const ch of n.choices ?? []) out.push({ where: `${s.id}.${nid}.${ch.id}`, text: ch.text, max: MAX_LEN.choice, scene: s });
    }
  }
  return out;
}

/** Graph of one scene: reachability, acyclicity, dead ends, best/worst path. */
function checkGraph(s: StoryScene): string[] {
  const p: string[] = [];
  const nodes = s.nodes;
  if (!nodes[s.start]) return [`${s.id}: start node "${s.start}" missing`];
  const succ = (id: string): string[] => {
    const n = nodes[id];
    if (!n) return [];
    if (n.choices) return n.choices.map((c) => c.next);
    return n.next !== undefined ? [n.next] : [];
  };
  for (const [id, n] of Object.entries(nodes)) {
    const kinds = [n.next !== undefined, n.choices !== undefined, n.end === true].filter(Boolean).length;
    if (kinds !== 1) p.push(`${s.id}.${id}: exactly one of next / choices / end`);
    for (const t of succ(id)) if (!nodes[t]) p.push(`${s.id}.${id}: next "${t}" missing (dead end)`);
    if (n.choices) {
      if (n.choices.length < 2 || n.choices.length > 4) p.push(`${s.id}.${id}: 2 to 4 choices`);
      if (!n.choices.some((c) => !c.if)) p.push(`${s.id}.${id}: every choice is conditional (possible dead end)`);
      for (const c of n.choices) {
        if (c.delta < CHOICE_DELTA_MIN || c.delta > CHOICE_DELTA_MAX) p.push(`${s.id}.${id}.${c.id}: delta ${c.delta} outside ${CHOICE_DELTA_MIN}..${CHOICE_DELTA_MAX}`);
        if (c.if?.seen !== undefined && !c.if.seen.startsWith(`${s.character}_`)) p.push(`${s.id}.${id}.${c.id}: if.seen must be a scene of ${s.character}`);
      }
    }
    if (n.fade && !n.end) p.push(`${s.id}.${id}: fade only on an end node`);
    if (n.fade && s.kind !== 'finale') p.push(`${s.id}.${id}: fade only in a finale`);
    if (n.end && s.kind === 'finale' && !n.fade) p.push(`${s.id}.${id}: every end of a finale fades to black`);
  }
  // reachability + cycle detection (DFS colors) + best/worst delta (DP on the DAG)
  const color = new Map<string, 1 | 2>();
  const best = new Map<string, number>();
  const worst = new Map<string, number>();
  let cyclic = false;
  const visit = (id: string): void => {
    if (cyclic || !nodes[id]) return;
    const c = color.get(id);
    if (c === 1) { cyclic = true; return; }
    if (c === 2) return;
    color.set(id, 1);
    const n = nodes[id];
    let b = 0;
    let w = 0;
    if (n.choices) {
      b = -Infinity; w = Infinity;
      for (const ch of n.choices) {
        visit(ch.next);
        b = Math.max(b, ch.delta + (best.get(ch.next) ?? 0));
        w = Math.min(w, ch.delta + (worst.get(ch.next) ?? 0));
      }
    } else if (n.next !== undefined) {
      visit(n.next);
      b = best.get(n.next) ?? 0;
      w = worst.get(n.next) ?? 0;
    }
    best.set(id, b);
    worst.set(id, w);
    color.set(id, 2);
  };
  visit(s.start);
  if (cyclic) p.push(`${s.id}: the graph has a cycle`);
  for (const id of Object.keys(nodes)) if (!color.has(id)) p.push(`${s.id}.${id}: unreachable from start`);
  if (!cyclic) {
    const b = best.get(s.start) ?? 0;
    const w = worst.get(s.start) ?? 0;
    if (b > DELTA_BUDGET[s.kind]) p.push(`${s.id}: best path +${b} above the ${s.kind} budget ${DELTA_BUDGET[s.kind]}`);
    if (w < WORST_PATH_MIN) p.push(`${s.id}: worst path ${w} below ${WORST_PATH_MIN}`);
    if (b <= 0 && s.kind !== 'smalltalk') p.push(`${s.id}: no path gains affinity`);
  }
  const count = Object.keys(nodes).length;
  const [lo, hi] = NODE_COUNT[s.kind];
  if (count < lo || count > hi) p.push(`${s.id}: ${count} nodes (expected ${lo}..${hi})`);
  const choiceNodes = Object.values(nodes).filter((n) => n.choices).length;
  if (choiceNodes < (s.kind === 'smalltalk' ? 1 : 2)) p.push(`${s.id}: ${choiceNodes} choice nodes (too few)`);
  const ids = Object.values(nodes).flatMap((n) => (n.choices ?? []).map((c) => c.id));
  if (new Set(ids).size !== ids.length) p.push(`${s.id}: choice ids must be unique in the scene`);
  return p;
}

const STRUCTURE: Array<{ suffix: string; kind: StoryScene['kind']; minTier: number; requires: string[]; reservationCents?: number }> = [
  { suffix: 'talk_1', kind: 'talk', minTier: 0, requires: [] },
  { suffix: 'talk_2', kind: 'talk', minTier: 1, requires: ['talk_1'] },
  { suffix: 'talk_3', kind: 'talk', minTier: 2, requires: ['talk_2'] },
  { suffix: 'talk_4', kind: 'talk', minTier: 3, requires: ['talk_3'] },
  { suffix: 'date_1', kind: 'date', minTier: 3, requires: ['talk_3'], reservationCents: 5_000 },
  { suffix: 'date_2', kind: 'date', minTier: 4, requires: ['date_1', 'talk_4'], reservationCents: 12_000 },
  { suffix: 'finale', kind: 'finale', minTier: 5, requires: ['date_2'], reservationCents: 20_000 },
];

export function checkStory(story: Story, incomplete: readonly CharacterId[]): string[] {
  const p: string[] = [];
  // --- characters
  for (const c of CHARACTER_IDS) {
    const ch = story.characters[c];
    if (!ch) { p.push(`characters.${c}: missing`); continue; }
    if (!(ch.age >= 24 && ch.age <= 38)) p.push(`characters.${c}: age ${ch.age} outside 24..38 (adults only)`);
    if (c === 'alex' && ch.pronoun !== 'they') p.push('characters.alex: pronoun must be "they" (iel)');
    for (const [g, t] of Object.entries(ch.tastes)) {
      if (!story.giftById.has(g)) p.push(`characters.${c}.tastes: unknown gift ${g}`);
      if (!['loved', 'liked', 'disliked'].includes(t)) p.push(`characters.${c}.tastes.${g}: bad taste ${t}`);
    }
    const loved = Object.values(ch.tastes).filter((t) => t === 'loved').length;
    if (loved < 1) p.push(`characters.${c}: at least one loved gift`);
    const cosmetics: string[] = [];
    for (let tier = 1; tier <= 5; tier++) {
      const rs = ch.rewards[String(tier)] ?? [];
      if (rs.length === 0) p.push(`characters.${c}.rewards.${tier}: empty`);
      for (const r of rs) {
        if (r.kind === 'cosmetic') {
          cosmetics.push(r.id);
          const info = COSMETICS[r.id];
          if (!info || info.free) p.push(`characters.${c}.rewards.${tier}: ${r.id} is not an exclusive cosmetic`);
          if (!r.id.startsWith(`rv_${c}_`)) p.push(`characters.${c}.rewards.${tier}: ${r.id} belongs to another character`);
        } else if (r.kind === 'power') {
          if (!(POWER_IDS as readonly string[]).includes(r.powerId)) p.push(`characters.${c}.rewards.${tier}: unknown power ${r.powerId}`);
          if (!(Number.isInteger(r.qty) && r.qty >= 1 && r.qty <= 5)) p.push(`characters.${c}.rewards.${tier}: qty 1..5`);
        } else p.push(`characters.${c}.rewards.${tier}: unknown reward kind`);
      }
    }
    for (const want of [`rv_${c}_back`, `rv_${c}_felt`, `rv_${c}_title`]) {
      const n = cosmetics.filter((x) => x === want).length;
      if (n !== 1) p.push(`characters.${c}.rewards: ${want} must appear exactly once (found ${n})`);
    }
  }
  if (Object.keys(story.characters).some((k) => !(CHARACTER_IDS as readonly string[]).includes(k))) p.push('characters: unknown character id');
  // --- gifts
  if (story.gifts.length !== 12) p.push(`gifts: ${story.gifts.length} gifts (expected 12)`);
  if (new Set(story.gifts.map((g) => g.id)).size !== story.gifts.length) p.push('gifts: duplicate id');
  for (const g of story.gifts) {
    if (!/^[a-z0-9_]{1,32}$/.test(g.id)) p.push(`gifts.${g.id}: bad id`);
    if (!(Number.isSafeInteger(g.priceCents) && g.priceCents >= 100 && g.priceCents % 100 === 0)) p.push(`gifts.${g.id}: price must be whole dollars`);
  }
  if (!story.gifts.some((g) => g.drink)) p.push('gifts: at least one drink');
  // --- dating lines
  const lines = story.datingLines;
  if (lines.length < 35 || lines.length > 50) p.push(`dating_lines: ${lines.length} lines (expected ~40)`);
  if (new Set(lines.map((l) => l.id)).size !== lines.length) p.push('dating_lines: duplicate id');
  const openers = lines.filter((l) => l.kind === 'opener');
  if (openers.length < 8) p.push('dating_lines: at least 8 openers');
  const listed = new Set(lines.flatMap((l) => l.replies));
  for (const l of lines) {
    if (!/^[a-z0-9_]{1,32}$/.test(l.id)) p.push(`dating_lines.${l.id}: bad id`);
    if (l.kind !== 'opener' && l.kind !== 'reply') p.push(`dating_lines.${l.id}: bad kind`);
    for (const r of l.replies) {
      const t = story.lineById.get(r);
      if (!t) p.push(`dating_lines.${l.id}: unknown reply ${r}`);
      else if (t.kind !== 'reply') p.push(`dating_lines.${l.id}: reply ${r} is not a "reply" line`);
    }
    if (l.kind === 'opener' && l.replies.length < 2) p.push(`dating_lines.${l.id}: an opener offers at least 2 replies`);
    if (l.kind === 'reply' && !listed.has(l.id)) p.push(`dating_lines.${l.id}: reply never allowed by any line`);
  }
  // --- table lines (every croupier)
  for (const d of DEALER_CHARACTER_IDS) {
    const t = story.tableLines[d];
    if (!t) { p.push(`table_lines.${d}: missing`); continue; }
    p.push(...zodProblems(`table_lines.${d}`, tableLinesSchema.safeParse(t)));
    for (let tier = 0; tier <= 5; tier++) if (!(t.greet?.[String(tier)]?.length >= 1)) p.push(`table_lines.${d}.greet.${tier}: at least one line`);
    for (const k of ['win', 'bigWin', 'lose', 'push'] as const) if (!((t[k]?.length ?? 0) >= 2)) p.push(`table_lines.${d}.${k}: at least 2 lines`);
  }
  for (const k of Object.keys(story.tableLines)) if (!(DEALER_CHARACTER_IDS as readonly string[]).includes(k)) p.push(`table_lines.${k}: not a croupier`);
  // --- scenes: schema, ids, graph
  const seenIds = new Set<string>();
  for (const c of CHARACTER_IDS) {
    const file = story.sceneFiles[c];
    if (file.character !== c) p.push(`scenes_${c}.json: "character" must be "${c}"`);
    for (const raw of file.scenes) {
      const r = sceneSchema.safeParse(raw);
      const id = (raw as { id?: string }).id ?? '?';
      p.push(...zodProblems(`scenes_${c}.${id}`, r));
      if (!r.success) continue;
      const s = raw as StoryScene;
      if (s.character !== c) p.push(`${s.id}: character must be ${c}`);
      if (!s.id.startsWith(`${c}_`)) p.push(`${s.id}: id must start with ${c}_`);
      if (seenIds.has(s.id)) p.push(`${s.id}: duplicate scene id`);
      seenIds.add(s.id);
      const dateLike = s.kind === 'date' || s.kind === 'finale';
      if (dateLike !== (s.reservationCents !== undefined)) p.push(`${s.id}: reservationCents only (and always) on dates and the finale`);
      if (s.kind === 'smalltalk' && !/_small_[a-z0-9_]+$/.test(s.id)) p.push(`${s.id}: smalltalk ids are <character>_small_<word>`);
      if (s.kind === 'smalltalk' && (s.minTier > 3 || s.requires.length > 0)) p.push(`${s.id}: smalltalk minTier ≤ 3, no requires`);
      for (const req of s.requires) if (!req.startsWith(`${c}_`)) p.push(`${s.id}: requires ${req} of another character`);
      p.push(...checkGraph(s));
    }
  }
  for (const s of story.scenes) for (const req of s.requires) if (!story.sceneById.has(req)) p.push(`${s.id}: requires unknown scene ${req}`);
  for (const s of story.scenes) {
    for (const n of Object.values(s.nodes)) for (const ch of n.choices ?? []) if (ch.if?.seen && !story.sceneById.has(ch.if.seen)) p.push(`${s.id}.${ch.id}: if.seen unknown scene ${ch.if.seen}`);
  }
  // --- structure of complete / incomplete characters
  for (const c of CHARACTER_IDS) {
    const scenes = story.scenesOf(c);
    const small = scenes.filter((s) => s.kind === 'smalltalk');
    const isIncomplete = incomplete.includes(c);
    if (small.length < (isIncomplete ? 2 : 3)) p.push(`${c}: ${small.length} smalltalk scenes (need ≥ ${isIncomplete ? 2 : 3})`);
    const full = STRUCTURE.every((st) => story.sceneById.get(`${c}_${st.suffix}`)?.kind === st.kind);
    if (isIncomplete) {
      if (full && small.length >= 3) p.push(`${c}: story is complete, remove it from INCOMPLETE_CHARACTERS`);
    } else {
      for (const st of STRUCTURE) {
        const s = story.sceneById.get(`${c}_${st.suffix}`);
        if (!s) { p.push(`${c}: missing scene ${c}_${st.suffix}`); continue; }
        if (s.kind !== st.kind) p.push(`${s.id}: kind must be ${st.kind}`);
        if (s.minTier !== st.minTier) p.push(`${s.id}: minTier must be ${st.minTier}`);
        const req = st.requires.map((x) => `${c}_${x}`);
        if (JSON.stringify([...s.requires].sort()) !== JSON.stringify(req.sort())) p.push(`${s.id}: requires must be [${req.join(', ')}]`);
        if (st.reservationCents !== undefined && s.reservationCents !== st.reservationCents) p.push(`${s.id}: reservationCents must be ${st.reservationCents}`);
      }
      const extra = scenes.filter((s) => s.kind !== 'smalltalk' && !STRUCTURE.some((st) => s.id === `${c}_${st.suffix}`));
      for (const s of extra) p.push(`${s.id}: unexpected ${s.kind} scene (only talk_1..4, date_1..2, finale)`);
    }
  }
  // --- texts: FR/EN present, lengths, forbidden words, kiss only at the finale, Alex's pronouns
  for (const t of textSites(story)) {
    for (const lang of ['fr', 'en'] as const) {
      const v = t.text?.[lang];
      if (typeof v !== 'string' || v.trim() === '') { p.push(`${t.where}: missing ${lang.toUpperCase()} text`); continue; }
      if (v.length > t.max) p.push(`${t.where}: ${lang} text is ${v.length} chars (max ${t.max})`);
      if (v !== v.trim()) p.push(`${t.where}: ${lang} text has leading/trailing spaces`);
      for (const re of FORBIDDEN[lang]) if (re.test(v)) p.push(`${t.where}: forbidden word ${re} in ${lang}`);
      if (t.scene?.kind !== 'finale') for (const re of KISS[lang]) if (re.test(v)) p.push(`${t.where}: kiss words only in a finale (${re})`);
      if (t.scene?.character === 'alex' && t.narrator && GENDERED[lang].test(v)) {
        p.push(`${t.where}: narration of Alex's scenes uses ${lang === 'fr' ? 'iel' : 'they'} (gendered pronoun found)`);
      }
      const ph = [...v.matchAll(/\{(\w*)\}/g)].map((m) => m[1]);
      if (ph.some((x) => x !== 'name') || (ph.length > 0 && !t.where.startsWith('table_lines.'))) p.push(`${t.where}: only {name}, only in table lines`);
    }
    if (t.text && typeof t.text.fr === 'string' && typeof t.text.en === 'string') {
      const phFr = (t.text.fr.match(/\{name\}/g) ?? []).length;
      const phEn = (t.text.en.match(/\{name\}/g) ?? []).length;
      if (phFr !== phEn) p.push(`${t.where}: {name} differs between FR and EN`);
    }
  }
  return p;
}
