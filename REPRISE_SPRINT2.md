# Reprise du Sprint 2 (4 jeux + méta « Rendez-vous ») — état au 2026-11-25 ~17 h

Plan approuvé par l'utilisateur : **`PLAN_SPRINT2.md`** (à la racine de ce dépôt, branche `sprint-2`).
Jeux : roulette européenne, baccarat Punto Banco, Texas hold'em NL, craps. Méta dating sim PG-13 :
croupiers + habitués + autres joueurs ; récompenses = cosmétiques + pouvoirs.

## Où en est-on
- Branche **`sprint-2`** (partie de `main` 59bdfb8), poussée sur GitHub. Tout le Sprint 2 se fait sur
  cette branche (et des branches `s2-<chantier>` en phase B), jamais directement sur `main`.
- Phase 0 faite. **Phase A0 (contrat figé) presque finie** :
  - TS : `firebase/functions/src/shared/games/{common,roulette,baccarat,holdem,craps}.ts`,
    `shared/romance.ts`, `shared/cosmetics.ts` ; `shared/types.ts` étendu (POWER_IDS = blackjack + 3
    nouveaux, BLACKJACK_POWER_IDS pour `act`, MARKET_KINDS + 12, LEDGER_TYPES + buyIn/cashOut/gift/
    reservation, ERROR_REASONS étendus, ProfileDoc.gameStats/title/rankDaily, MarketDoc.game/
    humanTradeCount, FeedEntryDoc.kind 'jackpot' + game, Callables gameJoin/gameLeave/gameAction/
    gamePoke/romance/dating + RATE_LIMITS) ; `paths.ts` (refs gameTables, romance, dating…) ;
    `equipCardStyle` vérifie déjà les cosmétiques exclusifs (COSMETIC_LOCKED) et gère `title`.
  - Dart : `app/lib/domain/games.dart` (GameId, gameOfTableId), `domain/cosmetics.dart`, enums
    PowerType/MarketKind/LedgerKind/WinKind/ServerReason étendus, switches exhaustifs complétés,
    44 nouvelles chaînes FR/EN en fin d'ARB.
  - Parité : `firebase/functions/test/golden/contract.json` (généré par `test/unit/contract.test.ts`)
    relu par `app/test/unit/contract_parity_test.dart` et `server_errors_test.dart`.
- Vérifié : backend typecheck + lint + 101 tests unitaires verts ; `flutter analyze` propre.
- **À corriger en premier (3 tests Flutter rouges)** dans `app/test/unit/dto_parsing_test.dart` :
  « FeedEntryDoc → RecentWin », « InventoryDoc → offers with POWER_PRICES_CENTS »,
  « LedgerEntryDoc: every LEDGER_TYPE, unknown type skipped » — ils figent les anciennes listes
  (ex. 'jackpot'/nouveaux pouvoirs/types de grand livre utilisés comme « inconnus »). Mettre à jour
  les attentes, puis `flutter test` doit être vert (255 passés / 3 échecs au dernier passage).
- Pas encore lancé : tests de règles et d'intégration (émulateurs). Les ports 9099/8080/5001/8088
  étaient occupés par les émulateurs de la salle de classe (lancés à 15 h 46).

## Reste à faire (ordre)
1. ~~Fin de A0~~ FAIT le 26/11 : 3 tests dto_parsing mis à jour (258 tests Flutter verts) ;
   `tools/sprint2/owners.json` + `check_owners.mjs <chantier>` (périmètre par chantier ; `--list`).
2. **A1 backend** (un agent) et **A2 Flutter** (un agent) en parallèle, chacun dans son worktree :
   - A1 : noyau `src/games/kernel/` (GameTableMachine pure + GameTableTx + interface GameModule),
     registre `src/games/registry.ts` avec modules stubs, callables `src/callables/games.ts`
     (`gameAction` : enveloppe `action: z.unknown()`, schéma du module ensuite ; `setBets` = voie
     rapide qui n'écrit que `bets/{uid}` + wallet ; `tableIdOf: () => null` sur gameAction/gamePoke),
     les 6 retouches blackjack (crochet d'échéances unique qui aiguille sur le préfixe d'id via
     `applyOverdueAny` ; contrôle « déjà assis ailleurs » commun ; tradeShares lit la bonne collection
     et incrémente humanTradeCount ; crochet d'affinité au règlement (écriture « incrément » aveugle
     dans `users/{uid}/romance/{DEALER_OF[game]}.tablePlay[day]`) ; `syncBots` sur les 2 collections),
     `rateKeyOf` dans framework.ts (limites par `op`), règles Firestore (gameTables + sous-coll.,
     datingMatches ; `users/{uid}` : le client ne modifie plus que theme/language via
     `diff().affectedKeys()` — inverser les assertions felt/cardBack/cardFace du test de règles),
     index, 120 bots (60 premiers identiques), `sim/gameSims.ts` (2 tables simulées par jeu),
     `ensureSeedV2` idempotent, runner en écoute (onSnapshot) + `fairEstimate` par module + tâches
     bots Rendez-vous (stubs), modules factices de test `coin` (tapis) et `duel` (PvP avec tapis)
     portant les tests de propriétés (conservation de l'argent, pas de solde négatif, aucune échéance
     qui débite, fermeture qui rembourse tout), sonde de charge 16 tables (tick p95 < 400 ms).
     Règles clés : une transition déclenchée par une échéance ne débite JAMAIS ; marchés fermés au
     plus tard dans la transaction qui révèle l'info, résolus dans celle qui rend l'issue certaine ;
     marchés longs seulement sur tables simulées ; points de rang anti-farming (cf. common.ts).
   - A2 : sons par groupe (`tools/sfx/games/<jeu>.mjs`, `MANIFEST.<groupe>.md`, budget 12 Mio,
     quotas), ARB en morceaux `app/l10n/parts/*.arb` + `app/tool/merge_arb.dart` (préfixes de clé,
     parité FR/EN, lancé par `tool/test.ps1`), 5 onglets Casino·Marchés·Rendez-vous·Portefeuille·
     Profil (classement dans Profil), sélecteur de jeu dans le salon, `/table/:id` → écran selon le
     préfixe, `GameTableRepository` (factice + Firebase), `GameTableState`, `StageController`
     (commandes avec begin/step/finish, à côté du DealerController qui ne bouge pas),
     `StageGeometry`, `CharacterSpec`/`CharacterPainter` + `cast.dart` (9 personnages),
     `GameTableScaffold`, boutique/marchés/profil/grand livre pilotés par registres, hub Rendez-vous
     vide. Ne PAS toucher `dealer_painters.dart`/`table_screen.dart` (phase D).
   - Puis fusion A dans `sprint-2` et suite complète (émulateurs compris, ports libres requis).
3. **B** : 5 agents en parallèle (roulette, baccarat, hold'em, craps, Rendez-vous), chacun sur sa
   branche `s2-<x>` et son worktree court (`C:\Users\<user>\s2\<x>` : limite 260 car. d'impellerc),
   périmètre de fichiers vérifié par check_owners. Détails de règles/marchés/pouvoirs : PLAN_SPRINT2.md.
4. **C** : fusions une par une (roulette, baccarat, craps, hold'em, Rendez-vous) + suite complète.
5. **D** : fusion de `main` ; tête de Lucas sur CharacterPainter (golden régénéré) ; répliques +
   jauge de cœur au blackjack ; tests AVD (un par jeu sur table privée, parcours Rendez-vous) ;
   2 clients via l'IP LAN ; `/security-review` ; mise à jour PLAN.md/REPRISE.md ; demander à
   l'utilisateur avant de fusionner dans `main`.

## Pour reprendre sur un poste neuf
```
git clone https://github.com/PierreOlivierBrillant/vingt-un-blackjack.git
cd vingt-un-blackjack
git checkout sprint-2
```
Puis `npm ci` dans `firebase/functions`, `flutter pub get` dans `app`. Prérequis et commandes :
voir REPRISE.md. Vérifier : `npm run typecheck && npm run lint && npm run test:unit` (firebase/functions),
`flutter analyze && flutter test` (app). Travailler dans un chemin court.
