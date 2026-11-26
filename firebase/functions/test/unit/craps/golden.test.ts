/**
 * Craps golden files (regenerate deliberately: `npx vitest run --config vitest.unit.config.mts
 * test/unit/craps/golden.test.ts -u`, then review the diff):
 *  - test/golden/craps_transcript.json: a fixed-seed public table (2 scripted humans + 2 bots), 40
 *    rolls — dice, verdicts, point, every settlement row and every board. Any behavioural change of
 *    the engine, the module, the bots or the kernel shows up as a diff;
 *  - test/golden/craps_fairness_vectors.json: seeds, SHA-256 commitments and the dice they roll
 *    (`seededRng(seed)`: nextInt(6)+1 twice), read by the Dart verifier
 *    (app/test/unit/craps/craps_fairness_test.dart).
 */
import { describe, expect, it } from 'vitest';
import { commitForSeed, seededRng, sha256Hex } from '../../../src/engine';
import { rollDice } from '../../../src/games/craps/engine';
import { FREE_BOTS } from '../../../src/sim/profiles';
import { human } from '../kernel/harness';
import { CrapsWorld } from './helpers';

function transcript(rolls: number) {
  const w = new CrapsWorld({ seed: 7 });
  for (const b of FREE_BOTS.slice(0, 2)) w.tx((m) => m.join({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true }));
  for (let i = 1; i <= 2; i++) {
    w.fund(`h${i}`, 100_000);
    w.tx((m) => m.join(human(i)));
  }
  const out: unknown[] = [];
  let betFor = -1;
  for (let guard = 0; out.length < rolls && guard < 1_000; guard++) {
    if (w.pub.phase === 'betting' && betFor !== w.pub.round) {
      betFor = w.pub.round;
      const p = w.g.point;
      const b1 = { ...w.board('h1') };
      if (p === null) b1.pass = 1_000;
      else {
        if (b1.pass && !b1['odds:pass']) b1['odds:pass'] = 2_000;
        if (!b1.place6 && p !== 6) b1.place6 = 600;
        if (w.pub.round % 3 === 0) b1.come = 500;
      }
      w.setBets('h1', b1);
      const b2: Record<string, number> = { ...w.board('h2'), field: 500 };
      if (p === null) b2.dontPass = 500;
      if (w.pub.round % 5 === 0) b2.hard8 = 100;
      w.setBets('h2', b2);
      const shooter = w.g.shooterUid;
      if (shooter === 'h1' || shooter === 'h2') w.roll(shooter);
    }
    w.expire();
    for (const e of w.ofKind('history', w.last)) {
      const settle = w.ofKind('settle', w.last)[0];
      out.push({
        round: e.doc.round,
        commit: e.doc.fairness.commit,
        result: e.doc.result,
        rows: settle.rows.map((r) => [r.seatIndex, r.stakedCents, r.returnCents, r.netCents, r.outcome, r.counters]),
        boards: Object.fromEntries(w.pub.seats.filter((s) => s).map((s) => [s!.seatIndex, w.board(s!.uid)])),
        events: w.pub.events.filter((x) => !['join', 'leave'].includes(x.type)).map((x) => [x.type, x.seatIndex]),
      });
    }
  }
  return { out, wallets: Object.fromEntries(w.wallets) };
}

describe('craps golden files', () => {
  it('transcript of 40 rolls at a fixed seed', async () => {
    const t = transcript(40);
    expect(t.out).toHaveLength(40);
    await expect(JSON.stringify(t, null, 1) + '\n').toMatchFileSnapshot('../../golden/craps_transcript.json');
  });

  it('fairness vectors (seed → commitment → dice) shared with the Dart verifier', async () => {
    const vectors = Array.from({ length: 24 }, (_, i) => {
      const seed = sha256Hex(`craps-vector-${i}`);
      const [d1, d2] = rollDice(seededRng(seed));
      return { seed, commit: commitForSeed(seed), dice: [d1, d2], total: d1 + d2 };
    });
    // every face appears on both dice (the vectors exercise the whole range)
    for (const k of [0, 1]) expect(new Set(vectors.map((v) => v.dice[k])).size).toBe(6);
    await expect(JSON.stringify({ algorithm: 'd1 = seededRng(seed).nextInt(6) + 1; d2 = nextInt(6) + 1 (same stream); commit = sha256(seed)', vectors }, null, 1) + '\n')
      .toMatchFileSnapshot('../../golden/craps_fairness_vectors.json');
  });
});
