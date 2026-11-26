Tu es l'implémenteur **roulette** de la phase B du Sprint 2 du projet « Vingt-Un » (casino en argent fictif : app Flutter + émulateurs Firebase, Cloud Functions TypeScript). Le plan est approuvé par l'utilisateur ; aucune question ne lui sera posée : décide et documente.

**Où travailler** : worktree `C:\Users\po.brillant\s2\rl` (Git Bash `/c/Users/po.brillant/s2/rl`), branche **`s2-roulette`** (partie de `sprint-2` @ 4878c35). Nom du chantier pour check_owners : `roulette`. Windows 11 ; commence par `npm ci` dans `firebase/functions` et `flutter pub get` dans `app`. Quatre autres implémenteurs (baccarat, hold'em, craps, Rendez-vous) travaillent en même temps dans d'autres worktrees.

**Lis d'abord `tools/sprint2/PHASE_B.md`** et suis-le à la lettre (lectures, périmètre, verrou des émulateurs, étapes vertes, push, rapport final). Puis `PLAN_SPRINT2.md` § « Roulette européenne », l'en-tête de `firebase/functions/src/games/roulette/module.ts` et celui de `app/lib/features/games/roulette/roulette_game.dart`.

## Ce que tu livres (roulette « au même niveau que le blackjack »)
**Backend** (`src/games/roulette/`) :
- moteur pur : 37 cases dans l'ordre réel du cylindre européen ; grammaire des identifiants de mise (à documenter dans `shared/games/roulette.ts` avec `g`, l'état des sièges et les événements) ; tous les paiements exacts au centime (plein 35:1, cheval 17:1, transversale et trios 0-1-2/0-2-3 11:1, carré et premier quatre 8:1, sixain 5:1, douzaine/colonne 2:1, chances simples 1:1) ; pas de « partage » par défaut, sauf pouvoir **Bouclier zéro** (la partage s'applique aux chances simples du joueur pour ce tour) ; plafonds par type de mise et par tour ;
- module complet (`rouletteModule`, `available: true`, `money: 'board'`) suivant l'en-tête du stub : 20 s de mises → « Rien ne va plus » (tirage `ctx.fairRng().nextInt(37)` dans cette transaction) → lancer ~8 s → paiement → tour suivant ; bots ; `fairEstimate` ; marchés par tour « Rouge ? », « Zéro ? », « 3e douzaine ? » (fermés et résolus quand le numéro devient public) et marché long « Un zéro dans les 37 prochains tours ? » (tables simulées seulement) ; `highlight: 'jackpot'` sur un plein gagnant ; compteurs de profil ;
- annonces (voisins du zéro, tiers, orphelins, jeu zéro, voisins d'un numéro), Annuler, Effacer, Rejouer, Doubler : calculés par le CLIENT, qui envoie la carte complète ; le serveur valide la carte ;
- tests : moteur (chaque mise, chaque paiement), fast-check (conservation de l'argent, validation des cartes), transcription golden à graine fixe (`test/golden/roulette*`), **Monte-Carlo de l'avantage maison 2,70 %**, vecteurs d'équité JSON partagés avec Dart (graine → numéro), intégration sur émulateurs (verrou !) : double dépense, rejeu, mise interdite, pouvoir non possédé, pari sur sa propre table, fermeture qui rembourse.

**Flutter** (`app/lib/features/games/roulette/`) :
- écran sur `GameTableScaffold` + `StageController` : cylindre en rotation, bille **calculée à rebours pour tomber dans la case tirée**, tapis tactile (une couleur de jetons par joueur, 7 places), racetrack et annonces, dolly, râteau, numéros chauds/froids, historique ;
- la croupière **Camille** animée (CharacterPainter + bras IK) ;
- vérificateur d'équité Dart (relit les vecteurs du backend), règles affichées, textes FR/EN (`app/l10n/parts/roulette.*.arb`), sons (`tools/sfx/games/roulette.mjs`, quota du groupe), `playable: true` ;
- tests : unitaires (géométrie de la bille, cartes de mises/annonces, vérificateur), widgets FR/EN (dont 360×640), goldens clair/sombre de l'écran.

Rapport final comme décrit dans PHASE_B.md (Monte-Carlo mesuré, dernier commit poussé).
