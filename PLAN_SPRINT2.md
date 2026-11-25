# Sprint 2 — Quatre nouveaux jeux + méta « Rendez-vous » (dating sim PG-13)

## Contexte

Le Sprint 1 a livré un blackjack multijoueur complet en argent fictif (Flutter + émulateurs Firebase) : moteur serveur pur, machine à états de table, bots, tables simulées, marchés LMSR, équité prouvable, croupier procédural animé, 83 sons, FR/EN, ~380 tests.

Le Sprint 2 ajoute :
- **Roulette européenne, Baccarat Punto Banco, Texas Hold'em No-Limit et Craps**, au même niveau que le blackjack ;
- un **dating simulator PG-13 en méta** avec trois sortes de personnages : croupiers, habitués et autres joueurs ;
- des récompenses **cosmétiques et pouvoirs**, sans jamais d'effet sur le tirage.

**« Même niveau »**, pour chaque jeu :
- moteur pur testé : propriétés, golden, Monte-Carlo de l'avantage maison ;
- tables partagées : matchmaking, file d'attente, bots qui cèdent leur siège, tables privées à code, tables simulées ;
- équité prouvable vérifiable dans l'app ;
- marchés spectateurs ;
- croupier animé dessiné en code ;
- sons, FR/EN, règles affichées, historique, mode spectateur, pubs ;
- tests unitaires, widgets, goldens et d'intégration.

**Ampleur** : environ 25 000 lignes, autant que tout le Sprint 1. C'est un travail de plusieurs heures, avec 5 implémenteurs en parallèle.

**Précaution** : deux autres sessions modifient en ce moment ce même dossier (`app_flow_test.dart`, `dealer_painters.dart`, `router.dart`, `table_screen.dart`…).
- Le Sprint 2 se fait dans des **worktrees git séparés**, sur la branche `sprint-2` partie de `main` (71dc82b), dans des chemins courts (`C:\Users\po.brillant\s2\<nom>`, à cause de la limite de 260 caractères d'`impellerc`).
- Les fichiers que ces sessions touchent n'entrent dans le Sprint 2 qu'à la phase D, après fusion de `main`.
- Les tests qui utilisent les émulateurs (ports 9099/8080/5001, partagés) passent un à la fois, seulement quand les ports sont libres.
- Poste DeepFreeze : chaque branche est poussée sur le dépôt GitHub privé à chaque étape verte, comme au Sprint 1. Rien n'est fusionné dans `main` sans ton accord.

## Règles des jeux (fixes, affichées dans l'app)

**Équité** : une graine par coup, avec engagement SHA-256 publié avant les mises et graine révélée après. Un seul et même générateur, `seededRng(graine)` (`engine/rng.ts`), déjà porté en Dart et testé à l'identique : échantillonnage par rejet, aucun biais. Des vecteurs de test JSON partagés valident le vérificateur Dart de chaque jeu.

### Roulette européenne — 7 places, une couleur de jetons par joueur
- 37 cases, ordre réel du cylindre européen. Tirage : `seededRng(graine).nextInt(37)`.
- Paiements :

  | Mise | Paie |
  |---|---|
  | Plein | 35:1 |
  | Cheval | 17:1 |
  | Transversale, trios 0-1-2 et 0-2-3 | 11:1 |
  | Carré, premier quatre | 8:1 |
  | Sixain | 5:1 |
  | Douzaine, colonne | 2:1 |
  | Chances simples | 1:1 |

  Pas de « partage » par défaut (avantage maison 2,70 %).
- Annonces (voisins du zéro, tiers, orphelins, jeu zéro, voisins d'un numéro), Annuler, Effacer, Rejouer, Doubler : tout est calculé par le client, qui envoie la carte complète de ses mises.
- Plafonds par type de mise et par tour.
- Déroulé : 20 s de mises → « Rien ne va plus » (tirage dans cette transaction) → lancer d'environ 8 s → paiement → tour suivant.

### Baccarat Punto Banco — 7 places, sabot de 8 jeux
- 416 cartes, coupe à 16 cartes de la fin. Brûlage selon la première carte, inclus dans la même preuve d'équité (`fairDealOrder(…, 8)`).
- Tableau de tirage officiel : la règle de la 3e carte de la Banque contre 0–9.
- Paiements :

  | Mise | Paie |
  |---|---|
  | Joueur | 1:1 |
  | Banquier | 0,95:1 (exact en centimes) |
  | Égalité | 8:1 (Joueur et Banquier rendus) |
  | Paire Joueur, Paire Banquier | 11:1 |

- *Bead Plate* et *Big Road* (*Big Eye Boy* en bonus). Squeeze animé côté client, sans aucune information secrète.

### Texas Hold'em No-Limit — 6 places, joueurs contre joueurs
- Blinds par palier : 1/2, 5/10, 25/50 $. Unité : 1 $ ; le jeton impair (1 $) va au premier joueur après le bouton.
- Cave de 40 à 100 grosses blinds, **débitée au `gameJoin`**. Le tapis est crédité quand on part ; un départ en cours de main est crédité à la fin de la main ; recave possible entre deux mains.
- Règles :
  - bouton tournant et règles du tête-à-tête ;
  - nouvel arrivant qui attend la grosse blind ;
  - relance minimale égale à la dernière relance ;
  - un tapis incomplet ne rouvre pas les enchères ;
  - pots annexes ;
  - abattage automatique, évaluateur des meilleures 5 cartes parmi 7.
- Délais : 20 s par décision (parole si possible, sinon passe). Deux expirations de suite → mis en pause ; trois mains en pause → tapis crédité et siège libéré.
- Cartes privées dans `holes/{uid}`, lisibles par ce seul joueur.
- Paquet : `fairDealOrder(paquet, graine, 1)` avec positions fixes. Le tableau est donc fixé dès la donne.
- **Ni commission ni pouvoir.** Les tapis des bots appartiennent à la maison.
- **Choix assumé, affiché dans les règles** : la graine révélée rend les cartes couchées vérifiables, donc visibles.

### Craps — 8 places, lanceur tournant
- Ligne de passe et Ne passe pas (12 barré), Come et Don't Come, cotes 3-4-5× (vraies cotes) et cotes « lay ».
- Place : 4/10 à 9:5, 5/9 à 7:5, 6/8 à 7:6.
- Field : 2 payé 2:1, 12 payé 3:1.
- Propositions : Any 7 4:1, Any Craps 7:1, Hardways 7:1 ou 9:1, Yo 15:1, 2 et 12 30:1, 3 15:1.
- Mises en dollars entiers. Pour que tout tombe juste au centime, place 6/8 et lay 5/9 ou 6/8 se misent **par multiples de 3 $** (message clair sinon).
- Places « off » au come-out ; mises contractuelles (ligne de passe après le point) non retirables.
- Chaque lancer est un coup : sa graine, son historique, `nextInt(6)+1` deux fois.
- Le lanceur doit miser Pass ou Don't Pass. Il lance d'un geste, ou automatiquement après 15 s. Le dé passe au joueur suivant après un *seven-out*.

### Pouvoirs ajoutés (boutique regroupée par jeu, 1 par coup, validés par le serveur)
- **Bouclier zéro** (roulette) : la « partage » s'applique à tes chances simples pour un tour.
- **Commission offerte** (baccarat) : pas de 5 % sur un gain Banquier, pour un coup.
- **Filet de sécurité** (craps) : ta ligne de passe est remboursée en cas de *seven-out*, du come-out jusqu'à sa résolution.

### Marchés spectateurs
Même LMSR, même règle « pas sur sa propre table ». Un marché ferme au plus tard dans la transaction qui rend publique une information utile, et se résout dans la transaction qui rend l'issue certaine.

| Jeu | Par coup | Longs (tables simulées seulement) |
|---|---|---|
| Roulette | « Rouge ? », « Zéro ? », « 3e douzaine ? » | « Un zéro dans les 37 prochains tours ? » |
| Baccarat | « Le Banquier gagne ? », « Égalité ? », « Une paire ? » | « Le Banquier gagne au moins 46 % du sabot ? » |
| Hold'em | « Un As au tableau ? », « 3 cartes ou plus d'une même couleur ? » | — |
| Craps | « Sept au prochain lancer ? » | « Le lanceur fait son point ? » |

- Au hold'em, seuls des marchés impossibles à manipuler par les joueurs ; ils ferment au flop. Si tout le monde se couche, ils se règlent sur le tableau prévu.
- Au craps, le marché du point dure le temps du point.

### Classement
- Échelle commune : gros gain +15, gain +10, perte −4.
- Une manche ne compte que si le net atteint au moins la moitié de la mise (gain) ou au plus moins la moitié (perte). Au hold'em : ±1 grosse blind.
- Plafond quotidien par jeu.
- But : empêcher de farmer des points en couvrant les 36 numéros.
- Statistiques par jeu dans le profil.

## Méta « Rendez-vous » (dating sim PG-13)

**Personnages** : tous adultes (24 à 38 ans), écrits PG-13. On flirte, on rit, on se confie, on se tient la main ; au plus un baiser à la finale, suivi d'un fondu au noir. On peut séduire n'importe quel personnage, quel que soit le profil du joueur.

| | Personnages |
|---|---|
| Croupiers | **Lucas** (blackjack, le croupier actuel), **Camille** (roulette), **Inès** (baccarat), **Alex**, iel (hold'em), **Marco** (craps) |
| Habitués | **Jade** (mixologue), **Théo** (pianiste), **Nora** (magicienne), **Hugo** (concierge VIP) |
| Autres joueurs | Humains volontaires et ~24 bots dotés d'un profil, avec un badge « Bot » visible |

**Boucle de jeu (tout autoritaire côté serveur)** :
- **Affinité** de 0 à 300, en 6 paliers : Inconnu·e → Connaissance → Ami·e → Complice → Flirt → Coup de cœur.
- **Discussion** : une scène de visual novel par jour et par personnage. Le joueur la joue localement, puis le serveur **rejoue le chemin des choix** depuis le JSON de l'histoire et vérifie les conditions. Chaque choix vaut de −5 à +10.
- **Jouer à la table** d'un croupier : +1 par coup joué à la mise minimale ou plus, plafonné à +10 par jour. Ce qui compte, c'est le temps de jeu, **pas le montant misé**.
  - Le règlement du coup fait une écriture « incrément » sans lecture, donc aucun coût sur la table.
  - Ces coups sont crédités à l'ouverture du hub.
- **Cadeaux** : 12 cadeaux en argent fictif, et des goûts propres à chaque personnage (+15, +8, +3 ou −5), dans la limite de 3 par jour.
- **Rendez-vous** aux paliers 3, 4 et 5, dans des lieux dessinés en code. La réservation n'est débitée que si le rendez-vous va jusqu'au bout.
- **Contenu** : par personnage, 4 discussions, 2 rendez-vous et 1 finale, plus une réserve de petites conversations. Soit environ 63 scènes FR/EN.
- **Récompenses à chaque palier**, accordées une seule fois même si l'affinité redescend : dos de carte, tapis ou titre exclusifs, et pouvoirs gratuits.
- **Galerie « Souvenirs »** pour rejouer les scènes déjà vues.
- **Méta en jeu** : à sa table, le croupier t'appelle par ton pseudo, a des répliques propres à votre palier, réagit à tes coups, et une jauge de cœur s'affiche.

**Rencontres entre joueurs, conçues pour une salle de classe** :
- **Désactivées côté serveur par défaut** (`config/features.dating`). Elles s'activent avec `start_classroom.ps1 -EnableDating`, parce que le KYC simulé accepte n'importe quelle date de naissance.
- **Sur inscription seulement**, réservées aux KYC vérifiés.
- **Fiche** : jeu préféré, 3 centres d'intérêt pris dans une liste, et « je cherche » (amitié, flirt ou les deux).
- **Découverte** par une fonction serveur, qui seule peut filtrer les blocages dans les deux sens.
- **« Clin d'œil »** : 10 par jour ; quand c'est réciproque, c'est un match.
- **Aucun texte libre** : environ 40 répliques PG-13 prédéfinies, avec des réponses autorisées, et des réactions.
- **Offrir un verre.** **Inviter à sa table privée** : le serveur joint lui-même le code, le client n'envoie aucun texte.
- **Affinité de duo** (messages, plafonnés par jour, et cadeaux), qui débloque des cosmétiques « duo ».
- **Bloquer** est immédiat et masque les deux personnes l'une à l'autre ; on peut aussi annuler un match.
- **Les bots** acceptent les clins d'œil et répondent avec un délai, via `sim_runner`.

**Cosmétiques verrouillables (correctif de sécurité au passage)** :
- Aujourd'hui, le client peut écrire librement `cardBack` et `felt` dans `users/{uid}`. Les règles ne lui laisseront plus modifier que `theme` et `language` (`diff().affectedKeys()`).
- Les styles de carte passent tous par `equipCardStyle`, qui vérifie la gratuité ou `users/{uid}/unlocks/{id}`.
- Les titres sont publics, écrits par le serveur dans `profiles/{uid}.title`.

## Architecture backend (`firebase/functions`)

**Nouvelle collection `gameTables/{id}`** :
- sous-collections `private/state` (lecture : personne), `bets/{uid}` (connectés), `holes/{uid}` (le joueur), `rounds/{n}` (connectés) ;
- **préfixe d'identifiant** `rl-`, `bc-`, `ho-`, `cr-` : le jeu se déduit de l'id partout (crochet d'échéances, `tradeShares`, position du profil, « regarder sa table », route Flutter), sans lecture supplémentaire ;
- **le blackjack reste dans `tables`**, avec six retouches seulement :
  1. un crochet d'échéances unique qui aiguille selon le préfixe ;
  2. un contrôle « déjà assis ailleurs » commun aux deux jeux ;
  3. `tradeShares` qui lit la bonne collection ;
  4. le crochet d'affinité au règlement ;
  5. `game` dans les marchés ;
  6. `syncBots` sur les deux collections.

**Noyau générique** (`src/games/kernel/`) :
- **`GameTableMachine`, pure et sans horloge**, comme `TableMachine`. Elle gère les sièges, la file, les bots qui cèdent leur place, la fermeture et les remboursements, les tours manqués, les événements (remis à zéro à chaque coup, plafonnés à 200), l'engagement et la révélation, les effets (débit/crédit, mises, secrets, historique, règlement, marchés, position, fil d'actualité) et les points de rang.
- **`GameTableTx`** applique les effets dans une seule transaction (modèle : `TableTx.commit`). Un crédit vers un wallet absent est journalisé, sans lever d'erreur.
- **Interface `GameModule`** par jeu : `limits`, `init`, `openRound`, `act`, `onDeadline`, `validateBets`, `closeBetting`, `seatClear`, `onLeaving`, `bot`, `power`, `rank`, `stats`, `fairEstimate`. Le registre `src/games/registry.ts` est complet dès la phase A.
- **Règles de solidité** :
  - **une transition déclenchée par une échéance ne débite jamais** : seule l'action d'un joueur débite, sinon un solde insuffisant gèlerait la table ;
  - roulette, baccarat et craps rangent les mises dans `bets/{uid}` : la mise n'écrit que ce document et le wallet, pas le document de table, donc pas de conflit entre 7 joueurs ;
  - la fermeture des mises relit tous les `bets/*` dans sa transaction.
- **Callables** :
  - `gameJoin`, `gameLeave`, `gameAction` (enveloppe stricte, action validée par le schéma zod du module), `gamePoke` ;
  - `romance{op}` et `dating{op}`, avec une limite de débit par opération : peu de fonctions, car chaque fonction coûte de la mémoire à l'émulateur.
- **Profils** :
  - `gameStats` par jeu, `title`, `rankDaily` ;
  - un seul `currentTableId`, valable pour tous les jeux ;
  - nouveaux types de grand livre : `buyIn`, `cashOut`, `gift`, `reservation`.
- **Bots et simulation** :
  - 120 bots au lieu de 60 : les 60 premiers restent identiques, 48 nouveaux sièges pour les tables simulées des jeux, 12 bots libres de plus ;
  - 2 tables simulées par jeu, et un nombre de tables réglable pour la classe ;
  - `ensureSeedV2` idempotent ;
  - `sim_runner` écoute les tables ouvertes au lieu de les sonder (environ 32 lectures par seconde en moins), estime les prix des marchés par module, et exécute les tâches de fond des bots de Rendez-vous.

## Architecture Flutter (`app`)

**Navigation et salon** :
- 5 onglets : **Casino · Marchés · Rendez-vous · Portefeuille · Profil**. Le classement passe dans Profil, avec un raccourci dans le salon.
- Le salon gagne un sélecteur de jeu animé. `/table/:id` choisit l'écran du jeu d'après le préfixe de l'identifiant.

**Socle commun, construit à côté du code du blackjack** (le blackjack ne migre pas pendant ce sprint) :
- **`StageController`** : file d'animation déterministe, `advance(dt)`, avance rapide, cues, minuterie de tour, clignement, respiration, bras IK. Chaque commande porte son propre `begin`, `step` et `finish`.
- `StageGeometry` propre à chaque jeu ; `GameTableRepository` (factice et Firebase) ; `GameTableState`.
- **`GameTableScaffold`** : sièges, minuterie, spectateur, pubs, règles, historique, feuille d'équité, célébrations, et un emplacement pour la méta du croupier.
- Réutilisés tels quels : `ik.dart`, `CardFacePainter`, `chips.dart`, `SeededRng`, `Live`, `CallableClient`, `FirebaseContext`, `wire.dart`, `AmbienceScope`, `SoundGovernor`, `pumpScreen`, le harnais golden.

**Personnages** :
- `CharacterSpec` / `CharacterPainter` (`lib/core/characters/`) : 8 coiffures, tenues, accessoires, 8 expressions, clignement, respiration ; `cast.dart` décrit les 9 personnages.
- Ce même peintre dessine les bustes du visual novel, les médaillons et les têtes des croupiers.

**Animations par jeu** (`lib/features/games/<jeu>/`) :
- Roulette : cylindre en rotation, bille **calculée à rebours pour tomber dans la case tirée**, tapis tactile, racetrack, dolly, râteau, numéros chauds et froids.
- Baccarat : sabot, 3e carte posée en travers, squeeze, tableaux de tendance.
- Hold'em : pitch des cartes, brûlage, flop/turn/river, mises poussées au pot, pots annexes, curseur de relance.
- Craps : *stickman* et sa canne, dés qui rebondissent sur le mur à pyramides puis se posent sur le résultat, palet ON/OFF, geste de lancer.

**Rendez-vous** (`lib/features/romance/`) :
- moteur de visual novel (texte animé, choix, expressions, décors procéduraux), hub, boutique de cadeaux, Souvenirs ;
- Rencontres : découverte, matchs, messagerie à répliques prédéfinies.
- Source unique de l'histoire : `firebase/functions/src/romance/story/*.json`, copiée dans `app/assets/story/` par `tools/sync_story.mjs`. Un test de parité SHA-256 de chaque côté, plus des tests de contenu : schéma, graphe sans impasse, FR et EN complets, longueurs, liste de mots interdits.

**À généraliser** :
- les énumérations exhaustives `PowerType`, `MarketKind`, `LedgerKind`, `WinKind`, `ServerReason` ;
- `Market.fromDoc`, qui ne doit plus planter ni masquer un type de marché inconnu ;
- `LiveTable.game` ;
- le médaillon « 21 » des dos de carte et l'enseigne « VINGT·UN » deviennent des paramètres.

**Sons** : environ 45 nouveaux effets, définis dans `tools/sfx/games/<jeu>.mjs`, un `MANIFEST.<groupe>.md` par jeu. Le budget passe de 8 à **12 Mio**, avec un quota par groupe ; les boucles sont en mono 22 kHz.

## Organisation du travail (sous-agents Opus, ce que je fais moi-même est indiqué)

Chaque implémenteur ne touche que ses fichiers ; un script `tools/sprint2/check_owners.mjs` refuse tout fichier hors de son périmètre.

**Fichiers partagés, rendus sans conflit** :
- unions de `types.ts` alimentées par des listes propres à chaque jeu (`shared/games/<jeu>.ts`) ;
- textes FR/EN en morceaux `app/l10n/parts/<jeu>.{fr,en}.arb`, fusionnés par `app/tool/merge_arb.dart` : préfixe de clé par jeu et parité FR/EN vérifiés, l'ARB fusionné étant traité comme un fichier généré ;
- sons par groupe ;
- registres de jeux côté serveur (`registry.ts`) et côté app (`kGames`).

**Phases** :
- **A0, contrat figé (moi)** : toutes les nouvelles valeurs d'énumération et toutes les signatures d'appels des 5 chantiers, côté TypeScript et côté Dart.
- **A1, backend, et A2, Flutter, en parallèle** :
  - A1 : noyau, testé avec deux modules factices (`coin` pour les mises sur tapis, `duel` pour le joueur contre joueur avec tapis) qui portent les tests de propriétés (conservation de l'argent, aucun solde négatif, aucune échéance qui débite, fermeture qui rembourse tout) ; callables ; règles ; index ; cosmétiques ; simulation ; sonde de charge avec 16 tables simulées ;
  - A2 : sons par groupe, fusion des ARB, onglets, registres, `StageController`, `CharacterPainter`, `GameTableScaffold`, et la boutique, les marchés, le profil et le grand livre pilotés par registre.
  - Je fusionne et je fais tourner toute la suite une fois, émulateurs compris.
- **B, 5 implémenteurs en parallèle** : roulette, baccarat, hold'em, craps, Rendez-vous. Chacun livre son moteur, son module, ses bots, ses marchés, son équité, son écran, ses animations, ses sons, ses textes et ses tests, et tient au vert ses tests sans émulateur.
- **C, fusions une par une (moi)** : roulette, puis baccarat, craps, hold'em, Rendez-vous. Après chaque fusion : régénération des fichiers dérivés et suite complète, émulateurs compris.
- **D, finitions (moi)** :
  - fusion de `main`, avec le travail des autres sessions ;
  - la tête de Lucas passe sur `CharacterPainter` (golden régénéré) ;
  - ses répliques et la jauge de cœur au blackjack ;
  - test de la salle de classe via l'IP LAN avec 2 clients ;
  - `/security-review` ;
  - mise à jour de `PLAN.md` et `REPRISE.md`.

## Vérification

- **Backend** : `tools\test_all.ps1` (typecheck, lint, tests unitaires, règles, intégration). Pour chaque jeu :
  - moteur : chaque règle et chaque paiement, exacts au centime ;
  - propriétés (fast-check) : conservation de l'argent, aucun état sans action légale ;
  - transcriptions golden à graine fixe ;
  - Monte-Carlo : roulette 2,70 %, baccarat Banquier 1,06 % et Joueur 1,24 %, craps ligne de passe 1,41 %, hold'em à somme nulle exacte ;
  - vecteurs d'équité partagés avec Dart ;
  - intégration sur émulateurs : double dépense, rejeu, hors tour, mise interdite, pouvoir non possédé, pari sur sa propre table, cave et tapis au hold'em, fermeture qui rembourse.
- **Rendez-vous** : graphe et parité de l'histoire, plafonds quotidiens, idempotence des récompenses, refus d'un chemin de choix truqué, rencontres (inscription obligatoire, blocage dans les deux sens, aucun texte libre accepté, interrupteur désactivé), et règles Firestore en positif et en négatif, y compris le verrou des cosmétiques.
- **Flutter** : `app\tool\test.ps1` (analyze, unitaires, widgets FR/EN, goldens clair/sombre de chaque nouvel écran et d'une image de chaque croupier, sons et quotas).
- **AVD** (`emulator-5554`, jamais le téléphone physique) :
  - un test d'intégration par jeu sur une table privée créée par le test, pour qu'il soit déterministe ;
  - un parcours Rendez-vous : scène, cadeau, palier, récompense équipée ;
  - captures d'écran de chaque écran ;
  - simulation lancée 10 minutes avec 16 tables, sans erreur, avec un tick p95 sous 400 ms ;
  - 2 clients sur la même table via l'IP LAN.
- **Fin** : tout ce qui n'aura pas pu être vérifié (par exemple l'écoute des sons) sera signalé explicitement.

## Limites assumées

- Le blackjack n'est pas migré sur le nouveau noyau (piste pour un Sprint 3).
- Hold'em : la collusion entre joueurs d'une même table n'est pas détectée.
- Le KYC est simulé : c'est pourquoi les rencontres entre joueurs sont désactivées par défaut.
- Capacité des émulateurs sur un seul poste : le nombre de tables simulées est réglable.
