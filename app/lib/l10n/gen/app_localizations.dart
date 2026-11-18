import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @accept.
  ///
  /// In fr, this message translates to:
  /// **'Accepter'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In fr, this message translates to:
  /// **'Refuser'**
  String get decline;

  /// No description provided for @back.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get back;

  /// No description provided for @close.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get close;

  /// No description provided for @save.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get save;

  /// No description provided for @play.
  ///
  /// In fr, this message translates to:
  /// **'Jouer'**
  String get play;

  /// No description provided for @watch.
  ///
  /// In fr, this message translates to:
  /// **'Regarder'**
  String get watch;

  /// No description provided for @live.
  ///
  /// In fr, this message translates to:
  /// **'EN DIRECT'**
  String get live;

  /// No description provided for @you.
  ///
  /// In fr, this message translates to:
  /// **'Vous'**
  String get you;

  /// No description provided for @yes.
  ///
  /// In fr, this message translates to:
  /// **'Oui'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In fr, this message translates to:
  /// **'Non'**
  String get no;

  /// No description provided for @buy.
  ///
  /// In fr, this message translates to:
  /// **'Acheter'**
  String get buy;

  /// No description provided for @sell.
  ///
  /// In fr, this message translates to:
  /// **'Vendre'**
  String get sell;

  /// No description provided for @amount.
  ///
  /// In fr, this message translates to:
  /// **'Montant'**
  String get amount;

  /// No description provided for @online.
  ///
  /// In fr, this message translates to:
  /// **'En ligne'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In fr, this message translates to:
  /// **'Hors ligne'**
  String get offline;

  /// No description provided for @chance.
  ///
  /// In fr, this message translates to:
  /// **'chance'**
  String get chance;

  /// No description provided for @errorGeneric.
  ///
  /// In fr, this message translates to:
  /// **'Une erreur est survenue. Réessayez.'**
  String get errorGeneric;

  /// No description provided for @errorInsufficientFunds.
  ///
  /// In fr, this message translates to:
  /// **'Solde insuffisant.'**
  String get errorInsufficientFunds;

  /// No description provided for @errorLimit.
  ///
  /// In fr, this message translates to:
  /// **'Plafond atteint.'**
  String get errorLimit;

  /// No description provided for @errorKycRequired.
  ///
  /// In fr, this message translates to:
  /// **'Vérification d\'identité requise.'**
  String get errorKycRequired;

  /// No description provided for @errorRateLimited.
  ///
  /// In fr, this message translates to:
  /// **'Trop de requêtes, patientez un instant.'**
  String get errorRateLimited;

  /// No description provided for @errorUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable.'**
  String get errorUnavailable;

  /// No description provided for @simulationBanner.
  ///
  /// In fr, this message translates to:
  /// **'SIMULATION — argent fictif uniquement, aucune valeur réelle.'**
  String get simulationBanner;

  /// No description provided for @fakeMoneyDisclaimer.
  ///
  /// In fr, this message translates to:
  /// **'Jeu d\'entraînement en argent 100 % fictif. Aucun gain réel, aucun paiement réel.'**
  String get fakeMoneyDisclaimer;

  /// No description provided for @handNumber.
  ///
  /// In fr, this message translates to:
  /// **'Main n° {n}'**
  String handNumber(int n);

  /// No description provided for @agoSeconds.
  ///
  /// In fr, this message translates to:
  /// **'il y a {n} s'**
  String agoSeconds(int n);

  /// No description provided for @agoMinutes.
  ///
  /// In fr, this message translates to:
  /// **'il y a {n} min'**
  String agoMinutes(int n);

  /// No description provided for @agoHours.
  ///
  /// In fr, this message translates to:
  /// **'il y a {n} h'**
  String agoHours(int n);

  /// No description provided for @agoDays.
  ///
  /// In fr, this message translates to:
  /// **'il y a {n} j'**
  String agoDays(int n);

  /// No description provided for @loginTagline.
  ///
  /// In fr, this message translates to:
  /// **'Blackjack multijoueur, croupier en direct, argent fictif.'**
  String get loginTagline;

  /// No description provided for @loginTitle.
  ///
  /// In fr, this message translates to:
  /// **'Connexion'**
  String get loginTitle;

  /// No description provided for @email.
  ///
  /// In fr, this message translates to:
  /// **'E-mail'**
  String get email;

  /// No description provided for @password.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get password;

  /// No description provided for @showPassword.
  ///
  /// In fr, this message translates to:
  /// **'Afficher le mot de passe'**
  String get showPassword;

  /// No description provided for @signIn.
  ///
  /// In fr, this message translates to:
  /// **'Se connecter'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get signOut;

  /// No description provided for @createAccount.
  ///
  /// In fr, this message translates to:
  /// **'Créer un compte'**
  String get createAccount;

  /// No description provided for @validationEmail.
  ///
  /// In fr, this message translates to:
  /// **'Adresse e-mail invalide.'**
  String get validationEmail;

  /// No description provided for @validationPasswordShort.
  ///
  /// In fr, this message translates to:
  /// **'6 caractères minimum.'**
  String get validationPasswordShort;

  /// No description provided for @validationUsername.
  ///
  /// In fr, this message translates to:
  /// **'3 à 16 caractères : lettres, chiffres, _ ou .'**
  String get validationUsername;

  /// No description provided for @authErrorInvalid.
  ///
  /// In fr, this message translates to:
  /// **'E-mail ou mot de passe incorrect.'**
  String get authErrorInvalid;

  /// No description provided for @authErrorEmailInUse.
  ///
  /// In fr, this message translates to:
  /// **'Cet e-mail est déjà utilisé.'**
  String get authErrorEmailInUse;

  /// No description provided for @authErrorWeakPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe trop faible.'**
  String get authErrorWeakPassword;

  /// No description provided for @authErrorUsernameTaken.
  ///
  /// In fr, this message translates to:
  /// **'Ce pseudo est déjà pris.'**
  String get authErrorUsernameTaken;

  /// No description provided for @authErrorNetwork.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de joindre le serveur.'**
  String get authErrorNetwork;

  /// No description provided for @signupTitle.
  ///
  /// In fr, this message translates to:
  /// **'Créer un compte'**
  String get signupTitle;

  /// No description provided for @signupBonus.
  ///
  /// In fr, this message translates to:
  /// **'Bonus de bienvenue : {amount} fictifs offerts'**
  String signupBonus(String amount);

  /// No description provided for @username.
  ///
  /// In fr, this message translates to:
  /// **'Pseudo'**
  String get username;

  /// No description provided for @usernameHelp.
  ///
  /// In fr, this message translates to:
  /// **'Visible par les autres joueurs'**
  String get usernameHelp;

  /// No description provided for @passwordHelp.
  ///
  /// In fr, this message translates to:
  /// **'8 caractères minimum, dont une lettre et un chiffre.'**
  String get passwordHelp;

  /// No description provided for @signupAdultCheckbox.
  ///
  /// In fr, this message translates to:
  /// **'J\'ai 18 ans ou plus et je comprends que l\'argent est fictif.'**
  String get signupAdultCheckbox;

  /// No description provided for @signupMustBeAdult.
  ///
  /// In fr, this message translates to:
  /// **'Vous devez confirmer avoir 18 ans ou plus.'**
  String get signupMustBeAdult;

  /// No description provided for @serverTitle.
  ///
  /// In fr, this message translates to:
  /// **'Serveur'**
  String get serverTitle;

  /// No description provided for @serverIntro.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du poste qui fait tourner les émulateurs Firebase (Auth 9099, Firestore 8080, Functions 5001). En classe : l\'IP du poste enseignant.'**
  String get serverIntro;

  /// No description provided for @serverHostLabel.
  ///
  /// In fr, this message translates to:
  /// **'Hôte (IP ou nom)'**
  String get serverHostLabel;

  /// No description provided for @serverHostInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez une IP ou un nom d\'hôte, sans http:// ni port.'**
  String get serverHostInvalid;

  /// No description provided for @serverCurrentCustom.
  ///
  /// In fr, this message translates to:
  /// **'Actuel : {host} (personnalisé)'**
  String serverCurrentCustom(String host);

  /// No description provided for @serverCurrentDefault.
  ///
  /// In fr, this message translates to:
  /// **'Actuel : {host} (par défaut)'**
  String serverCurrentDefault(String host);

  /// No description provided for @serverTest.
  ///
  /// In fr, this message translates to:
  /// **'Tester'**
  String get serverTest;

  /// No description provided for @serverReset.
  ///
  /// In fr, this message translates to:
  /// **'Revenir à {host}'**
  String serverReset(String host);

  /// No description provided for @serverSaved.
  ///
  /// In fr, this message translates to:
  /// **'Serveur enregistré.'**
  String get serverSaved;

  /// No description provided for @serverUnreachable.
  ///
  /// In fr, this message translates to:
  /// **'injoignable'**
  String get serverUnreachable;

  /// No description provided for @serverAllOk.
  ///
  /// In fr, this message translates to:
  /// **'Tous les services répondent.'**
  String get serverAllOk;

  /// No description provided for @serverSomeDown.
  ///
  /// In fr, this message translates to:
  /// **'Certains services ne répondent pas : l\'app reste utilisable hors ligne.'**
  String get serverSomeDown;

  /// No description provided for @serverHelpTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aide'**
  String get serverHelpTitle;

  /// No description provided for @serverHelpBody.
  ///
  /// In fr, this message translates to:
  /// **'10.0.2.2 désigne l\'ordinateur hôte depuis l\'émulateur Android. Sur le réseau de la classe, utilisez l\'IP affichée par le script du poste enseignant.'**
  String get serverHelpBody;

  /// No description provided for @kycTitle.
  ///
  /// In fr, this message translates to:
  /// **'Vérification d\'identité'**
  String get kycTitle;

  /// No description provided for @kycSimulationBanner.
  ///
  /// In fr, this message translates to:
  /// **'SIMULATION — aucune photo n\'est prise, aucun document n\'est envoyé.'**
  String get kycSimulationBanner;

  /// No description provided for @kycIntro.
  ///
  /// In fr, this message translates to:
  /// **'Requise avant tout dépôt ou retrait. Les mineurs sont refusés.'**
  String get kycIntro;

  /// No description provided for @kycDocType.
  ///
  /// In fr, this message translates to:
  /// **'Type de pièce'**
  String get kycDocType;

  /// No description provided for @kycIdCard.
  ///
  /// In fr, this message translates to:
  /// **'Carte d\'identité'**
  String get kycIdCard;

  /// No description provided for @kycPassport.
  ///
  /// In fr, this message translates to:
  /// **'Passeport'**
  String get kycPassport;

  /// No description provided for @kycLicense.
  ///
  /// In fr, this message translates to:
  /// **'Permis'**
  String get kycLicense;

  /// No description provided for @kycFullName.
  ///
  /// In fr, this message translates to:
  /// **'Nom complet'**
  String get kycFullName;

  /// No description provided for @kycBirthDate.
  ///
  /// In fr, this message translates to:
  /// **'Date de naissance'**
  String get kycBirthDate;

  /// No description provided for @kycChooseDate.
  ///
  /// In fr, this message translates to:
  /// **'Choisir une date'**
  String get kycChooseDate;

  /// No description provided for @kycFormIncomplete.
  ///
  /// In fr, this message translates to:
  /// **'Renseignez votre nom et votre date de naissance.'**
  String get kycFormIncomplete;

  /// No description provided for @kycStartScan.
  ///
  /// In fr, this message translates to:
  /// **'Lancer le scan'**
  String get kycStartScan;

  /// No description provided for @kycScanning.
  ///
  /// In fr, this message translates to:
  /// **'Analyse du document…'**
  String get kycScanning;

  /// No description provided for @kycStepEdges.
  ///
  /// In fr, this message translates to:
  /// **'Détection des bords'**
  String get kycStepEdges;

  /// No description provided for @kycStepMrz.
  ///
  /// In fr, this message translates to:
  /// **'Lecture de la bande MRZ'**
  String get kycStepMrz;

  /// No description provided for @kycStepFace.
  ///
  /// In fr, this message translates to:
  /// **'Comparaison du visage'**
  String get kycStepFace;

  /// No description provided for @kycStepAge.
  ///
  /// In fr, this message translates to:
  /// **'Contrôle de l\'âge'**
  String get kycStepAge;

  /// No description provided for @kycPending.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get kycPending;

  /// No description provided for @kycPendingBody.
  ///
  /// In fr, this message translates to:
  /// **'Votre dossier est en cours d\'examen.'**
  String get kycPendingBody;

  /// No description provided for @kycVerified.
  ///
  /// In fr, this message translates to:
  /// **'Vérifié'**
  String get kycVerified;

  /// No description provided for @kycVerifiedBody.
  ///
  /// In fr, this message translates to:
  /// **'Identité vérifiée. Dépôts et retraits débloqués.'**
  String get kycVerifiedBody;

  /// No description provided for @kycRejected.
  ///
  /// In fr, this message translates to:
  /// **'Refusé'**
  String get kycRejected;

  /// No description provided for @kycRejectedBody.
  ///
  /// In fr, this message translates to:
  /// **'Vérification refusée : vous devez avoir 18 ans ou plus.'**
  String get kycRejectedBody;

  /// No description provided for @kycNotStarted.
  ///
  /// In fr, this message translates to:
  /// **'Non vérifié'**
  String get kycNotStarted;

  /// No description provided for @kycGoToWallet.
  ///
  /// In fr, this message translates to:
  /// **'Aller au portefeuille'**
  String get kycGoToWallet;

  /// No description provided for @walletTitle.
  ///
  /// In fr, this message translates to:
  /// **'Portefeuille'**
  String get walletTitle;

  /// No description provided for @walletBalance.
  ///
  /// In fr, this message translates to:
  /// **'Solde disponible'**
  String get walletBalance;

  /// No description provided for @walletInPlay.
  ///
  /// In fr, this message translates to:
  /// **'En jeu'**
  String get walletInPlay;

  /// No description provided for @walletDepositLimit.
  ///
  /// In fr, this message translates to:
  /// **'Dépôts du jour'**
  String get walletDepositLimit;

  /// No description provided for @walletHistory.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get walletHistory;

  /// No description provided for @walletKycNeeded.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez votre identité pour déposer ou retirer.'**
  String get walletKycNeeded;

  /// No description provided for @deposit.
  ///
  /// In fr, this message translates to:
  /// **'Déposer'**
  String get deposit;

  /// No description provided for @withdraw.
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get withdraw;

  /// No description provided for @depositConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer le dépôt simulé'**
  String get depositConfirm;

  /// No description provided for @withdrawConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer le retrait simulé'**
  String get withdrawConfirm;

  /// No description provided for @depositDone.
  ///
  /// In fr, this message translates to:
  /// **'Dépôt simulé de {amount} effectué.'**
  String depositDone(String amount);

  /// No description provided for @withdrawDone.
  ///
  /// In fr, this message translates to:
  /// **'Retrait simulé de {amount} effectué.'**
  String withdrawDone(String amount);

  /// No description provided for @paymentSimulationBanner.
  ///
  /// In fr, this message translates to:
  /// **'SIMULATION — numéro de test pré-rempli, non modifiable. Aucune donnée bancaire n\'est demandée ni transmise.'**
  String get paymentSimulationBanner;

  /// No description provided for @paymentTestValue.
  ///
  /// In fr, this message translates to:
  /// **'Valeur de test fixe'**
  String get paymentTestValue;

  /// No description provided for @paymentAmountInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Montant invalide (minimum 1,00 \$).'**
  String get paymentAmountInvalid;

  /// No description provided for @methodCard.
  ///
  /// In fr, this message translates to:
  /// **'Carte'**
  String get methodCard;

  /// No description provided for @methodCrypto.
  ///
  /// In fr, this message translates to:
  /// **'Crypto'**
  String get methodCrypto;

  /// No description provided for @methodBank.
  ///
  /// In fr, this message translates to:
  /// **'Virement'**
  String get methodBank;

  /// No description provided for @cardNumber.
  ///
  /// In fr, this message translates to:
  /// **'Numéro de carte (test)'**
  String get cardNumber;

  /// No description provided for @cardExpiry.
  ///
  /// In fr, this message translates to:
  /// **'Expiration'**
  String get cardExpiry;

  /// No description provided for @cardCvc.
  ///
  /// In fr, this message translates to:
  /// **'CVC'**
  String get cardCvc;

  /// No description provided for @cryptoAddress.
  ///
  /// In fr, this message translates to:
  /// **'Adresse (test)'**
  String get cryptoAddress;

  /// No description provided for @iban.
  ///
  /// In fr, this message translates to:
  /// **'IBAN (test)'**
  String get iban;

  /// No description provided for @ledgerWelcome.
  ///
  /// In fr, this message translates to:
  /// **'Bonus de bienvenue'**
  String get ledgerWelcome;

  /// No description provided for @ledgerDeposit.
  ///
  /// In fr, this message translates to:
  /// **'Dépôt simulé'**
  String get ledgerDeposit;

  /// No description provided for @ledgerWithdrawal.
  ///
  /// In fr, this message translates to:
  /// **'Retrait simulé'**
  String get ledgerWithdrawal;

  /// No description provided for @ledgerBet.
  ///
  /// In fr, this message translates to:
  /// **'Mise'**
  String get ledgerBet;

  /// No description provided for @ledgerWin.
  ///
  /// In fr, this message translates to:
  /// **'Gain'**
  String get ledgerWin;

  /// No description provided for @ledgerPush.
  ///
  /// In fr, this message translates to:
  /// **'Égalité'**
  String get ledgerPush;

  /// No description provided for @ledgerPower.
  ///
  /// In fr, this message translates to:
  /// **'Achat de pouvoir'**
  String get ledgerPower;

  /// No description provided for @ledgerTrade.
  ///
  /// In fr, this message translates to:
  /// **'Ordre sur un marché'**
  String get ledgerTrade;

  /// No description provided for @ledgerMarketPayout.
  ///
  /// In fr, this message translates to:
  /// **'Règlement de marché'**
  String get ledgerMarketPayout;

  /// No description provided for @ledgerAd.
  ///
  /// In fr, this message translates to:
  /// **'Récompense publicitaire'**
  String get ledgerAd;

  /// No description provided for @navLobby.
  ///
  /// In fr, this message translates to:
  /// **'Salon'**
  String get navLobby;

  /// No description provided for @navMarkets.
  ///
  /// In fr, this message translates to:
  /// **'Marchés'**
  String get navMarkets;

  /// No description provided for @navLeaderboard.
  ///
  /// In fr, this message translates to:
  /// **'Classement'**
  String get navLeaderboard;

  /// No description provided for @navWallet.
  ///
  /// In fr, this message translates to:
  /// **'Portefeuille'**
  String get navWallet;

  /// No description provided for @navProfile.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get navProfile;

  /// No description provided for @lobbyHeroTitle.
  ///
  /// In fr, this message translates to:
  /// **'Blackjack en direct'**
  String get lobbyHeroTitle;

  /// No description provided for @lobbyHeroSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'5 places, un croupier qui distribue pour de vrai. Le blackjack paie 3 pour 2.'**
  String get lobbyHeroSubtitle;

  /// No description provided for @lobbyQuickPlay.
  ///
  /// In fr, this message translates to:
  /// **'Partie rapide'**
  String get lobbyQuickPlay;

  /// No description provided for @lobbyDealerDemo.
  ///
  /// In fr, this message translates to:
  /// **'Démo du croupier'**
  String get lobbyDealerDemo;

  /// No description provided for @lobbyStakes.
  ///
  /// In fr, this message translates to:
  /// **'Niveaux de mise'**
  String get lobbyStakes;

  /// No description provided for @lobbyLiveTables.
  ///
  /// In fr, this message translates to:
  /// **'Tables en direct'**
  String get lobbyLiveTables;

  /// No description provided for @lobbyAllTiers.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get lobbyAllTiers;

  /// No description provided for @lobbyTierStats.
  ///
  /// In fr, this message translates to:
  /// **'{tables} tables · {players} joueurs'**
  String lobbyTierStats(int tables, int players);

  /// No description provided for @tierMicro.
  ///
  /// In fr, this message translates to:
  /// **'Micro'**
  String get tierMicro;

  /// No description provided for @tierLow.
  ///
  /// In fr, this message translates to:
  /// **'Bas'**
  String get tierLow;

  /// No description provided for @tierMid.
  ///
  /// In fr, this message translates to:
  /// **'Moyen'**
  String get tierMid;

  /// No description provided for @tierHigh.
  ///
  /// In fr, this message translates to:
  /// **'Haut'**
  String get tierHigh;

  /// No description provided for @tierVip.
  ///
  /// In fr, this message translates to:
  /// **'VIP'**
  String get tierVip;

  /// No description provided for @tableFull.
  ///
  /// In fr, this message translates to:
  /// **'Complet'**
  String get tableFull;

  /// No description provided for @winKindBlackjack.
  ///
  /// In fr, this message translates to:
  /// **'blackjack'**
  String get winKindBlackjack;

  /// No description provided for @winKindDouble.
  ///
  /// In fr, this message translates to:
  /// **'double gagné'**
  String get winKindDouble;

  /// No description provided for @winKindSplit.
  ///
  /// In fr, this message translates to:
  /// **'split gagné'**
  String get winKindSplit;

  /// No description provided for @winKindMarket.
  ///
  /// In fr, this message translates to:
  /// **'pari spectateur'**
  String get winKindMarket;

  /// No description provided for @winKindWin.
  ///
  /// In fr, this message translates to:
  /// **'main gagnée'**
  String get winKindWin;

  /// No description provided for @feltPayout.
  ///
  /// In fr, this message translates to:
  /// **'LE BLACKJACK PAIE 3 POUR 2'**
  String get feltPayout;

  /// No description provided for @feltInsurance.
  ///
  /// In fr, this message translates to:
  /// **'ASSURANCE PAIE 2 POUR 1'**
  String get feltInsurance;

  /// No description provided for @feltRule.
  ///
  /// In fr, this message translates to:
  /// **'Le croupier reste sur tout 17'**
  String get feltRule;

  /// No description provided for @seatOpen.
  ///
  /// In fr, this message translates to:
  /// **'Libre'**
  String get seatOpen;

  /// No description provided for @badgeBlackjack.
  ///
  /// In fr, this message translates to:
  /// **'BLACKJACK'**
  String get badgeBlackjack;

  /// No description provided for @badgeBust.
  ///
  /// In fr, this message translates to:
  /// **'SAUTÉ'**
  String get badgeBust;

  /// No description provided for @badgeWin.
  ///
  /// In fr, this message translates to:
  /// **'GAGNÉ'**
  String get badgeWin;

  /// No description provided for @badgeLose.
  ///
  /// In fr, this message translates to:
  /// **'PERDU'**
  String get badgeLose;

  /// No description provided for @badgePush.
  ///
  /// In fr, this message translates to:
  /// **'ÉGALITÉ'**
  String get badgePush;

  /// No description provided for @actionHit.
  ///
  /// In fr, this message translates to:
  /// **'Tirer'**
  String get actionHit;

  /// No description provided for @actionStand.
  ///
  /// In fr, this message translates to:
  /// **'Rester'**
  String get actionStand;

  /// No description provided for @actionDouble.
  ///
  /// In fr, this message translates to:
  /// **'Doubler'**
  String get actionDouble;

  /// No description provided for @actionSplit.
  ///
  /// In fr, this message translates to:
  /// **'Séparer'**
  String get actionSplit;

  /// No description provided for @actionSurrender.
  ///
  /// In fr, this message translates to:
  /// **'Abandon'**
  String get actionSurrender;

  /// No description provided for @actionInsurance.
  ///
  /// In fr, this message translates to:
  /// **'Assurance'**
  String get actionInsurance;

  /// No description provided for @actionSent.
  ///
  /// In fr, this message translates to:
  /// **'Action envoyée : {action}'**
  String actionSent(String action);

  /// No description provided for @fairTitle.
  ///
  /// In fr, this message translates to:
  /// **'Équité vérifiable'**
  String get fairTitle;

  /// No description provided for @fairBody.
  ///
  /// In fr, this message translates to:
  /// **'Empreinte SHA-256 de la graine du sabot, publiée avant la main. La graine est révélée à la fin du sabot pour vérification.'**
  String get fairBody;

  /// No description provided for @leaveTable.
  ///
  /// In fr, this message translates to:
  /// **'Quitter la table'**
  String get leaveTable;

  /// No description provided for @powers.
  ///
  /// In fr, this message translates to:
  /// **'Pouvoirs'**
  String get powers;

  /// No description provided for @powersSheetTitle.
  ///
  /// In fr, this message translates to:
  /// **'Utiliser un pouvoir'**
  String get powersSheetTitle;

  /// No description provided for @powersSheetHint.
  ///
  /// In fr, this message translates to:
  /// **'Un seul pouvoir par main, validé par le serveur.'**
  String get powersSheetHint;

  /// No description provided for @dealerDemoTitle.
  ///
  /// In fr, this message translates to:
  /// **'Démo du croupier'**
  String get dealerDemoTitle;

  /// No description provided for @dealerIdle.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get dealerIdle;

  /// No description provided for @dealerQueue.
  ///
  /// In fr, this message translates to:
  /// **'{n} en file · {seconds} s'**
  String dealerQueue(int n, String seconds);

  /// No description provided for @dealerSpeed.
  ///
  /// In fr, this message translates to:
  /// **'Vitesse'**
  String get dealerSpeed;

  /// No description provided for @dealerLoop.
  ///
  /// In fr, this message translates to:
  /// **'Boucle'**
  String get dealerLoop;

  /// No description provided for @dealerPlayRound.
  ///
  /// In fr, this message translates to:
  /// **'Jouer une main'**
  String get dealerPlayRound;

  /// No description provided for @dealerShuffle.
  ///
  /// In fr, this message translates to:
  /// **'Mélanger'**
  String get dealerShuffle;

  /// No description provided for @dealerReset.
  ///
  /// In fr, this message translates to:
  /// **'Réinitialiser'**
  String get dealerReset;

  /// No description provided for @dealerRounds.
  ///
  /// In fr, this message translates to:
  /// **'{n, plural, =0{Aucune main jouée} =1{1 main jouée} other{{n} mains jouées}}'**
  String dealerRounds(int n);

  /// No description provided for @shopTitle.
  ///
  /// In fr, this message translates to:
  /// **'Boutique de pouvoirs'**
  String get shopTitle;

  /// No description provided for @shopSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Split gratuit, coup d\'œil, seconde chance…'**
  String get shopSubtitle;

  /// No description provided for @shopIntro.
  ///
  /// In fr, this message translates to:
  /// **'Payés en argent fictif. Un pouvoir par main, toujours validé par le serveur.'**
  String get shopIntro;

  /// No description provided for @shopOwned.
  ///
  /// In fr, this message translates to:
  /// **'{n, plural, =0{Aucun en stock} =1{1 en stock} other{{n} en stock}}'**
  String shopOwned(int n);

  /// No description provided for @shopBought.
  ///
  /// In fr, this message translates to:
  /// **'{name} ajouté à votre inventaire.'**
  String shopBought(String name);

  /// No description provided for @powerFreeSplit.
  ///
  /// In fr, this message translates to:
  /// **'Split gratuit'**
  String get powerFreeSplit;

  /// No description provided for @powerFreeSplitDesc.
  ///
  /// In fr, this message translates to:
  /// **'Séparez une paire sans miser une seconde fois.'**
  String get powerFreeSplitDesc;

  /// No description provided for @powerFreeDouble.
  ///
  /// In fr, this message translates to:
  /// **'Double gratuit'**
  String get powerFreeDouble;

  /// No description provided for @powerFreeDoubleDesc.
  ///
  /// In fr, this message translates to:
  /// **'Doublez sans ajouter de mise.'**
  String get powerFreeDoubleDesc;

  /// No description provided for @powerFreeInsurance.
  ///
  /// In fr, this message translates to:
  /// **'Assurance gratuite'**
  String get powerFreeInsurance;

  /// No description provided for @powerFreeInsuranceDesc.
  ///
  /// In fr, this message translates to:
  /// **'Assurance offerte quand le croupier montre un As.'**
  String get powerFreeInsuranceDesc;

  /// No description provided for @powerPeek.
  ///
  /// In fr, this message translates to:
  /// **'Coup d\'œil'**
  String get powerPeek;

  /// No description provided for @powerPeekDesc.
  ///
  /// In fr, this message translates to:
  /// **'Voyez la carte cachée du croupier (vous seul).'**
  String get powerPeekDesc;

  /// No description provided for @powerSecondChance.
  ///
  /// In fr, this message translates to:
  /// **'Seconde chance'**
  String get powerSecondChance;

  /// No description provided for @powerSecondChanceDesc.
  ///
  /// In fr, this message translates to:
  /// **'Remplace la dernière carte tirée.'**
  String get powerSecondChanceDesc;

  /// No description provided for @customizeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Personnalisation'**
  String get customizeTitle;

  /// No description provided for @customizeSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Dos de cartes, faces, tapis'**
  String get customizeSubtitle;

  /// No description provided for @customizeFaces.
  ///
  /// In fr, this message translates to:
  /// **'Style des faces'**
  String get customizeFaces;

  /// No description provided for @customizeBacks.
  ///
  /// In fr, this message translates to:
  /// **'Motif du dos'**
  String get customizeBacks;

  /// No description provided for @customizeBackColor.
  ///
  /// In fr, this message translates to:
  /// **'Couleur du dos'**
  String get customizeBackColor;

  /// No description provided for @customizeFelt.
  ///
  /// In fr, this message translates to:
  /// **'Tapis'**
  String get customizeFelt;

  /// No description provided for @customizeEquip.
  ///
  /// In fr, this message translates to:
  /// **'Équiper'**
  String get customizeEquip;

  /// No description provided for @customizeEquipped.
  ///
  /// In fr, this message translates to:
  /// **'Équipé'**
  String get customizeEquipped;

  /// No description provided for @customizeSaved.
  ///
  /// In fr, this message translates to:
  /// **'Style équipé.'**
  String get customizeSaved;

  /// No description provided for @faceClassic.
  ///
  /// In fr, this message translates to:
  /// **'Classique'**
  String get faceClassic;

  /// No description provided for @faceFourColor.
  ///
  /// In fr, this message translates to:
  /// **'4 couleurs'**
  String get faceFourColor;

  /// No description provided for @faceNeon.
  ///
  /// In fr, this message translates to:
  /// **'Néon'**
  String get faceNeon;

  /// No description provided for @backLattice.
  ///
  /// In fr, this message translates to:
  /// **'Treillis'**
  String get backLattice;

  /// No description provided for @backStripes.
  ///
  /// In fr, this message translates to:
  /// **'Rayures'**
  String get backStripes;

  /// No description provided for @backChevron.
  ///
  /// In fr, this message translates to:
  /// **'Chevrons'**
  String get backChevron;

  /// No description provided for @backDots.
  ///
  /// In fr, this message translates to:
  /// **'Pois'**
  String get backDots;

  /// No description provided for @backSunburst.
  ///
  /// In fr, this message translates to:
  /// **'Soleil'**
  String get backSunburst;

  /// No description provided for @feltGreen.
  ///
  /// In fr, this message translates to:
  /// **'Vert casino'**
  String get feltGreen;

  /// No description provided for @feltNavy.
  ///
  /// In fr, this message translates to:
  /// **'Bleu nuit'**
  String get feltNavy;

  /// No description provided for @feltCrimson.
  ///
  /// In fr, this message translates to:
  /// **'Pourpre'**
  String get feltCrimson;

  /// No description provided for @feltPurple.
  ///
  /// In fr, this message translates to:
  /// **'Violet'**
  String get feltPurple;

  /// No description provided for @feltCharcoal.
  ///
  /// In fr, this message translates to:
  /// **'Anthracite'**
  String get feltCharcoal;

  /// No description provided for @leaderboardTitle.
  ///
  /// In fr, this message translates to:
  /// **'Classement'**
  String get leaderboardTitle;

  /// No description provided for @lbGlobal.
  ///
  /// In fr, this message translates to:
  /// **'Global'**
  String get lbGlobal;

  /// No description provided for @lbFriends.
  ///
  /// In fr, this message translates to:
  /// **'Amis'**
  String get lbFriends;

  /// No description provided for @lbWeekly.
  ///
  /// In fr, this message translates to:
  /// **'Semaine'**
  String get lbWeekly;

  /// No description provided for @lbPointsRule.
  ///
  /// In fr, this message translates to:
  /// **'Victoire +10 · Blackjack +25 · Défaite −5. Paliers : Bronze → Diamant.'**
  String get lbPointsRule;

  /// No description provided for @lbHandsWinRate.
  ///
  /// In fr, this message translates to:
  /// **'{hands} mains · {rate} de victoires'**
  String lbHandsWinRate(int hands, String rate);

  /// No description provided for @lbPoints.
  ///
  /// In fr, this message translates to:
  /// **'{points} pts'**
  String lbPoints(String points);

  /// No description provided for @tierBronze.
  ///
  /// In fr, this message translates to:
  /// **'Bronze'**
  String get tierBronze;

  /// No description provided for @tierSilver.
  ///
  /// In fr, this message translates to:
  /// **'Argent'**
  String get tierSilver;

  /// No description provided for @tierGold.
  ///
  /// In fr, this message translates to:
  /// **'Or'**
  String get tierGold;

  /// No description provided for @tierPlatinum.
  ///
  /// In fr, this message translates to:
  /// **'Platine'**
  String get tierPlatinum;

  /// No description provided for @tierDiamond.
  ///
  /// In fr, this message translates to:
  /// **'Diamant'**
  String get tierDiamond;

  /// No description provided for @friendsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Amis'**
  String get friendsTitle;

  /// No description provided for @friendsSearchHint.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher un pseudo'**
  String get friendsSearchHint;

  /// No description provided for @friendsAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get friendsAdd;

  /// No description provided for @friendsRequestSent.
  ///
  /// In fr, this message translates to:
  /// **'Demande envoyée à {name}.'**
  String friendsRequestSent(String name);

  /// No description provided for @friendsRequests.
  ///
  /// In fr, this message translates to:
  /// **'Demandes ({n})'**
  String friendsRequests(int n);

  /// No description provided for @friendsWantsToAdd.
  ///
  /// In fr, this message translates to:
  /// **'veut vous ajouter'**
  String get friendsWantsToAdd;

  /// No description provided for @friendsList.
  ///
  /// In fr, this message translates to:
  /// **'Mes amis'**
  String get friendsList;

  /// No description provided for @friendsAtTable.
  ///
  /// In fr, this message translates to:
  /// **'Joue à {table}'**
  String friendsAtTable(String table);

  /// No description provided for @marketsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Marchés'**
  String get marketsTitle;

  /// No description provided for @marketsPortfolio.
  ///
  /// In fr, this message translates to:
  /// **'Valeur du portefeuille'**
  String get marketsPortfolio;

  /// No description provided for @marketsPnl.
  ///
  /// In fr, this message translates to:
  /// **'Gain / perte'**
  String get marketsPnl;

  /// No description provided for @filterAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get filterAll;

  /// No description provided for @filterHand.
  ///
  /// In fr, this message translates to:
  /// **'Par main'**
  String get filterHand;

  /// No description provided for @filterShoe.
  ///
  /// In fr, this message translates to:
  /// **'Par sabot'**
  String get filterShoe;

  /// No description provided for @filterMine.
  ///
  /// In fr, this message translates to:
  /// **'Mes positions'**
  String get filterMine;

  /// No description provided for @mqDealerBusts.
  ///
  /// In fr, this message translates to:
  /// **'Le croupier saute ?'**
  String get mqDealerBusts;

  /// No description provided for @mqPlayerWins.
  ///
  /// In fr, this message translates to:
  /// **'{player} gagne ?'**
  String mqPlayerWins(String player);

  /// No description provided for @mqNatural.
  ///
  /// In fr, this message translates to:
  /// **'Un blackjack naturel ?'**
  String get mqNatural;

  /// No description provided for @mqShoe.
  ///
  /// In fr, this message translates to:
  /// **'Le croupier saute 3 fois ou plus sur ce sabot ?'**
  String get mqShoe;

  /// No description provided for @marketPerShoe.
  ///
  /// In fr, this message translates to:
  /// **'sabot en cours'**
  String get marketPerShoe;

  /// No description provided for @marketVolume.
  ///
  /// In fr, this message translates to:
  /// **'Vol. {volume}'**
  String marketVolume(String volume);

  /// No description provided for @marketResolvedYes.
  ///
  /// In fr, this message translates to:
  /// **'Résolu : OUI'**
  String get marketResolvedYes;

  /// No description provided for @marketResolvedNo.
  ///
  /// In fr, this message translates to:
  /// **'Résolu : NON'**
  String get marketResolvedNo;

  /// No description provided for @marketTitle.
  ///
  /// In fr, this message translates to:
  /// **'Marché'**
  String get marketTitle;

  /// No description provided for @marketChanceLabel.
  ///
  /// In fr, this message translates to:
  /// **'{pct} de chance'**
  String marketChanceLabel(String pct);

  /// No description provided for @marketWatchTable.
  ///
  /// In fr, this message translates to:
  /// **'Voir la table'**
  String get marketWatchTable;

  /// No description provided for @marketClosedNotice.
  ///
  /// In fr, this message translates to:
  /// **'Ce marché est clos.'**
  String get marketClosedNotice;

  /// No description provided for @marketYourPositions.
  ///
  /// In fr, this message translates to:
  /// **'Vos positions'**
  String get marketYourPositions;

  /// No description provided for @positionShares.
  ///
  /// In fr, this message translates to:
  /// **'{n} parts · moy. {price}'**
  String positionShares(int n, String price);

  /// No description provided for @positionValue.
  ///
  /// In fr, this message translates to:
  /// **'Valeur : {value}'**
  String positionValue(String value);

  /// No description provided for @marketActivity.
  ///
  /// In fr, this message translates to:
  /// **'Activité'**
  String get marketActivity;

  /// No description provided for @tradeBought.
  ///
  /// In fr, this message translates to:
  /// **'a acheté'**
  String get tradeBought;

  /// No description provided for @tradeSold.
  ///
  /// In fr, this message translates to:
  /// **'a vendu'**
  String get tradeSold;

  /// No description provided for @marketRules.
  ///
  /// In fr, this message translates to:
  /// **'Règles'**
  String get marketRules;

  /// No description provided for @marketRulesBody.
  ///
  /// In fr, this message translates to:
  /// **'Chaque part gagnante paie 1,00 \$ fictif. Les prix sont fixés par un teneur de marché automatique (LMSR). Le marché ferme avant que le croupier ne révèle sa carte. Interdit sur votre propre table.'**
  String get marketRulesBody;

  /// No description provided for @shares.
  ///
  /// In fr, this message translates to:
  /// **'Parts'**
  String get shares;

  /// No description provided for @ticketAvgPrice.
  ///
  /// In fr, this message translates to:
  /// **'Prix moyen'**
  String get ticketAvgPrice;

  /// No description provided for @ticketCost.
  ///
  /// In fr, this message translates to:
  /// **'Coût'**
  String get ticketCost;

  /// No description provided for @ticketProceeds.
  ///
  /// In fr, this message translates to:
  /// **'Vous recevez'**
  String get ticketProceeds;

  /// No description provided for @ticketPayout.
  ///
  /// In fr, this message translates to:
  /// **'Gain si victoire'**
  String get ticketPayout;

  /// No description provided for @ticketPriceAfter.
  ///
  /// In fr, this message translates to:
  /// **'Prix après l\'ordre'**
  String get ticketPriceAfter;

  /// No description provided for @ticketSubmit.
  ///
  /// In fr, this message translates to:
  /// **'{side} {outcome}'**
  String ticketSubmit(String side, String outcome);

  /// No description provided for @ticketDone.
  ///
  /// In fr, this message translates to:
  /// **'Ordre envoyé.'**
  String get ticketDone;

  /// No description provided for @ticketDisclaimer.
  ///
  /// In fr, this message translates to:
  /// **'Estimation : le prix final est calculé par le serveur.'**
  String get ticketDisclaimer;

  /// No description provided for @adLabel.
  ///
  /// In fr, this message translates to:
  /// **'PUB'**
  String get adLabel;

  /// No description provided for @adsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Fausses publicités'**
  String get adsTitle;

  /// No description provided for @adsIntro.
  ///
  /// In fr, this message translates to:
  /// **'Publicités parodiques, sans lien ni pistage : bannière, interstitiel et vidéo récompensée.'**
  String get adsIntro;

  /// No description provided for @adsShowInterstitial.
  ///
  /// In fr, this message translates to:
  /// **'Afficher un interstitiel'**
  String get adsShowInterstitial;

  /// No description provided for @adsShowRewarded.
  ///
  /// In fr, this message translates to:
  /// **'Regarder une vidéo récompensée'**
  String get adsShowRewarded;

  /// No description provided for @adCoinTagline.
  ///
  /// In fr, this message translates to:
  /// **'La crypto qui ne monte jamais, garantie sans surprise.'**
  String get adCoinTagline;

  /// No description provided for @adCoinCta.
  ///
  /// In fr, this message translates to:
  /// **'Ne pas acheter'**
  String get adCoinCta;

  /// No description provided for @adBankTagline.
  ///
  /// In fr, this message translates to:
  /// **'Des intérêts imaginaires sur votre argent imaginaire.'**
  String get adBankTagline;

  /// No description provided for @adBankCta.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir un faux compte'**
  String get adBankCta;

  /// No description provided for @adAiTagline.
  ///
  /// In fr, this message translates to:
  /// **'Le grille-pain qui répond à vos e-mails. Mal.'**
  String get adAiTagline;

  /// No description provided for @adAiCta.
  ///
  /// In fr, this message translates to:
  /// **'Griller'**
  String get adAiCta;

  /// No description provided for @adNftTagline.
  ///
  /// In fr, this message translates to:
  /// **'Adoptez un pixel. Il ne fait rien, mais il est unique.'**
  String get adNftTagline;

  /// No description provided for @adNftCta.
  ///
  /// In fr, this message translates to:
  /// **'Adopter'**
  String get adNftCta;

  /// No description provided for @adParodyNotice.
  ///
  /// In fr, this message translates to:
  /// **'Ceci est une parodie. Aucune de ces marques n\'existe.'**
  String get adParodyNotice;

  /// No description provided for @adCloseIn.
  ///
  /// In fr, this message translates to:
  /// **'Fermer dans {n} s'**
  String adCloseIn(int n);

  /// No description provided for @adRewardedTitle.
  ///
  /// In fr, this message translates to:
  /// **'Vidéo récompensée'**
  String get adRewardedTitle;

  /// No description provided for @adRewardWatching.
  ///
  /// In fr, this message translates to:
  /// **'Regardez jusqu\'au bout pour être crédité…'**
  String get adRewardWatching;

  /// No description provided for @adRewardReady.
  ///
  /// In fr, this message translates to:
  /// **'Récompense disponible : {amount}'**
  String adRewardReady(String amount);

  /// No description provided for @adRewardCredited.
  ///
  /// In fr, this message translates to:
  /// **'{amount} crédités sur votre solde.'**
  String adRewardCredited(String amount);

  /// No description provided for @adRewardCap.
  ///
  /// In fr, this message translates to:
  /// **'Plafond quotidien de récompenses atteint.'**
  String get adRewardCap;

  /// No description provided for @adClaim.
  ///
  /// In fr, this message translates to:
  /// **'Récupérer'**
  String get adClaim;

  /// No description provided for @settingsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Réglages'**
  String get settingsTitle;

  /// No description provided for @settingsTheme.
  ///
  /// In fr, this message translates to:
  /// **'Thème'**
  String get settingsTheme;

  /// No description provided for @themeSystem.
  ///
  /// In fr, this message translates to:
  /// **'Système'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In fr, this message translates to:
  /// **'Clair'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In fr, this message translates to:
  /// **'Sombre'**
  String get themeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get settingsLanguage;

  /// No description provided for @settingsFeedback.
  ///
  /// In fr, this message translates to:
  /// **'Son et vibrations'**
  String get settingsFeedback;

  /// No description provided for @settingsSound.
  ///
  /// In fr, this message translates to:
  /// **'Sons'**
  String get settingsSound;

  /// No description provided for @settingsHaptics.
  ///
  /// In fr, this message translates to:
  /// **'Retour haptique'**
  String get settingsHaptics;

  /// No description provided for @settingsServerHint.
  ///
  /// In fr, this message translates to:
  /// **'Adresse des émulateurs Firebase'**
  String get settingsServerHint;

  /// No description provided for @settingsAbout.
  ///
  /// In fr, this message translates to:
  /// **'À propos'**
  String get settingsAbout;

  /// No description provided for @settingsAboutBody.
  ///
  /// In fr, this message translates to:
  /// **'Vingt-Un est un projet pédagogique : argent 100 % fictif, serveur local (émulateurs Firebase), aucune donnée réelle.'**
  String get settingsAboutBody;

  /// No description provided for @rulesSummary.
  ///
  /// In fr, this message translates to:
  /// **'Règles : 6 jeux, le croupier reste sur tout 17, blackjack payé 3:2, assurance 2:1, double sur deux cartes (aussi après split), split jusqu\'à 4 mains, As séparés : une carte chacun, abandon tardif.'**
  String get rulesSummary;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
