Tu es l'implémenteur **baccarat** de la phase B du Sprint 2 du projet « Vingt-Un » (casino en argent fictif : app Flutter + émulateurs Firebase, Cloud Functions TypeScript). Le plan est approuvé par l'utilisateur ; aucune question ne lui sera posée : décide et documente.

**Où travailler** : worktree `C:\Users\po.brillant\s2\bc` (Git Bash `/c/Users/po.brillant/s2/bc`), branche **`s2-baccarat`** (partie de `sprint-2` @ 4878c35). Nom du chantier pour check_owners : `baccarat`. Windows 11 ; commence par `npm ci` dans `firebase/functions` et `flutter pub get` dans `app`. Quatre autres implémenteurs (roulette, hold'em, craps, Rendez-vous) travaillent en même temps dans d'autres worktrees.

**Lis d'abord `tools/sprint2/PHASE_B.md`** et suis-le à la lettre (lectures, périmètre, verrou des émulateurs, étapes vertes, push, rapport final). Puis `PLAN_SPRINT2.md` § « Baccarat Punto Banco », l'en-tête de `firebase/functions/src/games/baccarat/module.ts` et celui de `app/lib/features/games/baccarat/baccarat_game.dart`. Cartes et équité du blackjack : `src/engine/{cards,fair,rng}.ts`.

## Ce que tu livres (baccarat « au même niveau que le blackjack »)
**Backend** (`src/games/baccarat/`) :
- moteur pur : sabot de 8 jeux (416 cartes), coupe à 16 cartes de la fin, brûlage selon la première carte inclus dans la même preuve d'équité (`fairDealOrder(…, 8)`, `remainingBefore`/`dealt`/`decks` dans `rounds/{n}`) ; tableau de tirage officiel (règle de la 3e carte de la Banque contre 0–9) ; paiements Joueur 1:1, Banquier 0,95:1 exact au centime, Égalité 8:1 (Joueur et Banquier rendus), Paire Joueur / Paire Banquier 11:1 ; pouvoir **Commission offerte** (pas de 5 % sur un gain Banquier, pour un coup) ;
- module complet (`baccaratModule`, `available: true`, `money: 'board'`) : mises → donne en une transaction (cartes et événements pour l'animation) → règlement ; bots ; `fairEstimate` ; marchés par coup « Le Banquier gagne ? », « Égalité ? », « Une paire ? » (fermés au plus tard quand les cartes deviennent publiques, résolus quand l'issue est certaine) et marché long « Le Banquier gagne au moins 46 % du sabot ? » (tables simulées seulement) ; données des tableaux de tendance (Bead Plate, Big Road, Big Eye Boy en bonus) dans `g` ou l'historique, documentées dans `shared/games/baccarat.ts` ; compteurs de profil, `highlight` ;
- tests : moteur (tableau de tirage complet, chaque paiement), fast-check (conservation de l'argent), golden à graine fixe, **Monte-Carlo : Banquier 1,06 %, Joueur 1,24 %** (et Égalité si tu veux), vecteurs d'équité JSON partagés avec Dart (graine + sabot → cartes), intégration sur émulateurs (verrou !) : double dépense, rejeu, mise interdite, pouvoir non possédé, pari sur sa propre table, fermeture qui rembourse.

**Flutter** (`app/lib/features/games/baccarat/`) :
- écran sur `GameTableScaffold` + `StageController` : sabot, cartes données, 3e carte posée en travers, **squeeze animé** côté client (sans information secrète : uniquement des cartes déjà publiques), tableaux de tendance, 7 places ;
- la croupière **Inès** animée (CharacterPainter + bras IK) ; réutilise `CardFacePainter` et les jetons ;
- vérificateur d'équité Dart, règles affichées, textes FR/EN (`app/l10n/parts/baccarat.*.arb`), sons (`tools/sfx/games/baccarat.mjs`), `playable: true` ;
- tests : unitaires (Big Road/Bead Plate, vérificateur), widgets FR/EN (dont 360×640), goldens clair/sombre.

Rapport final comme décrit dans PHASE_B.md (Monte-Carlo mesuré, dernier commit poussé).
