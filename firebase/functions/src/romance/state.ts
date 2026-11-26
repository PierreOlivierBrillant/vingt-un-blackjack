/**
 * Pure rules of the Rendez-vous meta (no Firebase): a character's RomanceDoc with defaults, table
 * play folding, affinity and tiers, rewards due (once per tier, ever), scene eligibility, DTO.
 * The transactional glue is in ./service.ts.
 */
import type { ErrorReason } from '../shared/types';
import {
  AFFINITY_MAX, CHARACTER_IDS, GIFTS_PER_CHARACTER_PER_DAY, TABLE_AFFINITY_DAILY_CAP, affinityTier,
  type CharacterId, type RomanceDoc, type RomanceStateDto,
} from '../shared/romance';
import type { StoryScene } from './story';

export function isCharacterId(v: unknown): v is CharacterId {
  return typeof v === 'string' && (CHARACTER_IDS as readonly string[]).includes(v);
}

const intMap = (v: unknown): Record<string, number> => {
  const out: Record<string, number> = {};
  if (v && typeof v === 'object') {
    for (const [k, n] of Object.entries(v as Record<string, unknown>)) if (typeof n === 'number' && Number.isFinite(n)) out[k] = Math.max(0, Math.floor(n));
  }
  return out;
};
const strList = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/**
 * The document with every field (a document written only by table settlements holds just
 * `tablePlay`; a missing document is all defaults).
 */
export function normalizeRomance(characterId: CharacterId, raw: Record<string, unknown> | undefined, now: number): RomanceDoc {
  const d = raw ?? {};
  const affinity = typeof d.affinity === 'number' ? Math.min(AFFINITY_MAX, Math.max(0, Math.floor(d.affinity))) : 0;
  const gifts = d.gifts && typeof d.gifts === 'object' ? (d.gifts as { day?: unknown; count?: unknown }) : {};
  return {
    characterId,
    affinity,
    tier: affinityTier(affinity),
    seen: strList(d.seen),
    talkDay: typeof d.talkDay === 'string' ? d.talkDay : null,
    gifts: { day: typeof gifts.day === 'string' ? gifts.day : '', count: typeof gifts.count === 'number' ? gifts.count : 0 },
    tablePlay: intMap(d.tablePlay),
    tableFolded: intMap(d.tableFolded),
    datesDone: strList(d.datesDone),
    finaleDone: d.finaleDone === true,
    rewardsGranted: Array.isArray(d.rewardsGranted) ? d.rewardsGranted.filter((x): x is number => Number.isInteger(x)) : [],
    updatedAtMs: typeof d.updatedAtMs === 'number' ? d.updatedAtMs : now,
  };
}

/** Days kept in tablePlay / tableFolded once folded (older settled days are pruned). */
export const TABLE_DAYS_KEPT = 3;

/**
 * Folds the blind table counters into affinity: per day, min(cap, played) − min(cap, folded before).
 * Returns the affinity added (before clamping) and prunes fully folded days older than TABLE_DAYS_KEPT
 * (the caller deletes them with FieldValue.delete, see `prunedDays`). Mutates `doc`.
 */
export function foldTablePlay(doc: RomanceDoc, today: string): { added: number; prunedDays: string[] } {
  let added = 0;
  for (const [day, played] of Object.entries(doc.tablePlay)) {
    const before = Math.min(TABLE_AFFINITY_DAILY_CAP, doc.tableFolded[day] ?? 0);
    const now = Math.min(TABLE_AFFINITY_DAILY_CAP, played);
    if (now > before) added += now - before;
    doc.tableFolded[day] = played;
  }
  const keep = new Set(lastDays(today, TABLE_DAYS_KEPT));
  const prunedDays = Object.keys(doc.tablePlay).filter((d) => !keep.has(d) && d < today);
  for (const d of prunedDays) {
    delete doc.tablePlay[d];
    delete doc.tableFolded[d];
  }
  for (const d of Object.keys(doc.tableFolded)) if (!(d in doc.tablePlay)) delete doc.tableFolded[d];
  if (added) addAffinity(doc, added);
  return { added, prunedDays };
}

function lastDays(today: string, n: number): string[] {
  const t = Date.parse(`${today}T00:00:00Z`);
  return Array.from({ length: n }, (_, i) => new Date(t - i * 86_400_000).toISOString().slice(0, 10));
}

/** Adds `delta` (clamped to 0..AFFINITY_MAX), updates the tier; returns the actual change. */
export function addAffinity(doc: RomanceDoc, delta: number): number {
  const before = doc.affinity;
  doc.affinity = Math.min(AFFINITY_MAX, Math.max(0, before + delta));
  doc.tier = affinityTier(doc.affinity);
  return doc.affinity - before;
}

/** Tiers 1..doc.tier whose rewards were never granted (marks them granted). Mutates `doc`. */
export function takeDueRewardTiers(doc: RomanceDoc): number[] {
  const due: number[] = [];
  for (let t = 1; t <= doc.tier; t++) if (!doc.rewardsGranted.includes(t)) due.push(t);
  doc.rewardsGranted = [...doc.rewardsGranted, ...due].sort((a, b) => a - b);
  return due;
}

/** Why `scene` cannot be played now (null = playable). The path itself is checked by replayScene. */
export function sceneBlock(scene: StoryScene, doc: RomanceDoc, today: string): ErrorReason | null {
  if (scene.character !== doc.characterId) return 'SCENE_NOT_AVAILABLE';
  if (doc.tier < scene.minTier) return 'SCENE_NOT_AVAILABLE';
  if (scene.requires.some((r) => !doc.seen.includes(r))) return 'SCENE_NOT_AVAILABLE';
  switch (scene.kind) {
    case 'talk':
      if (doc.seen.includes(scene.id)) return 'SCENE_NOT_AVAILABLE'; // story beats are played once (replay: Souvenirs)
      return doc.talkDay === today ? 'TALK_DONE_TODAY' : null;
    case 'smalltalk':
      return doc.talkDay === today ? 'TALK_DONE_TODAY' : null;
    case 'date':
      return doc.datesDone.includes(scene.id) ? 'SCENE_NOT_AVAILABLE' : null;
    case 'finale':
      return doc.finaleDone ? 'SCENE_NOT_AVAILABLE' : null;
  }
}

/** Records a completed scene. Mutates `doc`. */
export function completeScene(doc: RomanceDoc, scene: StoryScene, today: string): void {
  if (!doc.seen.includes(scene.id)) doc.seen = [...doc.seen, scene.id];
  if (scene.kind === 'talk' || scene.kind === 'smalltalk') doc.talkDay = today;
  if (scene.kind === 'date' && !doc.datesDone.includes(scene.id)) doc.datesDone = [...doc.datesDone, scene.id];
  if (scene.kind === 'finale') doc.finaleDone = true;
}

export function giftsLeftToday(doc: RomanceDoc, today: string): number {
  return doc.gifts.day === today ? Math.max(0, GIFTS_PER_CHARACTER_PER_DAY - doc.gifts.count) : GIFTS_PER_CHARACTER_PER_DAY;
}

export function toDto(doc: RomanceDoc, today: string): RomanceStateDto {
  return {
    characterId: doc.characterId,
    affinity: doc.affinity,
    tier: doc.tier,
    seen: [...doc.seen],
    talkAvailable: doc.talkDay !== today,
    giftsLeftToday: giftsLeftToday(doc, today),
    datesDone: [...doc.datesDone],
    finaleDone: doc.finaleDone,
    tableToday: Math.min(TABLE_AFFINITY_DAILY_CAP, doc.tablePlay[today] ?? 0),
    rewardsGranted: [...doc.rewardsGranted],
  };
}
