# Reprise du projet Vingt-Un (blackjack Flutter + émulateurs Firebase)

Instantané pris le 2026-11-19 vers 10 h 55, en cours de travail (poste DeepFreeze : rien de local ne survit au redémarrage).
Le plan complet approuvé est dans `PLAN.md`.

## Prérequis à vérifier sur le poste
Flutter 3.44.6 (`C:\Android\flutter`), Node 24, Java 21, Firebase CLI 15.25, SDK Android (`C:\Android\Sdk`, adb PAS dans le PATH : `C:\Android\Sdk\platform-tools\adb.exe`), AVD `android-36.1-medium_phone` et `android-36.1-medium_tablet` (`ANDROID_AVD_HOME=C:\Android\avd`), `gh auth login`.
Puis `npm ci` dans `firebase/functions` et `flutter pub get` dans `app`.

## État
- FAIT ET REVÉRIFIÉ par l'orchestrateur (commit a70ac7f) :
  - backend `firebase/` : typecheck, lint, unitaires, règles, 42 tests d'intégration verts (`tools\test_all.ps1 -BackendOnly`) ; job backend du CI GitHub vert.
  - branchement de `app/` sur le backend : table pilotée par les snapshots, pouvoirs, équité, table privée, spectateur, marchés, classement, amis, pubs. `flutter analyze` propre, 200 tests verts sous Windows. Parcours joué sur l'AVD (captures dans `app/screenshots/`).
  - banque de sons : 77 WAV synthétisés dans `app/assets/sfx/` (générateur `tools/sfx/`, `node tools/sfx/generate.mjs --check` vert). Voir `app/assets/sfx/MANIFEST.md`.
- FAIT, NON VÉRIFIÉ de bout en bout : `tools/start_classroom.ps1`, `tools/install_student.ps1`, `tools/test_flutter.ps1`, `.github/workflows/ci.yml`.
- EN COURS, INTERROMPU (le dernier commit contient ce travail À MI-CHEMIN ; `app/` peut ne pas compiler ni passer les tests) — un sous-agent Opus faisait :
  A. câblage des 77 sons (demande expresse : BEAUCOUP de sons « over the top », très casino) : `SoundService` Riverpod, sons synchronisés aux animations, réglages volume effets / ambiance / coupure, tests ;
  B. corrections visuelles (espace vide au-dessus de la table, coude du croupier, badges en thème clair, totaux des mains séparées, palier de profil codé en dur, animations coup d'œil / assurance / abandon / seconde chance, total croupier « 1/11 » au lieu de « 11 ») ;
  C. `app/integration_test/`, vérifications AVD manquantes (assurance, split, interstitiel, table privée, pari refusé sur sa propre table), preuve à deux joueurs via l'IP LAN, exécution réelle de `start_classroom.ps1` ;
  D. CI GitHub : le job Flutter échoue sous Linux sur 5 tests widget (débordements de quelques pixels, cause probable : polices différentes Windows/Linux ; voir `app/test/flutter_test_config.dart`). Tests : « my positions » (social_and_ads_test), « FR · market detail », « FR · ads », « small phone 360 × 640 » (screens_test), « order ticket … LMSR estimate » (interactions_test).
  Son rapport n'a PAS été reçu : regarder `git show --stat HEAD` pour voir où il en était, puis lancer `app\tool\test.ps1`.

## Reste à faire
1. Finir et vérifier A, B, C, D ci-dessus.
2. Revérifier toutes les suites (`tools\test_all.ps1`), revue de sécurité (`/security-review`).
3. Rendre le dépôt GitHub PUBLIC (demandé à l'origine ; à reconfirmer avec l'utilisateur avant de le faire).
4. Pousser l'APK sur les 23 postes du VLAN `10.10.96.0/24` avec les droits de l'utilisateur seulement (à reconfirmer) ; sinon repli sur la page de téléchargement (port 8088).
5. Faire écouter les sons à l'utilisateur (aucun agent ne peut les entendre) : points à risque = foule/ambiance « chœur synthétique », ambiance sourde sur téléphone.

## À savoir pour la salle de classe
- Ce poste est en profil réseau **Domaine** (pas Privé) : la règle pare-feu « profil privé » ne s'applique pas. Le port 8080 (Firestore, java.exe) semble bloqué en entrée ; 9099/5001/8088 sont couverts par une règle Node existante. Passer probablement par l'informatique du collège. Les scripts ne modifient jamais le pare-feu.
- IP LAN du poste enseignant lors de cette session : 10.10.96.130.
- Un humain est retiré de la table après 3 mains sans mise ; un callable prend ~3 s sur l'émulateur pour une fenêtre de mise de 15 s (à évaluer).

## Commandes (PowerShell, depuis la racine)
- Émulateurs : `powershell -ExecutionPolicy Bypass -File tools\run_emulators.ps1` ; données : `tools\seed.ps1` ; simulation : `tools\sim_runner.ps1`
- Tests backend : `tools\test_all.ps1 -BackendOnly` (arrêter les émulateurs avant) ; tests Flutter : `app\tool\test.ps1`
- Classe : `tools\start_classroom.ps1` (enseignant), `tools\install_student.ps1 -TeacherIp <IP>` (étudiant)
- Java 21 : voir `tools\_backend_env.ps1` ; pour Gradle : `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\nonexistent-afunix-dir`.
- Un téléphone physique peut être branché (série `f250e7c31e28b675`) : ne jamais y installer ; toujours cibler `emulator-55xx`.

## Décisions prises
Tables partagées (≤ 5 joueurs + bots), boutique de 5 pouvoirs, FR + EN, argent 100 % fictif, tout procédural (aucun asset externe, sons synthétisés), implémentation par des sous-agents Opus 5.5 (l'orchestrateur Fable relit et vérifie seulement), aucune question à l'utilisateur pendant l'implémentation. Sauvegardes : commits poussés sur `main` du dépôt GitHub privé.
