/**
 * Story of the Rendez-vous meta: typed view of `./story/*.json` (THE single source, copied to
 * app/assets/story/ and embedded in the Flutter app by tools/sync_story.mjs) + the pure replay of a
 * scene path. Format: ./story/README.md. Content rules (PG-13, adults, FR/EN, lengths, forbidden
 * words, graph without dead end) are enforced by test/unit/romance/content.test.ts.
 *
 * Pure module: no Firebase import (the callables in ../callables/romance.ts use it inside their
 * transaction).
 */
import charactersJson from './story/characters.json';
import datingLinesJson from './story/dating_lines.json';
import giftsJson from './story/gifts.json';
import rulesJson from './story/rules.json';
import tableLinesJson from './story/table_lines.json';
import scenesLucas from './story/scenes_lucas.json';
import scenesCamille from './story/scenes_camille.json';
import scenesInes from './story/scenes_ines.json';
import scenesAlex from './story/scenes_alex.json';
import scenesMarco from './story/scenes_marco.json';
import scenesJade from './story/scenes_jade.json';
import scenesTheo from './story/scenes_theo.json';
import scenesNora from './story/scenes_nora.json';
import scenesHugo from './story/scenes_hugo.json';
import type { CharacterId, GiftTaste, Reward, SceneKind } from '../shared/romance';
import { CHARACTER_IDS } from '../shared/romance';

/**
 * Characters whose story is NOT complete yet (only tastes, rewards, table lines and ≥ 2 small talks).
 * The content tests relax the "4 talks, 2 dates, 1 finale" rule for them ONLY. The story writer
 * removes a character from this list once its scenes are written (the test then requires the full
 * set, and fails if a complete character is still listed here).
 */
export const INCOMPLETE_CHARACTERS: readonly CharacterId[] = ['ines', 'alex', 'marco', 'theo', 'nora', 'hugo'];

export type Lang = 'fr' | 'en';
export interface LocalText { fr: string; en: string }

/** The 8 expressions of CharacterPainter (app/lib/core/characters/character_spec.dart). */
export const EXPRESSIONS = ['neutral', 'smile', 'laugh', 'wink', 'surprised', 'blush', 'sad', 'thinking'] as const;
export type Expression = (typeof EXPRESSIONS)[number];

/** Backdrops drawn in code by the Flutter scene player (romance/backdrops.dart). */
export const PLACES = [
  'casino', 'bar', 'lounge', 'terrace', 'rooftop', 'garden', 'restaurant', 'beach', 'harbor', 'museum', 'arcade', 'kitchen',
] as const;
export type Place = (typeof PLACES)[number];

export interface ChoiceCond {
  /** The choice is offered only from this tier (affinity tier BEFORE the scene). */
  minTier?: number;
  /** The choice is offered only if this scene was seen before. */
  seen?: string;
}

export interface StoryChoice {
  id: string;
  text: LocalText;
  /** Affinity delta (CHOICE_DELTA_MIN..CHOICE_DELTA_MAX). */
  delta: number;
  next: string;
  if?: ChoiceCond;
}

export interface StoryNode {
  /** Speaker: a character id, or 'narrator' (narration, no bust highlighted). */
  who: CharacterId | 'narrator';
  expr?: Expression;
  text: LocalText;
  /** Exactly one of next / choices / end. */
  next?: string;
  choices?: StoryChoice[];
  end?: boolean;
  /** End node only: fade to black (the finale). */
  fade?: boolean;
}

export interface StoryScene {
  id: string;
  character: CharacterId;
  kind: SceneKind;
  /** Minimum affinity tier to play it. */
  minTier: number;
  /** Scene ids (same character) that must have been completed first. */
  requires: string[];
  /** Dates / finale: reservation debited (ledger 'reservation') when the date is completed. */
  reservationCents?: number;
  place: Place;
  title: LocalText;
  start: string;
  nodes: Record<string, StoryNode>;
}

export interface StoryCharacter {
  age: number;
  pronoun: 'she' | 'he' | 'they';
  bio: LocalText;
  /** giftId → taste; absent = neutral. */
  tastes: Record<string, Exclude<GiftTaste, 'neutral'>>;
  /** Tier ("1".."5") → rewards granted once when the tier is first reached. */
  rewards: Record<string, Reward[]>;
}

export interface StoryGift {
  id: string;
  priceCents: number;
  /** A drink can also be offered to a match ("Offrir un verre", dating{op:'gift'}). */
  drink: boolean;
  icon: string;
  name: LocalText;
}

export interface DatingLine {
  id: string;
  /** opener: always allowed; reply: only right after a line of the OTHER member listing it in `replies`. */
  kind: 'opener' | 'reply';
  text: LocalText;
  /** Lines allowed as an answer to this one (besides openers). */
  replies: string[];
}

export interface TableLines {
  /** Tier ("0".."5") → greetings; `{name}` = the player's username. */
  greet: Record<string, LocalText[]>;
  win: LocalText[];
  bigWin: LocalText[];
  lose: LocalText[];
  push: LocalText[];
}

export interface StoryRules {
  affinityMax: number;
  tierThresholds: number[];
  tableAffinityDailyCap: number;
  giftsPerCharacterPerDay: number;
  giftAffinity: Record<GiftTaste, number>;
  choiceDeltaMin: number;
  choiceDeltaMax: number;
  dateTiers: number[];
  duoTierThresholds: number[];
  duoMessageAffinityDailyCap: number;
  duoGiftAffinity: number;
  datingLikesPerDay: number;
  datingMessagesPerMatchPerDay: number;
}

const SCENE_FILES: Record<CharacterId, { character: string; scenes: unknown[] }> = {
  lucas: scenesLucas, camille: scenesCamille, ines: scenesInes, alex: scenesAlex, marco: scenesMarco,
  jade: scenesJade, theo: scenesTheo, nora: scenesNora, hugo: scenesHugo,
};

export interface Story {
  rules: StoryRules;
  characters: Record<CharacterId, StoryCharacter>;
  gifts: StoryGift[];
  giftById: ReadonlyMap<string, StoryGift>;
  scenes: StoryScene[];
  sceneById: ReadonlyMap<string, StoryScene>;
  scenesOf: (c: CharacterId) => StoryScene[];
  datingLines: DatingLine[];
  lineById: ReadonlyMap<string, DatingLine>;
  tableLines: Partial<Record<CharacterId, TableLines>>;
  /** Raw scene files per character (content tests check `character` matches). */
  sceneFiles: Record<CharacterId, { character: string; scenes: unknown[] }>;
}

function build(): Story {
  const scenes: StoryScene[] = [];
  for (const c of CHARACTER_IDS) scenes.push(...(SCENE_FILES[c].scenes as StoryScene[]));
  const gifts = giftsJson.gifts as StoryGift[];
  const datingLines = datingLinesJson.lines as DatingLine[];
  const byChar = new Map<CharacterId, StoryScene[]>();
  for (const s of scenes) byChar.set(s.character, [...(byChar.get(s.character) ?? []), s]);
  return {
    rules: rulesJson as StoryRules,
    characters: charactersJson.characters as unknown as Record<CharacterId, StoryCharacter>,
    gifts,
    giftById: new Map(gifts.map((g) => [g.id, g])),
    scenes,
    sceneById: new Map(scenes.map((s) => [s.id, s])),
    scenesOf: (c) => byChar.get(c) ?? [],
    datingLines,
    lineById: new Map(datingLines.map((l) => [l.id, l])),
    tableLines: tableLinesJson.lines as unknown as Partial<Record<CharacterId, TableLines>>,
    sceneFiles: SCENE_FILES,
  };
}

export const STORY: Story = build();

// ---------------------------------------------------------------------------------- replay --

export interface ReplayContext {
  /** Affinity tier before the scene. */
  tier: number;
  /** Scenes completed before. */
  seen: ReadonlySet<string>;
}

export interface ReplayResult {
  /** Sum of the deltas of the choices taken. */
  delta: number;
  /** Id of the end node reached. */
  end: string;
}

/** Max nodes walked by a replay (scenes are acyclic, see the content tests; this is a guard). */
export const REPLAY_MAX_STEPS = 400;

export function choiceAllowed(c: StoryChoice, ctx: ReplayContext): boolean {
  if (c.if?.minTier !== undefined && ctx.tier < c.if.minTier) return false;
  if (c.if?.seen !== undefined && !ctx.seen.has(c.if.seen)) return false;
  return true;
}

/**
 * Replays the path `choices` (ids of the choices taken, in order) from the scene start: each choice
 * must exist at its node and be allowed (conditions), the path must reach an end node exactly when
 * the choices run out. Returns null for any invalid path (→ SCENE_INVALID_PATH).
 */
export function replayScene(scene: StoryScene, choices: readonly string[], ctx: ReplayContext): ReplayResult | null {
  let id = scene.start;
  let i = 0;
  let delta = 0;
  for (let steps = 0; steps < REPLAY_MAX_STEPS; steps++) {
    const node = scene.nodes[id];
    if (!node) return null;
    if (node.end) return i === choices.length ? { delta, end: id } : null;
    if (node.choices) {
      const want = choices[i++];
      if (want === undefined) return null;
      const c = node.choices.find((x) => x.id === want);
      if (!c || !choiceAllowed(c, ctx)) return null;
      delta += c.delta;
      id = c.next;
    } else if (node.next !== undefined) {
      id = node.next;
    } else {
      return null;
    }
  }
  return null;
}

/** Taste of `characterId` for `giftId` (neutral when not listed). */
export function tasteOf(characterId: CharacterId, giftId: string): GiftTaste {
  return STORY.characters[characterId]?.tastes[giftId] ?? 'neutral';
}

/** Rewards of reaching `tier` with `characterId` (tiers 1..5). */
export function tierRewards(characterId: CharacterId, tier: number): Reward[] {
  return STORY.characters[characterId]?.rewards[String(tier)] ?? [];
}
