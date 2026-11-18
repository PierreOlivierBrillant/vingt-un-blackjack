# Reprise du projet Vingt-Un (blackjack Flutter + émulateurs Firebase)

Instantané pris en cours de travail (poste avec DeepFreeze : rien de local ne survit au redémarrage).
Le plan complet approuvé est dans `PLAN.md`.

## Prérequis à réinstaller/vérifier sur le poste
Flutter 3.44.6, Node 24, Java 21, Firebase CLI 15.25, SDK Android (`C:\Android\Sdk`), AVD `android-36.1-medium_phone` et `android-36.1-medium_tablet`, `gh auth login`.
Cloner dans un chemin COURT (ex. `C:\dev\vingtun`) : le compilateur de shaders Flutter échoue au-delà de 260 caractères.
Puis `npm ci` dans `firebase/functions` et `flutter pub get` dans `app`.

## État
- FAIT (rapporté par l'agent, non revérifié par l'orchestrateur) : backend `firebase/` + `tools/` — moteur, LMSR, règles, 16 callables, bots, seed. 93 tests unitaires, 29 règles, 42 intégration ; avantage maison 0,443 %.
- FAIT (idem) : socle Flutter `app/` — thème, FR/EN, cartes, croupier animé, tous les écrans sur données factices. 104 tests, analyze propre.
- EN COURS, INTERROMPU : branchement de `app/` sur le backend. Le contenu de `app/` dans ce commit peut être à mi-chemin (peut ne pas compiler). Contrat : `firebase/functions/src/shared/types.ts` ; interfaces : `app/lib/data/repositories.dart`, `app/lib/data/providers.dart`.

## Reste à faire
1. Finir le branchement : implémentations Firebase des 11 dépôts, écran de table piloté par les snapshots (diff → commandes du `DealerController`), `pokeTable` à l'échéance, pouvoirs, équité prouvable, table privée, mode spectateur. Codes de carte : backend `"TH"` vs client `"10H"` à concilier.
2. Marchés spectateurs, classement, amis, pubs (interstitiel entre deux mains, pub récompensée) côté client.
3. Corrections visuelles : espace vide au-dessus de la table, coude du croupier, badges peu contrastés en clair, totaux superposés sur mains séparées, palier de profil codé en dur, animations coup d'œil/assurance/abandon, vrais sons.
4. Mode salle de classe : `tools/start_classroom.ps1` (IP LAN, émulateurs, seed, sim, build APK, page de téléchargement port 8088) et `tools/install_student.ps1` ; le script affiche la commande pare-feu sans la lancer.
5. `tools/test_flutter.ps1` + tests d'intégration sur l'AVD ; preuve à deux joueurs (téléphone + tablette) via l'IP LAN.
6. Revérifier soi-même toutes les suites (`tools\test_all.ps1`), revue de sécurité.
7. Rendre le dépôt GitHub PUBLIC (demandé), ajouter le CI/CD GitHub Actions qui produit l'APK.
8. Pousser l'APK sur les 23 postes du VLAN `10.10.96.0/24` avec les droits de l'utilisateur seulement (session non admin, domaine du collège) ; sinon repli sur la page de téléchargement.

## Commandes (PowerShell, depuis la racine)
- Émulateurs : `powershell -ExecutionPolicy Bypass -File tools\run_emulators.ps1`
- Données : `tools\seed.ps1` ; simulation : `tools\sim_runner.ps1`
- Tests backend : `tools\test_all.ps1 -BackendOnly` (arrêter les émulateurs avant)
- Tests Flutter : `app\tool\test.ps1`
- Particularité Java 21 sur ces postes : voir `tools\_backend_env.ps1` ; pour Gradle : `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\nonexistent-afunix-dir`.
- Ne jamais installer sur le téléphone physique branché ; toujours cibler l'émulateur.

## Décisions prises
Tables partagées (≤ 5 joueurs + bots), boutique de 5 pouvoirs, FR + EN, argent 100 % fictif, implémentation par Opus 5.5, aucune question à l'utilisateur pendant l'implémentation.
