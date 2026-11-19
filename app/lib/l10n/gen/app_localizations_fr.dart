// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get accept => 'Accepter';

  @override
  String get decline => 'Refuser';

  @override
  String get back => 'Retour';

  @override
  String get close => 'Fermer';

  @override
  String get save => 'Enregistrer';

  @override
  String get play => 'Jouer';

  @override
  String get watch => 'Regarder';

  @override
  String get live => 'EN DIRECT';

  @override
  String get you => 'Vous';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';

  @override
  String get buy => 'Acheter';

  @override
  String get sell => 'Vendre';

  @override
  String get amount => 'Montant';

  @override
  String get online => 'En ligne';

  @override
  String get offline => 'Hors ligne';

  @override
  String get chance => 'chance';

  @override
  String get errorGeneric => 'Une erreur est survenue. Réessayez.';

  @override
  String get errorInsufficientFunds => 'Solde insuffisant.';

  @override
  String get errorLimit => 'Plafond atteint.';

  @override
  String get errorKycRequired => 'Vérification d\'identité requise.';

  @override
  String get errorRateLimited => 'Trop de requêtes, patientez un instant.';

  @override
  String get errorUnavailable => 'Serveur injoignable.';

  @override
  String get simulationBanner =>
      'SIMULATION — argent fictif uniquement, aucune valeur réelle.';

  @override
  String get fakeMoneyDisclaimer =>
      'Jeu d\'entraînement en argent 100 % fictif. Aucun gain réel, aucun paiement réel.';

  @override
  String handNumber(int n) {
    return 'Main n° $n';
  }

  @override
  String agoSeconds(int n) {
    return 'il y a $n s';
  }

  @override
  String agoMinutes(int n) {
    return 'il y a $n min';
  }

  @override
  String agoHours(int n) {
    return 'il y a $n h';
  }

  @override
  String agoDays(int n) {
    return 'il y a $n j';
  }

  @override
  String get loginTagline =>
      'Blackjack multijoueur, croupier en direct, argent fictif.';

  @override
  String get loginTitle => 'Connexion';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Mot de passe';

  @override
  String get showPassword => 'Afficher le mot de passe';

  @override
  String get signIn => 'Se connecter';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get validationEmail => 'Adresse e-mail invalide.';

  @override
  String get validationPasswordShort => '6 caractères minimum.';

  @override
  String get validationUsername =>
      '3 à 16 caractères : lettres, chiffres, _ ou .';

  @override
  String get authErrorInvalid => 'E-mail ou mot de passe incorrect.';

  @override
  String get authErrorEmailInUse => 'Cet e-mail est déjà utilisé.';

  @override
  String get authErrorWeakPassword => 'Mot de passe trop faible.';

  @override
  String get authErrorUsernameTaken => 'Ce pseudo est déjà pris.';

  @override
  String get authErrorNetwork => 'Impossible de joindre le serveur.';

  @override
  String get signupTitle => 'Créer un compte';

  @override
  String signupBonus(String amount) {
    return 'Bonus de bienvenue : $amount fictifs offerts';
  }

  @override
  String get username => 'Pseudo';

  @override
  String get usernameHelp => 'Visible par les autres joueurs';

  @override
  String get passwordHelp =>
      '8 caractères minimum, dont une lettre et un chiffre.';

  @override
  String get signupAdultCheckbox =>
      'J\'ai 18 ans ou plus et je comprends que l\'argent est fictif.';

  @override
  String get signupMustBeAdult => 'Vous devez confirmer avoir 18 ans ou plus.';

  @override
  String get serverTitle => 'Serveur';

  @override
  String get serverIntro =>
      'Adresse du poste qui fait tourner les émulateurs Firebase (Auth 9099, Firestore 8080, Functions 5001). En classe : l\'IP du poste enseignant.';

  @override
  String get serverHostLabel => 'Hôte (IP ou nom)';

  @override
  String get serverHostInvalid =>
      'Saisissez une IP ou un nom d\'hôte, sans http:// ni port.';

  @override
  String serverCurrentCustom(String host) {
    return 'Actuel : $host (personnalisé)';
  }

  @override
  String serverCurrentDefault(String host) {
    return 'Actuel : $host (par défaut)';
  }

  @override
  String get serverTest => 'Tester';

  @override
  String serverReset(String host) {
    return 'Revenir à $host';
  }

  @override
  String get serverSaved => 'Serveur enregistré.';

  @override
  String get serverUnreachable => 'injoignable';

  @override
  String get serverAllOk => 'Tous les services répondent.';

  @override
  String get serverSomeDown =>
      'Certains services ne répondent pas : l\'app reste utilisable hors ligne.';

  @override
  String get serverHelpTitle => 'Aide';

  @override
  String get serverHelpBody =>
      '10.0.2.2 désigne l\'ordinateur hôte depuis l\'émulateur Android. Sur le réseau de la classe, utilisez l\'IP affichée par le script du poste enseignant.';

  @override
  String get kycTitle => 'Vérification d\'identité';

  @override
  String get kycSimulationBanner =>
      'SIMULATION — aucune photo n\'est prise, aucun document n\'est envoyé.';

  @override
  String get kycIntro =>
      'Requise avant tout dépôt ou retrait. Les mineurs sont refusés.';

  @override
  String get kycDocType => 'Type de pièce';

  @override
  String get kycIdCard => 'Carte d\'identité';

  @override
  String get kycPassport => 'Passeport';

  @override
  String get kycLicense => 'Permis';

  @override
  String get kycFullName => 'Nom complet';

  @override
  String get kycBirthDate => 'Date de naissance';

  @override
  String get kycChooseDate => 'Choisir une date';

  @override
  String get kycFormIncomplete =>
      'Renseignez votre nom et votre date de naissance.';

  @override
  String get kycStartScan => 'Lancer le scan';

  @override
  String get kycScanning => 'Analyse du document…';

  @override
  String get kycStepEdges => 'Détection des bords';

  @override
  String get kycStepMrz => 'Lecture de la bande MRZ';

  @override
  String get kycStepFace => 'Comparaison du visage';

  @override
  String get kycStepAge => 'Contrôle de l\'âge';

  @override
  String get kycPending => 'En attente';

  @override
  String get kycPendingBody => 'Votre dossier est en cours d\'examen.';

  @override
  String get kycVerified => 'Vérifié';

  @override
  String get kycVerifiedBody =>
      'Identité vérifiée. Dépôts et retraits débloqués.';

  @override
  String get kycRejected => 'Refusé';

  @override
  String get kycRejectedBody =>
      'Vérification refusée : vous devez avoir 18 ans ou plus.';

  @override
  String get kycNotStarted => 'Non vérifié';

  @override
  String get kycGoToWallet => 'Aller au portefeuille';

  @override
  String get walletTitle => 'Portefeuille';

  @override
  String get walletBalance => 'Solde disponible';

  @override
  String get walletInPlay => 'En jeu';

  @override
  String get walletDepositLimit => 'Dépôts du jour';

  @override
  String get walletHistory => 'Historique';

  @override
  String get walletKycNeeded =>
      'Vérifiez votre identité pour déposer ou retirer.';

  @override
  String get deposit => 'Déposer';

  @override
  String get withdraw => 'Retirer';

  @override
  String get depositConfirm => 'Confirmer le dépôt simulé';

  @override
  String get withdrawConfirm => 'Confirmer le retrait simulé';

  @override
  String depositDone(String amount) {
    return 'Dépôt simulé de $amount effectué.';
  }

  @override
  String withdrawDone(String amount) {
    return 'Retrait simulé de $amount effectué.';
  }

  @override
  String get paymentSimulationBanner =>
      'SIMULATION — numéro de test pré-rempli, non modifiable. Aucune donnée bancaire n\'est demandée ni transmise.';

  @override
  String get paymentTestValue => 'Valeur de test fixe';

  @override
  String get paymentAmountInvalid => 'Montant invalide (minimum 1,00 \$).';

  @override
  String get methodCard => 'Carte';

  @override
  String get methodCrypto => 'Crypto';

  @override
  String get methodBank => 'Virement';

  @override
  String get cardNumber => 'Numéro de carte (test)';

  @override
  String get cardExpiry => 'Expiration';

  @override
  String get cardCvc => 'CVC';

  @override
  String get cryptoAddress => 'Adresse (test)';

  @override
  String get iban => 'IBAN (test)';

  @override
  String get ledgerWelcome => 'Bonus de bienvenue';

  @override
  String get ledgerDeposit => 'Dépôt simulé';

  @override
  String get ledgerWithdrawal => 'Retrait simulé';

  @override
  String get ledgerBet => 'Mise';

  @override
  String get ledgerWin => 'Gain';

  @override
  String get ledgerPush => 'Égalité';

  @override
  String get ledgerPower => 'Achat de pouvoir';

  @override
  String get ledgerTrade => 'Ordre sur un marché';

  @override
  String get ledgerMarketPayout => 'Règlement de marché';

  @override
  String get ledgerAd => 'Récompense publicitaire';

  @override
  String get navLobby => 'Salon';

  @override
  String get navMarkets => 'Marchés';

  @override
  String get navLeaderboard => 'Classement';

  @override
  String get navWallet => 'Portefeuille';

  @override
  String get navProfile => 'Profil';

  @override
  String get lobbyHeroTitle => 'Blackjack en direct';

  @override
  String get lobbyHeroSubtitle =>
      '5 places, un croupier qui distribue pour de vrai. Le blackjack paie 3 pour 2.';

  @override
  String get lobbyQuickPlay => 'Partie rapide';

  @override
  String get lobbyDealerDemo => 'Démo du croupier';

  @override
  String get lobbyStakes => 'Niveaux de mise';

  @override
  String get lobbyLiveTables => 'Tables en direct';

  @override
  String get lobbyAllTiers => 'Tous';

  @override
  String lobbyTierStats(int tables, int players) {
    return '$tables tables · $players joueurs';
  }

  @override
  String get tierMicro => 'Micro';

  @override
  String get tierLow => 'Bas';

  @override
  String get tierMid => 'Moyen';

  @override
  String get tierHigh => 'Haut';

  @override
  String get tierVip => 'VIP';

  @override
  String get tableFull => 'Complet';

  @override
  String get winKindBlackjack => 'blackjack';

  @override
  String get winKindDouble => 'double gagné';

  @override
  String get winKindSplit => 'split gagné';

  @override
  String get winKindMarket => 'pari spectateur';

  @override
  String get winKindWin => 'main gagnée';

  @override
  String get feltPayout => 'LE BLACKJACK PAIE 3 POUR 2';

  @override
  String get feltInsurance => 'ASSURANCE PAIE 2 POUR 1';

  @override
  String get feltRule => 'Le croupier reste sur tout 17';

  @override
  String get seatOpen => 'Libre';

  @override
  String get badgeBlackjack => 'BLACKJACK';

  @override
  String get badgeBust => 'SAUTÉ';

  @override
  String get badgeWin => 'GAGNÉ';

  @override
  String get badgeLose => 'PERDU';

  @override
  String get badgePush => 'ÉGALITÉ';

  @override
  String get actionHit => 'Tirer';

  @override
  String get actionStand => 'Rester';

  @override
  String get actionDouble => 'Doubler';

  @override
  String get actionSplit => 'Séparer';

  @override
  String get actionSurrender => 'Abandon';

  @override
  String get actionInsurance => 'Assurance';

  @override
  String actionSent(String action) {
    return 'Action envoyée : $action';
  }

  @override
  String get fairTitle => 'Équité vérifiable';

  @override
  String get fairBody =>
      'Avant chaque main, le serveur publie l\'empreinte SHA-256 d\'une graine secrète. Après la main, il révèle la graine : on peut recalculer l\'ordre exact des cartes.';

  @override
  String get leaveTable => 'Quitter la table';

  @override
  String get powers => 'Pouvoirs';

  @override
  String get powersSheetTitle => 'Utiliser un pouvoir';

  @override
  String get powersSheetHint =>
      'Un seul pouvoir par main, validé par le serveur.';

  @override
  String get dealerDemoTitle => 'Démo du croupier';

  @override
  String get dealerIdle => 'En attente';

  @override
  String dealerQueue(int n, String seconds) {
    return '$n en file · $seconds s';
  }

  @override
  String get dealerSpeed => 'Vitesse';

  @override
  String get dealerLoop => 'Boucle';

  @override
  String get dealerPlayRound => 'Jouer une main';

  @override
  String get dealerShuffle => 'Mélanger';

  @override
  String get dealerReset => 'Réinitialiser';

  @override
  String dealerRounds(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n mains jouées',
      one: '1 main jouée',
      zero: 'Aucune main jouée',
    );
    return '$_temp0';
  }

  @override
  String get shopTitle => 'Boutique de pouvoirs';

  @override
  String get shopSubtitle => 'Split gratuit, coup d\'œil, seconde chance…';

  @override
  String get shopIntro =>
      'Payés en argent fictif. Un pouvoir par main, toujours validé par le serveur.';

  @override
  String shopOwned(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n en stock',
      one: '1 en stock',
      zero: 'Aucun en stock',
    );
    return '$_temp0';
  }

  @override
  String shopBought(String name) {
    return '$name ajouté à votre inventaire.';
  }

  @override
  String get powerFreeSplit => 'Split gratuit';

  @override
  String get powerFreeSplitDesc =>
      'Séparez une paire sans miser une seconde fois.';

  @override
  String get powerFreeDouble => 'Double gratuit';

  @override
  String get powerFreeDoubleDesc => 'Doublez sans ajouter de mise.';

  @override
  String get powerFreeInsurance => 'Assurance gratuite';

  @override
  String get powerFreeInsuranceDesc =>
      'Assurance offerte quand le croupier montre un As.';

  @override
  String get powerPeek => 'Coup d\'œil';

  @override
  String get powerPeekDesc => 'Voyez la carte cachée du croupier (vous seul).';

  @override
  String get powerSecondChance => 'Seconde chance';

  @override
  String get powerSecondChanceDesc => 'Remplace la dernière carte tirée.';

  @override
  String get customizeTitle => 'Personnalisation';

  @override
  String get customizeSubtitle => 'Dos de cartes, faces, tapis';

  @override
  String get customizeFaces => 'Style des faces';

  @override
  String get customizeBacks => 'Motif du dos';

  @override
  String get customizeBackColor => 'Couleur du dos';

  @override
  String get customizeFelt => 'Tapis';

  @override
  String get customizeEquip => 'Équiper';

  @override
  String get customizeEquipped => 'Équipé';

  @override
  String get customizeSaved => 'Style équipé.';

  @override
  String get faceClassic => 'Classique';

  @override
  String get faceFourColor => '4 couleurs';

  @override
  String get faceNeon => 'Néon';

  @override
  String get backLattice => 'Treillis';

  @override
  String get backStripes => 'Rayures';

  @override
  String get backChevron => 'Chevrons';

  @override
  String get backDots => 'Pois';

  @override
  String get backSunburst => 'Soleil';

  @override
  String get feltGreen => 'Vert casino';

  @override
  String get feltNavy => 'Bleu nuit';

  @override
  String get feltCrimson => 'Pourpre';

  @override
  String get feltPurple => 'Violet';

  @override
  String get feltCharcoal => 'Anthracite';

  @override
  String get leaderboardTitle => 'Classement';

  @override
  String get lbGlobal => 'Global';

  @override
  String get lbFriends => 'Amis';

  @override
  String get lbWeekly => 'Semaine';

  @override
  String get lbPointsRule =>
      'Victoire +10 · Blackjack +15 · Égalité +2 · Défaite −4. Paliers : Bronze → Diamant.';

  @override
  String lbHandsWinRate(int hands, String rate) {
    final intl.NumberFormat handsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String handsString = handsNumberFormat.format(hands);

    return '$handsString mains · $rate de victoires';
  }

  @override
  String lbPoints(String points) {
    return '$points pts';
  }

  @override
  String get tierBronze => 'Bronze';

  @override
  String get tierSilver => 'Argent';

  @override
  String get tierGold => 'Or';

  @override
  String get tierPlatinum => 'Platine';

  @override
  String get tierDiamond => 'Diamant';

  @override
  String get friendsTitle => 'Amis';

  @override
  String get friendsSearchHint => 'Rechercher un pseudo';

  @override
  String get friendsAdd => 'Ajouter';

  @override
  String friendsRequestSent(String name) {
    return 'Demande envoyée à $name.';
  }

  @override
  String friendsRequests(int n) {
    return 'Demandes ($n)';
  }

  @override
  String get friendsWantsToAdd => 'veut vous ajouter';

  @override
  String get friendsList => 'Mes amis';

  @override
  String friendsAtTable(String table) {
    return 'Joue à $table';
  }

  @override
  String get marketsTitle => 'Marchés';

  @override
  String get marketsPortfolio => 'Valeur du portefeuille';

  @override
  String get marketsPnl => 'Gain / perte';

  @override
  String get filterAll => 'Tous';

  @override
  String get filterHand => 'Par main';

  @override
  String get filterShoe => 'Par sabot';

  @override
  String get filterMine => 'Mes positions';

  @override
  String get mqDealerBusts => 'Le croupier saute ?';

  @override
  String mqPlayerWins(String player) {
    return '$player gagne ?';
  }

  @override
  String get mqNatural => 'Un blackjack naturel ?';

  @override
  String get mqShoe =>
      'Le croupier saute dans au moins 28 % des mains de ce sabot ?';

  @override
  String get marketPerShoe => 'sabot en cours';

  @override
  String marketVolume(String volume) {
    return 'Vol. $volume';
  }

  @override
  String get marketResolvedYes => 'Résolu : OUI';

  @override
  String get marketResolvedNo => 'Résolu : NON';

  @override
  String get marketTitle => 'Marché';

  @override
  String marketChanceLabel(String pct) {
    return '$pct de chance';
  }

  @override
  String get marketWatchTable => 'Voir la table';

  @override
  String get marketClosedNotice => 'Ce marché est clos.';

  @override
  String get marketYourPositions => 'Vos positions';

  @override
  String positionShares(int n, String price) {
    return '$n parts · moy. $price';
  }

  @override
  String positionValue(String value) {
    return 'Valeur : $value';
  }

  @override
  String get marketActivity => 'Activité';

  @override
  String get tradeBought => 'a acheté';

  @override
  String get tradeSold => 'a vendu';

  @override
  String get marketRules => 'Règles';

  @override
  String get marketRulesBody =>
      'Chaque part gagnante paie 1,00 \$ fictif. Les prix sont fixés par un teneur de marché automatique (LMSR). Le marché ferme avant que le croupier ne révèle sa carte. Interdit sur votre propre table.';

  @override
  String get shares => 'Parts';

  @override
  String get ticketAvgPrice => 'Prix moyen';

  @override
  String get ticketCost => 'Coût';

  @override
  String get ticketProceeds => 'Vous recevez';

  @override
  String get ticketPayout => 'Gain si victoire';

  @override
  String get ticketPriceAfter => 'Prix après l\'ordre';

  @override
  String ticketSubmit(String side, String outcome) {
    return '$side $outcome';
  }

  @override
  String get ticketDone => 'Ordre envoyé.';

  @override
  String get ticketDisclaimer =>
      'Estimation : le prix final est calculé par le serveur.';

  @override
  String get adLabel => 'PUB';

  @override
  String get adsTitle => 'Fausses publicités';

  @override
  String get adsIntro =>
      'Publicités parodiques, sans lien ni pistage : bannière, interstitiel et vidéo récompensée.';

  @override
  String get adsShowInterstitial => 'Afficher un interstitiel';

  @override
  String get adsShowRewarded => 'Regarder une vidéo récompensée';

  @override
  String get adCoinTagline =>
      'La crypto qui ne monte jamais, garantie sans surprise.';

  @override
  String get adCoinCta => 'Ne pas acheter';

  @override
  String get adBankTagline =>
      'Des intérêts imaginaires sur votre argent imaginaire.';

  @override
  String get adBankCta => 'Ouvrir un faux compte';

  @override
  String get adAiTagline => 'Le grille-pain qui répond à vos e-mails. Mal.';

  @override
  String get adAiCta => 'Griller';

  @override
  String get adNftTagline =>
      'Adoptez un pixel. Il ne fait rien, mais il est unique.';

  @override
  String get adNftCta => 'Adopter';

  @override
  String get adParodyNotice =>
      'Ceci est une parodie. Aucune de ces marques n\'existe.';

  @override
  String adCloseIn(int n) {
    return 'Fermer dans $n s';
  }

  @override
  String get adRewardedTitle => 'Vidéo récompensée';

  @override
  String get adRewardWatching => 'Regardez jusqu\'au bout pour être crédité…';

  @override
  String adRewardReady(String amount) {
    return 'Récompense disponible : $amount';
  }

  @override
  String adRewardCredited(String amount) {
    return '$amount crédités sur votre solde.';
  }

  @override
  String get adRewardCap => 'Plafond quotidien de récompenses atteint.';

  @override
  String get adClaim => 'Récupérer';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsTheme => 'Thème';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsFeedback => 'Son et vibrations';

  @override
  String get settingsSound => 'Sons';

  @override
  String get settingsHaptics => 'Retour haptique';

  @override
  String get settingsServerHint => 'Adresse des émulateurs Firebase';

  @override
  String get settingsAbout => 'À propos';

  @override
  String get settingsAboutBody =>
      'Vingt-Un est un projet pédagogique : argent 100 % fictif, serveur local (émulateurs Firebase), aucune donnée réelle.';

  @override
  String get rulesSummary =>
      'Règles : 6 jeux, le croupier reste sur tout 17, blackjack payé 3:2, assurance 2:1, double sur deux cartes (aussi après split), split jusqu\'à 4 mains, As séparés : une carte chacun, abandon tardif.';

  @override
  String get errReasonInvalidArgument =>
      'Requête invalide. Vérifiez les valeurs saisies.';

  @override
  String get errReasonUnauthenticated => 'Session expirée. Reconnectez-vous.';

  @override
  String get errReasonRateLimited =>
      'Trop de requêtes. Patientez un instant puis réessayez.';

  @override
  String get errReasonRequestIdReused =>
      'Requête en double refusée. Réessayez.';

  @override
  String get errReasonProfileRequired =>
      'Terminez d\'abord la création de votre profil.';

  @override
  String get errReasonProfileExists => 'Votre profil existe déjà.';

  @override
  String get errReasonUsernameTaken => 'Ce pseudo est déjà pris.';

  @override
  String get errReasonKycRequired =>
      'Vérification d\'identité requise avant tout dépôt ou retrait.';

  @override
  String get errReasonKycAlreadyVerified => 'Votre identité est déjà vérifiée.';

  @override
  String get errReasonKycRejected =>
      'Vérification d\'identité refusée (moins de 18 ans). Cette décision est définitive.';

  @override
  String get errReasonInsufficientFunds => 'Solde insuffisant.';

  @override
  String get errReasonDepositLimit =>
      'Montant hors limites : 5 \$ à 1 000 \$ par dépôt, 5 000 \$ par jour.';

  @override
  String get errReasonTableNotFound => 'Cette table n\'existe pas.';

  @override
  String get errReasonTableClosed => 'Cette table est fermée.';

  @override
  String get errReasonTableFull => 'Cette table privée est complète.';

  @override
  String get errReasonBadCode => 'Code de table inconnu.';

  @override
  String get errReasonAlreadySeated =>
      'Vous êtes déjà assis à une autre table. Quittez-la d\'abord.';

  @override
  String get errReasonNotSeated => 'Vous n\'êtes pas assis à cette table.';

  @override
  String get errReasonBadPhase => 'Action impossible à ce moment de la main.';

  @override
  String get errReasonStaleHand => 'La main a changé entre-temps. Réessayez.';

  @override
  String get errReasonAlreadyBet => 'Vous avez déjà misé sur cette main.';

  @override
  String get errReasonBetOutOfRange =>
      'Mise hors limites (dollars entiers, entre le minimum et le maximum de la table).';

  @override
  String get errReasonNotYourTurn => 'Ce n\'est pas votre tour.';

  @override
  String get errReasonIllegalAction => 'Action non autorisée avec cette main.';

  @override
  String get errReasonPowerNotOwned => 'Vous ne possédez pas ce pouvoir.';

  @override
  String get errReasonPowerAlreadyUsed => 'Un seul pouvoir par main.';

  @override
  String get errReasonPowerNotApplicable =>
      'Ce pouvoir ne s\'applique pas à cette action.';

  @override
  String get errReasonInventoryFull => 'Inventaire plein (99 maximum).';

  @override
  String get errReasonMarketNotFound => 'Ce pari n\'existe pas.';

  @override
  String get errReasonMarketClosed => 'Ce pari est fermé.';

  @override
  String get errReasonOwnTableMarket =>
      'Impossible de parier sur la table où vous jouez.';

  @override
  String get errReasonInsufficientShares =>
      'Vous n\'avez pas assez de parts à vendre.';

  @override
  String get errReasonSlippage =>
      'Le prix a bougé. Vérifiez le nouveau prix et réessayez.';

  @override
  String get errReasonMarketLimit =>
      'Ordre trop gros : le prix atteindrait sa limite.';

  @override
  String get errReasonUserNotFound => 'Joueur introuvable.';

  @override
  String get errReasonSelfFriend =>
      'Vous ne pouvez pas vous ajouter vous-même.';

  @override
  String get errReasonAlreadyFriends => 'Vous êtes déjà amis.';

  @override
  String get errReasonRequestExists => 'Demande d\'ami déjà envoyée.';

  @override
  String get errReasonRequestNotFound => 'Cette demande d\'ami n\'existe plus.';

  @override
  String get errReasonNotFriends => 'Vous n\'êtes pas amis.';

  @override
  String get errReasonAdCooldown =>
      'Patientez 30 secondes entre deux récompenses.';

  @override
  String get errReasonAdDailyLimit =>
      'Limite quotidienne de récompenses atteinte (10 par jour).';

  @override
  String get errReasonInternal => 'Erreur du serveur. Réessayez plus tard.';

  @override
  String get errFailureUnavailable =>
      'Serveur injoignable. Vérifiez votre connexion et l\'adresse du serveur.';

  @override
  String get errFailurePermissionDenied => 'Action non autorisée.';

  @override
  String get errFailureInvalidArgument => 'Requête invalide.';

  @override
  String get errFailureInsufficientFunds => 'Fonds insuffisants.';

  @override
  String get errFailureKycRequired => 'Vérification d\'identité requise.';

  @override
  String get errFailureLimitExceeded => 'Limite atteinte.';

  @override
  String get errFailureRateLimited => 'Trop de requêtes, patientez un instant.';

  @override
  String get errFailureNotFound => 'Élément introuvable.';

  @override
  String get errFailureUnknown => 'Une erreur est survenue. Réessayez.';

  @override
  String get errAuthInvalidCredentials => 'E-mail ou mot de passe incorrect.';

  @override
  String get errAuthInvalidEmail => 'Adresse e-mail invalide.';

  @override
  String get errAuthEmailInUse => 'Cette adresse e-mail est déjà utilisée.';

  @override
  String get errAuthWeakPassword =>
      'Mot de passe trop faible (8 caractères minimum).';

  @override
  String get errAuthUsernameTaken => 'Ce pseudo est déjà pris.';

  @override
  String get errAuthInvalidUsername =>
      'Pseudo invalide : 3 à 16 caractères, lettres, chiffres ou _.';

  @override
  String get errAuthProfileExists => 'Votre profil existe déjà.';

  @override
  String get errAuthTooManyRequests =>
      'Trop de tentatives. Réessayez dans quelques minutes.';

  @override
  String get errAuthNetwork =>
      'Impossible de joindre le serveur. Vérifiez votre connexion.';

  @override
  String get errAuthUnknown => 'Erreur d\'authentification. Réessayez.';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get completeProfileTitle => 'Terminer votre profil';

  @override
  String get completeProfileIntro =>
      'Choisissez un pseudo et un avatar pour terminer l\'inscription. Le bonus de bienvenue est crédité ensuite.';

  @override
  String get completeProfileSubmit => 'Terminer';

  @override
  String get authUsernameRule => '3 à 16 caractères : lettres, chiffres ou _';

  @override
  String get authAvatarTitle => 'Avatar';

  @override
  String get authLanguageTitle => 'Langue';

  @override
  String get actionPeek => 'Coup d\'œil';

  @override
  String tableBetting(int seconds) {
    return 'Faites vos jeux · $seconds s';
  }

  @override
  String tablePlaceBet(String amount) {
    return 'Miser $amount';
  }

  @override
  String tableBetPlaced(String amount) {
    return 'Mise placée : $amount';
  }

  @override
  String get tableClearBet => 'Effacer';

  @override
  String get tableWaitingNextHand =>
      'Main en cours : vous jouerez la suivante.';

  @override
  String get tableQueued =>
      'En file d\'attente : place attribuée à la prochaine main.';

  @override
  String get tableSpectating => 'Mode spectateur';

  @override
  String get tableSpectatorHint =>
      'Vous regardez cette table. Pariez sur ses marchés !';

  @override
  String get tableMarkets => 'Paris';

  @override
  String tableYourTurn(int seconds) {
    return 'À vous · $seconds s';
  }

  @override
  String tableTurnOf(String name, int seconds) {
    return 'Tour de $name · $seconds s';
  }

  @override
  String get tableInsuranceTitle => 'Assurance ?';

  @override
  String tableInsuranceBody(String amount) {
    return 'Le croupier montre un As. Assurez jusqu\'à $amount (payé 2 pour 1 s\'il a un blackjack).';
  }

  @override
  String tableInsuranceTake(String amount) {
    return 'Assurer $amount';
  }

  @override
  String get tableInsuranceDecline => 'Non merci';

  @override
  String tableInsuranceWait(int seconds) {
    return 'Assurance · $seconds s';
  }

  @override
  String tableResult(String amount) {
    return 'Résultat de la main : $amount';
  }

  @override
  String get tableSettled => 'Main terminée';

  @override
  String get tableDealerPlays => 'Le croupier joue…';

  @override
  String get tableIdle => 'En attente de joueurs…';

  @override
  String get tableClosedNotice => 'Cette table est fermée.';

  @override
  String tablePowerArmed(String name) {
    return 'Pouvoir prêt : $name';
  }

  @override
  String tablePowerUsed(String name) {
    return 'Pouvoir utilisé : $name';
  }

  @override
  String get tablePowerNone => 'Aucun';

  @override
  String get tablePowerHint =>
      'S\'applique à votre prochaine action compatible.';

  @override
  String get tablePowerShop => 'Acheter des pouvoirs';

  @override
  String tablePeekCard(String card) {
    return 'Coup d\'œil : carte cachée $card';
  }

  @override
  String tablePrivateCode(String code) {
    return 'Code : $code';
  }

  @override
  String tableSecondChance(String card) {
    return 'Seconde chance : la carte $card a été remplacée.';
  }

  @override
  String get tableOffline => 'Hors ligne : affichage possiblement périmé.';

  @override
  String get tableLeaveConfirm =>
      'Quitter la table ? Une main en cours sera jouée « rester » automatiquement.';

  @override
  String tableShoeInfo(int n, int cards) {
    return 'Sabot n° $n · $cards cartes';
  }

  @override
  String get fairCurrentCommit =>
      'Engagement de la main en cours (SHA-256 de la graine)';

  @override
  String fairLastHand(int n) {
    return 'Main n° $n : graine révélée';
  }

  @override
  String get fairVerify => 'Vérifier la dernière main';

  @override
  String fairVerified(int n) {
    return 'Vérifié : SHA-256(graine) = engagement, et les $n cartes distribuées correspondent à l\'ordre recalculé.';
  }

  @override
  String get fairFailed =>
      'Échec de la vérification : la preuve ne correspond pas.';

  @override
  String get fairNoHistory =>
      'Aucune main terminée sur cette table pour l\'instant.';

  @override
  String get lobbyPrivate => 'Table privée';

  @override
  String get privateIntro =>
      'Jouez entre amis, sans bots : créez une table et partagez son code, ou rejoignez celle d\'un ami.';

  @override
  String get privateCreate => 'Créer une table';

  @override
  String get privateJoin => 'Rejoindre';

  @override
  String get privateCodeLabel => 'Code de table (6 caractères)';

  @override
  String get privateCodeInvalid => '6 lettres ou chiffres.';

  @override
  String privateCreated(String code) {
    return 'Table privée créée. Code : $code';
  }

  @override
  String get friendsSuggestions => 'Suggestions';

  @override
  String get friendsSent => 'Demandes envoyées';

  @override
  String get friendsPending => 'En attente de réponse';

  @override
  String get friendsRemove => 'Retirer';

  @override
  String friendsRemoved(String name) {
    return '$name retiré de vos amis.';
  }

  @override
  String friendsAccepted(String name) {
    return 'Vous êtes maintenant ami avec $name.';
  }

  @override
  String get friendsEmpty =>
      'Pas encore d\'amis : recherchez un pseudo ci-dessus.';

  @override
  String walletWatchAd(String amount) {
    return 'Regarder une pub (+$amount)';
  }

  @override
  String adRewardsLeft(int n) {
    return '$n récompenses restantes aujourd\'hui';
  }

  @override
  String get marketsEmpty => 'Aucun marché ouvert pour l\'instant.';

  @override
  String get positionOpen => 'En cours';

  @override
  String get positionWon => 'Gagné';

  @override
  String get positionLost => 'Perdu';

  @override
  String get positionVoid => 'Remboursé';

  @override
  String get tableBetsHere => 'Paris sur cette table';
}
