// Feeds maps shaped EXACTLY like the documents / callable responses of
// `firebase/functions/src/shared/types.ts` into the client parsers.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/data/fake/fake_data.dart';
import 'package:vingtun/domain/backend_constants.dart';
import 'package:vingtun/domain/card_style.dart';
import 'package:vingtun/domain/cards.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/domain/table_state.dart';
import 'package:vingtun/domain/wire.dart';

const t0 = 1795462200000; // a fixed epoch-ms instant
DateTime ms(int v) => DateTime.fromMillisecondsSinceEpoch(v);

void main() {
  group('TableDoc', () {
    Map<String, Object?> seat(int i, {bool bot = false}) => {
          'seatIndex': i, 'uid': bot ? 'bot_00$i' : 'u$i', 'username': 'P$i', 'avatar': 'avatar0${i + 1}', 'isBot': bot,
          'rankTier': 'platinum', 'status': i == 1 ? 'leaving' : 'active', 'joinedAtMs': t0 - 1000, 'betCents': 2500,
          'hands': [
            {
              'cards': ['TH', 'AS'], 'total': 21, 'soft': true, 'betCents': 2500, 'stakedCents': 2500, 'doubled': false,
              'fromSplit': false, 'splitAces': false, 'surrendered': false, 'busted': false, 'blackjack': true,
              'done': true, 'result': 'blackjack', 'returnCents': 6250,
            },
          ],
          'insurance': {'betCents': 1250, 'stakedCents': 0, 'decided': true, 'result': 'lose'},
          'powerUsed': 'freeInsurance', 'roundNetCents': 3750, 'missedRounds': 0,
        };
    Map<String, Object?> ev(int seq, String type, {String? card}) => {
          'seq': seq, 'type': type, 'seatIndex': 0, 'handIndex': 0, 'card': card, 'amountCents': null,
          'result': null, 'power': null, 'dealerBlackjack': null, 'atMs': t0 + seq,
        };
    final doc = <String, Object?>{
      'tableId': 'tbl1', 'name': 'Rubis 4', 'stakeTier': 'mid', 'minBetCents': 500, 'maxBetCents': 50000,
      'isPrivate': true, 'simManaged': false, 'status': 'open', 'phase': 'settled', 'phaseStartedAtMs': t0,
      'deadlineMs': t0 + 6000, 'handNumber': 12,
      'shoe': {'shoeNumber': 2, 'totalCards': 312, 'cardsRemaining': 150, 'handsDealt': 20, 'dealerBusts': 6, 'naturals': 3},
      'seats': [seat(0), seat(1, bot: true), null], // only 3 entries: padded to 5
      'dealer': {'cards': ['9C', 'TD'], 'holeHidden': false, 'total': 19, 'soft': false, 'blackjack': false, 'busted': false},
      'turn': null,
      'fairness': {'currentCommit': null, 'currentHandNumber': 12, 'lastHandNumber': 12, 'lastCommit': 'ab', 'lastSeed': 'cd'},
      'events': [ev(7, 'reveal', card: 'TD'), ev(5, 'deal', card: 'TH'), ev(6, 'futureThing'), ev(4, 'shuffle')],
      'eventSeq': 7, 'humanCount': 1, 'botCount': 1, 'seatedUids': ['u0', 'bot_001'],
      'queue': [{'uid': 'q1', 'username': 'Wait', 'avatar': 'avatar03', 'rankTier': 'gold', 'queuedAtMs': t0}],
      'markets': {'dealerBust': 'tbl1__h12__dealerBust', 'natural': null, 'shoe': 'tbl1__s2__shoe', 'players': {'0': 'tbl1__h12__p0'}},
      'rankTier': 'gold', 'createdAtMs': t0 - 99999, 'updatedAtMs': t0 + 1,
    };

    test('parses every field; seats padded to 5; T = ten; events sorted; unknown events ignored', () {
      final t = TableState.fromDoc('tbl1', doc);
      expect(t.name, 'Rubis 4');
      expect(t.stakeTier, 'mid');
      expect(t.isPrivate, isTrue);
      expect(t.phase, ServerTablePhase.settled);
      expect(t.deadline, ms(t0 + 6000));
      expect(t.seats, hasLength(5));
      expect(t.seats.sublist(2), everyElement(isNull));
      final s0 = t.seats[0]!;
      expect(s0.hands.single.cards.first, const PlayingCard(Rank.ten, Suit.hearts));
      expect(s0.hands.single.result, HandResult.blackjack);
      expect(s0.hands.single.returnCents, 6250);
      expect(s0.insurance!.won, isFalse);
      expect(s0.powerUsed, PowerType.freeInsurance);
      expect(s0.rankTier, RankTier.platinum);
      expect(t.seats[1]!.leaving, isTrue);
      expect(t.seats[1]!.isBot, isTrue);
      expect(t.dealer.cards.last, const PlayingCard(Rank.ten, Suit.diamonds));
      expect([for (final e in t.events) e.seq], [4, 5, 7]);
      expect(t.events.last.type, TableEventType.reveal);
      expect(t.turn, isNull);
      expect(t.shoe.cardsRemaining, 150);
      expect(t.fairness.lastSeed, 'cd');
      expect(t.queue.single.username, 'Wait');
      expect(t.markets.players, {0: 'tbl1__h12__p0'});
      expect(t.markets.all, ['tbl1__h12__dealerBust', 'tbl1__s2__shoe', 'tbl1__h12__p0']);
      expect(cardToWire(t.dealer.cards.last), 'TD');
    });

    test('an empty map falls back to safe values', () {
      final t = TableState.fromDoc('x', const {});
      expect(t.id, 'x');
      expect(t.seats, hasLength(5));
      expect(t.phase, ServerTablePhase.idle);
      expect(t.events, isEmpty);
    });

    test('LiveTable (lobby row) from the same doc', () {
      final l = LiveTable.fromDoc(doc);
      expect(l.id, 'tbl1');
      expect(l.tierId, 'mid');
      expect(l.phase, ServerTablePhase.settled);
      expect(l.humans, 1);
      expect(l.bots, 1);
      expect(l.seatsTaken, 2);
      expect(l.queueLength, 1);
      expect(l.isPrivate, isTrue);
      expect(l.hasMarket, isTrue);
      expect(l.rankTier, RankTier.gold);
    });

    test('the fake table doc goes through the same parser', () {
      final t = TableState.fromDoc('t-saphir-1', FakeData.tableDoc('t-saphir-1'));
      expect(t.seatOf(FakeData.demoUid)?.hands.single.soft, isTrue);
      expect(t.turn, const TableTurn(2, 0));
      expect(t.markets.natural, 'm-saphir1-441-bj');
    });
  });

  test('ProfileDoc → PlayerProfile (+ online rule 120 s)', () {
    final p = PlayerProfile.fromDoc({
      'uid': 'u1', 'username': 'Ada_99', 'usernameLower': 'ada_99', 'avatar': 'avatar07', 'isBot': false,
      'rankPoints': 1600, 'rankTier': 'gold', 'weeklyPoints': 85, 'weekId': '2026-W47',
      'stats': {'handsPlayed': 40, 'handsWon': 18, 'handsLost': 19, 'handsPushed': 3, 'blackjacks': 2, 'netCents': -1500, 'biggestWinCents': 7500},
      'currentTableId': 'tbl1', 'lastSeenAtMs': t0, 'kycVerified': true, 'createdAtMs': t0 - 86400000,
    });
    expect(p.username, 'Ada_99');
    expect(p.avatar, 'avatar07');
    expect(p.avatarHue, 90);
    expect(p.rankTier, RankTier.gold);
    expect(p.weeklyPoints, 85);
    expect(p.weekId, '2026-W47');
    expect(p.stats.handsPushed, 3);
    expect(p.stats.netCents, -1500);
    expect(p.stats.winRate, closeTo(0.45, 1e-9));
    expect(p.currentTableId, 'tbl1');
    expect(p.kycVerified, isTrue);
    expect(p.onlineAt(ms(t0 + 119000)), isTrue);
    expect(p.onlineAt(ms(t0 + 120000)), isFalse);
    // Missing tier → derived from rankPoints (RANK_TIER_THRESHOLDS).
    expect(PlayerProfile.fromDoc({'uid': 'x', 'rankPoints': 3600}).rankTier, RankTier.platinum);
    expect(PlayerProfile.fromDoc(const {}, id: 'z').uid, 'z');

    final u = AppUser.fromProfile(uid: 'u1', email: 'a@b.c', profile: p);
    expect(u.profileComplete, isTrue);
    expect(u.kycStatus, KycStatus.verified);
    expect(u.rankTier, RankTier.gold);
    expect(AppUser.fromProfile(uid: 'u1', email: 'a@b.c').profileComplete, isFalse);
  });

  test('UserSettingsDoc ↔ CardStyle (6 backs, 3 faces, 5 felts)', () {
    final s = UserSettings.fromDoc({'theme': 'light', 'language': 'en', 'cardBack': 'neonGrid', 'cardFace': 'fourColor', 'felt': 'blue', 'updatedAtMs': t0});
    expect(s.theme, ThemePreference.light);
    expect(s.language, 'en');
    expect(s.style.serverBack, CardBackId.neonGrid);
    expect(s.style.back, CardBackDesign.dots);
    expect(s.style.face, CardFaceStyle.fourColor);
    expect(s.style.felt, FeltColor.navy);
    expect(s.toDoc(ms(t0)), {'theme': 'light', 'language': 'en', 'cardBack': 'neonGrid', 'cardFace': 'fourColor', 'felt': 'blue', 'updatedAtMs': t0});
    // Unknown values → server defaults.
    final d = UserSettings.fromDoc(const {'cardBack': 'rainbow'});
    expect(d.style, CardStyle.serverDefault);
    expect(d.style.serverBack, CardBackId.classicBlue);
    // Round trip of every server value.
    for (final b in CardBackId.values) {
      for (final f in FeltColor.values) {
        final st = CardStyle.fromWire(cardBack: b.name, cardFace: 'neon', felt: f.wire);
        expect(st.isServerStyle, isTrue);
        expect(st.toWire(), {'cardBack': b.name, 'cardFace': 'neon', 'felt': f.wire});
      }
    }
    expect({for (final b in CardBackId.values) (b.design, b.colorIndex)}, hasLength(6), reason: 'backs are distinct');
    expect(FeltColor.values.map((f) => f.wire), ['green', 'blue', 'red', 'purple', 'black']);
    // A non-server combination maps to the nearest back (same colour first).
    const odd = CardStyle(back: CardBackDesign.sunburst, backColorIndex: 2);
    expect(odd.isServerStyle, isFalse);
    expect(odd.serverBack, CardBackId.emerald);
    expect(odd.normalized.isServerStyle, isTrue);
  });

  test('WalletDoc: deposited today only when dailyDeposit.day is today (UTC)', () {
    final now = DateTime.utc(2026, 11, 18, 21);
    Map<String, Object?> doc(String day) => {
          'balanceCents': 123456, 'totalDepositedCents': 200000, 'totalWithdrawnCents': 5000,
          'dailyDeposit': {'day': day, 'amountCents': 150000}, 'updatedAtMs': t0,
        };
    final w = WalletSnapshot.fromDoc(doc('2026-11-18'), now: now);
    expect(w.balanceCents, 123456);
    expect(w.totalDepositedCents, 200000);
    expect(w.totalWithdrawnCents, 5000);
    expect(w.depositedTodayCents, 150000);
    expect(w.depositLimitCents, 500000);
    expect(w.depositRemainingTodayCents, 350000);
    expect(WalletSnapshot.fromDoc(doc('2026-11-17'), now: now).depositedTodayCents, 0);
    expect(utcDayId(DateTime.utc(2026, 1, 2, 23, 59)), '2026-01-02');
  });

  test('KycDoc and SubmitKycResponse', () {
    final k = KycState.fromDoc({
      'status': 'pending', 'docType': 'driverLicense', 'submittedAtMs': t0, 'verifyAfterMs': t0 + 3000,
      'verifiedAtMs': null, 'rejectionReason': null,
    });
    expect(k.status, KycStatus.pending);
    expect(k.docType, IdDocumentType.driverLicense);
    expect(k.verifyAfter, ms(t0 + 3000));
    expect(k.rejection, isNull);
    final r = KycState.fromResponse({'status': 'rejected', 'verifyAfterMs': null, 'rejectionReason': 'underage'});
    expect(r.status, KycStatus.rejected);
    expect(r.rejection, KycRejection.underage);
    expect(KycState.fromDoc(const {}).status, KycStatus.none);
    expect(KycSubmission(documentType: IdDocumentType.passport, birthDate: DateTime(2001, 12, 31)).toRequest(),
        {'docType': 'passport', 'birthDate': '2001-12-31'});
  });

  test('LedgerEntryDoc: every LEDGER_TYPE, unknown type skipped', () {
    const types = [
      'welcomeBonus', 'deposit', 'withdrawal', 'bet', 'double', 'split', 'insurance', 'payout', 'refund',
      'powerPurchase', 'marketBuy', 'marketSell', 'marketPayout', 'adReward',
    ];
    expect(LedgerKind.values.map((k) => k.name), types);
    final e = LedgerEntry.fromDoc({
      'entryId': 'e1', 'type': 'powerPurchase', 'amountCents': -4000, 'balanceAfterCents': 96000, 'createdAtMs': t0,
      'tableId': null, 'handNumber': null, 'marketId': null, 'powerId': 'secondChance', 'method': null,
    })!;
    expect(e.id, 'e1');
    expect(e.kind, LedgerKind.powerPurchase);
    expect(e.amountCents, -4000);
    expect(e.balanceAfterCents, 96000);
    expect(e.power, PowerType.secondChance);
    expect(e.at, ms(t0));
    final d = LedgerEntry.fromDoc({'entryId': 'e2', 'type': 'deposit', 'amountCents': 5000, 'balanceAfterCents': 5000, 'createdAtMs': t0, 'method': 'bankTransfer'})!;
    expect(d.method, PaymentMethod.bankTransfer);
    final b = LedgerEntry.fromDoc({'entryId': 'e3', 'type': 'double', 'amountCents': -2500, 'balanceAfterCents': 0, 'createdAtMs': t0, 'tableId': 'tbl1', 'handNumber': 12})!;
    expect((b.tableId, b.handNumber), ('tbl1', 12));
    expect(LedgerEntry.fromDoc({'type': 'jackpot'}), isNull);
  });

  test('InventoryDoc → offers with POWER_PRICES_CENTS', () {
    final items = [
      InventoryItem.fromDoc({'powerId': 'peek', 'quantity': 3, 'updatedAtMs': t0})!,
      InventoryItem.fromDoc({'powerId': 'freeDouble', 'quantity': 98, 'updatedAtMs': t0})!,
    ];
    expect(InventoryItem.fromDoc({'powerId': 'nuke', 'quantity': 1}), isNull);
    final offers = PowerOffer.fromInventory(items);
    expect(offers.map((o) => o.type), PowerType.values);
    expect(offers.map((o) => o.priceCents), [2000, 2500, 1000, 3000, 4000]);
    expect(offers.firstWhere((o) => o.type == PowerType.peek).owned, 3);
    expect(offers.firstWhere((o) => o.type == PowerType.freeDouble).maxBuyable, 1);
    expect(offers.firstWhere((o) => o.type == PowerType.freeSplit).maxBuyable, 10);
    expect(BuyPowerResult.fromResponse({'quantity': 4, 'balanceCents': 77000}).quantity, 4);
  });

  test('MarketDoc (incl. void status and resolved outcome)', () {
    Map<String, Object?> doc(String status, String? outcome) => {
          'marketId': 'tbl1__h12__p0', 'tableId': 'tbl1', 'tableName': 'Rubis 4', 'kind': 'playerWins', 'handNumber': 12,
          'shoeNumber': 2, 'subjectUid': 'u0', 'subjectUsername': 'P0', 'subjectSeatIndex': 0,
          'question': {'fr': 'P0 gagne ?', 'en': 'Will P0 win?'}, 'status': status, 'outcome': outcome,
          'b': 60, 'qYes': 25, 'qNo': 10, 'priceYes': 0.5621765008857981, 'volumeCents': 12345, 'tradeCount': 9,
          'payoutsDone': status != 'open', 'createdAtMs': t0, 'closedAtMs': status == 'open' ? null : t0 + 5000,
          'resolvedAtMs': status == 'resolved' ? t0 + 9000 : null,
        };
    final m = Market.fromDoc(doc('resolved', 'yes'))!;
    expect(m.id, 'tbl1__h12__p0');
    expect(m.kind, MarketKind.playerWins);
    expect(m.status, MarketStatus.resolved);
    expect(m.outcome, Outcome.yes);
    expect(m.subjectUsername, 'P0');
    expect(m.subjectSeatIndex, 0);
    expect(m.handNumber, 12);
    expect(m.shoeNumber, 2);
    expect((m.b, m.qYes, m.qNo), (60.0, 25.0, 10.0));
    expect(m.priceYes, closeTo(0.5621765, 1e-6));
    expect(m.noPrice, closeTo(1 - m.priceYes, 1e-12));
    expect(m.question.of('en'), 'Will P0 win?');
    expect(m.question.of('fr'), 'P0 gagne ?');
    expect(m.tradeCount, 9);
    expect(m.payoutsDone, isTrue);
    expect(m.resolvedAt, ms(t0 + 9000));
    expect(m.isFinal, isTrue);
    final v = Market.fromDoc(doc('void', null))!;
    expect(v.status, MarketStatus.voided);
    expect(v.outcome, isNull);
    final shoe = Market.fromDoc({'kind': 'shoeDealerBustRate', 'handNumber': null, 'status': 'open'}, id: 'm-shoe')!;
    expect(shoe.id, 'm-shoe');
    expect(shoe.handNumber, isNull);
    expect(shoe.b, Backend.marketLiquidity[MarketKind.shoeDealerBustRate]);
    expect(Market.fromDoc({'kind': 'weather'}), isNull);
  });

  test('PositionDoc (one doc holds both sides)', () {
    final p = MarketPosition.fromDoc({
      'marketId': 'm1', 'tableId': 'tbl1', 'kind': 'dealerBust', 'question': {'fr': 'Le croupier saute ?', 'en': 'Will the dealer bust?'},
      'yesShares': 30, 'noShares': 10, 'costCents': 1900, 'proceedsCents': 300, 'payoutCents': 0, 'status': 'open', 'updatedAtMs': t0,
    });
    expect(p.sharesOf(Outcome.yes), 30);
    expect(p.sharesOf(Outcome.no), 10);
    expect(p.netCostCents, 1600);
    expect(p.valueCents(0.25), 30 * 25 + 10 * 75);
    expect(p.pnlCents(0.25), 1500 - 1600);
    expect(p.avgPrice, closeTo(0.4, 1e-12));
    final won = MarketPosition.fromDoc({'marketId': 'm1', 'yesShares': 30, 'noShares': 0, 'costCents': 900, 'proceedsCents': 0, 'payoutCents': 3000, 'status': 'won'});
    expect(won.status, PositionStatus.won);
    expect(won.valueCents(0.1), 3000);
    expect(won.pnlCents(0.1), 2100);
    expect(MarketPosition.fromDoc({'status': 'void'}, id: 'm2').status, PositionStatus.voided);
    expect(MarketPosition.fromDoc({'status': 'void'}, id: 'm2').marketId, 'm2');
  });

  test('TradeDoc and PricePointDoc', () {
    final t = MarketTrade.fromDoc({
      'tradeId': 'tr1', 'uid': 'bot_003', 'username': 'AceOfBase', 'isBot': true, 'side': 'no', 'direction': 'sell',
      'shares': 20, 'amountCents': 1380, 'priceYesAfter': 0.33, 'createdAtMs': t0,
    })!;
    expect(t.outcome, Outcome.no);
    expect(t.isBuy, isFalse);
    expect(t.isBot, isTrue);
    expect(t.price, closeTo(0.69, 1e-12));
    expect(t.priceYesAfter, 0.33);
    expect(MarketTrade.fromDoc({'side': 'maybe'}), isNull);
    final pt = PricePoint.fromDoc({'atMs': t0, 'priceYes': 0.61});
    expect(pt.t, ms(t0));
    expect(pt.yes, 0.61);
  });

  test('FriendRequestDoc, FriendshipDoc, FriendSuggestionsDoc', () {
    final doc = {'fromUid': 'bot_014', 'toUid': 'me', 'fromUsername': 'splitzilla', 'toUsername': 'Me', 'fromAvatar': 'avatar05', 'createdAtMs': t0};
    final inc = FriendRequest.fromDoc(doc, myUid: 'me');
    expect(inc.id, 'bot_014_me');
    expect(inc.incoming, isTrue);
    expect(inc.otherUid, 'bot_014');
    expect(inc.otherUsername, 'splitzilla');
    expect(inc.createdAt, ms(t0));
    final out = FriendRequest.fromDoc(doc, myUid: 'bot_014');
    expect(out.incoming, isFalse);
    expect(out.otherUsername, 'Me');
    final f = Friendship.fromDoc({'uids': ['a1', 'b2'], 'usernames': {'a1': 'Ann', 'b2': 'Bob'}, 'sinceMs': t0});
    expect(f.otherUid('b2'), 'a1');
    expect(f.usernames['b2'], 'Bob');
    expect(Friendship.idFor('b2', 'a1'), 'a1_b2');
    expect(FriendSuggestions.fromDoc({'uids': ['bot_001', 'bot_002'], 'updatedAtMs': t0}).uids, ['bot_001', 'bot_002']);
    final p = PlayerProfile.fromDoc({'uid': 'a1', 'username': 'Ann', 'avatar': 'avatar02', 'rankTier': 'silver', 'currentTableId': 'tbl1', 'lastSeenAtMs': t0});
    final fr = Friend.fromProfile(p, now: ms(t0 + 5000), tableName: 'Rubis 4', since: f.since);
    expect((fr.online, fr.tableId, fr.tableName, fr.tier), (true, 'tbl1', 'Rubis 4', RankTier.silver));
  });

  test('FeedEntryDoc → RecentWin', () {
    final w = RecentWin.fromDoc({'username': 'LunaRiver', 'avatar': 'avatar12', 'isBot': false, 'kind': 'bigWin', 'amountCents': 50000, 'tableId': null, 'createdAtMs': t0}, id: 'f1')!;
    expect(w.kind, WinKind.bigWin);
    expect(w.avatar, 'avatar12');
    expect(w.at, ms(t0));
    expect(w.tableId, isNull);
    expect(RecentWin.fromDoc({'kind': 'jackpot'}), isNull);
  });

  test('HandHistoryDoc and PeekDoc', () {
    final h = HandHistory.fromDoc({
      'tableId': 'tbl1', 'handNumber': 11, 'startedAtMs': t0, 'endedAtMs': t0 + 30000, 'dealerCards': ['KS', 'TH'], 'dealerTotal': 20,
      'seats': [
        {
          'seatIndex': 0, 'uid': 'u0', 'username': 'P0', 'isBot': false, 'netCents': -2500,
          'hands': [
            {'cards': ['9S', '8D'], 'total': 17, 'soft': false, 'betCents': 2500, 'stakedCents': 2500, 'doubled': false, 'fromSplit': false,
             'splitAces': false, 'surrendered': false, 'busted': false, 'blackjack': false, 'done': true, 'result': 'lose', 'returnCents': 0},
          ],
        },
      ],
      'fairness': {'commit': 'c0ffee', 'seed': 'beef', 'remainingBefore': ['AS', 'TH'], 'dealt': ['AS']},
    });
    expect(h.handNumber, 11);
    expect(h.dealerCards.last, const PlayingCard(Rank.ten, Suit.hearts));
    expect(h.seats.single.hands.single.result, HandResult.lose);
    expect(h.seats.single.netCents, -2500);
    expect(h.remainingBefore, ['AS', 'TH']);
    expect(h.commit, 'c0ffee');
    final p = PeekResult.fromDoc({'handNumber': 12, 'holeCard': 'TC', 'createdAtMs': t0})!;
    expect(p.holeCard, const PlayingCard(Rank.ten, Suit.clubs));
    expect(p.createdAt, ms(t0));
    expect(PeekResult.fromDoc(const {'handNumber': 12}), isNull);
  });

  test('AdStateDoc', () {
    final now = DateTime.utc(2026, 11, 18, 12);
    final s = AdState.fromDoc({'day': '2026-11-18', 'claimedToday': 4, 'lastClaimAtMs': now.millisecondsSinceEpoch - 10000});
    expect(s.remainingAt(now), 6);
    expect(s.nextClaimAt(now)!.millisecondsSinceEpoch, now.add(const Duration(seconds: 20)).millisecondsSinceEpoch);
    expect(s.remainingAt(DateTime.utc(2026, 11, 19, 1)), 10);
    expect(s.nextClaimAt(now.add(const Duration(minutes: 1))), isNull);
  });

  group('callable responses', () {
    test('CompleteProfile / Deposit / Withdraw', () {
      final c = CompleteProfileResult.fromResponse({'uid': 'u1', 'username': 'Ada_99', 'balanceCents': 100000});
      expect((c.uid, c.username, c.balanceCents), ('u1', 'Ada_99', 100000));
      final d = WalletMoveResult.fromResponse({'balanceCents': 105000, 'ledgerEntryId': 'L9'});
      expect((d.balanceCents, d.ledgerEntryId), (105000, 'L9'));
    });
    test('JoinMatchmaking', () {
      final q = MatchResult.fromResponse({'tableId': 'tbl1', 'status': 'queued', 'seatIndex': null, 'code': null});
      expect((q.tableId, q.seated, q.seatIndex, q.code), ('tbl1', false, null, null));
      final p = MatchResult.fromResponse({'tableId': 'tbl2', 'status': 'seated', 'seatIndex': 3, 'code': 'K7Q2ZX'});
      expect((p.seated, p.seatIndex, p.code), (true, 3, 'K7Q2ZX'));
    });
    test('PokeTable', () {
      final p = PokeResult.fromResponse({'phase': 'playerTurns', 'handNumber': 12, 'deadlineMs': t0, 'advanced': true});
      expect((p.phase, p.handNumber, p.deadline, p.advanced), (ServerTablePhase.playerTurns, 12, ms(t0), true));
    });
    test('TradeShares', () {
      final t = TradeResult.fromResponse({'amountCents': 307, 'priceYes': 0.3244636770105458, 'balanceCents': 99693, 'position': {'yesShares': 10, 'noShares': 0}});
      expect((t.amountCents, t.balanceCents, t.yesShares, t.noShares), (307, 99693, 10, 0));
      expect(t.priceYes, closeTo(0.32446, 1e-5));
    });
    test('FriendRequest', () {
      expect(FriendRequestOutcome.fromResponse({'status': 'accepted', 'toUid': 'u2'}).accepted, isTrue);
      expect(FriendRequestOutcome.fromResponse({'status': 'pending', 'toUid': 'u2'}).accepted, isFalse);
    });
    test('ClaimAdReward', () {
      final r = AdRewardResult.fromResponse({'rewardCents': 500, 'balanceCents': 100500, 'remainingToday': 9});
      expect((r.rewardCents, r.balanceCents, r.remainingToday), (500, 100500, 9));
    });
    test('SubmitKyc', () {
      final k = KycState.fromResponse({'status': 'pending', 'verifyAfterMs': t0 + 3000, 'rejectionReason': null});
      expect((k.status, k.verifyAfter), (KycStatus.pending, ms(t0 + 3000)));
    });
  });

  test('leaderboard entries from profiles: weekly points only for the current week', () {
    final p = PlayerProfile.fromDoc({'uid': 'u1', 'username': 'A', 'rankPoints': 800, 'weeklyPoints': 120, 'weekId': '2026-W46', 'stats': {'handsPlayed': 10, 'handsWon': 4}});
    final g = LeaderboardEntry.fromProfile(p, rank: 1, scope: LeaderboardScope.global, myUid: 'u1', currentWeekId: '2026-W47');
    expect((g.points, g.rankPoints, g.weeklyPoints, g.isMe, g.winRate), (800, 800, 0, true, 0.4));
    final w = LeaderboardEntry.fromProfile(p, rank: 1, scope: LeaderboardScope.weekly, currentWeekId: '2026-W46');
    expect(w.points, 120);
  });

  test('stake tiers mirror STAKE_TIER_LIMITS; fakes use backend tier ids', () {
    final tiers = StakeTier.allFrom(FakeData.tables);
    expect(tiers.map((t) => (t.id, t.minBetCents, t.maxBetCents)), [('low', 100, 10000), ('mid', 500, 50000), ('high', 2500, 250000)]);
    expect(tiers.fold<int>(0, (a, t) => a + t.tablesLive), FakeData.tables.length);
    expect(rankTierForPoints(499), RankTier.bronze);
    expect(rankTierForPoints(7000), RankTier.diamond);
  });

  test('every fake doc parses through the shared parsers', () {
    final now = FakeData.baseNow;
    expect(FakeData.profiles(now), hasLength(FakeData.profileDocs(now).length));
    expect(FakeData.profiles(now).every((p) => Backend.usernamePattern.hasMatch(p.username)), isTrue);
    expect(FakeData.markets(now), hasLength(FakeData.marketDocs(now).length));
    expect(FakeData.markets(now).map((m) => m.status).toSet(), containsAll(MarketStatus.values));
    expect(FakeData.ledger(now), hasLength(FakeData.ledgerDocs(now).length));
    expect(FakeData.recentWins(now), hasLength(FakeData.feedDocs(now).length));
    expect(FakeData.positions(now).first.yesShares, 40);
    for (final m in FakeData.markets(now)) {
      expect(m.priceYes, closeTo(1 / (1 + math.exp((m.qNo - m.qYes) / m.b)), 1e-12), reason: m.id);
    }
  });
}
