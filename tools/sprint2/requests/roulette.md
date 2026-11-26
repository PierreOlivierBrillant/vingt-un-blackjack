# Chantier roulette — décisions et demandes hors périmètre

## Décisions

- **Grammaire des mises** (documentée dans `firebase/functions/src/shared/games/roulette.ts`) : `n0`..`n36`,
  `sp{a}-{b}` (a < b voisins sur le tapis, dont `sp0-1`, `sp0-2`, `sp0-3`), `st{a}` (transversale, a = 1, 4…34),
  `tr0-1-2` / `tr0-2-3`, `co{a}` (carré a, a+1, a+3, a+4), `first4`, `ln{a}` (sixain), `dozen1..3`, `col1..3`,
  `red/black/odd/even/low/high`. Une seule forme canonique par mise : 157 cases. Compatible avec les ids des
  données factices de A2 (`red`, `n17`, `dozen2`, `odd`).
- **Plafonds** (`limits.extra`) : `STAKE_TIER_LIMITS` (min 1 / 5 / 25 $, max 100 / 500 / 2 500 $ par case),
  plein ¼ du max, cheval ½, transversale et trios ¾, carré et au-delà le max ; 5 × le max par tour
  (500 / 2 500 / 12 500 $). Chaque case ≥ la mise minimale de la table (BET_OUT_OF_RANGE sinon).
- **Bouclier zéro** : exige au moins une chance simple sur le tapis (sinon POWER_NOT_APPLICABLE) ; sur 0, chaque
  chance simple du joueur rend la moitié de sa mise (montants entiers en dollars → moitiés au centime près).
- **Couleur de jetons** : `seats[i].g.color` (0..6), la première couleur libre de la table à l'arrivée.
- **Aucune action de jeu** : `actionSchema = z.never()` (toute autre action → INVALID_ARGUMENT), seulement `setBets`.
- **Durées** : mises 20 s, lancer 8 s (`step` 'spinning'), règlement 6 s. Le numéro est publié dès « Rien ne va
  plus » (`g.number` + événement `spin`) : le client calcule la bille à rebours vers ce numéro.
- **Événements** : `spin` {number, color, spinMs}, `result` {number, color}, `payout` (par siège)
  {stakedCents, returnCents, netCents, wins, shield}.
- **Marché long** « Un zéro dans les 37 prochains tours ? » : compté à partir du tour où il s'ouvre, fermé
  (plus d'échanges) après 18 tours, résolu OUI au premier zéro, NON après 37 tours ; annulé si la table ferme.
- **Compteurs de profil** : `straightUps` (pleins gagnés), `zeroShieldSaves`. `highlight: 'jackpot'` sur un plein gagnant.
- **Bots** : 8 % de tours passés ; style 'min' = chances simples / douzaines, 'flat' = chances simples + numéro
  fétiche + extérieur, 'aggressive' = annonces (voisins, tiers, orphelins, jeu zéro, voisins du numéro fétiche).
  Les annonces existent donc aussi côté serveur (`engine.ts`, pour les bots) ; le client a les siennes en Dart,
  vérifiées contre les mêmes vecteurs.
- **Vecteurs partagés** : `app/assets/fairness/roulette_vectors.json`, généré par
  `test/unit/roulette/vectors.test.ts` (graine → engagement → numéro, flux de 40 tirages, cylindre, rouges,
  157 cases, paiements, plafonds, annonces, voisins, 30 règlements). Lu par les tests Dart (pas déclaré dans
  `pubspec.yaml`, inutile : l'app recalcule, seuls les tests lisent le fichier).
- **Intégration** : `test/integration/roulette.test.ts`, en processus (`inproc.ts`) avec le VRAI module (registre
  de production), comme `games_kernel.test.ts`.
- **Monte-Carlo** : 1 000 000 de tours tirés exactement comme en production (une graine par tour,
  `seededRng(sha256("roulette-mc:i")).nextInt(37)`), variable `ROULETTE_MC_SPINS` ; ~7 s.

## Demandes hors périmètre (tests de A1 / A2 qui supposaient la roulette « pas encore disponible »)

Rendre la roulette jouable (`available: true`, `playable: true`, écran réel) casse par construction ces tests,
qui ne sont pas à moi. Je ne les ai pas modifiés. À corriger à la fusion (correctifs proposés) :

1. `firebase/functions/test/unit/kernel/kernel.test.ts` — « every game has a module file; phase-A stubs are
   unavailable and safe » : la boucle attend `available === false` pour les 4 jeux et `availableGames()` vide.
   Correctif : ne tester `available === false` que pour les jeux encore en stub
   (`const stubs = GAME_IDS.filter((g) => PRODUCTION_GAME_MODULES[g].available === false)`), et remplacer
   `expect(availableGames()).toEqual([])` par `expect(availableGames()).toEqual(GAME_IDS.filter((g) => !stubs.includes(g)))`
   (idem pour la ligne `toEqual(['baccarat'])` après l'override : `toContain('baccarat')`).
2. `firebase/functions/test/integration/games.test.ts` — « every kernel game is "not available yet" » : retirer
   `'roulette'` de la liste (ou filtrer sur les stubs).
3. `firebase/functions/test/integration/games_kernel.test.ts` — « a withdrawn game » : `overrideGameModuleForTests('roulette', null)`
   rétablit maintenant le vrai module (disponible). Utiliser `overrideGameModuleForTests('roulette', unavailableModule('roulette'))`
   (c'est ce que fait mon test `roulette.test.ts`, dernier cas).
4. `firebase/functions/test/integration/z_sim.test.ts` — « the runner advances tables… » : les tables `rl-sim-*` ne sont
   plus fermées par le runner (la roulette est disponible). Exclure `'roulette'` de la boucle `expect(status).toBe('closed')`.
