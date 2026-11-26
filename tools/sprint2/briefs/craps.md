Tu es l'implémenteur **craps** de la phase B du Sprint 2 du projet « Vingt-Un » (casino en argent fictif : app Flutter + émulateurs Firebase, Cloud Functions TypeScript). Le plan est approuvé par l'utilisateur ; aucune question ne lui sera posée : décide et documente.

**Où travailler** : worktree `C:\Users\po.brillant\s2\cr` (Git Bash `/c/Users/po.brillant/s2/cr`), branche **`s2-craps`** (partie de `sprint-2` @ 4878c35). Nom du chantier pour check_owners : `craps`. Windows 11 ; commence par `npm ci` dans `firebase/functions` et `flutter pub get` dans `app`. Quatre autres implémenteurs (roulette, baccarat, hold'em, Rendez-vous) travaillent en même temps dans d'autres worktrees.

**Lis d'abord `tools/sprint2/PHASE_B.md`** et suis-le à la lettre (lectures, périmètre, verrou des émulateurs, étapes vertes, push, rapport final). Puis `PLAN_SPRINT2.md` § « Craps », l'en-tête de `firebase/functions/src/games/craps/module.ts` et celui de `app/lib/features/games/craps/craps_game.dart`. Le noyau gère les mises qui restent sur le tapis d'un lancer à l'autre (`carry` au règlement, voir l'en-tête de `kernel/module.ts`). Raisons existantes : `NOT_SHOOTER`, `MUST_BET_LINE`.

## Ce que tu livres (craps « au même niveau que le blackjack »)
**Backend** (`src/games/craps/`) :
- moteur pur 8 places, lanceur tournant : Ligne de passe et Ne passe pas (12 barré), Come et Don't Come, cotes 3-4-5× (vraies cotes) et cotes « lay » ; Place 4/10 à 9:5, 5/9 à 7:5, 6/8 à 7:6 ; Field (2 payé 2:1, 12 payé 3:1) ; propositions Any 7 4:1, Any Craps 7:1, Hardways 7:1 ou 9:1, Yo 15:1, 2 et 12 30:1, 3 15:1 ;
- mises en dollars entiers, tout juste au centime : place 6/8 et lay 5/9 ou 6/8 **par multiples de 3 $** (sinon `BET_INCREMENT`, message clair) ; places « off » au come-out ; mises contractuelles (ligne de passe après le point, etc.) non retirables (`BET_NOT_REMOVABLE`) ;
- chaque lancer est un coup (sa graine, son historique, `nextInt(6)+1` deux fois) ; le lanceur doit miser Pass ou Don't Pass (`MUST_BET_LINE`), lance d'un geste (action `roll`, `NOT_SHOOTER` sinon) ou automatiquement après 15 s ; le dé passe au joueur suivant après un *seven-out* ;
- pouvoir **Filet de sécurité** : ta ligne de passe est remboursée en cas de *seven-out*, du come-out jusqu'à sa résolution ;
- module complet (`crapsModule`, `available: true`, `money: 'board'`) : bots (dont un lanceur bot), `fairEstimate`, marchés « Sept au prochain lancer ? » (par lancer) et « Le lanceur fait son point ? » (dure le temps du point ; tables simulées seulement), compteurs de profil, `highlight` ; documente la grammaire des identifiants de mise, `g` (point, palet ON/OFF, lanceur, derniers dés), l'état des sièges, les actions et les événements dans `shared/games/craps.ts` ;
- tests : moteur (chaque mise, paiement, résolution au centime), fast-check (conservation de l'argent, aucune mise contractuelle retirée), golden à graine fixe, **Monte-Carlo de la ligne de passe 1,41 %** (Don't Pass aussi si tu veux), vecteurs d'équité JSON partagés avec Dart, intégration sur émulateurs (verrou !) : double dépense, rejeu, hors tour (NOT_SHOOTER), mise interdite, pouvoir non possédé, pari sur sa propre table, fermeture qui rembourse le tapis reporté.

**Flutter** (`app/lib/features/games/craps/`) :
- écran sur `GameTableScaffold` + `StageController` : tapis de craps tactile (8 places), *stickman* et sa canne, dés qui **rebondissent sur le mur à pyramides puis se posent sur le résultat tiré**, palet ON/OFF, **geste de lancer** pour le lanceur ;
- le croupier **Marco** animé (CharacterPainter + bras IK) ;
- vérificateur d'équité Dart, règles affichées, textes FR/EN (`app/l10n/parts/craps.*.arb`), sons (`tools/sfx/games/craps.mjs`), `playable: true` ;
- tests : unitaires (trajectoire des dés déterministe, tapis, vérificateur), widgets FR/EN (dont 360×640), goldens clair/sombre.

Rapport final comme décrit dans PHASE_B.md (Monte-Carlo mesuré, dernier commit poussé).
