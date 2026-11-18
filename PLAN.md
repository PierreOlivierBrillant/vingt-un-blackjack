# Plan — Application mobile Blackjack (Flutter + émulateurs Firebase)

## Contexte

Requis tirés du tableau blanc : classement, connexion, création de compte, vérification d'identité simulée, matchmaking, amis, mode clair/sombre, Flutter, cartes personnalisables, wallet en argent **fictif** (ajouter/retirer), jeu très animé, pouvoirs à dépenser (ex. premier split gratuit), spectateurs qui parient sur le résultat, fausses pubs.

Décisions confirmées : tables partagées (≤ 5 joueurs contre le croupier, bots en complément) · boutique de ~5 pouvoirs · interface français (défaut) + anglais · argent 100 % fictif.

Contraintes : UI inspirée de stake.com (sans reprendre nom/logo), paris spectateurs inspirés de Polymarket, animation réaliste du croupier, sécurité stricte, beaucoup de tests + tests de régression, données fictives réalistes. **Implémentation par Opus 5.5** : si la session est encore sur Fable à l'approbation, tout le code est écrit par des sous-agents `model: opus`, phase par phase ; l'orchestrateur ne fait que relire et vérifier.

Environnement vérifié : Flutter 3.44.6 / Dart 3.12.2, Node 24, Java 21, Firebase CLI 15.25, SDK Android `C:\Android\Sdk`, AVD `android-36.1-medium_phone` (cible) et `android-36.1-medium_tablet`. Un téléphone physique est aussi branché → toujours cibler l'émulateur explicitement (`-d emulator-5554`).

**Autonomie** : après approbation de ce plan, plus aucune question à l'utilisateur jusqu'à la fin. Toute ambiguïté est tranchée par l'implémenteur (choix le plus simple et le plus sûr), consignée dans le rapport final. Seul un blocage réel (outil manquant, droit refusé) est signalé, et le reste du travail continue en attendant.

## Jeu en réseau local (salle de classe)

Objectif : tous les étudiants, chacun avec son émulateur Android sur son poste, jouent ensemble sur le serveur du poste de l'enseignant.

- `firebase.json` : Auth, Firestore et Functions écoutent sur `0.0.0.0` ; l'UI des émulateurs et le hub restent sur `127.0.0.1`.
- Adresse du serveur dans l'app : valeur par défaut via `--dart-define=BACKEND_HOST` (sinon `10.0.2.2`), **modifiable à l'écran de connexion** (« Serveur », avec test de connexion, mémorisée). Un émulateur Android atteint directement l'IP LAN du poste enseignant.
- `tools/start_classroom.ps1` (poste enseignant) : détecte l'IP LAN, démarre les émulateurs avec persistance (`--import/--export-on-exit`), seed si base vide, lance `sim_runner`, construit l'APK avec l'IP intégrée, sert l'APK + une page d'instructions sur `http://<IP>:8088`, affiche l'IP et un QR/URL.
- `tools/install_student.ps1` (poste étudiant) : télécharge l'APK depuis le poste enseignant et fait `adb install` sur l'émulateur local.
- Pare-feu Windows : le script vérifie les ports (9099, 8080, 5001, 8088) et, s'ils sont bloqués, affiche la commande `New-NetFirewallRule` à exécuter en administrateur (limitée au profil réseau privé). **Le script ne modifie pas le pare-feu lui-même.**
- Les tables humaines sont prioritaires au matchmaking : les étudiants d'un même palier de mise se retrouvent à la même table ; les bots ne font que compléter et cèdent leur siège. Code de table privé pour s'asseoir ensemble volontairement.
- Test : deux clients simultanés (AVD téléphone + AVD tablette, plus tests d'intégration multi-clients via le SDK) à la même table en passant par l'IP LAN et non `10.0.2.2`.
- Limite assumée : les émulateurs Firebase n'ont pas d'authentification d'administration ; quiconque sur le réseau local connaît les ports peut contourner les règles via l'API de l'émulateur. Acceptable pour une salle de classe en argent fictif, à ne jamais exposer sur Internet. Les règles et les validations serveur restent testées comme pour un vrai déploiement.

## Architecture

Dossier vide au départ ; tout est nouveau.

```
app/                 Flutter (Riverpod, go_router, firebase_auth, cloud_firestore,
                     cloud_functions, flutter_localizations/intl, fl_chart)
firebase/
  firebase.json      émulateurs Auth 9099, Firestore 8080, Functions 5001, UI 4000
  firestore.rules, firestore.indexes.json
  functions/src/     TypeScript
    engine/          moteur de blackjack pur (aucune dépendance Firebase)
    market/          LMSR pur
    callables/       points d'entrée validés (zod)
    table/           machine à états de table, timeouts
    sim/             bots + seed (réutilise engine/table/market)
tools/               run_emulators.ps1, seed.ps1, sim_runner.ps1, test_all.ps1
```

- Projet `demo-blackjack` (préfixe `demo-` : aucun projet Firebase réel, aucun identifiant).
- **Serveur autoritaire** : le client n'écrit jamais d'argent, de cartes, de paris ni de classement. Il lit Firestore en temps réel et appelle des fonctions.
- L'app Android joint les émulateurs via `10.0.2.2` ; trafic en clair autorisé uniquement dans le manifeste *debug*.
- Minuteries : chaque document de table porte une `deadline`. Tout appel applique d'abord les timeouts échus ; le client peut appeler `pokeTable` (le serveur revérifie l'heure) ; `sim_runner` (processus Node local, Admin SDK) fait tourner les bots et les ticks. Aucune dépendance aux fonctions planifiées (non déclenchées par l'émulateur).

## Règles du blackjack (fixes, affichées dans l'app)

Vérifiées en ligne : les règles varient selon le casino ; on fige le jeu standard « américain » le plus courant.

- 6 jeux (312 cartes), carte de coupe à ~75 %, remélange entre deux mains.
- Croupier : carte cachée, **vérifie le blackjack** sur As/10, **reste sur tout 17** (S17).
- Blackjack naturel payé **3:2** ; égalité = mise rendue ; blackjack bat un 21 en 3+ cartes.
- Assurance sur As visible : ≤ moitié de la mise, payée 2:1.
- Doubler sur deux cartes quelconques, une seule carte ; autorisé après split.
- Split de cartes de même valeur, jusqu'à 4 mains ; **As séparés : une carte chacun, pas de re-split, As+10 après split = 21 ordinaire**.
- Abandon tardif (moitié de la mise) sur les deux premières cartes, pas après split.
- Argent en **centimes entiers** ; mises par pas de 1,00 (3:2 toujours exact) ; min/max par table.
- Tour : 15 s pour miser, 20 s par décision (sinon « rester »).

## Modèle de données et sécurité

| Chemin | Lecture | Écriture client |
|---|---|---|
| `profiles/{uid}` (pseudo, avatar, rang, stats) | connectés | aucune |
| `users/{uid}` (réglages : thème, langue, dos de carte équipé) | propriétaire | champs en liste blanche, types validés |
| `users/{uid}/private/wallet`, `ledger/*`, `inventory/*`, `positions/*`, `kyc` | propriétaire | aucune |
| `tables/{id}` (sièges, cartes visibles, phase, deadline) | connectés | aucune |
| `tables/{id}/private/*` (sabot, carte cachée, graine) | **personne** | aucune |
| `tables/{id}/peeks/{uid}` (pouvoir « coup d'œil ») | ce uid | aucune |
| `markets/{id}`, `trades`, `priceHistory` | connectés | aucune |
| `friendships`, `friendRequests` | participants | aucune |

Mesures :
- Toutes les mutations passent par des callables : auth obligatoire, schéma zod strict (entiers, bornes, énumérations), **transactions Firestore**, clé d'idempotence par requête, limitation de débit par utilisateur, vérification du tour/siège/phase.
- Mélange Fisher-Yates avec `crypto.randomInt` ; engagement **« provably fair »** : SHA-256 de la graine publié avant la main, graine révélée après.
- Pari spectateur interdit sur sa propre table ; marché fermé avant que le croupier ne révèle.
- KYC simulé requis pour déposer/retirer ; refus < 18 ans ; plafonds de dépôt.
- Faux formulaire de paiement : numéro de test **pré-rempli et non modifiable**, bandeau « Simulation » ; le serveur ne reçoit que montant + méthode (aucune donnée de carte ne transite ni n'est stockée).
- Mots de passe : politique Firebase Auth + validation ; pseudo unique via `usernames/{nom}` en transaction ; aucun secret dans le dépôt ; journaux sans données personnelles.

Callables : `completeProfile`, `submitKyc`, `deposit`, `withdraw`, `joinMatchmaking`, `leaveTable`, `placeBet`, `act` (hit/stand/double/split/surrender/insurance + pouvoir optionnel), `pokeTable`, `buyPower`, `tradeShares` (achat/vente), `friendRequest`/`respondFriend`/`removeFriend`, `claimAdReward`, `equipCardStyle`.

## Fonctionnalités

1. **Compte** — inscription / connexion e-mail + mot de passe, pseudo, avatar ; **KYC simulé** (type de pièce, date de naissance, faux scan animé → en attente → vérifié).
2. **Wallet fictif** — solde, dépôt/retrait simulés (carte, crypto, virement), historique du grand livre, bonus de bienvenue.
3. **Matchmaking** — choix du niveau de mise ; appariement par palier de rang ; bots pour compléter ; file d'attente animée.
4. **Table de jeu** — tapis, 5 sièges, jetons, minuterie, actions, assurance, mains séparées, historique, vérification d'équité.
5. **Croupier animé** — personnage vectoriel dessiné en code (`CustomPainter`), bras à cinématique inverse 2 segments : tire du sabot, distribue en trajectoire courbe avec rotation et ombre, retourne la carte en 3D, ramasse les cartes, pousse/ramasse les jetons ; clignement, respiration, réactions (blackjack, bust) ; sons + retour haptique. Mélange animé au changement de sabot. *(Pas d'asset graphique externe : tout est procédural.)*
6. **Pouvoirs** (boutique, payés en argent fictif, 1 par main, validés serveur) : Split gratuit · Double gratuit · Assurance gratuite · Coup d'œil (carte cachée, visible du seul joueur) · Seconde chance (remplace la dernière carte tirée).
7. **Spectateur / marchés façon Polymarket** — liste des tables en direct sous forme de cartes de marché ; par main : « Le croupier saute ? », « {Joueur} gagne ? », « Un blackjack naturel ? » ; par sabot : un marché long. Parts Oui/Non cotées en ¢ (paiement 1,00 $ par part gagnante), teneur de marché **LMSR** côté serveur (perte maison bornée), graphique de prix, ticket d'ordre, positions, activité, vue de la table en direct.
8. **Classement** — points par main (victoire, blackjack, défaite), paliers Bronze→Diamant ; onglets global / amis / hebdo.
9. **Amis** — recherche par pseudo, demandes, liste, statut en ligne, « regarder sa table ».
10. **Personnalisation des cartes** — dos (motifs/couleurs), style de face (classique, 4 couleurs, néon), tapis ; aperçu en direct.
11. **Fausses pubs** — bannières parodiques, interstitiel occasionnel entre deux mains, pub « récompensée » (petit crédit, débit limité).
12. **Thème** — sombre (défaut, palette bleu nuit + vert façon Stake) / clair / système ; **FR/EN**.
13. **Données fictives** — `seed` : ~60 profils de bots, historiques, classement rempli, amis suggérés ; `sim_runner` : 8 tables vivantes, bots qui jouent (stratégie de base bruitée) et qui échangent sur les marchés, bandeau « gains récents ».

## Ordre d'implémentation (chaque phase se termine tests verts)

1. Squelette : `flutter create`, config Firebase/émulateurs, scripts `tools/`, thème + i18n + navigation.
2. Moteur de blackjack TS + tests complets (aucune UI).
3. LMSR + tests.
4. Règles Firestore + callables wallet/KYC/profil + tests de règles et d'intégration.
5. Machine à états de table, matchmaking, pouvoirs, bots, seed.
6. UI Flutter : auth/KYC → wallet → lobby → table + croupier animé → boutique/personnalisation.
7. Marchés spectateurs (serveur puis UI), classement, amis, pubs.
8. Tests d'intégration sur l'AVD, passe sécurité (`/security-review`), polissage.

## Tests et vérification

**Functions (vitest + fast-check + `@firebase/rules-unit-testing`)**
- Moteur : valeur des mains (As souples), chaque règle ci-dessus, tous les cas de paiement, peek, split d'As, abandon, assurance.
- Propriétés : 312 cartes sans doublon ; conservation de l'argent (somme des variations = 0 avec la maison) ; aucun solde négatif ; aucun état sans action légale.
- **Régression** : transcriptions « golden » (graine fixe → déroulé JSON attendu, versionné) ; Monte-Carlo à graine fixe en stratégie de base : avantage maison dans la fourchette attendue (~0,3–0,7 %) ; un test ajouté pour chaque bogue corrigé.
- LMSR : prix ∈ ]0,1[, somme = 1, coût aller-retour ≥ 0, perte bornée par `b·ln 2`, règlement correct.
- Règles Firestore : chaque ligne du tableau, en positif et en négatif (lecture du sabot refusée, écriture du wallet refusée, etc.).
- Intégration (émulateurs) : double dépense concurrente, rejeu d'une requête (idempotence), action hors tour / sur le siège d'autrui, mises négatives / décimales / énormes, pouvoir non possédé, pari sur sa propre table, limitation de débit.

**Flutter**
- Unitaires (modèles, formatage monétaire, contrôleurs), widgets (chaque écran, FR/EN), **golden** clair/sombre des écrans clés, tests des contrôleurs d'animation du croupier (durées, ordre des cartes).
- `integration_test` sur `android-36.1-medium_phone` contre les émulateurs : inscription → KYC → dépôt → matchmaking → main complète (hit/split/double) → achat et usage d'un pouvoir → pari spectateur + règlement → demande d'ami → changement de thème/langue.

**Bout en bout** : `tools/test_all.ps1` (lint `flutter analyze`, `tsc --noEmit`, tests functions, tests Flutter, intégration) ; puis lancement manuel sur l'AVD avec captures d'écran (`adb exec-out screencap`) de chaque écran pour contrôle visuel, et vérification du grand livre dans l'UI des émulateurs (port 4000).

## Limites connues

- Tout tourne en local sur les émulateurs ; un déploiement réel demanderait App Check, Cloud Tasks pour les minuteries et un vrai projet Firebase.
- « Aucune erreur » est visé par la couverture de tests ci-dessus ; ce qui n'aura pas pu être vérifié sera signalé explicitement en fin d'implémentation.
