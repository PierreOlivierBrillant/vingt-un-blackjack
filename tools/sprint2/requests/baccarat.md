# Chantier baccarat — décisions et demandes hors périmètre

## Décisions

### Règles et argent
- **Sabot** : 8 jeux (416 cartes), carte de coupe à 16 cartes de la fin. Le coup pendant lequel la coupe
  sort (≤ 16 cartes restantes après lui) est le dernier du sabot ; le coup suivant ouvre un sabot neuf
  (événement `shuffle`). Un coup prend au plus 6 cartes : il ne manque jamais de cartes.
- **Brûlage** au premier coup de chaque sabot : la première carte est montrée, puis autant de cartes
  que sa valeur sont brûlées (as 1, 2–9 valeur faciale, 10/V/D/R 10). Brûlage et coup forment UN seul
  ordre `fairDealOrder(remainingBefore, seed, 8)` ; `rounds/{n}.fairness.dealt` commence par la carte
  de brûlage et les cartes brûlées (révélées avec la preuve, pas pendant le coup).
- **Équité** comme le blackjack : à chaque coup, les cartes non distribuées (multiensemble, gardé trié
  dans `private/state`) sont repermutées par la graine du coup ; `remainingBefore` (n) = `remainingBefore`
  (n−1) − `dealt` (n−1), testé.
- **Paiements** : Banquier 0,95:1 exact (mises en dollars entiers ⇒ 95 cents par dollar). Égalité 8:1 et,
  sur égalité, Joueur et Banquier rendus. Paires 11:1 (même rang : R-D n'est pas une paire).
- **Limites** : mise min/max des paliers (`STAKE_TIER_LIMITS`) sur Joueur/Banquier ; égalité et paires
  plafonnées au cinquième du max (`limits.extra.sideMaxCents`, pour borner l'exposition à 8:1 / 11:1) ;
  chaque case non nulle ≥ min ; total d'un coup ≤ 2 × max. Miser Joueur ET Banquier est permis.
- **Pouvoir Commission offerte** : n'est accepté qu'avec une mise Banquier (sinon POWER_NOT_APPLICABLE) ;
  ce coup-là, un gain Banquier est payé 1:1. Compteur `commissionSaved` dans le profil.
- **Aucune action de jeu** : tout passe par `setBets` ; `{type:'none'}` est refusé (ILLEGAL_ACTION).
- **Une seule transaction pour la donne** (`closeBetting`) : cartes publiques (`g.coup`), événements pour
  l'animation, marchés par coup fermés ET résolus, compteurs du sabot, perles des tableaux de tendance.
  Puis phase `live`, étape `dealing`, dont la durée couvre l'animation (brûlage 2,6 s, 4 cartes × 0,65 s,
  3e carte 1,5 s chacune, révélation 2,6 s) ; le règlement se fait à l'échéance suivante.
- **Classement** : règle par défaut du noyau (couvrir Joueur et Banquier ne rapporte jamais de points).
  Mise en avant `jackpot` (fil d'actualité) : une égalité ou une paire gagnée.

### Marchés
- Par coup : « Le Banquier gagne ? » (une égalité vaut NON), « Égalité ? », « Une paire (Joueur ou
  Banquier) ? » ; ouverts pendant les mises, fermés et résolus dans la transaction de la donne.
- Long (tables simulées) : « Le Banquier gagne au moins 46 % des coups du sabot n°N ? » — dénominateur =
  tous les coups du sabot, égalités comprises (P(Banquier) = 45,86 % : marché proche de 50/50). Un marché
  par sabot (numéro de série = numéro du sabot), créé au premier coup, fermé à la moitié du sabot (comme
  le marché de sabot du blackjack), résolu dès que l'issue est certaine (borne : au plus
  ⌊(restantes − 17)/4⌋ + 1 coups restants), au plus tard au coup de la coupe.
- `fairEstimate` : probabilités EXACTES 8 jeux (énumération combinatoire sans remise : Banquier
  0,458597, Égalité 0,095156, une paire 0,143817) ; marché de sabot : approximation normale à partir
  des compteurs publics du sabot.

### Bots
- 7 % passent leur tour ; sinon Banquier (≈ 32 %), Joueur (≈ 33 %) ou « suivre la route » (30 % : le
  dernier gagnant hors égalité) ; égalité 9 %, chaque paire 6 %, à la mise minimale. Unités selon
  `betStyle` du profil.

### Tableaux de tendance
- Le serveur ne publie que les perles du sabot (`g.beads`, documentées dans `shared/games/baccarat.ts`) ;
  le client en dérive Bead Plate, Big Road (égalités marquées sur la case précédente, « queue de dragon »
  au-delà de 6) et Big Eye Boy.

### Monte-Carlo (graine fixe 20261126, 2 000 000 coups sur 25 042 vrais sabots, brûlage et coupe)
- Banquier 1,067 %, Joueur 1,226 %, Égalité 14,450 %, Paire Joueur 10,186 %, Paire Banquier 10,188 %.
- Valeurs exactes (énumération) : Banquier 1,0579 %, Joueur 1,2351 %, Égalité 14,36 %, paires 10,36 %.

## Demandes hors périmètre (avec contournement)

1. **`firebase/functions/test/unit/kernel/kernel.test.ts`** (a1), test « every game has a module file;
   phase-A stubs are unavailable and safe » : il exige `available === false` pour les 4 jeux et
   `availableGames() == []`. Le baccarat est maintenant disponible, donc ce test échoue sur cette branche
   (seul échec de `npm run test:unit`, 178/179 verts). À la fusion : n'y garder que les jeux encore en
   bouchon (ou tester `PRODUCTION_GAME_MODULES[g].game === g` seulement). Pas de contournement possible
   sans désactiver le jeu.
2. **`firebase/functions/test/integration/games.test.ts`** (a1), « every kernel game is "not available
   yet" » : même cause, échouera pour `baccarat` (non lancé ici, conformément aux consignes : je ne lance
   que `test/integration/baccarat*`). À retirer de la liste à la fusion.
