/**
 * Pure rules of the player-to-player "Rencontres" (no Firebase): preset lines allowed after the
 * previous line, message bookkeeping on the match (unread, anti-spam, duo affinity and its daily
 * cap), discover ranking, and the bots' choice of an answer.
 */
import {
  DATING_MESSAGES_PER_MATCH_PER_DAY, DATING_REACTION_IDS, DUO_MESSAGE_AFFINITY_DAILY_CAP, duoTier,
  type DatingCard, type DatingMatchDoc, type DatingMessageDoc, type DatingReactionId, type Uid,
} from '../shared/romance';
import { hash32 } from './datingBots';
import { STORY } from './story';

export function otherOf(match: Pick<DatingMatchDoc, 'uids'>, uid: Uid): Uid {
  return match.uids[0] === uid ? match.uids[1] : match.uids[0];
}

/**
 * A preset line is allowed if it is an opener, or a reply listed by the OTHER member's last line.
 * Anything else (unknown id, a reply out of context) is refused: there is no free text at all.
 */
export function lineAllowed(match: Pick<DatingMatchDoc, 'uids' | 'lastLine'>, fromUid: Uid, lineId: string): boolean {
  const line = STORY.lineById.get(lineId);
  if (!line) return false;
  if (line.kind === 'opener') return true;
  const last = match.lastLine;
  if (!last || last.fromUid === fromUid) return false;
  return STORY.lineById.get(last.lineId)?.replies.includes(lineId) ?? false;
}

/** Messages `uid` already sent in this match today. */
export function sentToday(match: Pick<DatingMatchDoc, 'sent'>, uid: Uid, today: string): number {
  const s = match.sent?.[uid];
  return s && s.day === today ? s.count : 0;
}

export function canSend(match: Pick<DatingMatchDoc, 'sent'>, uid: Uid, today: string): boolean {
  return sentToday(match, uid, today) < DATING_MESSAGES_PER_MATCH_PER_DAY;
}

/**
 * Records `msg` (sent by msg.fromUid) on the match: last message / line, unread counters, anti-spam
 * counter, duo affinity (+1 per message within the member's daily cap, + `extraDuo` uncapped, e.g. a
 * drink). Returns the duo levels newly reached whose rewards were never granted (marked granted).
 */
export function recordMessage(match: DatingMatchDoc, msg: DatingMessageDoc, today: string, extraDuo = 0): number[] {
  const from = msg.fromUid;
  const other = otherOf(match, from);
  match.lastMessage = { fromUid: from, kind: msg.kind, lineId: msg.lineId, reaction: msg.reaction };
  match.lastMessageAtMs = msg.createdAtMs;
  if (msg.kind === 'line' && msg.lineId) match.lastLine = { fromUid: from, lineId: msg.lineId };
  match.unread = { ...match.unread, [other]: (match.unread?.[other] ?? 0) + 1, [from]: 0 };
  match.sent = { ...match.sent, [from]: { day: today, count: sentToday(match, from, today) + 1 } };
  const daily = match.duoDaily?.[from];
  const earned = daily && daily.day === today ? daily.count : 0;
  let gain = extraDuo;
  if (earned < DUO_MESSAGE_AFFINITY_DAILY_CAP) {
    gain += 1;
    match.duoDaily = { ...match.duoDaily, [from]: { day: today, count: earned + 1 } };
  }
  match.duoAffinity = (match.duoAffinity ?? 0) + gain;
  match.duoTier = duoTier(match.duoAffinity);
  const due: number[] = [];
  for (let t = 1; t <= match.duoTier; t++) if (!match.rewardsGranted.includes(t)) due.push(t);
  match.rewardsGranted = [...match.rewardsGranted, ...due].sort((a, b) => a - b);
  return due;
}

/** Discover order: most shared interests first, then a stable per-day shuffle. */
export function rankCards(me: { uid: Uid; interests: readonly string[] }, cards: DatingCard[], today: string): DatingCard[] {
  const shared = (c: DatingCard) => c.interests.filter((i) => me.interests.includes(i)).length;
  return [...cards].sort((a, b) => shared(b) - shared(a) || hash32(`${me.uid}|${a.uid}|${today}`) - hash32(`${me.uid}|${b.uid}|${today}`));
}

export type BotMessage = { kind: 'line'; lineId: string } | { kind: 'reaction'; reaction: DatingReactionId };

/**
 * What a bot answers in `match` (deterministic from the conversation): a reply to the human's last
 * line when that line allows some, a reaction to a drink / an invite, otherwise an opener.
 */
export function botAnswer(match: DatingMatchDoc, botUid: Uid): BotMessage {
  const h = hash32(`${match.pairId}|${match.lastMessageAtMs}`);
  const last = match.lastMessage;
  if (last && last.fromUid !== botUid) {
    if (last.kind === 'gift') return { kind: 'reaction', reaction: 'blush' };
    if (last.kind === 'invite') return { kind: 'reaction', reaction: 'star' };
    if (last.kind === 'reaction') return { kind: 'reaction', reaction: DATING_REACTION_IDS[h % DATING_REACTION_IDS.length] };
    if (last.kind === 'line' && match.lastLine && match.lastLine.fromUid !== botUid) {
      const replies = STORY.lineById.get(match.lastLine.lineId)?.replies ?? [];
      if (replies.length) return { kind: 'line', lineId: replies[h % replies.length] };
    }
  }
  const openers = STORY.datingLines.filter((l) => l.kind === 'opener' && l.id !== match.lastLine?.lineId);
  return { kind: 'line', lineId: openers[h % openers.length].id };
}
