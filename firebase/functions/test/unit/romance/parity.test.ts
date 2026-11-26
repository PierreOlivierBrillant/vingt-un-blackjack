/**
 * The story is copied to the app by tools/sync_story.mjs: app/assets/story/*.json and the embedded
 * Dart bundle must hold exactly the same bytes (SHA-256 of the LF-normalized text, as the Dart test
 * app/test/unit/romance_story_test.dart checks from its side).
 */
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

const ROOT = path.resolve(__dirname, '../../../../..');
const SRC = path.join(ROOT, 'firebase/functions/src/romance/story');
const ASSETS = path.join(ROOT, 'app/assets/story');
const BUNDLE = path.join(ROOT, 'app/lib/features/romance/story/story_bundle.g.dart');

const lf = (s: string) => s.replace(/\r\n/g, '\n');
const sha = (s: string) => createHash('sha256').update(Buffer.from(lf(s), 'utf8')).digest('hex');
const jsonFiles = (dir: string) => fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort();

describe('story parity (server ↔ app), run `node tools/sync_story.mjs` after editing the story', () => {
  it('app/assets/story has the same files with the same SHA-256', () => {
    expect(jsonFiles(ASSETS)).toEqual(jsonFiles(SRC));
    for (const f of jsonFiles(SRC)) {
      expect(sha(fs.readFileSync(path.join(ASSETS, f), 'utf8')), f).toBe(sha(fs.readFileSync(path.join(SRC, f), 'utf8')));
    }
  });

  it('the embedded Dart bundle lists the same SHA-256', () => {
    const dart = fs.readFileSync(BUNDLE, 'utf8');
    const listed = Object.fromEntries([...dart.matchAll(/^ {2}'([a-z0-9_]+\.json)': '([0-9a-f]{64})',$/gm)].map((m) => [m[1], m[2]]));
    expect(Object.keys(listed).sort()).toEqual(jsonFiles(SRC));
    for (const f of jsonFiles(SRC)) expect(listed[f], f).toBe(sha(fs.readFileSync(path.join(SRC, f), 'utf8')));
  });
});
