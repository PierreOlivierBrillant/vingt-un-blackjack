# Phase B du Sprint 2 — consignes communes aux 5 chantiers

Chantiers : `roulette`, `baccarat`, `holdem`, `craps`, `romance` (Rendez-vous). Chacun sur sa branche
`s2-<chantier>` (partie de `sprint-2`), dans son worktree court `C:\Users\po.brillant\s2\<court>` :
`rl` roulette, `bc` baccarat, `ho` hold'em, `cr` craps, `rv` Rendez-vous.

## À lire
1. `PLAN_SPRINT2.md` : règles de ton jeu (ou de la méta Rendez-vous), marchés, pouvoirs, classement,
   architecture, « Vérification ».
2. Backend : `firebase/functions/src/games/kernel/module.ts` (en-tête = mode d'emploi du noyau : cycle
   d'un coup, règles d'argent, marchés, rang), l'en-tête de `src/games/<jeu>/module.ts` (ce que tu dois
   fournir), les modules de test `src/games/testing/{coin,duel}.ts` (exemples complets), les tests
   `test/unit/kernel/*`, `test/integration/games*.test.ts` et `inproc.ts`, le contrat
   `src/shared/games/common.ts` + `src/shared/games/<jeu>.ts` (à compléter : tu en es propriétaire).
3. Flutter : l'en-tête « TO PROVIDE » de `app/lib/features/games/<jeu>/<jeu>_game.dart`,
   `features/games/game_ui.dart`, `features/games/common/game_table_scaffold.dart`,
   `features/stage/` (StageController : commandes begin/step/finish, cues, bras IK),
   `core/characters/` (CharacterPainter, cast), `domain/game_table.dart`, les dépôts factices
   `data/fake/fake_game_{repository,data}.dart`, l'écran placeholder et ses tests
   (`test/widget/games_screens_test.dart`, goldens `game_<jeu>_*`).
4. Sons : `tools/sfx/catalog.mjs`, `tools/sfx/quotas.json`, `tools/sfx/games/<groupe>.mjs` (préfixe
   `<groupe>_`, quota du groupe), `app/test/unit/sound_test.dart`.
5. Textes : `app/l10n/parts/<groupe>.{fr,en}.arb` (préfixe de clé du groupe, parité FR/EN), fusionnés
   par `app/tool/merge_arb.dart` (lancé par `app/tool/test.ps1`).

## Périmètre (vérifié)
`node tools/sprint2/check_owners.mjs <chantier>` doit sortir avec 0 avant CHAQUE commit
(`tools/sprint2/owners.json`). Fichiers dérivés (ARB fusionnés, `lib/l10n/gen`, `contract.json`,
`app/assets/sfx/**`) : régénère-les librement, ils seront régénérés à la fusion. Ne modifie jamais le
noyau (`src/games/kernel/**`), le registre, `callables/games.ts`, `shared/types.ts`,
`games/common.ts`, ni `features/games/{registry,game_ui}.dart`, `common/**`, `stage/**`,
`core/characters/**`. Si tu as besoin d'un changement hors périmètre (un crochet du noyau, un champ
de `GameUi`, un paramètre du scaffold…) : écris-le, avec la raison et un contournement si possible,
dans `tools/sprint2/requests/<chantier>.md`, et continue avec le contournement.
- Nouvelles valeurs d'énumération : seulement EN FIN de tes listes de `shared/games/<jeu>.ts`
  (ou `shared/romance.ts`), puis régénère `contract.json`
  (`npx vitest run --config vitest.unit.config.mts test/unit/contract.test.ts -u` dans
  `firebase/functions`) et reflète-les côté Dart (`app/lib/data/server_errors.dart` pour les raisons,
  `error_messages.dart` + message dans ton morceau ARB) pour que `contract_parity_test.dart` reste vert.

## Émulateurs (ports 9099/8080/5001 partagés par les 5 chantiers)
Verrou obligatoire : `mkdir C:\Users\po.brillant\s2\emu.lock` (atomique : s'il existe déjà, quelqu'un
d'autre teste ; attends et réessaie plus tard, ne le supprime jamais s'il n'est pas à toi). Une fois
le verrou pris, écris ton nom dans `emu.lock\owner.txt`, lance UNIQUEMENT tes fichiers d'intégration
(depuis `firebase/` : `. ..\tools\_backend_env.ps1` puis
`firebase emulators:exec --project demo-blackjack --only auth,firestore,functions "npm --prefix functions run test:integration --silent -- test/integration/<jeu>"`),
puis supprime le verrou, même en cas d'échec. Garde-le moins de 15 minutes. Ne lance jamais la suite
complète (`tools/test_all.ps1`) : sa sonde de charge échoue quand le poste est chargé, et la session
principale la lance elle-même en phase C.

## Étapes vertes et sauvegardes
- Backend : `npm run typecheck && npm run lint && npm run test:unit` dans `firebase/functions`.
- Flutter : `powershell -ExecutionPolicy Bypass -File app\tool\test.ps1` (pub get, fusion ARB,
  gen-l10n, analyze, tests). Les goldens des autres écrans ne doivent pas changer ; régénère les tiens
  (`-UpdateGoldens` puis vérifie que seuls tes fichiers ont changé).
- Commite sur ta branche à chaque étape verte (messages en français terminés par
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`) et pousse (`git push -u origin s2-<chantier>`) :
  poste DeepFreeze.
- Ne touche jamais `main`, ni les autres worktrees, ne fusionne rien. Ne laisse aucun processus tourner.
- Aucune question à l'utilisateur : décide, documente dans `tools/sprint2/requests/<chantier>.md`
  (section « Décisions »).

## Rapport final (ton dernier message)
En français, concis : ce qui est livré, résultats exacts des tests (backend unitaires, intégration
sur émulateurs, Flutter), Monte-Carlo mesuré, décisions, demandes hors périmètre, ce qui n'est PAS
fait ou pas vérifié, dernier commit poussé.
