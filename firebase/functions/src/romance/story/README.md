# Histoire de « Rendez-vous » — format des fichiers

Ce dossier est la **source unique** de l'histoire. Le serveur l'importe (`../story.ts`), et
`node tools/sync_story.mjs` (depuis la racine du dépôt) le copie octet pour octet dans
`app/assets/story/` et l'embarque dans `app/lib/features/romance/story/story_bundle.g.dart`.
Après **toute** modification : relancer `node tools/sync_story.mjs`, puis
`npx vitest run --config vitest.unit.config.mts test/unit/romance` (dans `firebase/functions`) et
`flutter test test/unit/romance_story_test.dart` (dans `app`). Les deux côtés vérifient la parité
SHA-256 des fichiers.

## Règles de contenu (non négociables, vérifiées par `test/unit/romance/content.test.ts`)

- Tous les personnages sont **adultes (24 à 38 ans)**, écriture **PG-13** : on flirte, on rit, on se
  confie, on se tient la main. **Au plus un baiser, à la finale**, suivi d'un fondu au noir
  (`"fade": true` sur le nœud de fin). Les mots du baiser (embrasser, bisou, kiss…) sont **refusés
  hors des finales**. Rien de sexuel, de graphique, de vulgaire ; pas d'ivresse ni de drogue.
- On peut séduire n'importe quel personnage, quel que soit le profil du joueur : **le joueur n'est
  jamais genré** (« tu », « you » ; pas d'accord au féminin ou au masculin qui le désigne :
  écrire « Tu es venu·e » est interdit aussi, reformuler : « Te voilà ! »).
- **Alex** utilise **« iel »** en français et **« they »** en anglais (accords : « Alex est
  concentré·e » → préférer des tournures neutres : « Alex garde les yeux sur le tapis »). Les
  nœuds `narrator` des scènes d'Alex n'emploient jamais il/elle ni he/she/him/her/his.
- Tout texte existe en **FR et EN** (`{ "fr": "…", "en": "…" }`), non vide, sans texte libre entre
  joueurs. Longueurs maximales : réplique 280, choix 90, titre 40 caractères.
- Liste de mots interdits : voir `FORBIDDEN` dans `test/unit/romance/storyCheck.ts`.

## Fichiers

| Fichier | Contenu |
|---|---|
| `rules.json` | Constantes de jeu reflétées côté Dart (copie de `shared/romance.ts`, vérifiée par test). |
| `characters.json` | Par personnage : âge, pronom, bio FR/EN, goûts (`tastes`), récompenses par palier (`rewards`). |
| `gifts.json` | Les 12 cadeaux (prix en centimes, `drink` = peut s'offrir à un match). |
| `scenes_<personnage>.json` | `{ "character": "<id>", "scenes": [Scene…] }`. |
| `table_lines.json` | Répliques des 5 croupiers à leur table (accueil par palier, réactions). `{name}` = pseudo. |
| `dating_lines.json` | Les ~40 répliques prédéfinies des Rencontres entre joueurs. |

### Goûts et récompenses (`characters.json`)

`tastes` : `giftId` → `"loved"` (+15) | `"liked"` (+8) | `"disliked"` (−5) ; absent = neutre (+3).
`rewards` : palier `"1"`..`"5"` → liste de `{ "kind": "cosmetic", "id": "rv_<perso>_back|felt|title" }`
ou `{ "kind": "power", "powerId": "<POWER_IDS>", "qty": n }`. Chaque cosmétique exclusif du
personnage apparaît une fois. Accordées une seule fois, même si l'affinité redescend.

### Scène

```json
{
  "id": "lucas_talk_1",
  "character": "lucas",
  "kind": "talk",
  "minTier": 0,
  "requires": [],
  "place": "casino",
  "title": { "fr": "Première main", "en": "First hand" },
  "start": "a",
  "nodes": {
    "a": { "who": "narrator", "text": { "fr": "…", "en": "…" }, "next": "b" },
    "b": { "who": "lucas", "expr": "smile", "text": { "fr": "…", "en": "…" },
           "choices": [
             { "id": "joke", "text": { "fr": "…", "en": "…" }, "delta": 6, "next": "c" },
             { "id": "shy",  "text": { "fr": "…", "en": "…" }, "delta": 2, "next": "d" },
             { "id": "deal", "text": { "fr": "…", "en": "…" }, "delta": 4, "next": "d", "if": { "minTier": 1 } }
           ] },
    "c": { "who": "lucas", "expr": "laugh", "text": { "fr": "…", "en": "…" }, "next": "end" },
    "d": { "who": "lucas", "expr": "blush", "text": { "fr": "…", "en": "…" }, "next": "end" },
    "end": { "who": "narrator", "text": { "fr": "…", "en": "…" }, "end": true }
  }
}
```

- `id` : `<perso>_talk_<1-4>`, `<perso>_date_<1-2>`, `<perso>_finale`, `<perso>_small_<mot>` ;
  `[a-z0-9_]`, ≤ 64 caractères, unique dans toute l'histoire.
- `kind` : `talk` (discussion de l'histoire), `smalltalk` (petite conversation de la réserve,
  rejouable), `date` (rendez-vous), `finale`.
- `minTier` : palier minimal (0 Inconnu·e, 1 Connaissance, 2 Ami·e, 3 Complice, 4 Flirt,
  5 Coup de cœur). `requires` : scènes du même personnage à avoir terminées.
- `reservationCents` (rendez-vous et finale seulement, > 0) : débité (grand livre `reservation`)
  quand le rendez-vous va jusqu'au bout.
- `place` : décor dessiné en code : `casino`, `bar`, `lounge`, `terrace`, `rooftop`, `garden`,
  `restaurant`, `beach`, `harbor`, `museum`, `arcade`, `kitchen`.
- Nœud : `who` (id du personnage, ou `narrator`), `expr` (`neutral`, `smile`, `laugh`, `wink`,
  `surprised`, `blush`, `sad`, `thinking` ; pour les répliques d'un personnage), `text`, et
  **exactement un** de `next` (nœud suivant), `choices` (2 à 4 choix), `end: true` (fin ;
  `fade: true` = fondu au noir, finale seulement).
- Choix : `id` (`[a-z0-9_]`, ≤ 24, unique dans la scène), `text` (ce que dit le joueur),
  `delta` (affinité, **de −5 à +10**), `next`, et `if` facultatif (`minTier`, `seen`) : chaque nœud
  garde au moins un choix sans condition.
- **Graphe sans impasse** : tous les nœuds sont atteignables depuis `start`, le graphe est sans
  cycle, chaque chemin mène à une fin.
- Budgets d'affinité (chemin le plus favorable) : smalltalk ≤ 10, talk ≤ 25, date ≤ 35,
  finale ≤ 40 ; chemin le moins favorable ≥ −15.

### Structure imposée d'un personnage complet

| Scène | `minTier` | `requires` | Notes |
|---|---|---|---|
| `<p>_talk_1` | 0 | — | 6 à 40 nœuds, ≥ 2 nœuds à choix |
| `<p>_talk_2` | 1 | `<p>_talk_1` | |
| `<p>_talk_3` | 2 | `<p>_talk_2` | |
| `<p>_talk_4` | 3 | `<p>_talk_3` | |
| `<p>_date_1` | 3 | `<p>_talk_3` | `reservationCents` 5000 |
| `<p>_date_2` | 4 | `<p>_date_1`, `<p>_talk_4` | `reservationCents` 12000 |
| `<p>_finale` | 5 | `<p>_date_2` | `reservationCents` 20000, un nœud de fin `fade` |
| `<p>_small_*` | 0..3 | — | au moins 3 (au moins 2 pour un personnage incomplet), 3 à 20 nœuds, ≥ 1 choix |

Le serveur (`romance{op:'playScene'}`) rejoue le chemin des choix depuis ce JSON : il vérifie le
palier, les prérequis, « une discussion (talk ou smalltalk) par jour et par personnage », les
conditions des choix, et que le chemin atteint une fin.

## Personnages incomplets

`INCOMPLETE_CHARACTERS` (dans `../story.ts`) liste les personnages dont l'histoire reste à
écrire (aujourd'hui : Inès, Alex, Marco, Théo, Nora, Hugo). Ils ont déjà leurs goûts, leurs
récompenses, leurs répliques de table (croupiers) et 2 petites conversations. **Pour en terminer
un** : écrire dans `scenes_<p>.json` ses 4 `talk`, 2 `date`, sa `finale` et au moins une
smalltalk de plus (structure ci-dessus), le retirer de `INCOMPLETE_CHARACTERS`, relancer
`node tools/sync_story.mjs` et les tests. Rien d'autre à toucher : le serveur et l'app lisent
tout depuis ces fichiers (l'app affiche « Histoire à venir » tant qu'un personnage n'a pas de
`talk`).

### Répliques de table (`table_lines.json`)

`lines.<croupier>` : `greet` (palier `"0"`..`"5"` → au moins 1 réplique, `{name}` = pseudo du
joueur), `win`, `bigWin`, `lose`, `push` (au moins 2 chacune). ≤ 90 caractères.

### Répliques des Rencontres (`dating_lines.json`)

`{ "id", "kind": "opener" | "reply", "text", "replies": [ids] }`. Une `opener` est toujours
permise ; une `reply` seulement juste après une réplique de l'autre membre qui la liste dans
`replies`. ≤ 90 caractères, PG-13, neutres (aucun genre supposé).
