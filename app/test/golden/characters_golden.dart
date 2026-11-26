// Goldens of the procedural characters (included by golden_test.dart): one
// image per member of the cast (bust, head, medallion), plus the expression
// and hairstyle sheets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/core/characters/cast.dart';
import 'package:vingtun/core/characters/character_spec.dart';
import 'package:vingtun/core/characters/character_view.dart';

import '../helpers.dart';

Widget _sheet(List<Widget> children) => Scaffold(
      backgroundColor: const Color(0xFF16222C),
      body: Center(child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: children)),
    );

void charactersGoldens() {
  for (final c in Cast.all) {
    testWidgets('character ${c.id}', (tester) async {
      usePhoneSurface(tester, size: const Size(411, 300));
      await pumpScreen(
        tester,
        _sheet([
          CharacterPortrait(spec: c, size: 190, framing: CharacterFraming.bust),
          Column(mainAxisSize: MainAxisSize.min, children: [
            CharacterPortrait(spec: c, size: 92, framing: CharacterFraming.head, expression: CharacterExpression.smile),
            const SizedBox(height: 8),
            CharacterPortrait(spec: c, size: 92, expression: CharacterExpression.wink),
          ]),
        ]),
      );
      await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/character_${c.id}.png'));
    });
  }

  testWidgets('character expressions and hairstyles', (tester) async {
    usePhoneSurface(tester, size: const Size(411, 520));
    await pumpScreen(
      tester,
      _sheet([
        for (final e in CharacterExpression.values) CharacterPortrait(spec: Cast.camille, size: 88, expression: e),
        for (final h in HairStyle.values) CharacterPortrait(spec: Cast.alex.copyWith(hairStyle: h, accessories: const {}), size: 88, framing: CharacterFraming.head),
        const CharacterPortrait(spec: Cast.lucas, size: 88, pose: CharacterPose(blink: 1, talk: 1, headTilt: 0.2, gaze: Offset(1, 0))),
      ]),
    );
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/character_sheet.png'));
  });
}
