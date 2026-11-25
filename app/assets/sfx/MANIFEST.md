# Banque de sons — Vingt-Un

> Fichier généré par `node tools/sfx/generate.mjs` — ne pas éditer à la main.

Tous les sons sont **100 % synthétisés** (aucun échantillon externe) par `tools/sfx/` : additif, FM, bruit filtré,
enveloppes, réverbération Schroeder/Freeverb, écho, saturation douce. Rendu déterministe (graine dérivée du nom).

Format : WAV PCM 16 bits mono, 32 000 Hz (sons brillants : cloches, pièces) ou 22 050 Hz (graves, ambiance).
Crêtes : −1 dBFS pour les gros effets, −3 à −6 dBFS pour les sons de jeu, −8 à −12 dBFS pour l'interface.
Les variantes `_1.._n` sont à tirer au hasard pour éviter la répétition.
Les sons **bouclables** ont une jointure fondue enchaînée : les jouer en `ReleaseMode.loop` sans fondu supplémentaire.

## Cartes

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `card_deal_1.wav` | 0.28 s | 32000 Hz | -6 dBFS | — | Distribution d'une carte : glissement sur le feutre + petit choc (variante 1/4, à tirer au hasard). |
| `card_deal_2.wav` | 0.28 s | 32000 Hz | -6 dBFS | — | Distribution d'une carte : glissement sur le feutre + petit choc (variante 2/4, à tirer au hasard). |
| `card_deal_3.wav` | 0.28 s | 32000 Hz | -6 dBFS | — | Distribution d'une carte : glissement sur le feutre + petit choc (variante 3/4, à tirer au hasard). |
| `card_deal_4.wav` | 0.28 s | 32000 Hz | -6 dBFS | — | Distribution d'une carte : glissement sur le feutre + petit choc (variante 4/4, à tirer au hasard). |
| `card_flip_1.wav` | 0.16 s | 32000 Hz | -6 dBFS | — | Retournement d'une carte face visible (variante 1/2). |
| `card_flip_2.wav` | 0.16 s | 32000 Hz | -6 dBFS | — | Retournement d'une carte face visible (variante 2/2). |
| `card_reveal_hole.wav` | 1.70 s | 32000 Hz | -1 dBFS | — | Retournement dramatique de la carte cachée du croupier : mini-roulement + montée, claquement, accord de cuivres, timbale, paillettes. |
| `shuffle_riffle.wav` | 1.35 s | 32000 Hz | -5 dBFS | — | Mélange en queue d'aronde : fermeture du pouce, crépitement des 52 cartes, cascade du pont, tapotement pour égaliser le paquet. |
| `shuffle_bridge.wav` | 0.95 s | 32000 Hz | -5 dBFS | — | Pont (cascade des cartes qui retombent) puis égalisation du paquet. |
| `cards_collect.wav` | 0.90 s | 32000 Hz | -6 dBFS | — | Ramassage des cartes en fin de main : glissements superposés puis paquet tapoté. |

## Jetons

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `chip_clink_1.wav` | 0.20 s | 32000 Hz | -6 dBFS | — | Choc de deux jetons d'argile (variante 1/4, à tirer au hasard). |
| `chip_clink_2.wav` | 0.20 s | 32000 Hz | -6 dBFS | — | Choc de deux jetons d'argile (variante 2/4, à tirer au hasard). |
| `chip_clink_3.wav` | 0.20 s | 32000 Hz | -6 dBFS | — | Choc de deux jetons d'argile (variante 3/4, à tirer au hasard). |
| `chip_clink_4.wav` | 0.20 s | 32000 Hz | -6 dBFS | — | Choc de deux jetons d'argile (variante 4/4, à tirer au hasard). |
| `chip_stack.wav` | 0.55 s | 32000 Hz | -5 dBFS | — | Empilement rapide de 5 jetons. |
| `chip_bet_place.wav` | 0.30 s | 32000 Hz | -5 dBFS | — | Pose d'une mise sur le tapis. |
| `chips_push_win.wav` | 1.15 s | 32000 Hz | -3 dBFS | — | Le croupier pousse la pile de gains vers le joueur : frottement sur le feutre + cliquetis. |
| `chips_rake_lose.wav` | 1.00 s | 32000 Hz | -4 dBFS | — | Le râteau du croupier ramasse la mise perdue : raclement descendant + jetons qui s'éloignent. |
| `chip_allin.wav` | 1.80 s | 32000 Hz | -1 dBFS | — | Tapis ! Avalanche de jetons poussés d'un coup, grosse caisse, timbale, coup de cuivres, cymbale. |

## Actions

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `action_hit.wav` | 0.25 s | 32000 Hz | -6 dBFS | — | Tirer (« carte ! ») : tapotement du doigt sur le feutre + petit claquement. |
| `action_stand.wav` | 0.40 s | 22050 Hz | -5 dBFS | — | Rester : double toc-toc sur la table. |
| `action_double.wav` | 1.35 s | 32000 Hz | -2 dBFS | — | Doubler : coup de tambour + montée + coup de cuivres. |
| `action_split.wav` | 0.85 s | 32000 Hz | -3 dBFS | — | Séparer : lame tranchante « shhing » puis deux cartes qui s'écartent. |
| `action_surrender.wav` | 1.00 s | 22050 Hz | -10 dBFS | — | Abandon : sifflet à coulisse qui dégringole (drapeau blanc comique). |
| `action_insurance.wav` | 1.00 s | 32000 Hz | -4 dBFS | — | Assurance : choc sourd protecteur + carillon « bouclier ». |

## Résultats

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `win_small.wav` | 1.00 s | 32000 Hz | -3 dBFS | — | Petite victoire : arpège brillant + jetons + paillettes. |
| `win_medium.wav` | 1.80 s | 32000 Hz | -1 dBFS | — | Victoire moyenne : arpège sur deux octaves, cloches, pièces, paillettes. |
| `win_big.wav` | 3.00 s | 32000 Hz | -1 dBFS | — | Grosse victoire : fanfare « ta-ta-ta-taaa », timbale, cymbale, cloches, pluie de pièces. |
| `blackjack_jackpot.wav` | 4.00 s | 32000 Hz | -1 dBFS | — | BLACKJACK ! Carillon de cloches, sirène de jackpot, cuivres, cascade de pièces, foule en délire. |
| `push_tie.wav` | 0.80 s | 32000 Hz | -6 dBFS | — | Égalité : deux notes neutres identiques, discrètes. |
| `lose_hand.wav` | 1.20 s | 22050 Hz | -8 dBFS | — | Main perdue : « bwom-bwooomp » de trombone bouché, comique. |
| `bust.wav` | 2.90 s | 22050 Hz | -6 dBFS | — | Sauté (>21) : buzzer de jeu télévisé puis trombone triste « wah-wah-wah-waaaah ». |
| `dealer_bust.wav` | 2.40 s | 22050 Hz | -1 dBFS | — | Le croupier saute : « ta-daa » de cuivres + foule qui acclame. |
| `dealer_blackjack.wav` | 2.80 s | 22050 Hz | -1 dBFS | — | Blackjack du croupier : « dun-dun-DUNNN » dramatique (accord diminué, timbales). |
| `win_streak_3.wav` | 1.60 s | 32000 Hz | -1 dBFS | — | Série de 3 victoires : montée « combo » 8-bit + coup de cuivres + pièces. |
| `win_streak_5.wav` | 2.80 s | 32000 Hz | -1 dBFS | — | Série de 5 victoires : double montée 8-bit, sirène, fanfare, foule, pièces. |

## Tension

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `drumroll_short.wav` | 1.80 s | 22050 Hz | -2 dBFS | — | Roulement de caisse claire en crescendo terminé par grosse caisse + cymbale. |
| `drumroll_long.wav` | 2.00 s | 22050 Hz | -4 dBFS | oui | Roulement de caisse claire continu, BOUCLABLE (attente du tirage du croupier, suspense). |
| `timer_tick.wav` | 0.12 s | 32000 Hz | -8 dBFS | — | Tic du compte à rebours (temps de décision). |
| `timer_urgent.wav` | 0.32 s | 32000 Hz | -5 dBFS | — | Tic urgent des dernières secondes : double tic aigu + bip. |
| `timeout.wav` | 1.30 s | 22050 Hz | -2 dBFS | — | Temps écoulé : tonalité qui chute + buzzer + timbale grave. |

## Argent

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `cash_register_kaching.wav` | 1.60 s | 32000 Hz | -1 dBFS | — | Dépôt : caisse enregistreuse « ka-ching » (mécanisme, tiroir, clochette, pièces). |
| `coin_shower.wav` | 2.60 s | 32000 Hz | -1 dBFS | — | Pluie de pièces (2,6 s) : gros gain, bonus. |
| `coin_single.wav` | 0.60 s | 32000 Hz | -4 dBFS | — | Une pièce qui tombe et rebondit. |
| `withdraw_whoosh.wav` | 0.90 s | 32000 Hz | -3 dBFS | — | Retrait : souffle + billets qui s'envolent + petit arpège descendant. |
| `welcome_bonus.wav` | 2.80 s | 32000 Hz | -1 dBFS | — | Bonus de bienvenue : fanfare montante, cloches, cymbale, pluie de pièces, paillettes. |

## Pouvoirs

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `power_free_split.wav` | 1.30 s | 32000 Hz | -1 dBFS | — | Pouvoir « séparation gratuite » : double lame, rayons divergents, cartes, paillettes. |
| `power_free_double.wav` | 1.30 s | 32000 Hz | -1 dBFS | — | Pouvoir « double gratuit » : montée 8-bit sur 3 octaves + double coup de grosse caisse « ×2 » + cuivres. |
| `power_free_insurance.wav` | 1.60 s | 32000 Hz | -2 dBFS | — | Pouvoir « assurance gratuite » : bouclier qui s'active (vrombissement grave + nappe lumineuse + carillons). |
| `power_peek.wav` | 1.80 s | 32000 Hz | -3 dBFS | — | Pouvoir « coup d'œil » : mystérieux (thérémine, glissando par tons entiers, bourdon grave). |
| `power_second_chance.wav` | 1.80 s | 32000 Hz | -2 dBFS | — | Pouvoir « seconde chance » : rembobinage (son joué à l'envers en décélérant, effet bande) puis redémarrage lumineux. |
| `power_buy.wav` | 1.20 s | 32000 Hz | -2 dBFS | — | Achat d'un pouvoir : ka-ching court + montée + paillettes. |

## Progression

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `rank_up.wav` | 3.40 s | 32000 Hz | -1 dBFS | — | Montée de rang : roulement de timbales, grande fanfare I-IV-V-I, cymbales, cloches, pièces. |
| `leaderboard_climb.wav` | 1.50 s | 32000 Hz | -3 dBFS | — | Remontée au classement : gamme montante + souffle ascendant + cloche. |
| `kyc_verified.wav` | 1.10 s | 32000 Hz | -3 dBFS | — | Identité vérifiée : coup de tampon + deux notes « validé » + paillettes. |
| `achievement.wav` | 1.90 s | 32000 Hz | -2 dBFS | — | Succès débloqué : arpège, cloche, nappe, paillettes. |

## Marchés

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `trade_buy.wav` | 0.45 s | 32000 Hz | -5 dBFS | — | Achat d'une position : « bloop » montant + pièce. |
| `trade_sell.wav` | 0.50 s | 32000 Hz | -5 dBFS | — | Vente d'une position : « bloop » descendant + jeton + clochette. |
| `market_resolved_win.wav` | 1.60 s | 32000 Hz | -2 dBFS | — | Marché résolu en votre faveur : mini-fanfare + pièces + cloche. |
| `market_resolved_lose.wav` | 1.30 s | 22050 Hz | -6 dBFS | — | Marché résolu en votre défaveur : trois accords de cuivres sourds qui descendent chromatiquement. |
| `price_tick_up.wav` | 0.09 s | 32000 Hz | -12 dBFS | — | Cote qui monte (micro-blip, très fréquent). |
| `price_tick_down.wav` | 0.09 s | 32000 Hz | -12 dBFS | — | Cote qui baisse (micro-blip, très fréquent). |

## Social

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `friend_request.wav` | 0.95 s | 32000 Hz | -4 dBFS | — | Demande d'ami reçue : sonnette « ding-dong ». |
| `friend_accept.wav` | 0.90 s | 32000 Hz | -4 dBFS | — | Ami accepté : arpège joyeux + paillettes. |
| `ad_reward.wav` | 1.50 s | 32000 Hz | -2 dBFS | — | Récompense après une pub : montée + pièces + clochette + paillettes. |
| `ad_interstitial_sting.wav` | 1.20 s | 32000 Hz | -2 dBFS | — | Jingle d'entrée d'une pub interstitielle : souffle + coup de cuivres + cymbale. |

## Interface

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `ui_tap.wav` | 0.06 s | 32000 Hz | -12 dBFS | — | Appui sur un bouton (très fréquent, discret). |
| `ui_chip_tap.wav` | 0.12 s | 32000 Hz | -9 dBFS | — | Appui n'importe où dans l'appli (très fréquent) : petit clic net de jeton en céramique + soupçon de scintillement. |
| `ui_toggle.wav` | 0.10 s | 32000 Hz | -12 dBFS | — | Interrupteur / case à cocher. |
| `ui_error.wav` | 0.35 s | 22050 Hz | -11 dBFS | — | Erreur / action impossible : double « bonk » grave. |
| `ui_success.wav` | 0.50 s | 32000 Hz | -8 dBFS | — | Validation réussie : deux notes cristallines montantes. |
| `nav_swoosh.wav` | 0.30 s | 32000 Hz | -10 dBFS | — | Changement d'écran / glissement de panneau. |
| `matchmaking_search.wav` | 2.40 s | 32000 Hz | -8 dBFS | oui | Recherche d'une table, BOUCLABLE : pings type sonar + nappe douce (période 2,4 s). |
| `matchmaking_found.wav` | 1.20 s | 32000 Hz | -3 dBFS | — | Table trouvée : arpège montant + coup de cuivres + paillettes. |
| `seat_join.wav` | 0.60 s | 32000 Hz | -6 dBFS | — | Un joueur s'assoit à la table : jeton posé + petit carillon. |

## Ambiance

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `ambience_casino_loop.wav` | 10.00 s | 22050 Hz | -6 dBFS | oui | Fond sonore de casino, BOUCLABLE (10 s) : brouhaha de foule, machines à sous lointaines, pièces et jetons, réverbération de grande salle. |
| `slot_reel_spin.wav` | 1.00 s | 22050 Hz | -6 dBFS | oui | Rouleaux de machine à sous qui tournent, BOUCLABLE : cliquet 20 Hz + ronronnement moteur. |
| `slot_reel_stop.wav` | 0.50 s | 32000 Hz | -4 dBFS | — | Arrêt d'un rouleau de machine à sous : « clonk » + cliquet + petite clochette. |
| `ambience_slots_loop.wav` | 8.00 s | 22050 Hz | -14 dBFS | oui | Salle des machines à sous au loin, BOUCLABLE (8 s), couche discrète à jouer sous ambience_casino_loop : petits jingles épars, carillons, rouleaux qui s'arrêtent, pièces, ronronnement grave. |

## Las Vegas

| Fichier | Durée | Fréq. | Crête | Boucle | Usage prévu |
|---|---:|---:|---:|:---:|---|
| `vegas_intro.wav` | 3.20 s | 32000 Hz | -1 dBFS | — | « Bienvenue à Las Vegas » à l'arrivée dans le hall : levier de machine à sous (cliquet), rouleaux qui tournent, trois arrêts « clonk » (1,0 / 1,25 / 1,5 s), puis sonnerie de jackpot, « ta-da » de cuivres, pluie de pièces, foule en liesse, paillettes. |
| `slot_jackpot_bells.wav` | 2.60 s | 32000 Hz | -2 dBFS | — | Paiement d'une machine à sous : sonnerie mécanique de jackpot à deux timbres (~12 coups/s) + pièces qui dégringolent dans le bac métallique, puis extinction. |
| `crowd_cheer.wav` | 1.80 s | 22050 Hz | -3 dBFS | — | La table acclame : « ouais ! » collectif, applaudissements et un sifflet. |
| `crowd_ooh.wav` | 1.40 s | 22050 Hz | -5 dBFS | — | La table compatit : « ooooh » qui retombe (joueur qui saute, blackjack du croupier). |

Total : 83 fichiers, 6.25 Mio.
