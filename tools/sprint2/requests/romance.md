# Chantier Rendez-vous (romance) — demandes et décisions

## Demandes hors périmètre (contournées)

_(complétées au fil du chantier, voir plus bas)_

## Décisions

### Histoire
- **Source unique** : `firebase/functions/src/romance/story/*.json` (format : `story/README.md`). `node tools/sync_story.mjs`
  les copie dans `app/assets/story/` ET les embarque dans `app/lib/features/romance/story/story_bundle.g.dart`
  (`--check` pour vérifier). SHA-256 calculés sur le texte en LF (le dépôt est extrait en CRLF sous Windows,
  `core.autocrlf=true`, pas de `.gitattributes`).
- `rules.json` reflète les constantes de `shared/romance.ts` (vérifié par `test/unit/romance/content.test.ts`) :
  c'est par lui que l'app Dart lit les seuils, plafonds et goûts (je ne peux pas étendre `contract.json`,
  dont le test n'est pas dans mon périmètre).
- Structure imposée d'un personnage complet : talk_1..4 (paliers 0, 1, 2, 3), date_1 (palier 3, après talk_3,
  50 $), date_2 (palier 4, après date_1 et talk_4, 120 $), finale (palier 5, après date_2, 200 $), ≥ 3 smalltalks.
- `INCOMPLETE_CHARACTERS` (dans `src/romance/story.ts`) : Inès, Alex, Marco, Théo, Nora, Hugo. Le test échoue si un
  personnage complet y reste listé.
- Mots interdits par langue, bornes de mot Unicode (`\b` de JS coupe sur « é », « œ ») ; mots du baiser réservés
  aux finales ; narration des scènes d'Alex sans il/elle/he/she ; le joueur n'est jamais genré (consigne d'écriture,
  relue à la main, non vérifiable automatiquement).
- Contenu écrit : Lucas, Camille, Jade complets (4 talks, 2 dates, finale, 4 smalltalks chacun) ; 2 smalltalks pour
  chacun des 6 autres ; répliques de table des 5 croupiers ; 45 répliques de Rencontres.
