/**
 * Table state machine (pure: no Firebase, no clock — `now` and randomness are injected).
 *
 *   idle ──join──▶ betting ──deadline / all humans bet──▶ [insurance] ──▶ playerTurns ──▶ settled ──6 s──▶ betting …
 *
 * Every transition that is due (`deadlineMs <= now`) is applied by `advance()`, which callables
 * run first, `pokeTable` runs on demand and the sim runner runs on a timer. Bots act when their
 * (short) turn deadline expires; humans time out to "stand" / "no insurance".
 * Side effects that touch other documents (wallet credits, profile stats, markets, history,
 * peeks, feed) are returned in `effects` and applied by table/service.ts in the same transaction.
 */
import {
  actInPlace, actionCost, buildShoe, commitForSeed, cryptoRng, fairDealOrder, forfeitTurnsInPlace, handValue,
  newSeedHex, noisyStrategy, nextFloat, shuffleInPlace, situationFor, startRound, summarize, timeoutInPlace,
  type EngineHand, type RoundRules, type Rng,
} from '../engine';
import { BOT_BY_UID, FREE_BOTS, simRoster, SIM_TABLE_COUNT, simTableId } from '../sim/profiles';
import { fail } from '../shared/errors';
import type {
  LedgerType, LocalizedText, MarketDoc, MarketKind, PlayerAction, PowerId, QueueEntry, RankTier, SeatDoc,
  SeatHandDoc, StakeTier, TableDoc, TableEvent, TablePhase,
} from '../shared/types';
import {
  CUT_CARD_REMAINING, DECKS_PER_SHOE, MARKET_LIQUIDITY, SEATS_PER_TABLE, SHOE_BUST_RATE_THRESHOLD, SHOE_SIZE,
  STAKE_TIER_LIMITS, TIMING,
} from '../shared/types';
import { marketIds, type Effect, type PlayerInfo, type TablePrivateDoc } from './model';

export interface MachineDeps {
  /** Bot decisions, bot bets, churn. */
  rng: Rng;
  /** Shuffle of a fresh shoe (crypto.randomInt Fisher-Yates in production). */
  shuffleRng: Rng;
  /** 32-byte hex seed for the provably-fair deal order (CSPRNG in production). */
  newSeed: () => string;
}

export function prodDeps(): MachineDeps {
  return { rng: cryptoRng(), shuffleRng: cryptoRng(), newSeed: newSeedHex };
}

export interface NewTableParams {
  tableId: string;
  name: string;
  stakeTier: StakeTier;
  isPrivate: boolean;
  simManaged: boolean;
  rankTier: RankTier;
}

export function newTableState(p: NewTableParams, now: number, deps: MachineDeps): { pub: TableDoc; priv: TablePrivateDoc } {
  const lim = STAKE_TIER_LIMITS[p.stakeTier];
  const pub: TableDoc = {
    tableId: p.tableId, name: p.name, stakeTier: p.stakeTier, minBetCents: lim.minBetCents, maxBetCents: lim.maxBetCents,
    isPrivate: p.isPrivate, simManaged: p.simManaged, status: 'open', phase: 'idle', phaseStartedAtMs: now,
    deadlineMs: null, handNumber: 0,
    shoe: { shoeNumber: 1, totalCards: SHOE_SIZE, cardsRemaining: SHOE_SIZE, handsDealt: 0, dealerBusts: 0, naturals: 0 },
    seats: Array.from({ length: SEATS_PER_TABLE }, () => null),
    dealer: { cards: [], holeHidden: false, total: null, soft: false, blackjack: false, busted: false },
    turn: null,
    fairness: { currentCommit: null, currentHandNumber: 0, lastHandNumber: null, lastCommit: null, lastSeed: null },
    events: [], eventSeq: 0, humanCount: 0, botCount: 0, seatedUids: [], queue: [],
    markets: { dealerBust: null, natural: null, shoe: null, players: {} },
    rankTier: p.rankTier, createdAtMs: now, updatedAtMs: now,
  };
  const priv: TablePrivateDoc = {
    shoe: shuffleInPlace(buildShoe(DECKS_PER_SHOE), deps.shuffleRng),
    round: null, remainingBefore: null, seed: null, commit: null, roundEventsApplied: 0, startedAtMs: null,
    shoeMarketClosed: false,
  };
  return { pub, priv };
}

const BOT_MISSED_LIMIT = 3;

export interface ActRequestInternal {
  handNumber: number;
  action: PlayerAction;
  handIndex?: number;
  amountCents?: number;
  power?: PowerId;
}

export class TableMachine {
  readonly effects: Effect[] = [];
  changed = false;

  constructor(
    public pub: TableDoc,
    public priv: TablePrivateDoc,
    private readonly deps: MachineDeps,
    public now: number,
  ) {}

  // ------------------------------------------------------------------------------------------
  // helpers

  private get rules(): RoundRules {
    return { minBetCents: this.pub.minBetCents, maxBetCents: this.pub.maxBetCents };
  }

  private event(type: TableEvent['type'], f: Partial<Omit<TableEvent, 'seq' | 'type' | 'atMs'>> = {}): void {
    this.pub.eventSeq += 1;
    this.pub.events.push({
      seq: this.pub.eventSeq, type, seatIndex: null, handIndex: null, card: null, amountCents: null, result: null,
      power: null, dealerBlackjack: null, atMs: this.now, ...f,
    });
  }

  private setPhase(phase: TablePhase, deadline: number | null): void {
    if (this.pub.phase !== phase) this.pub.phaseStartedAtMs = this.now;
    this.pub.phase = phase;
    this.pub.deadlineMs = deadline;
    this.changed = true;
  }

  private refreshCounts(): void {
    const seats = this.pub.seats.filter((s): s is SeatDoc => s !== null);
    this.pub.humanCount = seats.filter((s) => !s.isBot).length;
    this.pub.botCount = seats.filter((s) => s.isBot).length;
    this.pub.seatedUids = seats.map((s) => s.uid);
    this.pub.updatedAtMs = this.now;
  }

  seatOf(uid: string): SeatDoc | null {
    return this.pub.seats.find((s) => s?.uid === uid) ?? null;
  }

  isQueued(uid: string): boolean {
    return this.pub.queue.some((q) => q.uid === uid);
  }

  private freeSeat(): number | null {
    const i = this.pub.seats.findIndex((s) => s === null);
    return i < 0 ? null : i;
  }

  /** Seat index of a bot that may yield right now (last bot seat), or null. */
  private yieldableBot(): number | null {
    for (let i = SEATS_PER_TABLE - 1; i >= 0; i--) if (this.pub.seats[i]?.isBot) return i;
    return null;
  }

  private canChangeSeatsNow(): boolean {
    return this.pub.phase === 'idle' || this.pub.phase === 'betting' || this.pub.phase === 'settled';
  }

  /** Whether a human could get a seat or a queue slot here. */
  hasRoomForHuman(): boolean {
    if (this.pub.status !== 'open') return false;
    if (this.freeSeat() !== null) return true;
    if (this.pub.isPrivate) return false;
    const bots = this.pub.botCount;
    const queuedHumans = this.pub.queue.length;
    return bots > queuedHumans;
  }

  private botDelay(): number {
    return TIMING.botMinMs + this.deps.rng.nextInt(TIMING.botMaxMs - TIMING.botMinMs + 1);
  }

  private newSeat(p: PlayerInfo, idx: number): SeatDoc {
    return {
      seatIndex: idx, uid: p.uid, username: p.username, avatar: p.avatar, isBot: p.isBot, rankTier: p.rankTier,
      status: 'active', joinedAtMs: this.now, betCents: 0, hands: [], insurance: null, powerUsed: null,
      roundNetCents: null, missedRounds: 0,
    };
  }

  private place(p: PlayerInfo, idx: number): void {
    this.pub.seats[idx] = this.newSeat(p, idx);
    this.event('join', { seatIndex: idx });
    this.effects.push({ kind: 'location', uid: p.uid, tableId: this.pub.tableId });
    this.refreshCounts();
    this.changed = true;
  }

  private removeSeat(idx: number): void {
    const s = this.pub.seats[idx];
    if (!s) return;
    this.pub.seats[idx] = null;
    this.event('leave', { seatIndex: idx });
    this.effects.push({ kind: 'location', uid: s.uid, tableId: null });
    this.refreshCounts();
    this.changed = true;
  }

  private botInfo(uid: string): PlayerInfo {
    const b = BOT_BY_UID.get(uid)!;
    return { uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true };
  }

  // ------------------------------------------------------------------------------------------
  // seating

  /** Seat (or queue) a player. Bots yield their seat to humans. */
  join(p: PlayerInfo): { status: 'seated' | 'queued'; seatIndex: number | null } {
    if (this.pub.status !== 'open') throw fail.pre('TABLE_CLOSED');
    const existing = this.seatOf(p.uid);
    if (existing && existing.status === 'active') return { status: 'seated', seatIndex: existing.seatIndex };
    if (existing) {
      // came back before the hand they left was over: keep the seat (hands already auto-stood)
      existing.status = 'active';
      this.effects.push({ kind: 'location', uid: p.uid, tableId: this.pub.tableId });
      this.changed = true;
      return { status: 'seated', seatIndex: existing.seatIndex };
    }
    if (this.isQueued(p.uid)) return { status: 'queued', seatIndex: null };
    let idx = this.freeSeat();
    if (idx === null && !p.isBot && !this.pub.isPrivate && this.canChangeSeatsNow()) {
      const botIdx = this.yieldableBot();
      if (botIdx !== null) {
        this.removeSeat(botIdx);
        idx = botIdx;
      }
    }
    if (idx !== null) {
      this.place(p, idx);
      // Bots seated first on a fresh matchmaking table must not open (and immediately close) it.
      if (this.pub.phase === 'idle' && (this.pub.simManaged || this.pub.humanCount > 0)) this.openBetting();
      return { status: 'seated', seatIndex: idx };
    }
    if (this.pub.isPrivate) throw fail.pre('TABLE_FULL');
    if (!this.hasRoomForHuman()) throw fail.pre('TABLE_FULL');
    const q: QueueEntry = { uid: p.uid, username: p.username, avatar: p.avatar, rankTier: p.rankTier, queuedAtMs: this.now };
    this.pub.queue.push(q);
    this.effects.push({ kind: 'location', uid: p.uid, tableId: this.pub.tableId });
    this.changed = true;
    return { status: 'queued', seatIndex: null };
  }

  /** Leave the seat or the queue. Returns the refunded bet (cents). */
  leave(uid: string): number {
    const qi = this.pub.queue.findIndex((q) => q.uid === uid);
    if (qi >= 0) {
      this.pub.queue.splice(qi, 1);
      this.effects.push({ kind: 'location', uid, tableId: null });
      this.changed = true;
      return 0;
    }
    const seat = this.seatOf(uid);
    if (!seat) throw fail.pre('NOT_SEATED');
    const round = this.priv.round;
    const inRound = round !== null && round.phase !== 'settled' && round.seats.some((s) => s.seatIndex === seat.seatIndex);
    let refund = 0;
    if (!inRound) {
      if (this.pub.phase === 'betting' && seat.betCents > 0) {
        refund = seat.betCents;
        this.effects.push({ kind: 'refund', uid, cents: refund, handNumber: this.pub.handNumber });
      }
      this.removeSeat(seat.seatIndex);
    } else {
      seat.status = 'leaving';
      this.effects.push({ kind: 'location', uid, tableId: null });
      forfeitTurnsInPlace(round, seat.seatIndex);
      this.afterEngineStep();
    }
    this.maybeClose();
    this.changed = true;
    return refund;
  }

  /** Non-simulated tables close when no human remains (between hands). */
  private maybeClose(): void {
    if (this.pub.simManaged || this.pub.status !== 'open') return;
    const humansActive = this.pub.seats.some((s) => s && !s.isBot && s.status === 'active') || this.pub.queue.length > 0;
    if (humansActive) return;
    const midHand = this.priv.round !== null && this.priv.round.phase !== 'settled';
    if (midHand) return;
    this.closeTable();
  }

  private closeTable(): void {
    for (let i = 0; i < SEATS_PER_TABLE; i++) if (this.pub.seats[i]) this.removeSeat(i);
    for (const q of this.pub.queue) this.effects.push({ kind: 'location', uid: q.uid, tableId: null });
    this.pub.queue = [];
    const m = this.pub.markets;
    for (const id of [m.dealerBust, m.natural, m.shoe, ...Object.values(m.players)]) {
      if (id) this.effects.push({ kind: 'marketStatus', marketId: id, status: 'void', outcome: null });
    }
    this.pub.markets = { dealerBust: null, natural: null, shoe: null, players: {} };
    this.pub.status = 'closed';
    this.pub.turn = null;
    this.setPhase('closed', null);
    this.refreshCounts();
  }

  // ------------------------------------------------------------------------------------------
  // markets

  private market(kind: MarketKind, id: string, question: LocalizedText, extra: Partial<MarketDoc> = {}): MarketDoc {
    return {
      marketId: id, tableId: this.pub.tableId, tableName: this.pub.name, kind,
      handNumber: kind === 'shoeDealerBustRate' ? null : this.pub.handNumber, shoeNumber: this.pub.shoe.shoeNumber,
      subjectUid: null, subjectUsername: null, subjectSeatIndex: null, question, status: 'open', outcome: null,
      b: MARKET_LIQUIDITY[kind], qYes: 0, qNo: 0, priceYes: 0.5, volumeCents: 0, tradeCount: 0, payoutsDone: false,
      createdAtMs: this.now, closedAtMs: null, resolvedAtMs: null, ...extra,
    };
  }

  private setMarket(id: string | null, status: 'closed' | 'resolved' | 'void', outcome: 'yes' | 'no' | null = null): void {
    if (id) this.effects.push({ kind: 'marketStatus', marketId: id, status, outcome });
  }

  private createShoeMarket(): void {
    const n = this.pub.shoe.shoeNumber;
    const pct = Math.round(SHOE_BUST_RATE_THRESHOLD * 100);
    const id = marketIds.shoe(this.pub.tableId, n);
    this.effects.push({
      kind: 'marketCreate',
      market: this.market('shoeDealerBustRate', id, {
        fr: `Le croupier saute dans au moins ${pct} % des mains du sabot n°${n} (${this.pub.name}) ?`,
        en: `Dealer busts in at least ${pct}% of hands of shoe #${n} (${this.pub.name})?`,
      }),
    });
    this.pub.markets.shoe = id;
  }

  // ------------------------------------------------------------------------------------------
  // betting

  private cleanupSeats(): void {
    for (const s of this.pub.seats) {
      if (!s) continue;
      if (s.status === 'leaving' || (!s.isBot && s.missedRounds >= BOT_MISSED_LIMIT)) this.removeSeat(s.seatIndex);
    }
  }

  /** Sim tables: bots come and go a little, keeping 2..5 seats; humans always keep priority. */
  private simChurn(): void {
    if (!this.pub.simManaged) return;
    const idx = Number(this.pub.tableId.replace('sim-', '')) - 1;
    if (!(idx >= 0 && idx < SIM_TABLE_COUNT && simTableId(idx) === this.pub.tableId)) return;
    const roster = simRoster(idx);
    const seated = this.pub.seats.filter((s): s is SeatDoc => s !== null);
    const r = nextFloat(this.deps.rng);
    if (r < 0.12 && this.pub.botCount > 2) {
      const bots = seated.filter((s) => s.isBot);
      this.removeSeat(bots[this.deps.rng.nextInt(bots.length)].seatIndex);
    } else if ((r > 0.75 || seated.length < 2) && this.freeSeat() !== null && this.pub.queue.length === 0 && seated.length < 4) {
      const out = roster.filter((b) => !this.seatOf(b.uid));
      if (out.length > 0) this.place(this.botInfo(out[this.deps.rng.nextInt(out.length)].uid), this.freeSeat()!);
    }
  }

  private seatQueue(): void {
    while (this.pub.queue.length > 0) {
      let idx = this.freeSeat();
      if (idx === null) {
        const b = this.yieldableBot();
        if (b === null) break;
        this.removeSeat(b);
        idx = b;
      }
      const q = this.pub.queue.shift()!;
      this.pub.seats[idx] = this.newSeat({ ...q, isBot: false }, idx);
      this.event('join', { seatIndex: idx });
      this.refreshCounts();
    }
  }

  /** Opens a new hand: seat changes, shoe change, new seed/commit, markets, bots bet. */
  openBetting(): void {
    this.cleanupSeats();
    if (!this.pub.simManaged) {
      this.maybeClose();
      if (this.pub.status !== 'open') return;
    }
    this.simChurn();
    this.seatQueue();
    this.priv.round = null;
    this.priv.remainingBefore = null;
    this.priv.roundEventsApplied = 0;
    this.pub.events = [];
    this.pub.turn = null;
    this.pub.dealer = { cards: [], holeHidden: false, total: null, soft: false, blackjack: false, busted: false };
    this.pub.markets.players = {};
    this.pub.markets.dealerBust = null;
    this.pub.markets.natural = null;
    for (const s of this.pub.seats) {
      if (!s) continue;
      s.betCents = 0;
      s.hands = [];
      s.insurance = null;
      s.powerUsed = null;
      s.roundNetCents = null;
    }
    if (this.pub.seats.every((s) => s === null)) {
      this.setPhase('idle', null);
      this.refreshCounts();
      return;
    }

    // shoe
    if (this.priv.shoe.length < CUT_CARD_REMAINING) {
      const sh = this.pub.shoe;
      if (this.pub.markets.shoe) {
        if (sh.handsDealt === 0) this.setMarket(this.pub.markets.shoe, 'void');
        else this.setMarket(this.pub.markets.shoe, 'resolved', sh.dealerBusts / sh.handsDealt >= SHOE_BUST_RATE_THRESHOLD ? 'yes' : 'no');
      }
      this.priv.shoe = shuffleInPlace(buildShoe(DECKS_PER_SHOE), this.deps.shuffleRng);
      this.pub.shoe = { shoeNumber: sh.shoeNumber + 1, totalCards: SHOE_SIZE, cardsRemaining: SHOE_SIZE, handsDealt: 0, dealerBusts: 0, naturals: 0 };
      this.pub.markets.shoe = null;
      this.event('shuffle');
    }
    if (!this.pub.markets.shoe) {
      this.createShoeMarket();
      this.priv.shoeMarketClosed = false;
    } else if (!this.priv.shoeMarketClosed && (SHOE_SIZE - this.priv.shoe.length) / SHOE_SIZE >= 0.5) {
      this.setMarket(this.pub.markets.shoe, 'closed');
      this.priv.shoeMarketClosed = true;
    }
    this.pub.shoe.cardsRemaining = this.priv.shoe.length;

    // new hand + provably-fair commitment
    this.pub.handNumber += 1;
    this.priv.seed = this.deps.newSeed();
    this.priv.commit = commitForSeed(this.priv.seed);
    this.pub.fairness.currentCommit = this.priv.commit;
    this.pub.fairness.currentHandNumber = this.pub.handNumber;

    const h = this.pub.handNumber;
    const t = this.pub.tableId;
    this.pub.markets.dealerBust = marketIds.dealerBust(t, h);
    this.pub.markets.natural = marketIds.natural(t, h);
    this.effects.push({ kind: 'marketCreate', market: this.market('dealerBust', this.pub.markets.dealerBust, { fr: `Le croupier saute ? (${this.pub.name}, main n°${h})`, en: `Dealer busts? (${this.pub.name}, hand #${h})` }) });
    this.effects.push({ kind: 'marketCreate', market: this.market('natural', this.pub.markets.natural, { fr: `Un blackjack naturel ? (${this.pub.name}, main n°${h})`, en: `A natural blackjack? (${this.pub.name}, hand #${h})` }) });

    this.setPhase('betting', this.now + TIMING.bettingMs);
    this.refreshCounts();
    this.botsBet();
  }

  private botsBet(): void {
    for (const s of this.pub.seats) {
      if (!s || !s.isBot || s.status !== 'active') continue;
      const bot = BOT_BY_UID.get(s.uid);
      if (!bot) continue;
      if (nextFloat(this.deps.rng) < 0.07) continue; // sits out this hand
      const min = this.pub.minBetCents;
      const max = this.pub.maxBetCents;
      let units: number;
      if (bot.betStyle === 'min') units = 1 + this.deps.rng.nextInt(2);
      else if (bot.betStyle === 'flat') units = 2 + (bot.seed % 4);
      else units = 1 + this.deps.rng.nextInt(20);
      const bet = Math.min(max, Math.max(min, Math.round((min * units) / 100) * 100));
      s.betCents = bet;
      this.event('bet', { seatIndex: s.seatIndex, amountCents: bet });
    }
  }

  placeBet(uid: string, handNumber: number, amountCents: number): void {
    if (this.pub.phase !== 'betting') throw fail.pre('BAD_PHASE');
    if (handNumber !== this.pub.handNumber) throw fail.pre('STALE_HAND');
    const seat = this.seatOf(uid);
    if (!seat || seat.status !== 'active') throw fail.pre('NOT_SEATED');
    if (seat.betCents > 0) throw fail.pre('ALREADY_BET');
    if (!Number.isSafeInteger(amountCents) || amountCents % 100 !== 0 || amountCents < this.pub.minBetCents || amountCents > this.pub.maxBetCents) {
      throw fail.invalid('BET_OUT_OF_RANGE');
    }
    seat.betCents = amountCents;
    seat.missedRounds = 0;
    this.event('bet', { seatIndex: seat.seatIndex, amountCents });
    this.changed = true;
    const humans = this.pub.seats.filter((s): s is SeatDoc => !!s && !s.isBot && s.status === 'active');
    if (humans.length > 0 && humans.every((s) => s.betCents > 0)) this.deal();
  }

  private deal(): void {
    const seats = this.pub.seats.filter((s): s is SeatDoc => !!s);
    for (const s of seats) if (!s.isBot && s.betCents === 0) s.missedRounds += 1;
    const betting = seats.filter((s) => s.betCents > 0 && s.status === 'active');
    if (betting.length === 0) {
      this.cleanupSeats();
      if (!this.pub.simManaged) this.maybeClose();
      if (this.pub.status !== 'open') return;
      if (this.pub.seats.every((s) => s === null)) { this.setPhase('idle', null); return; }
      this.botsBet();
      this.setPhase('betting', this.now + TIMING.bettingMs);
      return;
    }
    this.setMarket(this.pub.markets.natural, 'closed');
    const deck = fairDealOrder(this.priv.shoe, this.priv.seed!, DECKS_PER_SHOE);
    this.priv.remainingBefore = this.priv.shoe.slice();
    this.priv.startedAtMs = this.now;
    this.priv.roundEventsApplied = 0;
    this.priv.round = startRound(this.rules, betting.map((s) => ({ seatIndex: s.seatIndex, playerId: s.uid, betCents: s.betCents })), deck);
    const h = this.pub.handNumber;
    for (const s of betting) {
      const id = marketIds.player(this.pub.tableId, h, s.seatIndex);
      this.pub.markets.players[String(s.seatIndex)] = id;
      this.effects.push({
        kind: 'marketCreate',
        market: this.market('playerWins', id, { fr: `${s.username} gagne ? (${this.pub.name}, main n°${h})`, en: `${s.username} wins? (${this.pub.name}, hand #${h})` }, {
          subjectUid: s.uid, subjectUsername: s.username, subjectSeatIndex: s.seatIndex,
        }),
      });
    }
    this.afterEngineStep();
  }

  // ------------------------------------------------------------------------------------------
  // engine glue

  private syncFromRound(): void {
    const r = this.priv.round;
    if (!r) return;
    for (const es of r.seats) {
      const seat = this.pub.seats[es.seatIndex];
      if (!seat) continue;
      seat.hands = es.hands.map((h: EngineHand): SeatHandDoc => {
        const v = handValue(h.cards);
        return {
          cards: h.cards.slice(), total: v.total, soft: v.soft, betCents: h.betCents, stakedCents: h.stakedCents,
          doubled: h.doubled, fromSplit: h.fromSplit, splitAces: h.splitAces, surrendered: h.surrendered,
          busted: h.busted, blackjack: h.blackjack, done: h.done, result: h.result, returnCents: h.returnCents,
        };
      });
      seat.insurance = es.insurance.offered
        ? { betCents: es.insurance.betCents, stakedCents: es.insurance.stakedCents, decided: es.insurance.decided, result: es.insurance.result }
        : null;
      seat.powerUsed = es.powerUsed;
    }
    const visible = r.dealer.holeRevealed ? r.dealer.cards.slice() : r.dealer.cards.slice(0, 1);
    const dv = handValue(visible);
    this.pub.dealer = {
      cards: visible, holeHidden: !r.dealer.holeRevealed, total: visible.length ? dv.total : null, soft: dv.soft,
      blackjack: r.dealer.blackjack, busted: r.dealer.busted,
    };
    this.pub.turn = r.turn ? { ...r.turn } : null;
    for (let i = this.priv.roundEventsApplied; i < r.events.length; i++) {
      const e = r.events[i];
      this.event(e.type, {
        seatIndex: e.seatIndex, handIndex: e.handIndex, card: e.card, amountCents: e.amountCents, result: e.result,
        power: e.power, dealerBlackjack: e.dealerBlackjack,
      });
    }
    this.priv.roundEventsApplied = r.events.length;
    this.pub.shoe.cardsRemaining = Math.max(0, (this.priv.remainingBefore?.length ?? this.priv.shoe.length) - r.deckPos);
    this.changed = true;
  }

  /** After any engine change: auto-decisions (bots' insurance, leavers), markets, deadlines, settlement. */
  private afterEngineStep(): void {
    const r = this.priv.round!;
    const wasPhase = this.pub.phase;
    for (let guard = 0; guard < 50 && r.phase !== 'settled'; guard++) {
      let acted = false;
      if (r.phase === 'insurance') {
        for (const es of r.seats) {
          const seat = this.pub.seats[es.seatIndex];
          if (!es.insurance.decided && seat && (seat.isBot || seat.status === 'leaving')) {
            actInPlace(r, es.seatIndex, 'insurance', { amountCents: 0 });
            acted = true;
            break;
          }
        }
      } else if (r.phase === 'playerTurns' && r.turn) {
        const seat = this.pub.seats[r.turn.seatIndex];
        if (!seat || seat.status === 'leaving') {
          forfeitTurnsInPlace(r, r.turn.seatIndex);
          acted = true;
        }
      }
      if (!acted) break;
    }
    this.syncFromRound();

    // close "player wins" markets whose outcome is already known (all hands busted/surrendered)
    for (const es of r.seats) {
      const id = this.pub.markets.players[String(es.seatIndex)];
      if (id && r.phase !== 'settled' && es.hands.every((h) => h.done && (h.busted || h.surrendered))) {
        this.setMarket(id, 'closed');
      }
    }

    if (r.phase === 'settled') {
      this.settle();
      return;
    }
    if (r.phase === 'insurance') {
      if (wasPhase !== 'insurance') this.setPhase('insurance', this.now + TIMING.insuranceMs);
      return;
    }
    const seat = this.pub.seats[r.turn!.seatIndex]!;
    this.setPhase('playerTurns', this.now + (seat.isBot ? this.botDelay() : TIMING.decisionMs));
  }

  private settle(): void {
    const r = this.priv.round!;
    const sums = summarize(r);
    const settlements = sums.map((x) => {
      const seat = this.pub.seats[x.seatIndex]!;
      seat.roundNetCents = x.netCents;
      return {
        uid: x.playerId, username: seat.username, avatar: seat.avatar, isBot: seat.isBot, seatIndex: x.seatIndex,
        stakedCents: x.stakedCents, returnCents: x.returnCents, netCents: x.netCents, outcome: x.outcome,
        handsWon: x.handsWon, handsLost: x.handsLost, handsPushed: x.handsPushed, blackjacks: x.blackjacks,
      };
    });
    const h = this.pub.handNumber;
    this.effects.push({ kind: 'settle', handNumber: h, seats: settlements });

    // markets: resolved atomically with the dealer's play (no trade can interleave)
    const anyNatural = r.dealer.blackjack || r.seats.some((s) => s.hands.some((x) => x.blackjack));
    this.setMarket(this.pub.markets.dealerBust, 'resolved', r.dealer.busted ? 'yes' : 'no');
    this.setMarket(this.pub.markets.natural, 'resolved', anyNatural ? 'yes' : 'no');
    for (const x of sums) this.setMarket(this.pub.markets.players[String(x.seatIndex)] ?? null, 'resolved', x.netCents > 0 ? 'yes' : 'no');

    // shoe statistics
    this.pub.shoe.handsDealt += 1;
    if (r.dealer.busted) this.pub.shoe.dealerBusts += 1;
    if (anyNatural) this.pub.shoe.naturals += 1;
    const before = this.priv.remainingBefore!;
    const dealt = r.deck.slice(0, r.deckPos);
    this.priv.shoe = r.deckPos <= before.length ? r.deck.slice(r.deckPos, before.length) : [];
    this.pub.shoe.cardsRemaining = this.priv.shoe.length;

    // fairness reveal + history
    this.pub.fairness.lastHandNumber = h;
    this.pub.fairness.lastCommit = this.priv.commit;
    this.pub.fairness.lastSeed = this.priv.seed;
    this.effects.push({
      kind: 'history',
      doc: {
        tableId: this.pub.tableId, handNumber: h, startedAtMs: this.priv.startedAtMs ?? this.now, endedAtMs: this.now,
        dealerCards: r.dealer.cards.slice(), dealerTotal: handValue(r.dealer.cards).total,
        seats: sums.map((x) => {
          const seat = this.pub.seats[x.seatIndex]!;
          return { seatIndex: x.seatIndex, uid: seat.uid, username: seat.username, isBot: seat.isBot, hands: seat.hands, netCents: x.netCents };
        }),
        fairness: { commit: this.priv.commit!, seed: this.priv.seed!, remainingBefore: before, dealt },
      },
    });

    for (const s of settlements) {
      if (s.blackjacks > 0 || s.netCents >= 10_000) {
        this.effects.push({
          kind: 'feed',
          entry: {
            username: s.username, avatar: s.avatar, isBot: s.isBot, kind: s.blackjacks > 0 ? 'blackjack' : 'bigWin',
            amountCents: s.netCents, tableId: this.pub.tableId, createdAtMs: this.now,
          },
        });
      }
    }
    this.pub.turn = null;
    this.setPhase('settled', this.now + TIMING.settledMs);
  }

  // ------------------------------------------------------------------------------------------
  // player decisions

  /** Validates and applies a decision of `uid`. Returns the extra stake to debit. */
  act(uid: string, req: ActRequestInternal): { costCents: number; ledgerType: LedgerType | null } {
    if (this.pub.phase !== 'insurance' && this.pub.phase !== 'playerTurns') throw fail.pre('BAD_PHASE');
    if (req.handNumber !== this.pub.handNumber) throw fail.pre('STALE_HAND');
    const seat = this.seatOf(uid);
    if (!seat || seat.status !== 'active') throw fail.pre('NOT_SEATED');
    const r = this.priv.round!;
    if (!r.seats.some((s) => s.seatIndex === seat.seatIndex)) throw fail.pre('NOT_SEATED', 'no bet this hand');
    if (req.action === 'insurance') {
      if (r.phase !== 'insurance') throw fail.pre('BAD_PHASE');
    } else {
      if (r.phase !== 'playerTurns') throw fail.pre('BAD_PHASE');
      if (!r.turn || r.turn.seatIndex !== seat.seatIndex) throw fail.pre('NOT_YOUR_TURN');
      if (req.handIndex !== undefined && req.handIndex !== r.turn.handIndex) throw fail.pre('NOT_YOUR_TURN', 'wrong hand');
    }
    const opts = { power: req.power ?? null, amountCents: req.amountCents };
    const cost = actionCost(r, seat.seatIndex, req.action, opts); // throws EngineError if illegal
    actInPlace(r, seat.seatIndex, req.action, opts);
    if (req.power === 'peek') {
      this.effects.push({ kind: 'peek', uid, holeCard: r.dealer.cards[1], handNumber: this.pub.handNumber });
    }
    this.afterEngineStep();
    const ledgerType: LedgerType | null = req.action === 'double' ? 'double' : req.action === 'split' ? 'split' : req.action === 'insurance' ? 'insurance' : null;
    return { costCents: cost, ledgerType };
  }

  // ------------------------------------------------------------------------------------------
  // timers

  /** Applies every transition that is due at `now`. Returns true if something changed. */
  advance(): boolean {
    const start = this.changed;
    this.changed = false;
    let any = false;
    for (let guard = 0; guard < 60; guard++) {
      const p = this.pub;
      if (p.status !== 'open' || p.deadlineMs === null || p.deadlineMs > this.now) break;
      switch (p.phase) {
        case 'betting':
          this.deal();
          break;
        case 'insurance':
          timeoutInPlace(this.priv.round!);
          this.afterEngineStep();
          break;
        case 'playerTurns': {
          const r = this.priv.round!;
          const seat = r.turn ? p.seats[r.turn.seatIndex] : null;
          if (seat?.isBot) {
            const bot = BOT_BY_UID.get(seat.uid);
            const a = noisyStrategy(situationFor(r)!, this.deps.rng, bot?.noise ?? 0.05);
            actInPlace(r, seat.seatIndex, a);
          } else {
            timeoutInPlace(r);
          }
          this.afterEngineStep();
          break;
        }
        case 'settled':
        case 'idle':
          this.openBetting();
          break;
        default:
          p.deadlineMs = null;
      }
      any = true;
    }
    this.changed = start || this.changed || any;
    return any;
  }
}

/** Info of a bot for seating on a new matchmaking table (from the free pool). */
export function pickFreeBots(rng: Rng, n: number): PlayerInfo[] {
  const pool = [...FREE_BOTS];
  shuffleInPlace(pool, rng);
  return pool.slice(0, n).map((b) => ({ uid: b.uid, username: b.username, avatar: b.avatar, rankTier: b.rankTier, isBot: true }));
}
