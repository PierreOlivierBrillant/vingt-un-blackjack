import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/audio/app_sound_events.dart';
import 'package:vingtun/core/audio/sfx.dart';
import 'package:vingtun/core/audio/sound_providers.dart';
import 'package:vingtun/core/audio/sound_service.dart';
import 'package:vingtun/core/settings/settings_controller.dart';
import 'package:vingtun/domain/cards.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/domain/table_state.dart';
import 'package:vingtun/features/dealer/dealer_controller.dart';
import 'package:vingtun/features/dealer/dealer_feedback.dart';
import 'package:vingtun/features/table/table_director.dart';
import 'package:vingtun/features/table/table_sounds.dart';

import '../helpers.dart';
import '../table_fixtures.dart';

TableState snap(Map<String, Object?> d) => TableState.fromDoc('tbl', d);

/// (sample rate, frames) of a PCM WAV file.
(int, int) wavInfo(Uint8List b) {
  final d = ByteData.sublistView(b);
  expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');
  var p = 12;
  int? rate, blockAlign, frames;
  while (p + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(p, p + 4));
    final size = d.getUint32(p + 4, Endian.little);
    if (id == 'fmt ') {
      rate = d.getUint32(p + 12, Endian.little);
      blockAlign = d.getUint16(p + 20, Endian.little);
    } else if (id == 'data') {
      frames = size ~/ blockAlign!;
    }
    p += 8 + size + (size.isOdd ? 1 : 0);
  }
  return (rate!, frames!);
}

void main() {
  group('sound bank (assets/sfx)', () {
    final dir = Directory('assets/sfx');
    final files = {for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last};

    test('every Sfx has its WAV and every WAV is catalogued', () {
      for (final s in Sfx.values) {
        expect(files, contains('${s.file}.wav'), reason: s.name);
      }
      final wavs = files.where((f) => f.endsWith('.wav')).toSet();
      expect(wavs, {for (final s in Sfx.values) '${s.file}.wav'});
      expect(Sfx.values.length, 77);
    });

    test('durations match the files, loops match the manifest, total ≤ 6 MiB', () {
      final manifest = File('assets/sfx/MANIFEST.md').readAsStringSync();
      var total = 0;
      for (final s in Sfx.values) {
        final f = File('assets/sfx/${s.file}.wav');
        final bytes = f.readAsBytesSync();
        total += bytes.length;
        final (rate, frames) = wavInfo(bytes);
        final ms = frames * 1000 / rate;
        expect((ms - s.durationMs).abs(), lessThan(25), reason: '${s.file}: $ms ms vs ${s.durationMs}');
        final row = manifest.split('\n').firstWhere((l) => l.startsWith('| `${s.file}.wav`'));
        expect(row.contains('| oui |'), s.loop, reason: '${s.file} loop flag');
      }
      expect(total, lessThanOrEqualTo(6 * 1024 * 1024));
    });

    test('pubspec bundles the folder', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/sfx/'));
    });

    test('no hard-coded sound path in lib/ points to a missing file', () {
      final re = RegExp(r'''['"](?:assets/)?sfx/([a-z0-9_]+)\.wav['"]''');
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          expect(files, contains('${m.group(1)}.wav'), reason: f.path);
        }
      }
    });

    test('variant groups and preload sets only use one-shots', () {
      expect(Sfx.cardDeal3.group, 'card_deal');
      expect(Sfx.cardRevealHole.group, 'card_reveal_hole');
      for (final s in [...kTableSfx, ...kUiSfx]) {
        expect(s.loop, isFalse, reason: s.name);
      }
    });
  });

  group('SoundGovernor (anti-fatigue)', () {
    late RecordingSoundService rec;
    late SoundGovernor g;
    var now = DateTime(2026);
    void wait(int ms) => now = now.add(Duration(milliseconds: ms));

    setUp(() {
      now = DateTime(2026);
      rec = RecordingSoundService();
      g = SoundGovernor(rec, now: () => now);
    });

    test('very repeated sounds are rate-limited (price ticks, variants share a voice)', () {
      for (var i = 0; i < 20; i++) {
        g.play(Sfx.priceTickUp);
        wait(50);
      }
      // 1 s of ticks every 50 ms → one every 250 ms.
      expect(rec.count(Sfx.priceTickUp), 4);
      g.play(Sfx.cardDeal1);
      g.play(Sfx.cardDeal2); // same group, same instant
      expect(rec.sounds.where((s) => s.group == 'card_deal').length, 1);
      wait(40);
      g.play(Sfx.cardDeal3);
      expect(rec.sounds.where((s) => s.group == 'card_deal').length, 2);
    });

    test('no pile of fanfares: at most two together, never under a jackpot', () {
      g.play(Sfx.winSmall);
      g.play(Sfx.dealerBust);
      g.play(Sfx.winMedium); // third fanfare at once → dropped
      expect(rec.sounds, [Sfx.winSmall, Sfx.dealerBust]);
      wait(2000);
      g.play(Sfx.blackjackJackpot); // a jackpot always gets through when room
      g.play(Sfx.winSmall); // lesser fanfare under a jackpot → dropped
      expect(rec.sounds.last, Sfx.blackjackJackpot);
      wait(2900); // 70 % of 4 s elapsed
      g.play(Sfx.winSmall);
      expect(rec.sounds.last, Sfx.winSmall);
      expect(g.dropped, 2);
    });

    test('ten fanfares in a row: only the first ones play', () {
      for (var i = 0; i < 10; i++) {
        g.play(Sfx.winStreak3);
        wait(100);
      }
      expect(rec.count(Sfx.winStreak3), 1); // same sound: cooldown + slot rule
    });

    test('voice cap keeps room for fanfares', () {
      final g2 = SoundGovernor(rec, now: () => now, maxVoices: 3);
      g2.play(Sfx.chipStack);
      g2.play(Sfx.actionHit);
      g2.play(Sfx.chipBetPlace);
      g2.play(Sfx.cardsCollect); // 4th regular voice → dropped
      g2.play(Sfx.winSmall); // fanfare still plays
      expect(rec.sounds, [Sfx.chipStack, Sfx.actionHit, Sfx.chipBetPlace, Sfx.winSmall]);
    });

    test('muted, zero effects volume or suspended → silence; loops are forwarded', () {
      g.setLevels(const SoundLevels(muted: true));
      g.play(Sfx.uiTap);
      g.setLevels(const SoundLevels(effects: 0));
      g.play(Sfx.uiTap);
      g.setLevels(const SoundLevels());
      g.suspend();
      g.play(Sfx.uiTap);
      expect(rec.played, isEmpty);
      expect(rec.suspended, isTrue);
      g.resume();
      g.play(Sfx.uiTap);
      expect(rec.sounds, [Sfx.uiTap]);
      g.startLoop(SoundChannel.ambience, Sfx.ambienceCasinoLoop);
      g.stopLoop(SoundChannel.ambience);
      expect(rec.loopLog, ['ambience:ambienceCasinoLoop', 'ambience:stop']);
    });
  });

  group('settings → audio levels', () {
    test('volumes persist and reach the sound service', () async {
      final prefs = await testPrefs();
      final rec = RecordingSoundService();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        soundBackendProvider.overrideWithValue(rec),
      ]);
      addTearDown(c.dispose);
      c.read(soundProvider);
      expect(rec.levels, const SoundLevels(effects: 0.9, ambience: 0.45));
      await c.read(settingsProvider.notifier).setEffectsVolume(0.3);
      await c.read(settingsProvider.notifier).setAmbienceVolume(0.7);
      await c.read(settingsProvider.notifier).setSound(false);
      expect(rec.levels, const SoundLevels(effects: 0.3, ambience: 0.7, muted: true));
      expect(prefs.getDouble('settings.effectsVolume'), 0.3);
      expect(prefs.getDouble('settings.ambienceVolume'), 0.7);
      final c2 = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      expect(c2.read(settingsProvider).soundLevels, const SoundLevels(effects: 0.3, ambience: 0.7, muted: true));
    });

    test('ambience zones: the latest entered wins, leaving restores', () {
      final rec = RecordingSoundService();
      final a = AmbienceController(rec);
      final lobby = a.enter(AmbienceZone.lobby);
      final table = a.enter(AmbienceZone.table);
      expect(a.current, AmbienceZone.table);
      a.leave(table);
      expect(a.current, AmbienceZone.lobby);
      a.leave(lobby);
      expect(rec.loops, isEmpty);
      expect(rec.loopLog.first, 'ambience:ambienceCasinoLoop');
      expect(rec.loopLog.last, 'ambience:stop');
    });

    test('matchmaking: sonar loop while searching, then "found"', () async {
      final rec = RecordingSoundService();
      final r = await withMatchmakingSounds(rec, () async {
        expect(rec.loops[SoundChannel.matchmaking], Sfx.matchmakingSearch);
        return 42;
      });
      expect(r, 42);
      expect(rec.loops, isEmpty);
      expect(rec.sounds, [Sfx.matchmakingFound]);
      await expectLater(withMatchmakingSounds<int>(rec, () async => throw StateError('x')), throwsStateError);
      expect(rec.loops, isEmpty);
      expect(rec.count(Sfx.matchmakingFound), 1);
    });
  });

  group('table sounds (director → controller → soundscape)', () {
    late RecordingSoundService rec;
    late TableSoundscape scape;
    late DealerController dealer;
    late TableDirector director;
    var mySeat = 0;

    setUp(() {
      rec = RecordingSoundService();
      mySeat = 0;
      scape = TableSoundscape(sound: rec, mySeat: () => mySeat, minBetCents: () => 100, maxBetCents: () => 10000);
      dealer = DealerController(feedback: scape);
      director = TableDirector(dealer, now: () => DateTime.fromMillisecondsSinceEpoch(kT0));
      // Silent first snapshot (rebuild from state).
      director.apply(snap(tableDoc(seats: [seatDoc(0, 'me'), seatDoc(1, 'b', bot: true)])));
    });
    tearDown(() => dealer.dispose());

    void playAll() => dealer.advance(dealer.remainingDuration + const Duration(milliseconds: 1));

    List<Sfx> cardDeals() => [for (final s in rec.sounds) if (s.group == 'card_deal') s];

    test('a full hand: deals, stand, drum-rolled reveal, dealer bust, big win', () {
      final events = [
        ev(1, 'bet', seat: 0, amount: 1000),
        ev(2, 'bet', seat: 1, amount: 500),
        ev(3, 'deal', seat: 0, hand: 0, card: 'TH'),
        ev(4, 'deal', seat: 1, hand: 0, card: '9C'),
        ev(5, 'dealerUp', card: '7D'),
        ev(6, 'deal', seat: 0, hand: 0, card: '6S'),
        ev(7, 'deal', seat: 1, hand: 0, card: '9H'),
        ev(8, 'dealerHole'),
        ev(9, 'stand', seat: 0, hand: 0),
        ev(10, 'stand', seat: 1, hand: 0),
        ev(11, 'reveal', card: '9S'),
        ev(12, 'dealerHit', card: 'KD'),
        ev(13, 'settle', seat: 0, hand: 0, result: 'win', amount: 2000),
        ev(14, 'settle', seat: 1, hand: 0, result: 'win', amount: 1000),
      ];
      director.apply(snap(tableDoc(
        phase: 'settled',
        seats: [
          seatDoc(0, 'me', bet: 1000, net: 1000, hands: [handDoc(['TH', '6S'], done: true, result: 'win', ret: 2000)]),
          seatDoc(1, 'b', bot: true, bet: 500, net: 500, hands: [handDoc(['9C', '9H'], bet: 500, done: true, result: 'win', ret: 1000)]),
        ],
        dealerCards: ['7D', '9S', 'KD'],
        events: events,
      )));
      playAll();
      final s = rec.sounds;
      // One felt thump per card: 4 player cards + up card + hole card + hit.
      expect(cardDeals().length, 7);
      expect(rec.count(Sfx.chipBetPlace), 2);
      expect(rec.count(Sfx.actionStand), 2);
      // Mine at full volume, the bot's quieter.
      final stands = rec.played.where((p) => p.sfx == Sfx.actionStand).map((p) => p.volume).toList();
      expect(stands, [1.0, TableSoundscape.othersVolume]);
      expect(s, containsAllInOrder([Sfx.cardRevealHole, Sfx.dealerBust, Sfx.winBig, Sfx.chipsPushWin]));
      // Suspense loop during the dealer's draw, stopped before the payout.
      expect(rec.loopLog, ['suspense:drumrollLong', 'suspense:stop']);
      // The bot's win: a coin, no fanfare.
      expect(rec.count(Sfx.coinSingle), greaterThanOrEqualTo(1));
      expect(s.where((x) => x.tier == SfxTier.jackpot), [Sfx.winBig]);
      expect(scape.celebrations.value?.kind, CelebrationKind.bigWin);
      expect(scape.streak, 1);
    });

    test('the reveal sound starts so that its clack lands on the flip', () {
      final fb = RecordingDealerFeedback();
      final d = DealerController(feedback: fb);
      addTearDown(d.dispose);
      d.dealCard(const HandTarget.dealer(), faceUp: false);
      d.advance(const Duration(seconds: 2));
      d.revealHoleCard(PlayingCardFixtures.nine);
      var t = Duration.zero;
      Duration? revealAt, flipAt;
      while (d.isBusy) {
        d.advance(const Duration(milliseconds: 10));
        t += const Duration(milliseconds: 10);
        if (revealAt == null && fb.cues.contains(DealerCue.holeReveal)) revealAt = t;
        if (flipAt == null && fb.cues.contains(DealerCue.holeFlip)) flipAt = t;
      }
      // card_reveal_hole.wav: card clack at 0.72 s.
      expect((flipAt! - revealAt!).inMilliseconds, inInclusiveRange(680, 760));
    });

    test('a card thump is cued just before the card lands (sample impact at 148 ms)', () {
      final fb = RecordingDealerFeedback();
      final d = DealerController(feedback: fb);
      addTearDown(d.dispose);
      d.dealCard(const HandTarget.seat(0), card: PlayingCardFixtures.nine);
      var t = 0;
      int? landCue;
      while (d.isBusy) {
        d.advance(const Duration(milliseconds: 4));
        t += 4;
        if (landCue == null && fb.cues.contains(DealerCue.cardLand)) landCue = t;
      }
      // The card comes to rest at 86 % of 640 ms = 550 ms.
      expect(550 - landCue!, inInclusiveRange(140, 156));
      expect(fb.infos[fb.cues.indexOf(DealerCue.cardLand)].seat, 0);
    });

    test('bust: buzzer, losing streak reset, bet raked', () {
      scape.streak = 2;
      director.apply(snap(tableDoc(
        phase: 'settled',
        seats: [seatDoc(0, 'me', bet: 1000, net: -1000, hands: [handDoc(['TH', '6S', '9D'], done: true, result: 'bust', ret: 0)])],
        dealerCards: ['7D', '9S'],
        events: [
          ev(1, 'bet', seat: 0, amount: 1000),
          ev(2, 'deal', seat: 0, hand: 0, card: 'TH'),
          ev(3, 'dealerUp', card: '7D'),
          ev(4, 'deal', seat: 0, hand: 0, card: '6S'),
          ev(5, 'dealerHole'),
          ev(6, 'hit', seat: 0, hand: 0, card: '9D'),
          ev(7, 'reveal', card: '9S'),
          ev(8, 'settle', seat: 0, hand: 0, result: 'bust', amount: 0),
        ],
      )));
      playAll();
      expect(rec.sounds, containsAllInOrder([Sfx.actionHit, Sfx.bust, Sfx.chipsRakeLose]));
      expect(scape.streak, 0);
      expect(rec.loopLog, isEmpty); // the dealer did not draw
    });

    test('blackjack: the full jackpot + celebration', () {
      director.apply(snap(tableDoc(
        phase: 'settled',
        seats: [seatDoc(0, 'me', bet: 1000, net: 1500, hands: [handDoc(['AS', 'KC'], done: true, result: 'blackjack', ret: 2500)])],
        dealerCards: ['9D', '8C'],
        events: [
          ev(1, 'bet', seat: 0, amount: 1000),
          ev(2, 'deal', seat: 0, hand: 0, card: 'AS'),
          ev(3, 'dealerUp', card: '9D'),
          ev(4, 'deal', seat: 0, hand: 0, card: 'KC'),
          ev(5, 'dealerHole'),
          ev(6, 'reveal', card: '8C'),
          ev(7, 'settle', seat: 0, hand: 0, result: 'blackjack', amount: 2500),
        ],
      )));
      playAll();
      expect(rec.sounds, containsAllInOrder([Sfx.cardRevealHole, Sfx.blackjackJackpot, Sfx.chipsPushWin]));
      expect(scape.celebrations.value?.kind, CelebrationKind.blackjack);
      expect(scape.celebrations.value?.big, isTrue);
    });

    test('win grading and streaks of 3 and 5', () {
      void win(int cents) => scape.cue(DealerCue.react, CueInfo(seat: 0, reaction: 'win', cents: cents));
      win(100); // 1× min bet → small
      expect(rec.sounds.last, Sfx.winSmall);
      win(300); // 3× → medium
      expect(rec.sounds.last, Sfx.winMedium);
      win(100); // 3rd in a row → streak sound instead
      expect(rec.sounds.last, Sfx.winStreak3);
      expect(scape.celebrations.value?.streak, 3);
      win(900); // 9× → big
      expect(rec.sounds.last, Sfx.winBig);
      win(100); // 5th → streak 5
      expect(rec.sounds.last, Sfx.winStreak5);
      expect(scape.celebrations.value?.big, isTrue);
      scape.cue(DealerCue.react, const CueInfo(seat: 0, reaction: 'push'));
      expect(rec.sounds.last, Sfx.pushTie);
      expect(scape.streak, 5); // a push keeps the streak
      scape.cue(DealerCue.react, const CueInfo(seat: 0, reaction: 'lose'));
      expect(rec.sounds.last, Sfx.loseHand);
      expect(scape.streak, 0);
      expect(gradeWin(199, 100), WinGrade.small);
      expect(gradeWin(200, 100), WinGrade.medium);
      expect(gradeWin(800, 100), WinGrade.big);
    });

    test('other seats never trigger fanfares', () {
      for (final r in ['win', 'blackjack', 'bust', 'lose']) {
        scape.cue(DealerCue.react, CueInfo(seat: 3, reaction: r, cents: 5000));
      }
      expect(rec.sounds.where((s) => s.tier.index >= SfxTier.fanfare.index), isEmpty);
      expect(scape.celebrations.value, isNull);
    });

    test('turn timer: ticks, urgent in the last 5 s, only on my turn', () {
      dealer.startTurnTimer(0, const Duration(seconds: 10));
      for (var i = 0; i < 10; i++) {
        dealer.advance(const Duration(seconds: 1));
      }
      expect(rec.count(Sfx.timerTick), 4); // 9, 8, 7, 6
      expect(rec.count(Sfx.timerUrgent), 5); // 5..1
      rec.clear();
      dealer.startTurnTimer(1, const Duration(seconds: 10));
      for (var i = 0; i < 10; i++) {
        dealer.advance(const Duration(seconds: 1));
      }
      expect(rec.played, isEmpty);
    });

    test('timeout, insurance (lost at the peek), surrender, powers, second chance, all-in', () {
      director.apply(snap(tableDoc(
        phase: 'playerTurns',
        seats: [seatDoc(0, 'me', bet: 10000, hands: [handDoc(['TH', '6S'], bet: 10000)]), seatDoc(1, 'b', bot: true)],
        dealerCards: ['AD'],
        holeHidden: true,
        events: [
          ev(1, 'bet', seat: 0, amount: 10000), // table max → "tapis !"
          ev(2, 'deal', seat: 0, hand: 0, card: 'TH'),
          ev(3, 'dealerUp', card: 'AD'),
          ev(4, 'deal', seat: 0, hand: 0, card: '6S'),
          ev(5, 'dealerHole'),
          ev(6, 'insurance', seat: 0, amount: 5000),
          ev(7, 'peek', dealerBlackjack: false),
          ev(8, 'power', seat: 0, hand: 0, power: 'freeDouble'),
          ev(9, 'power', seat: 0, hand: 0, power: 'secondChance'),
          ev(10, 'secondChance', seat: 0, hand: 0, card: 'KD'),
          ev(11, 'hit', seat: 0, hand: 0, card: '3C'),
          ev(12, 'timeout', seat: 0, hand: 0),
          ev(13, 'surrender', seat: 0, hand: 0),
        ],
      )));
      playAll();
      final s = rec.sounds;
      expect(s.first, Sfx.chipAllin);
      expect(
        s,
        containsAllInOrder([
          Sfx.actionInsurance,
          Sfx.chipsRakeLose, // insurance lost
          Sfx.powerFreeDouble,
          Sfx.powerSecondChance,
          Sfx.actionHit,
          Sfx.timeout,
          Sfx.actionSurrender,
          Sfx.cardsCollect, // cards folded
        ]),
      );
      // The second-chance card was rewound to the discard: 10H 6S 3C left
      // until the surrender folded the hand.
      expect(dealer.cardsFor(const HandTarget.seat(0)), isEmpty);
      // Half of the bet left on the felt after the surrender.
      expect(dealer.chipStacks.where((c) => c.seat == 0 && c.kind == ChipStackKind.bet).single.cents, 5000);
      expect(dealer.chipStacks.where((c) => c.kind == ChipStackKind.insurance), isEmpty);
    });

    test('a seat joining chimes; shuffle riffles then bridges', () {
      director.apply(snap(tableDoc(
        seats: [seatDoc(0, 'me'), seatDoc(1, 'b', bot: true), seatDoc(2, 'x')],
        hand: 2,
        events: [ev(1, 'join', seat: 2), ev(2, 'shuffle')],
      )));
      playAll();
      expect(rec.sounds, containsAllInOrder([Sfx.seatJoin, Sfx.shuffleRiffle, Sfx.shuffleBridge]));
    });

    test('resync from a snapshot is silent', () {
      final d = DealerController(feedback: scape);
      addTearDown(d.dispose);
      TableDirector(d).apply(snap(tableDoc(
        phase: 'settled',
        seats: [seatDoc(0, 'me', bet: 1000, net: 1500, hands: [handDoc(['AS', 'KC'], done: true, result: 'blackjack', ret: 2500)])],
        dealerCards: ['9D', '8C'],
        eventSeq: 9,
      )));
      expect(rec.played, isEmpty);
    });
  });

  group('app-wide data sounds', () {
    late RecordingSoundService rec;
    late AppSoundEvents e;
    setUp(() {
      rec = RecordingSoundService();
      e = AppSoundEvents(rec);
    });

    LedgerEntry entry(String id, LedgerKind k) =>
        LedgerEntry(id: id, kind: k, amountCents: 1000, at: DateTime(2026, 1, 1, 0, 0, int.parse(id)), balanceAfterCents: 0);

    test('ledger: history is a baseline, new money moves ring', () {
      e.onLedger([entry('1', LedgerKind.welcomeBonus), entry('2', LedgerKind.deposit)]);
      expect(rec.played, isEmpty);
      e.onLedger([
        entry('1', LedgerKind.welcomeBonus),
        entry('2', LedgerKind.deposit),
        entry('3', LedgerKind.deposit),
        entry('4', LedgerKind.withdrawal),
        entry('5', LedgerKind.bet),
        entry('6', LedgerKind.powerPurchase),
        entry('7', LedgerKind.marketBuy),
        entry('8', LedgerKind.marketPayout),
        entry('9', LedgerKind.adReward),
      ]);
      expect(rec.sounds, [
        Sfx.cashRegisterKaching,
        Sfx.coinShower,
        Sfx.withdrawWhoosh,
        Sfx.powerBuy,
        Sfx.tradeBuy,
        Sfx.marketResolvedWin,
        Sfx.adReward,
      ]);
      e.onLedger([entry('10', LedgerKind.welcomeBonus)]);
      expect(rec.sounds.sublist(rec.sounds.length - 2), [Sfx.welcomeBonus, Sfx.coinShower]);
    });

    test('KYC verified, friend request / acceptance, lost market, rank up, leaderboard climb', () {
      e.onKyc(KycStatus.pending);
      e.onKyc(KycStatus.verified);
      e.onRequests(const []);
      e.onRequests([
        const FriendRequest(fromUid: 'u2', toUid: 'me', fromUsername: 'Bob', toUsername: 'Moi', fromAvatar: 'a', incoming: true),
      ]);
      e.onFriends(const []);
      e.onFriends([const Friend(uid: 'u2', username: 'Bob', avatar: 'a', tier: RankTier.bronze, rankPoints: 0, online: false)]);
      MarketPosition pos(PositionStatus st) => MarketPosition(
            marketId: 'm1',
            tableId: 't',
            kind: MarketKind.dealerBust,
            question: const LocalizedText(fr: 'q', en: 'q'),
            yesShares: 1,
            noShares: 0,
            costCents: 10,
            proceedsCents: 0,
            payoutCents: 0,
            status: st,
          );
      e.onPositions([pos(PositionStatus.open)]);
      e.onPositions([pos(PositionStatus.lost)]);
      PlayerProfile prof(RankTier t) => PlayerProfile(
            uid: 'me',
            username: 'Moi',
            avatar: 'a',
            isBot: false,
            rankPoints: 0,
            rankTier: t,
            weeklyPoints: 0,
            weekId: 'w',
          );
      e.onProfile(prof(RankTier.bronze));
      e.onProfile(prof(RankTier.silver));
      e.onLeaderboardRank(12);
      e.onLeaderboardRank(9);
      e.onLeaderboardRank(10);
      expect(rec.sounds, [
        Sfx.kycVerified,
        Sfx.friendRequest,
        Sfx.friendAccept,
        Sfx.marketResolvedLose,
        Sfx.rankUp,
        Sfx.leaderboardClimb,
      ]);
    });
  });
}

abstract final class PlayingCardFixtures {
  static final nine = PlayingCard.parse('9S');
}
