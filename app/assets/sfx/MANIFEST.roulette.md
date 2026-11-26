# Banque de sons — groupe « roulette »

> Fichier généré par `node tools/sfx/generate.mjs` — ne pas éditer à la main.

Source : `tools/sfx/games/roulette.mjs` (mode d'emploi : `tools/sfx/catalog.mjs`). Mêmes conventions que
`MANIFEST.md` (WAV PCM 16 bits mono, 32 000 ou 22 050 Hz) ; les **boucles** sont en 22 050 Hz.

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `roulette_ball_tick.wav` | 0.16 s | 32000 Hz | -8 dBFS | — | La bille heurte une frette du cylindre (tic métallique court), en rafale pendant les rebonds. |
| `roulette_spin_loop.wav` | 2.00 s | 22050 Hz | -9 dBFS | oui | Bille qui roule sur la piste du cylindre, BOUCLABLE (2 s) : grondement boisé + léger sifflement, pendant le lancer. |
| `roulette_ball_launch.wav` | 0.50 s | 32000 Hz | -6 dBFS | — | Lancer de la bille par la croupière (pichenette + souffle rapide). |
| `roulette_ball_drop.wav` | 0.70 s | 32000 Hz | -5 dBFS | — | La bille tombe et se cale dans la case gagnante (cliquetis décroissant). |
| `roulette_place_bets.wav` | 0.90 s | 32000 Hz | -8 dBFS | — | « Faites vos jeux » : carillon montant à l'ouverture des mises. |
| `roulette_no_more_bets.wav` | 1.20 s | 32000 Hz | -6 dBFS | — | « Rien ne va plus » : ding-dong descendant au tirage. |
| `roulette_chip_place.wav` | 0.18 s | 32000 Hz | -9 dBFS | — | Un jeton posé sur le tapis (tap sur une case). |
| `roulette_dolly.wav` | 0.35 s | 32000 Hz | -7 dBFS | — | Le dolly posé sur le numéro gagnant (choc sourd + tintement cristallin). |
| `roulette_rake.wav` | 0.80 s | 22050 Hz | -7 dBFS | — | Le râteau ramasse les jetons perdants (frottement sur le feutre + jetons qui s'entrechoquent). |
| `roulette_payout.wav` | 0.60 s | 32000 Hz | -7 dBFS | — | Paiement d'un gagnant : jetons comptés et poussés vers sa place. |
| `roulette_straight_win.wav` | 1.80 s | 32000 Hz | -3 dBFS | — | Plein gagnant (35:1) : arpège de cloches, paillettes et pluie de jetons. |
| `roulette_zero.wav` | 1.20 s | 32000 Hz | -5 dBFS | — | Le zéro sort : coup de timbale grave et cloche (les chances simples perdent, sauf bouclier). |

Total : 12 fichier(s), 0.58 Mio sur un quota de 1.25 Mio.
