/**
 * Pure blackjack round engine (one hand of a table). No Firebase, no clock, no randomness:
 * the caller supplies the ordered deck, so a given deck + action sequence always yields the
 * same result.
 *
 * Fixed rules ("American" standard):
 *  - 6 decks, dealer has a hole card and PEEKS for blackjack with an Ace or ten-value up card.
 *  - Dealer STANDS on all 17 (S17). Natural pays 3:2. Push returns the bet. Natural beats 3+ card 21.
 *  - Insurance offered on an Ace up card: up to half the bet, pays 2:1.
 *  - Double on any first two cards (one card only), double after split allowed.
 *  - Split equal-VALUE cards up to 4 hands. Split aces get one card each, cannot be re-split,
 *    and A+10 after a split is a plain 21 (not a natural).
 *  - Late surrender (half the bet back) on the first two cards, not after a split.
 *  - A hand reaching 21 is complete automatically.
 *
 * Money: integer cents. For each hand, `betCents` is the amount at risk for payout purposes and
 * `stakedCents` the part actually paid by the player (lower when a "free" power is used).
 * Return to player = max(0, stakedCents + profit) with profit = mult × betCents
 * (blackjack 3/2, win 1, push 0, lose/bust −1, surrender −1/2). Bets are whole dollars, so every
 * amount stays an integer.
 *
 * Public functions return a NEW state (input is never mutated). `*InPlace` variants mutate and
 * exist for fast Monte-Carlo simulation.
 */
import type { CardCode, HandResult, PlayerAction, PowerId, TableEventType } from '../shared/types';
import { FREE_INSURANCE_MAX_CENTS, FREE_POWER_MAX_STAKE_CENTS, MAX_HANDS_PER_SEAT } from '../shared/types';
import { cardPoints, handValue, isAce, isTenValue, isTwoCardTwentyOne } from './cards';

export type EngineErrorCode =
  | 'BAD_PHASE' | 'NOT_YOUR_TURN' | 'ILLEGAL_ACTION' | 'BAD_AMOUNT' | 'BET_OUT_OF_RANGE'
  | 'POWER_NOT_APPLICABLE' | 'POWER_ALREADY_USED' | 'DECK_EXHAUSTED' | 'NOT_SEATED';

export class EngineError extends Error {
  constructor(public readonly code: EngineErrorCode, message?: string) {
    super(message ?? code);
    this.name = 'EngineError';
  }
}

export interface RoundRules {
  minBetCents: number;
  maxBetCents: number;
  /** Max hands per seat after splits (default MAX_HANDS_PER_SEAT = 4). */
  maxHands?: number;
}

export interface EngineHand {
  cards: CardCode[];
  betCents: number;
  stakedCents: number;
  doubled: boolean;
  fromSplit: boolean;
  splitAces: boolean;
  surrendered: boolean;
  busted: boolean;
  blackjack: boolean;
  done: boolean;
  result: HandResult | null;
  returnCents: number | null;
}

export interface EngineInsurance {
  /** Insurance is only "offered" when the dealer shows an Ace. */
  offered: boolean;
  decided: boolean;
  betCents: number;
  stakedCents: number;
  result: 'win' | 'lose' | null;
  returnCents: number | null;
}

export interface EngineSeat {
  seatIndex: number;
  playerId: string;
  hands: EngineHand[];
  insurance: EngineInsurance;
  powerUsed: PowerId | null;
}

export type RoundPhase = 'insurance' | 'playerTurns' | 'settled';

export interface EngineEvent {
  type: TableEventType;
  seatIndex: number | null;
  handIndex: number | null;
  card: CardCode | null;
  amountCents: number | null;
  result: HandResult | null;
  power: PowerId | null;
  dealerBlackjack: boolean | null;
}

export interface RoundState {
  v: 1;
  rules: RoundRules;
  phase: RoundPhase;
  /** Betting seats, ascending seatIndex. */
  seats: EngineSeat[];
  dealer: { cards: CardCode[]; holeRevealed: boolean; peeked: boolean; blackjack: boolean; busted: boolean };
  deck: CardCode[];
  deckPos: number;
  turn: { seatIndex: number; handIndex: number } | null;
  events: EngineEvent[];
}

export interface BetEntry {
  seatIndex: number;
  playerId: string;
  betCents: number;
}

export interface ActOptions {
  power?: PowerId | null;
  /** Insurance amount (cents). */
  amountCents?: number;
}

// ---------------------------------------------------------------------------------------------

function ev(s: RoundState, e: Partial<EngineEvent> & { type: TableEventType }): void {
  s.events.push({
    seatIndex: null, handIndex: null, card: null, amountCents: null, result: null, power: null,
    dealerBlackjack: null, ...e,
  });
}

function draw(s: RoundState): CardCode {
  if (s.deckPos >= s.deck.length) throw new EngineError('DECK_EXHAUSTED');
  return s.deck[s.deckPos++];
}

function newHand(cards: CardCode[], bet: number, staked: number, fromSplit: boolean, splitAces: boolean): EngineHand {
  return {
    cards, betCents: bet, stakedCents: staked, doubled: false, fromSplit, splitAces, surrendered: false,
    busted: false, blackjack: false, done: false, result: null, returnCents: null,
  };
}

export function validateBet(rules: RoundRules, betCents: number): void {
  if (!Number.isSafeInteger(betCents) || betCents % 100 !== 0 || betCents < rules.minBetCents || betCents > rules.maxBetCents) {
    throw new EngineError('BET_OUT_OF_RANGE', `bet ${betCents}`);
  }
}

function seatOf(s: RoundState, seatIndex: number): EngineSeat {
  const seat = s.seats.find((x) => x.seatIndex === seatIndex);
  if (!seat) throw new EngineError('NOT_SEATED');
  return seat;
}

/** Re-evaluate a hand after it received a card: bust / 21 → done. */
function refreshHand(h: EngineHand): void {
  const v = handValue(h.cards);
  if (v.total > 21) {
    h.busted = true;
    h.done = true;
  } else if (v.total === 21) {
    h.done = true;
  }
}

// ---------------------------------------------------------------------------------------------
// Start / deal

export function startRound(rules: RoundRules, bets: BetEntry[], deck: readonly CardCode[]): RoundState {
  return startRoundInPlace(rules, bets, deck.slice());
}

export function startRoundInPlace(rules: RoundRules, bets: BetEntry[], deck: CardCode[]): RoundState {
  if (bets.length === 0) throw new EngineError('ILLEGAL_ACTION', 'no bets');
  const seen = new Set<number>();
  for (const b of bets) {
    if (!Number.isInteger(b.seatIndex) || b.seatIndex < 0 || seen.has(b.seatIndex)) throw new EngineError('NOT_SEATED');
    seen.add(b.seatIndex);
    validateBet(rules, b.betCents);
  }
  const sorted = [...bets].sort((a, b) => a.seatIndex - b.seatIndex);
  const s: RoundState = {
    v: 1,
    rules: { ...rules },
    phase: 'playerTurns',
    seats: sorted.map((b) => ({
      seatIndex: b.seatIndex,
      playerId: b.playerId,
      hands: [newHand([], b.betCents, b.betCents, false, false)],
      insurance: { offered: false, decided: true, betCents: 0, stakedCents: 0, result: null, returnCents: null },
      powerUsed: null,
    })),
    dealer: { cards: [], holeRevealed: false, peeked: false, blackjack: false, busted: false },
    deck,
    deckPos: 0,
    turn: null,
    events: [],
  };

  for (let round = 0; round < 2; round++) {
    for (const seat of s.seats) {
      const c = draw(s);
      seat.hands[0].cards.push(c);
      ev(s, { type: 'deal', seatIndex: seat.seatIndex, handIndex: 0, card: c });
    }
    const d = draw(s);
    s.dealer.cards.push(d);
    if (round === 0) ev(s, { type: 'dealerUp', card: d });
    else ev(s, { type: 'dealerHole' });
  }
  for (const seat of s.seats) {
    const h = seat.hands[0];
    if (isTwoCardTwentyOne(h.cards)) {
      h.blackjack = true;
      h.done = true;
    }
  }

  const up = s.dealer.cards[0];
  if (isAce(up)) {
    s.phase = 'insurance';
    for (const seat of s.seats) seat.insurance = { offered: true, decided: false, betCents: 0, stakedCents: 0, result: null, returnCents: null };
  } else {
    peekAndContinue(s);
  }
  return s;
}

function maxHandsOf(s: RoundState): number {
  return s.rules.maxHands ?? MAX_HANDS_PER_SEAT;
}

/** Dealer peek (Ace/ten up), insurance resolution, then first turn or immediate settlement. */
function peekAndContinue(s: RoundState): void {
  const up = s.dealer.cards[0];
  const dealerBj = isTwoCardTwentyOne(s.dealer.cards);
  if (isAce(up) || isTenValue(up)) {
    s.dealer.peeked = true;
    ev(s, { type: 'peek', dealerBlackjack: dealerBj });
  }
  for (const seat of s.seats) {
    const ins = seat.insurance;
    if (ins.offered && ins.betCents > 0) ins.result = dealerBj ? 'win' : 'lose';
  }
  if (dealerBj && s.dealer.peeked) {
    s.dealer.blackjack = true;
    for (const seat of s.seats) for (const h of seat.hands) h.done = true;
    revealHole(s);
    settleInPlace(s);
    return;
  }
  s.phase = 'playerTurns';
  s.turn = null;
  advanceTurn(s);
}

function revealHole(s: RoundState): void {
  if (!s.dealer.holeRevealed) {
    s.dealer.holeRevealed = true;
    ev(s, { type: 'reveal', card: s.dealer.cards[1] });
  }
}

/** Move `turn` to the next unfinished hand (seat order, then hand order); dealer plays when none left. */
function advanceTurn(s: RoundState): void {
  for (const seat of s.seats) {
    for (let i = 0; i < seat.hands.length; i++) {
      if (!seat.hands[i].done) {
        s.turn = { seatIndex: seat.seatIndex, handIndex: i };
        return;
      }
    }
  }
  s.turn = null;
  dealerPlay(s);
  settleInPlace(s);
}

function dealerPlay(s: RoundState): void {
  revealHole(s);
  const live = s.seats.some((seat) => seat.hands.some((h) => !h.busted && !h.surrendered && !h.blackjack));
  if (!live) return;
  for (;;) {
    const v = handValue(s.dealer.cards);
    if (v.total >= 17) break; // S17: stand on all 17, soft included
    const c = draw(s);
    s.dealer.cards.push(c);
    ev(s, { type: 'dealerHit', card: c });
  }
  if (handValue(s.dealer.cards).total > 21) s.dealer.busted = true;
}

function settleHand(h: EngineHand, dealerTotal: number, dealerBj: boolean, dealerBusted: boolean): void {
  let num: number; // profit multiplier numerator over 2
  let result: HandResult;
  if (h.surrendered) { result = 'surrender'; num = -1; }
  else if (h.busted) { result = 'bust'; num = -2; }
  else if (h.blackjack) {
    if (dealerBj) { result = 'push'; num = 0; } else { result = 'blackjack'; num = 3; }
  } else if (dealerBj) { result = 'lose'; num = -2; }
  else {
    const t = handValue(h.cards).total;
    if (dealerBusted || t > dealerTotal) { result = 'win'; num = 2; }
    else if (t === dealerTotal) { result = 'push'; num = 0; }
    else { result = 'lose'; num = -2; }
  }
  // betCents is a multiple of 100 for initial bets/doubles/splits → (num*bet)/2 is an integer.
  const profit = (num * h.betCents) / 2;
  h.result = result;
  h.returnCents = Math.max(0, h.stakedCents + profit);
}

function settleInPlace(s: RoundState): void {
  const dTotal = handValue(s.dealer.cards).total;
  for (const seat of s.seats) {
    seat.hands.forEach((h, i) => {
      settleHand(h, dTotal, s.dealer.blackjack, s.dealer.busted);
      ev(s, { type: 'settle', seatIndex: seat.seatIndex, handIndex: i, result: h.result, amountCents: h.returnCents });
    });
    const ins = seat.insurance;
    if (ins.betCents > 0) {
      ins.returnCents = ins.result === 'win' ? ins.stakedCents + 2 * ins.betCents : Math.max(0, ins.stakedCents - ins.betCents);
    } else {
      ins.returnCents = 0;
    }
  }
  s.phase = 'settled';
  s.turn = null;
}

// ---------------------------------------------------------------------------------------------
// Decisions

/** Actions currently legal for `seatIndex` (empty if it is not this seat's decision). */
export function legalActions(s: RoundState, seatIndex: number): PlayerAction[] {
  const seat = s.seats.find((x) => x.seatIndex === seatIndex);
  if (!seat) return [];
  if (s.phase === 'insurance') return seat.insurance.decided ? [] : ['insurance'];
  if (s.phase !== 'playerTurns' || !s.turn || s.turn.seatIndex !== seatIndex) return [];
  const h = seat.hands[s.turn.handIndex];
  const out: PlayerAction[] = ['hit', 'stand'];
  if (canDouble(h)) out.push('double');
  if (canSplit(s, seat, h)) out.push('split');
  if (canSurrender(seat, h)) out.push('surrender');
  if (seat.powerUsed === null) out.push('peek');
  return out;
}

export function canDouble(h: EngineHand): boolean {
  return h.cards.length === 2 && !h.done && !h.doubled && !h.splitAces;
}

export function canSplit(s: RoundState, seat: EngineSeat, h: EngineHand): boolean {
  return h.cards.length === 2 && !h.done && !h.splitAces && seat.hands.length < maxHandsOf(s)
    && cardPoints(h.cards[0]) === cardPoints(h.cards[1]);
}

export function canSurrender(seat: EngineSeat, h: EngineHand): boolean {
  return seat.hands.length === 1 && h.cards.length === 2 && !h.fromSplit && !h.doubled && !h.done;
}

const POWER_FOR_ACTION: Record<PowerId, PlayerAction[]> = {
  freeSplit: ['split'],
  freeDouble: ['double'],
  freeInsurance: ['insurance'],
  peek: ['peek'],
  secondChance: ['hit', 'double'],
};

/** Extra stake (cents) the player must pay for this action (0 if free or none). Throws if illegal. */
export function actionCost(s: RoundState, seatIndex: number, action: PlayerAction, opts: ActOptions = {}): number {
  const before = totalStaked(s, seatIndex);
  const after = totalStaked(act(s, seatIndex, action, opts), seatIndex);
  return after - before;
}

export function totalStaked(s: RoundState, seatIndex: number): number {
  const seat = s.seats.find((x) => x.seatIndex === seatIndex);
  if (!seat) return 0;
  return seat.hands.reduce((a, h) => a + h.stakedCents, 0) + seat.insurance.stakedCents;
}

export function act(s: RoundState, seatIndex: number, action: PlayerAction, opts: ActOptions = {}): RoundState {
  const c = structuredClone(s);
  actInPlace(c, seatIndex, action, opts);
  return c;
}

export function actInPlace(s: RoundState, seatIndex: number, action: PlayerAction, opts: ActOptions = {}): void {
  const seat = seatOf(s, seatIndex);
  const power = opts.power ?? null;
  if (power !== null) {
    if (seat.powerUsed !== null) throw new EngineError('POWER_ALREADY_USED');
    if (!POWER_FOR_ACTION[power].includes(action)) throw new EngineError('POWER_NOT_APPLICABLE');
  }

  if (action === 'insurance') {
    if (s.phase !== 'insurance') throw new EngineError('BAD_PHASE');
    if (seat.insurance.decided) throw new EngineError('ILLEGAL_ACTION', 'insurance already decided');
    const amount = opts.amountCents ?? 0;
    const max = Math.floor(seat.hands[0].betCents / 2);
    if (!Number.isSafeInteger(amount) || amount < 0 || amount > max) throw new EngineError('BAD_AMOUNT');
    if (power === 'freeInsurance' && amount === 0) throw new EngineError('POWER_NOT_APPLICABLE');
    if (power === 'freeInsurance' && amount > FREE_INSURANCE_MAX_CENTS) throw new EngineError('BAD_AMOUNT');
    seat.insurance.decided = true;
    seat.insurance.betCents = amount;
    seat.insurance.stakedCents = power === 'freeInsurance' ? 0 : amount;
    if (power) {
      seat.powerUsed = power;
      ev(s, { type: 'power', seatIndex, power });
    }
    ev(s, { type: 'insurance', seatIndex, amountCents: amount });
    if (s.seats.every((x) => x.insurance.decided)) peekAndContinue(s);
    return;
  }

  if (s.phase !== 'playerTurns') throw new EngineError('BAD_PHASE');
  if (!s.turn || s.turn.seatIndex !== seatIndex) throw new EngineError('NOT_YOUR_TURN');
  const hi = s.turn.handIndex;
  const h = seat.hands[hi];

  const markPower = (): void => {
    if (power) {
      seat.powerUsed = power;
      ev(s, { type: 'power', seatIndex, handIndex: hi, power });
    }
  };

  /** Draw a card for this hand, applying second chance if it would bust. */
  const drawFor = (evType: 'hit' | 'double'): void => {
    let c = draw(s);
    if (power === 'secondChance' && handValue([...h.cards, c]).total > 21) {
      ev(s, { type: 'secondChance', seatIndex, handIndex: hi, card: c });
      c = draw(s);
    }
    h.cards.push(c);
    ev(s, { type: evType, seatIndex, handIndex: hi, card: c, amountCents: evType === 'double' ? h.betCents : null });
  };

  switch (action) {
    case 'peek': {
      if (power !== 'peek') throw new EngineError('ILLEGAL_ACTION', 'peek requires the peek power');
      markPower();
      return; // does not end the turn
    }
    case 'hit': {
      markPower();
      drawFor('hit');
      refreshHand(h);
      break;
    }
    case 'stand': {
      h.done = true;
      ev(s, { type: 'stand', seatIndex, handIndex: hi });
      break;
    }
    case 'double': {
      if (!canDouble(h)) throw new EngineError('ILLEGAL_ACTION', 'cannot double');
      if (power === 'freeDouble' && h.betCents > FREE_POWER_MAX_STAKE_CENTS) throw new EngineError('POWER_NOT_APPLICABLE');
      markPower();
      const extra = h.betCents;
      h.betCents += extra;
      h.stakedCents += power === 'freeDouble' ? 0 : extra;
      h.doubled = true;
      drawFor('double');
      refreshHand(h);
      h.done = true;
      break;
    }
    case 'split': {
      if (!canSplit(s, seat, h)) throw new EngineError('ILLEGAL_ACTION', 'cannot split');
      if (power === 'freeSplit' && h.betCents > FREE_POWER_MAX_STAKE_CENTS) throw new EngineError('POWER_NOT_APPLICABLE');
      markPower();
      const aces = isAce(h.cards[0]);
      const second = h.cards.pop() as CardCode;
      const nh = newHand([second], h.betCents, power === 'freeSplit' ? 0 : h.betCents, true, aces);
      h.fromSplit = true;
      h.splitAces = aces;
      seat.hands.splice(hi + 1, 0, nh);
      ev(s, { type: 'split', seatIndex, handIndex: hi, amountCents: nh.betCents });
      for (const [idx, hand] of [[hi, h], [hi + 1, nh]] as const) {
        const c = draw(s);
        hand.cards.push(c);
        ev(s, { type: 'deal', seatIndex, handIndex: idx, card: c });
        refreshHand(hand);
        if (aces) hand.done = true;
      }
      break;
    }
    case 'surrender': {
      if (!canSurrender(seat, h)) throw new EngineError('ILLEGAL_ACTION', 'cannot surrender');
      h.surrendered = true;
      h.done = true;
      ev(s, { type: 'surrender', seatIndex, handIndex: hi });
      break;
    }
    default:
      throw new EngineError('ILLEGAL_ACTION');
  }
  s.turn = null;
  advanceTurn(s);
}

/**
 * Apply a timeout to the pending decision: in 'insurance' every undecided seat declines;
 * in 'playerTurns' the current hand stands. Returns a new state.
 */
export function timeout(s: RoundState): RoundState {
  const c = structuredClone(s);
  timeoutInPlace(c);
  return c;
}

export function timeoutInPlace(s: RoundState): void {
  if (s.phase === 'insurance') {
    for (const seat of s.seats) {
      if (!seat.insurance.decided) {
        seat.insurance.decided = true;
        ev(s, { type: 'timeout', seatIndex: seat.seatIndex });
        ev(s, { type: 'insurance', seatIndex: seat.seatIndex, amountCents: 0 });
      }
    }
    peekAndContinue(s);
    return;
  }
  if (s.phase === 'playerTurns' && s.turn) {
    const { seatIndex, handIndex } = s.turn;
    ev(s, { type: 'timeout', seatIndex, handIndex });
    actInPlace(s, seatIndex, 'stand');
    return;
  }
  throw new EngineError('BAD_PHASE');
}

/** Stand every remaining hand of a seat (player left the table). */
export function forfeitTurnsInPlace(s: RoundState, seatIndex: number): void {
  const seat = s.seats.find((x) => x.seatIndex === seatIndex);
  if (!seat) return;
  if (s.phase === 'insurance' && !seat.insurance.decided) {
    seat.insurance.decided = true;
    ev(s, { type: 'insurance', seatIndex, amountCents: 0 });
    if (s.seats.every((x) => x.insurance.decided)) peekAndContinue(s);
  }
  while (s.phase === 'playerTurns' && s.turn && s.turn.seatIndex === seatIndex) {
    actInPlace(s, seatIndex, 'stand');
  }
}

// ---------------------------------------------------------------------------------------------
// Summary

export interface SeatSummary {
  seatIndex: number;
  playerId: string;
  stakedCents: number;
  returnCents: number;
  netCents: number;
  /** Best outcome over the seat's hands for ranking: blackjack > win > push > lose. */
  outcome: 'blackjack' | 'win' | 'push' | 'lose';
  handsWon: number;
  handsLost: number;
  handsPushed: number;
  blackjacks: number;
}

export function summarize(s: RoundState): SeatSummary[] {
  if (s.phase !== 'settled') throw new EngineError('BAD_PHASE');
  return s.seats.map((seat) => {
    const staked = totalStaked(s, seat.seatIndex);
    const ret = seat.hands.reduce((a, h) => a + (h.returnCents ?? 0), 0) + (seat.insurance.returnCents ?? 0);
    const results = seat.hands.map((h) => h.result as HandResult);
    const won = results.filter((r) => r === 'win' || r === 'blackjack').length;
    const pushed = results.filter((r) => r === 'push').length;
    const bj = results.filter((r) => r === 'blackjack').length;
    const outcome = bj > 0 ? 'blackjack' : won > 0 ? 'win' : pushed > 0 ? 'push' : 'lose';
    return {
      seatIndex: seat.seatIndex, playerId: seat.playerId, stakedCents: staked, returnCents: ret,
      netCents: ret - staked, outcome, handsWon: won, handsLost: results.length - won - pushed,
      handsPushed: pushed, blackjacks: bj,
    };
  });
}

/** Cards consumed from the deck so far, in order. */
export function dealtCards(s: RoundState): CardCode[] {
  return s.deck.slice(0, s.deckPos);
}

/** Total of the dealer's visible cards (the hole card is hidden until revealed). */
export function dealerVisibleCards(s: RoundState): CardCode[] {
  return s.dealer.holeRevealed ? s.dealer.cards.slice() : s.dealer.cards.slice(0, 1);
}
