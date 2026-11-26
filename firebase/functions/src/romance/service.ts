/**
 * romance{op} inside the callable's transaction (src/callables/romance.ts): reads first, then the
 * pure rules of ./state.ts and the story replay of ./story.ts, then the writes.
 *
 *  - sync:      folds every character's table play, grants due rewards, returns the 9 characters.
 *  - playScene: eligibility (tier, prerequisites, once a day for talk/smalltalk, dates/finale once),
 *               replays the submitted path from the JSON (SCENE_INVALID_PATH), debits the date's
 *               reservation (ledger 'reservation') only now that it is completed, applies the deltas.
 *  - gift:      GIFTS_PER_CHARACTER_PER_DAY, ledger 'gift', affinity by taste.
 * Rewards of a tier are granted once ever (`rewardsGranted`), even if affinity drops and rises:
 * cosmetics → users/{uid}/unlocks/{id}, powers → users/{uid}/inventory (capped at POWER_MAX_INVENTORY).
 */
import type { DocumentSnapshot, Firestore, Transaction } from 'firebase-admin/firestore';
import type { UnlockDoc } from '../shared/cosmetics';
import { COSMETICS } from '../shared/cosmetics';
import { fail } from '../shared/errors';
import { refs } from '../shared/paths';
import {
  CHARACTER_IDS, GIFT_AFFINITY, GIFTS_PER_CHARACTER_PER_DAY,
  type CharacterId, type RomanceDoc, type RomanceRequest, type RomanceResponse,
} from '../shared/romance';
import { dayId } from '../shared/time';
import type { InventoryDoc, PowerId } from '../shared/types';
import { POWER_MAX_INVENTORY } from '../shared/types';
import { WalletSession } from '../shared/wallet';
import {
  addAffinity, completeScene, foldTablePlay, giftsLeftToday, normalizeRomance, sceneBlock, takeDueRewardTiers, toDto,
} from './state';
import { STORY, replayScene, tasteOf, tierRewards } from './story';

type Granted = RomanceResponse['granted'];

interface Ctx { db: Firestore; uid: string; now: number }

/** Rewards due on `docs` (marks them granted), then reads the inventories it needs (reads before writes). */
async function prepareRewards(tx: Transaction, { db, uid }: Ctx, docs: RomanceDoc[]): Promise<{ granted: Granted; inv: Map<PowerId, number> }> {
  const granted: Granted = [];
  for (const doc of docs) {
    for (const tier of takeDueRewardTiers(doc)) {
      for (const r of tierRewards(doc.characterId, tier)) granted.push({ ...r, characterId: doc.characterId, tier });
    }
  }
  const powers = [...new Set(granted.flatMap((g) => (g.kind === 'power' ? [g.powerId] : [])))];
  const snaps = powers.length ? await tx.getAll(...powers.map((p) => refs(db).inventory(uid, p))) : [];
  const inv = new Map<PowerId, number>(powers.map((p, i) => [p, (snaps[i].get('quantity') as number | undefined) ?? 0]));
  return { granted, inv };
}

function writeRewards(tx: Transaction, { db, uid, now }: Ctx, granted: Granted, inv: Map<PowerId, number>): void {
  const r = refs(db);
  for (const g of granted) {
    if (g.kind === 'cosmetic') {
      const info = COSMETICS[g.id];
      if (!info) continue;
      const unlock: UnlockDoc = { cosmeticId: g.id, slot: info.slot, source: 'romance', characterId: g.characterId, tier: g.tier, pairId: null, grantedAtMs: now };
      tx.set(r.unlock(uid, g.id), unlock);
    } else {
      inv.set(g.powerId, Math.min(POWER_MAX_INVENTORY, (inv.get(g.powerId) ?? 0) + g.qty));
    }
  }
  for (const [powerId, quantity] of inv) {
    const doc: InventoryDoc = { powerId, quantity, updatedAtMs: now };
    tx.set(r.inventory(uid, powerId), doc);
  }
}

function writeDoc(tx: Transaction, { db, uid, now }: Ctx, doc: RomanceDoc): void {
  doc.updatedAtMs = now;
  tx.set(refs(db).romance(uid, doc.characterId), doc);
}

async function requireProfile(tx: Transaction, { db, uid }: Ctx): Promise<void> {
  const p = await tx.get(refs(db).profile(uid));
  if (!p.exists) throw fail.pre('PROFILE_REQUIRED');
}

function docOf(characterId: CharacterId, snap: DocumentSnapshot, now: number): RomanceDoc {
  return normalizeRomance(characterId, snap.exists ? (snap.data() as Record<string, unknown>) : undefined, now);
}

export async function romanceOp(tx: Transaction, data: RomanceRequest, ctx: Ctx): Promise<RomanceResponse> {
  const { db, uid, now } = ctx;
  const today = dayId(now);
  const r = refs(db);

  if (data.op === 'sync') {
    await requireProfile(tx, ctx);
    const snaps = await tx.getAll(...CHARACTER_IDS.map((c) => r.romance(uid, c)));
    const docs = CHARACTER_IDS.map((c, i) => docOf(c, snaps[i], now));
    let affinityDelta = 0;
    const changed = new Set<CharacterId>();
    for (const doc of docs) {
      const before = JSON.stringify(doc);
      const a0 = doc.affinity;
      foldTablePlay(doc, today);
      affinityDelta += doc.affinity - a0;
      if (JSON.stringify(doc) !== before) changed.add(doc.characterId);
    }
    const { granted, inv } = await prepareRewards(tx, ctx, docs);
    for (const g of granted) changed.add(g.characterId);
    for (const doc of docs) if (changed.has(doc.characterId)) writeDoc(tx, ctx, doc);
    writeRewards(tx, ctx, granted, inv);
    return { characters: docs.map((d) => toDto(d, today)), granted, affinityDelta, balanceCents: null };
  }

  await requireProfile(tx, ctx);
  const snap = await tx.get(r.romance(uid, data.characterId));
  const doc = docOf(data.characterId, snap, now);
  const a0 = doc.affinity;

  if (data.op === 'playScene') {
    const scene = STORY.sceneById.get(data.sceneId);
    if (!scene || scene.character !== data.characterId) throw fail.pre('SCENE_NOT_AVAILABLE', 'unknown scene');
    const cost = scene.reservationCents ?? 0;
    const wallet = cost > 0 ? await WalletSession.load(db, tx, uid, now) : null;
    foldTablePlay(doc, today);
    const block = sceneBlock(scene, doc, today);
    if (block) throw fail.pre(block);
    const replay = replayScene(scene, data.choices, { tier: doc.tier, seen: new Set(doc.seen) });
    if (!replay) throw fail.invalid('SCENE_INVALID_PATH');
    // A date is paid only now that it went to the end (INSUFFICIENT_FUNDS: nothing is recorded).
    if (wallet) wallet.debit(cost, 'reservation', { itemId: scene.id });
    addAffinity(doc, replay.delta);
    completeScene(doc, scene, today);
    const { granted, inv } = await prepareRewards(tx, ctx, [doc]);
    writeDoc(tx, ctx, doc);
    writeRewards(tx, ctx, granted, inv);
    wallet?.write(tx);
    return { characters: [toDto(doc, today)], granted, affinityDelta: doc.affinity - a0, balanceCents: wallet?.balance ?? null };
  }

  // gift
  const gift = STORY.giftById.get(data.giftId);
  if (!gift) throw fail.invalid('INVALID_ARGUMENT', 'unknown gift');
  const wallet = await WalletSession.load(db, tx, uid, now);
  foldTablePlay(doc, today);
  if (giftsLeftToday(doc, today) <= 0) throw fail.pre('GIFT_DAILY_LIMIT');
  wallet.debit(gift.priceCents, 'gift', { itemId: gift.id });
  doc.gifts = doc.gifts.day === today ? { day: today, count: doc.gifts.count + 1 } : { day: today, count: 1 };
  if (doc.gifts.count > GIFTS_PER_CHARACTER_PER_DAY) throw fail.pre('GIFT_DAILY_LIMIT');
  addAffinity(doc, GIFT_AFFINITY[tasteOf(data.characterId, gift.id)]);
  const { granted, inv } = await prepareRewards(tx, ctx, [doc]);
  writeDoc(tx, ctx, doc);
  writeRewards(tx, ctx, granted, inv);
  wallet.write(tx);
  return { characters: [toDto(doc, today)], granted, affinityDelta: doc.affinity - a0, balanceCents: wallet.balance };
}

