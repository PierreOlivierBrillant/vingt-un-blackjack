# Banque de sons — groupe « holdem »

> Fichier généré par `node tools/sfx/generate.mjs` — ne pas éditer à la main.

Source : `tools/sfx/games/holdem.mjs` (mode d'emploi : `tools/sfx/catalog.mjs`). Mêmes conventions que
`MANIFEST.md` (WAV PCM 16 bits mono, 32 000 ou 22 050 Hz) ; les **boucles** sont en 22 050 Hz.

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `holdem_check_knock.wav` | 0.32 s | 32000 Hz | -8 dBFS | — | Un joueur dit « parole » en tapant deux fois sur la table. |
| `holdem_card_pitch.wav` | 0.20 s | 32000 Hz | -9 dBFS | — | Pitch d'une carte (cartes privées, cartes du tableau qui quittent le paquet). |
| `holdem_card_burn.wav` | 0.24 s | 32000 Hz | -11 dBFS | — | Le croupier brûle une carte avant le flop, la turn ou la river. |
| `holdem_board_flip.wav` | 0.22 s | 32000 Hz | -8 dBFS | — | Retournement des cartes du tableau ou de vos cartes privées. |
| `holdem_chips_bet.wav` | 0.34 s | 32000 Hz | -7 dBFS | — | Blind, mise, relance ou suivi : jetons poussés devant le joueur. |
| `holdem_chips_collect.wav` | 0.60 s | 32000 Hz | -6 dBFS | — | Fin d'un tour d'enchères : le croupier rassemble les mises dans le pot. |
| `holdem_all_in.wav` | 0.95 s | 32000 Hz | -3 dBFS | — | Un joueur fait tapis. |
| `holdem_fold.wav` | 0.26 s | 32000 Hz | -11 dBFS | — | Un joueur se couche : ses cartes glissent vers le croupier. |
| `holdem_showdown.wav` | 0.70 s | 32000 Hz | -6 dBFS | — | Abattage : les mains encore en jeu sont retournées. |
| `holdem_pot_win.wav` | 0.75 s | 32000 Hz | -5 dBFS | — | Le croupier pousse le pot (ou un pot annexe) vers le gagnant. |
| `holdem_your_turn.wav` | 0.36 s | 32000 Hz | -12 dBFS | — | C'est à vous de parler. |

Total : 11 fichier(s), 0.30 Mio sur un quota de 0.85 Mio.
