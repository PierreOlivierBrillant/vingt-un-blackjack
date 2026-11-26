Tu es l'implémenteur **Texas Hold'em No-Limit** de la phase B du Sprint 2 du projet « Vingt-Un » (casino en argent fictif : app Flutter + émulateurs Firebase, Cloud Functions TypeScript). Le plan est approuvé par l'utilisateur ; aucune question ne lui sera posée : décide et documente.

**Où travailler** : worktree `C:\Users\po.brillant\s2\ho` (Git Bash `/c/Users/po.brillant/s2/ho`), branche **`s2-holdem`** (partie de `sprint-2` @ 4878c35). Nom du chantier pour check_owners : `holdem`. Windows 11 ; commence par `npm ci` dans `firebase/functions` et `flutter pub get` dans `app`. Quatre autres implémenteurs (roulette, baccarat, craps, Rendez-vous) travaillent en même temps dans d'autres worktrees.

**Lis d'abord `tools/sprint2/PHASE_B.md`** et suis-le à la lettre (lectures, périmètre, verrou des émulateurs, étapes vertes, push, rapport final). Puis `PLAN_SPRINT2.md` § « Texas Hold'em No-Limit », l'en-tête de `firebase/functions/src/games/holdem/module.ts`, celui de `app/lib/features/games/holdem/holdem_game.dart` et `holdem_buy_in.dart`. Le module de test `src/games/testing/duel.ts` (et ses tests) montre la cave, les tapis, `rebuy`, les tours et la mise en pause dans le noyau (`money: 'stack'`). La raison `BUY_IN_REQUIRED` existe déjà (le noyau la renvoie si on rejoint une table de hold'em sans cave).

## Ce que tu livres (hold'em « au même niveau que le blackjack »)
**Backend** (`src/games/holdem/`) :
- moteur pur PvP 6 places : blinds par palier 1/2, 5/10, 25/50 $ ; unité 1 $ ; jeton impair au premier joueur après le bouton ; cave 40–100 grosses blinds (débitée au `gameJoin` : déjà géré par le noyau), recave entre deux mains, départ en cours de main crédité à la fin de la main ; bouton tournant et règles du tête-à-tête ; nouvel arrivant qui attend la grosse blind ; relance minimale égale à la dernière relance ; un tapis incomplet ne rouvre pas les enchères ; pots annexes ; abattage automatique avec un **évaluateur des meilleures 5 cartes parmi 7** (testé à fond) ;
- délais : 20 s par décision (parole si possible, sinon passe) ; deux expirations de suite → mis en pause ; trois mains en pause → tapis crédité et siège libéré ; cartes privées dans `holes/{uid}` ; paquet `fairDealOrder(buildShoe(1), seed, 1)` à positions fixes (cf. `shared/games/holdem.ts`) : le tableau est fixé dès la donne ;
- **ni commission ni pouvoir** ; les tapis des bots appartiennent à la maison ; bots avec une stratégie raisonnable (force de main, cotes du pot) et déterministes sous `ctx.rng` ; rang ±1 grosse blind (surcharge `rank`) ;
- marchés : « Un As au tableau ? » et « 3 cartes ou plus d'une même couleur au tableau ? », fermés au flop ; si tout le monde se couche, réglés sur le tableau prévu ; pas de marché long ;
- documente `g`, l'état des sièges, les actions (`fold`, `check`, `call`, `allIn`, `bet`/`raise` avec `toCents`, `rebuy` avec `cents`) et les événements dans `shared/games/holdem.ts` ;
- tests : évaluateur (cas classiques, égalité de mains équivalentes), enchères (relance minimale, tapis incomplet, tête-à-tête, pots annexes, jeton impair), fast-check (**somme nulle exacte** : argent conservé wallets + tapis + pot), golden à graine fixe, vecteurs d'équité partagés avec Dart, intégration sur émulateurs (verrou !) : cave et tapis, recave, départ en cours de main, hors tour, rejeu, fermeture qui crédite les tapis.

**Flutter** (`app/lib/features/games/holdem/`) :
- écran sur `GameTableScaffold` + `StageController` : pitch des cartes, brûlage, flop/turn/river, mises poussées au pot, pots annexes, **curseur de relance** (relance minimale, tapis), cartes privées du joueur (`holes/{uid}`), abattage ;
- **Alex** (croupier·e, pronom iel / they) animé·e (CharacterPainter + bras IK) ;
- règles affichées (FR/EN, `app/l10n/parts/holdem.*.arb`), qui disent explicitement que **la graine révélée rend les cartes couchées vérifiables, donc visibles** ; vérificateur d'équité Dart ; sons (`tools/sfx/games/holdem.mjs`) ; `playable: true` ; traitement de `BUY_IN_REQUIRED` dans ton dossier si utile ;
- tests : unitaires (curseur, vérificateur), widgets FR/EN (dont 360×640), goldens clair/sombre.

Rapport final comme décrit dans PHASE_B.md (vérification de somme nulle à la place du Monte-Carlo, dernier commit poussé).
