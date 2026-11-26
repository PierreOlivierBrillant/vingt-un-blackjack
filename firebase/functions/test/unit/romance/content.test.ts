/**
 * Rendez-vous story content (src/romance/story/*.json): schema, graph without dead end, FR/EN,
 * lengths, forbidden words, choice deltas, structure (4 talks, 2 dates, 1 finale for every character
 * not listed in INCOMPLETE_CHARACTERS), rules.json = shared/romance.ts constants. Each rule is also
 * proven to fire on a broken copy of the story.
 */
import { describe, expect, it } from 'vitest';
import {
  AFFINITY_MAX, AFFINITY_TIER_THRESHOLDS, CHARACTER_IDS, CHOICE_DELTA_MAX, CHOICE_DELTA_MIN, DATE_TIERS,
  DATING_LIKES_PER_DAY, DATING_MESSAGES_PER_MATCH_PER_DAY, DUO_GIFT_AFFINITY, DUO_MESSAGE_AFFINITY_DAILY_CAP,
  DUO_TIER_THRESHOLDS, GIFT_AFFINITY, GIFTS_PER_CHARACTER_PER_DAY, TABLE_AFFINITY_DAILY_CAP,
} from '../../../src/shared/romance';
import { INCOMPLETE_CHARACTERS, STORY, type Story, type StoryScene } from '../../../src/romance/story';
import { checkStory, FORBIDDEN, GENDERED, KISS } from './storyCheck';

const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x)) as T;

/** A deep copy of the story with `mutate` applied to its scene list (indexes rebuilt). */
function brokenStory(mutate: (s: Story) => void): Story {
  const s = clone({
    rules: STORY.rules, characters: STORY.characters, gifts: STORY.gifts, scenes: STORY.scenes,
    datingLines: STORY.datingLines, tableLines: STORY.tableLines, sceneFiles: STORY.sceneFiles,
  }) as unknown as Story;
  mutate(s);
  s.giftById = new Map(s.gifts.map((g) => [g.id, g]));
  s.lineById = new Map(s.datingLines.map((l) => [l.id, l]));
  s.scenes = CHARACTER_IDS.flatMap((c) => s.sceneFiles[c].scenes as StoryScene[]);
  s.sceneById = new Map(s.scenes.map((x) => [x.id, x]));
  s.scenesOf = (c) => s.scenes.filter((x) => x.character === c);
  return s;
}

function firstScene(s: Story, kind: StoryScene['kind']): StoryScene {
  for (const c of CHARACTER_IDS) {
    const f = (s.sceneFiles[c].scenes as StoryScene[]).find((x) => x.kind === kind);
    if (f) return f;
  }
  throw new Error(`no ${kind} scene`);
}

describe('Rendez-vous story content', () => {
  it('passes every content check', () => {
    expect(checkStory(STORY, INCOMPLETE_CHARACTERS)).toEqual([]);
  });

  it('rules.json mirrors the constants of shared/romance.ts (read by the Flutter app)', () => {
    expect(STORY.rules).toEqual({
      affinityMax: AFFINITY_MAX,
      tierThresholds: [...AFFINITY_TIER_THRESHOLDS],
      tableAffinityDailyCap: TABLE_AFFINITY_DAILY_CAP,
      giftsPerCharacterPerDay: GIFTS_PER_CHARACTER_PER_DAY,
      giftAffinity: GIFT_AFFINITY,
      choiceDeltaMin: CHOICE_DELTA_MIN,
      choiceDeltaMax: CHOICE_DELTA_MAX,
      dateTiers: [...DATE_TIERS],
      duoTierThresholds: [...DUO_TIER_THRESHOLDS],
      duoMessageAffinityDailyCap: DUO_MESSAGE_AFFINITY_DAILY_CAP,
      duoGiftAffinity: DUO_GIFT_AFFINITY,
      datingLikesPerDay: DATING_LIKES_PER_DAY,
      datingMessagesPerMatchPerDay: DATING_MESSAGES_PER_MATCH_PER_DAY,
    });
  });

  it('complete characters: Lucas, Camille and Jade (4 talks, 2 dates, 1 finale, small talks)', () => {
    for (const c of ['lucas', 'camille', 'jade'] as const) {
      expect(INCOMPLETE_CHARACTERS).not.toContain(c);
      const kinds = STORY.scenesOf(c).map((s) => s.kind);
      expect(kinds.filter((k) => k === 'talk')).toHaveLength(4);
      expect(kinds.filter((k) => k === 'date')).toHaveLength(2);
      expect(kinds.filter((k) => k === 'finale')).toHaveLength(1);
      expect(kinds.filter((k) => k === 'smalltalk').length).toBeGreaterThanOrEqual(3);
    }
  });

  it('the 6 other characters: tastes, rewards and at least 2 small talks', () => {
    expect([...INCOMPLETE_CHARACTERS].sort()).toEqual(['alex', 'hugo', 'ines', 'marco', 'nora', 'theo']);
    for (const c of INCOMPLETE_CHARACTERS) {
      expect(Object.keys(STORY.characters[c].tastes).length).toBeGreaterThan(0);
      expect(Object.keys(STORY.characters[c].rewards).sort()).toEqual(['1', '2', '3', '4', '5']);
      expect(STORY.scenesOf(c).filter((s) => s.kind === 'smalltalk').length).toBeGreaterThanOrEqual(2);
    }
  });

  it('about 63 scenes are planned; the delivered ones are counted', () => {
    expect(STORY.scenes.length).toBeGreaterThanOrEqual(3 * 10 + 6 * 2);
  });

  it('word checks use Unicode boundaries and the language of the text', () => {
    const hit = (lang: 'fr' | 'en', s: string) => FORBIDDEN[lang].some((re) => re.test(s));
    expect(hit('fr', 'Les pieds nus dans le sable')).toBe(true);
    expect(hit('fr', 'Vénus brille, dénué de nuages')).toBe(false); // « é » is a letter
    expect(hit('en', 'Relax, it does not bite')).toBe(false); // « bite » is only refused in French
    expect(hit('en', 'A drunken sailor')).toBe(true);
    expect(GENDERED.fr.test('Un clin d’œil complice')).toBe(false);
    expect(GENDERED.fr.test('Il sourit.')).toBe(true);
    expect(GENDERED.en.test('Their hand, then hers.')).toBe(true);
    expect(KISS.fr.some((re) => re.test('Elle l’embrasse.'))).toBe(true);
  });

  describe('every rule fires on a broken copy', () => {
    const cases: Array<[string, (s: Story) => void, RegExp]> = [
      ['dead end (missing next)', (s) => {
        const sc = firstScene(s, 'talk');
        const n = Object.values(sc.nodes).find((x) => x.next !== undefined)!;
        n.next = 'nowhere';
      }, /dead end/],
      ['cycle', (s) => {
        const sc = firstScene(s, 'talk');
        const ends = Object.entries(sc.nodes).filter(([, n]) => n.end);
        const [id, n] = ends[0];
        delete n.end;
        n.next = sc.start;
        void id;
      }, /cycle/],
      ['unreachable node', (s) => {
        firstScene(s, 'talk').nodes.orphan = { who: 'narrator', text: { fr: 'Rien.', en: 'Nothing.' }, end: true };
      }, /unreachable/],
      ['delta out of range', (s) => {
        const sc = firstScene(s, 'talk');
        Object.values(sc.nodes).find((x) => x.choices)!.choices![0].delta = 11;
      }, /delta 11 outside/],
      ['missing English text', (s) => {
        const sc = firstScene(s, 'talk');
        sc.nodes[sc.start].text.en = '';
      }, /missing EN text/],
      ['too long', (s) => {
        const sc = firstScene(s, 'talk');
        sc.nodes[sc.start].text.fr = 'a'.repeat(281);
      }, /max 280/],
      ['forbidden word', (s) => {
        const sc = firstScene(s, 'smalltalk');
        sc.nodes[sc.start].text.en = 'You look so sexy tonight.';
      }, /forbidden word/],
      ['kiss outside the finale', (s) => {
        const sc = firstScene(s, 'date');
        sc.nodes[sc.start].text.fr = 'On s’embrasse ?';
      }, /kiss words only in a finale/],
      ['finale without fade', (s) => {
        const sc = firstScene(s, 'finale');
        for (const n of Object.values(sc.nodes)) delete n.fade;
      }, /fades to black/],
      ['minor', (s) => { s.characters.jade.age = 17; }, /adults only/],
      ['Alex gendered', (s) => {
        const sc = (s.sceneFiles.alex.scenes as StoryScene[])[0];
        const n = Object.values(sc.nodes).find((x) => x.who === 'narrator') ?? sc.nodes[sc.start];
        n.who = 'narrator';
        n.text.fr = 'Il sourit.';
      }, /gendered pronoun/],
      ['complete character missing its finale', (s) => {
        s.sceneFiles.lucas.scenes = (s.sceneFiles.lucas.scenes as StoryScene[]).filter((x) => x.kind !== 'finale');
      }, /missing scene lucas_finale/],
      ['all choices conditional', (s) => {
        const sc = firstScene(s, 'talk');
        for (const c of Object.values(sc.nodes).find((x) => x.choices)!.choices!) c.if = { minTier: 5 };
      }, /every choice is conditional/],
    ];
    for (const [name, mutate, expected] of cases) {
      it(name, () => {
        const problems = checkStory(brokenStory(mutate), INCOMPLETE_CHARACTERS);
        expect(problems.join('\n')).toMatch(expected);
      });
    }
  });
});
