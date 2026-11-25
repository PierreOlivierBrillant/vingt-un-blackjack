# Reprise du projet Vingt-Un (blackjack Flutter + émulateurs Firebase)

Instantané mis à jour le 2026-11-25 (poste DeepFreeze : rien de local ne survit au redémarrage).
Le plan complet approuvé est dans `PLAN.md`.

## Prérequis à vérifier sur le poste
Flutter 3.44.6 (`C:\Android\flutter`), Node 24, Java 21, Firebase CLI 15.25, SDK Android (`C:\Android\Sdk`, adb PAS dans le PATH : `C:\Android\Sdk\platform-tools\adb.exe`), AVD `android-36.1-medium_phone` et `android-36.1-medium_tablet` (`ANDROID_AVD_HOME=C:\Android\avd`), `gh auth login`.
Puis `npm ci` dans `firebase/functions` et `flutter pub get` dans `app`.

## État (2026-11-25)
- Backend `firebase/` : typecheck, lint, 100 tests unitaires, 29 tests de règles, tests d'intégration sur émulateurs : tout vert (`tools\test_all.ps1 -BackendOnly`).
- App `app/` : `flutter analyze` propre, 248 tests verts sous Windows (unitaires, widgets, goldens).
- CI GitHub : jobs backend et Flutter verts. Les goldens diffèrent sous Linux (rendu) : étape non bloquante, à générer et comparer sous Windows seulement.
- A. Sons : 83 effets (77 + 6 « Las Vegas » ajoutés le 25/11 : `vegas_intro`, `slot_jackpot_bells`, `crowd_cheer`, `crowd_ooh`, `ambience_slots_loop`, `ui_chip_tap`), tous branchés. Partout : clic de jeton sur CHAQUE toucher (détecteur global de taps), swoosh à chaque changement d'écran et carte à l'ouverture des dialogues, jingle « Welcome to Las Vegas » à la première arrivée dans le salon, machines à sous en fond (canal `slots`, suit le curseur d'ambiance), gains des autres joueurs qui sonnent dans le salon, foule qui acclame / fait « ooooh » à la table, cloches de jackpot pour les gros gains, paiements de marché et pubs récompensées. Aussi : roulement court au coup d'œil du croupier, « succès » aux paliers, rouleaux pendant la pub récompensée. Corrections : contexte audio invalide en debug (option iOS), et suivi de position audioplayers désactivé (il forçait une frame à chaque image pour chaque lecteur : coût de performance permanent).
- B. Corrections visuelles : présentes dans le code et testées (total « 11 » pour un As seul, notation souple réservée aux joueurs, contraste des badges ≥ 4,5, coude du croupier, golden régénéré).
- C. Salle de classe : `start_classroom.ps1` exécuté pour de vrai (APK construit avec l'IP LAN, émulateurs, seed, simulation, page 8088, diagnostic pare-feu en lecture seule). `install_student.ps1` vérifié sur l'AVD (téléchargement, SHA-256, installation sur l'émulateur seulement). Test d'intégration `app/integration_test/app_flow_test.dart` sur l'AVD via l'IP LAN : le parcours complet est passé UNE fois de bout en bout (inscription → KYC → dépôt → boutique → main avec coup d'œil → pari spectateur → ami → thème/langue). Le test reste INSTABLE face au serveur en direct (il dépend du rythme réel des mains et des bots) : sur 8 passages, échecs à des étapes différentes (table non trouvée en 60 s, retour aux onglets, fin de test avec animations audio en attente — cette dernière cause est corrigée). Déjà fiabilisé : déconnexion de toutes les instances Firebase, clavier fermé avant les taps, retour système, attente de son tour, marchés qui ferment. Bogue réel trouvé : le graphique d'un marché tout neuf (un seul point de prix) plantait (intervalle d'axe nul) → corrigé + test.
- D. CI Linux : réglé (polices embarquées dans `app/test/fonts`).
- Revue de sécurité (2026-11-25), corrigée avec tests de régression :
  - marché « {joueur} gagne ? » resté ouvert après un blackjack naturel (achat de OUI sans risque) → fermé dès les tours des joueurs ;
  - code de table privée visible dans le nom public de la table (salon, questions des marchés) → retiré du nom ;
  - marché long du sabot annulé (remboursé) à la fermeture d'une table alors qu'il ne se négociait plus (option gratuite) → résolu sur les mains jouées ;
  - rejeu d'idempotence : vérifie aussi le propriétaire de la requête.
  - NON corrigé (faible) : `profiles/{uid}` expose `kycVerified` et `currentTableId` à tous les connectés. Pour corriger : retirer `kycVerified` du profil public (l'app lit déjà `users/{uid}/private/kyc`, voir `app/lib/domain/models.dart` vers la ligne 173) et ne publier `currentTableId` que pour les tables publiques.

## Reste à faire
1. Rendre le dépôt GitHub PUBLIC (demandé à l'origine ; à reconfirmer avec l'utilisateur avant de le faire).
2. Pousser l'APK sur les 23 postes du VLAN `10.10.96.0/24` avec les droits de l'utilisateur seulement (à reconfirmer) ; sinon repli sur la page de téléchargement (port 8088).
3. Faire écouter les sons à l'utilisateur (aucun agent ne peut les entendre) : points à risque = foule/ambiance « chœur synthétique », ambiance sourde sur téléphone, et les 6 nouveaux sons Las Vegas (surtout `crowd_ooh`, synthèse de voyelles, et le clic `ui_chip_tap` entendu à chaque toucher).
4. Fiabiliser `app/integration_test/app_flow_test.dart` (idéalement une table privée créée par le test, sans dépendre des tables simulées), puis le lancer 3 fois de suite sans échec.
5. Preuve à deux clients humains simultanés via l'IP LAN (AVD téléphone + AVD tablette) : non refaite cette session (les tests d'intégration backend couvrent le multi-clients via le SDK).
6. Faible priorité : le point KYC public ci-dessus.

## À savoir pour la salle de classe
- Ce poste est en profil réseau **Domaine** (pas Privé) : la règle pare-feu « profil privé » ne s'applique pas. Le port 8080 (Firestore, java.exe) est signalé bloqué en entrée ; 9099/5001/8088 sont couverts par une règle Node existante. Passer par l'informatique du collège. Les scripts ne modifient jamais le pare-feu.
- IP LAN du poste enseignant : 10.10.96.130 (sessions du 19 et du 25 novembre).
- Un humain est retiré de la table après 3 mains sans mise ; un callable prend ~3 s sur l'émulateur pour une fenêtre de mise de 15 s (à évaluer).
- Fluidité : un build debug est lent sur l'émulateur (JIT, assertions). Pour juger la fluidité : `flutter run --profile -d emulator-5554 --dart-define=BACKEND_HOST=<IP>` depuis `app`.
- Le test d'intégration crée un compte neuf à chaque passage et se déconnecte de TOUTES les instances Firebase (l'app en crée une par adresse de serveur).

## Commandes (PowerShell, depuis la racine)
- Émulateurs : `powershell -ExecutionPolicy Bypass -File tools\run_emulators.ps1` ; données : `tools\seed.ps1` ; simulation : `tools\sim_runner.ps1`
- Tests backend : `tools\test_all.ps1 -BackendOnly` (arrêter les émulateurs avant) ; tests Flutter : `app\tool\test.ps1`
- Intégration sur l'AVD (émulateurs lancés) : `flutter test integration_test -d emulator-5554 --dart-define=BACKEND_HOST=<IP>` depuis `app\` (avec le `JAVA_TOOL_OPTIONS` ci-dessous)
- Classe : `tools\start_classroom.ps1` (enseignant), `tools\install_student.ps1 -TeacherIp <IP>` (étudiant), `tools\stop_classroom.ps1` (arrêt propre avec export des données)
- Java 21 : voir `tools\_backend_env.ps1` ; pour Gradle : `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\nonexistent-afunix-dir`.
- Un téléphone physique peut être branché (série `f250e7c31e28b675`) : ne jamais y installer ; toujours cibler `emulator-55xx`.

## Décisions prises
Tables partagées (≤ 5 joueurs + bots), boutique de 5 pouvoirs, FR + EN, argent 100 % fictif, tout procédural (aucun asset externe, sons synthétisés), aucune question à l'utilisateur pendant l'implémentation. Sauvegardes : commits poussés sur `main` du dépôt GitHub privé.
