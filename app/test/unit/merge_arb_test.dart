// ARB parts (app/l10n/parts) → generated lib/l10n/app_{fr,en}.arb (tool/merge_arb.dart).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/merge_arb.dart';

Map<String, Map<String, Map<String, Object?>>> partsOf(Map<String, (Map<String, Object?>, Map<String, Object?>)> byPart) => {
      for (final e in byPart.entries)
        e.key: {
          'fr': {'@@locale': 'fr', ...e.value.$1},
          'en': {'@@locale': 'en', ...e.value.$2},
        },
    };

/// Minimal valid set: every known part present (empty), plus [extra].
Map<String, Map<String, Map<String, Object?>>> valid([Map<String, (Map<String, Object?>, Map<String, Object?>)> extra = const {}]) =>
    partsOf({
      for (final p in kArbParts.keys) p: (const {}, const {}),
      'core': (const {'hello': 'Bonjour {name}', '@hello': {'placeholders': {'name': {'type': 'String'}}}}, const {'hello': 'Hello {name}'}),
      ...extra,
    });

List<String> errorsOf(Map<String, Map<String, Map<String, Object?>>> parts) {
  try {
    mergeArbParts(parts);
    return const [];
  } on ArbMergeException catch (e) {
    return e.errors;
  }
}

void main() {
  test('the merged ARB files are up to date with l10n/parts (run dart run tool/merge_arb.dart)', () {
    final files = mergedArbFiles(Directory.current);
    for (final e in files.entries) {
      expect(File(e.key).readAsStringSync().replaceAll('\r\n', '\n'), e.value, reason: '${e.key} is generated: edit l10n/parts, then merge');
    }
  });

  test('merge: core first then each part in kArbParts order, @@locale + generated note, metadata kept', () {
    final out = mergeArbParts(valid({
      'roulette': (const {'rouletteSpin': 'Lancer', '@rouletteSpin': {'description': 'x'}}, const {'rouletteSpin': 'Spin'}),
      'craps': (const {'crapsRoll': 'Lancer les dés'}, const {'crapsRoll': 'Roll'}),
    }));
    expect(out['fr']!.keys.toList(), ['@@locale', '@@x-generated', 'hello', '@hello', 'rouletteSpin', '@rouletteSpin', 'crapsRoll']);
    expect(out['en']!['@@locale'], 'en');
    expect(out['en']!['rouletteSpin'], 'Spin');
    // The encoding round-trips through JSON (one entry per line, compact metadata).
    final text = encodeArb(out['fr']!);
    expect(jsonDecode(text), out['fr']);
    expect(text, contains('  "@hello": {"placeholders": {"name": {"type": "String"}}},\n'));
  });

  test('a game part must prefix its keys; core may not use a game prefix', () {
    expect(errorsOf(valid({'roulette': (const {'spin': 'x'}, const {'spin': 'y'})})), [contains('roulette.fr.arb: key "spin" must start with "roulette"'), contains('roulette.en.arb')]);
    expect(errorsOf(valid({'roulette': (const {'roulette': 'x'}, const {'roulette': 'y'})})), isNotEmpty);
    expect(errorsOf(valid({'roulettes': (const {}, const {})})), [contains('unknown part')]);
    expect(
      errorsOf(valid({'core': (const {'crapsTable': 'x'}, const {'crapsTable': 'y'})})),
      [contains('reserved for another part'), contains('reserved for another part')],
    );
    // Romance accepts both of its prefixes.
    expect(errorsOf(valid({'romance': (const {'romanceHub': 'a', 'datingCard': 'b'}, const {'romanceHub': 'a', 'datingCard': 'b'})})), isEmpty);
  });

  test('FR/EN parity: missing keys and different placeholders are refused', () {
    expect(errorsOf(valid({'holdem': (const {'holdemFold': 'Se coucher'}, const {})})), [contains('holdem.en.arb: missing "holdemFold"')]);
    expect(errorsOf(valid({'holdem': (const {}, const {'holdemFold': 'Fold'})})), [contains('holdem.fr.arb: missing "holdemFold"')]);
    expect(
      errorsOf(valid({'holdem': (const {'holdemPot': 'Pot de {amount}'}, const {'holdemPot': 'Pot of {cents}'})})),
      [contains('placeholders differ')],
    );
    // ICU plurals: branch texts are not placeholders, nested arguments are.
    expect(
      errorsOf(valid({
        'craps': (
          const {'crapsRolls': '{n, plural, =0{Aucun} =1{Un lancer} other{{n} lancers de {who}}}'},
          const {'crapsRolls': '{n, plural, =0{None} =1{One roll} other{{n} rolls by {who}}}'},
        ),
      })),
      isEmpty,
    );
  });

  test('duplicates across parts, orphan metadata and a wrong @@locale are refused', () {
    final dup = valid({'baccarat': (const {'baccaratTie': 'Égalité'}, const {'baccaratTie': 'Tie'})});
    dup['romance']!['fr']!['baccaratTie'] = 'x';
    expect(errorsOf(dup), contains(contains('must start with "romance"')));
    final orphan = valid({'baccarat': (const {'@baccaratGhost': {}}, const {})});
    expect(errorsOf(orphan), [contains('has no message')]);
    final locale = valid();
    locale['craps']!['en']!['@@locale'] = 'fr';
    expect(errorsOf(locale), [contains('"@@locale" must be "en"')]);
    final missing = valid()..remove('craps');
    expect(errorsOf(missing), [contains('missing part "craps"')]);
  });

  test('icuArguments', () {
    expect(icuArguments('Main n° {n}'), {'n'});
    expect(icuArguments('{rounds, plural, =0{Aucun tour} =1{1 tour} other{{rounds} tours}} · {won} gagnés'), {'rounds', 'won'});
    expect(icuArguments("Pas d'argument"), isEmpty);
    expect(icuArguments('{choice, select, a{A {x}} other{B}}'), {'choice', 'x'});
  });

  test('every real part follows the rules (no error on the repository files)', () {
    expect(() => mergeArbParts(readArbParts(Directory.current)), returnsNormally);
  });
}
