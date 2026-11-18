// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get back => 'Back';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get play => 'Play';

  @override
  String get watch => 'Watch';

  @override
  String get live => 'LIVE';

  @override
  String get you => 'You';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get buy => 'Buy';

  @override
  String get sell => 'Sell';

  @override
  String get amount => 'Amount';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get chance => 'chance';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorInsufficientFunds => 'Insufficient balance.';

  @override
  String get errorLimit => 'Limit reached.';

  @override
  String get errorKycRequired => 'Identity check required.';

  @override
  String get errorRateLimited => 'Too many requests, please wait a moment.';

  @override
  String get errorUnavailable => 'Server unreachable.';

  @override
  String get simulationBanner => 'SIMULATION — play money only, no real value.';

  @override
  String get fakeMoneyDisclaimer =>
      'Practice game with 100% play money. No real winnings, no real payments.';

  @override
  String handNumber(int n) {
    return 'Hand #$n';
  }

  @override
  String agoSeconds(int n) {
    return '${n}s ago';
  }

  @override
  String agoMinutes(int n) {
    return '$n min ago';
  }

  @override
  String agoHours(int n) {
    return '${n}h ago';
  }

  @override
  String agoDays(int n) {
    return '${n}d ago';
  }

  @override
  String get loginTagline => 'Multiplayer blackjack, live dealer, play money.';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get createAccount => 'Create account';

  @override
  String get validationEmail => 'Invalid email address.';

  @override
  String get validationPasswordShort => 'At least 6 characters.';

  @override
  String get validationUsername =>
      '3 to 16 characters: letters, digits, _ or .';

  @override
  String get authErrorInvalid => 'Wrong email or password.';

  @override
  String get authErrorEmailInUse => 'This email is already in use.';

  @override
  String get authErrorWeakPassword => 'Password too weak.';

  @override
  String get authErrorUsernameTaken => 'This username is taken.';

  @override
  String get authErrorNetwork => 'Cannot reach the server.';

  @override
  String get signupTitle => 'Create account';

  @override
  String signupBonus(String amount) {
    return 'Welcome bonus: $amount in play money';
  }

  @override
  String get username => 'Username';

  @override
  String get usernameHelp => 'Visible to other players';

  @override
  String get passwordHelp =>
      'At least 8 characters, including a letter and a digit.';

  @override
  String get signupAdultCheckbox =>
      'I am 18 or older and I understand the money is not real.';

  @override
  String get signupMustBeAdult => 'You must confirm you are 18 or older.';

  @override
  String get serverTitle => 'Server';

  @override
  String get serverIntro =>
      'Address of the machine running the Firebase emulators (Auth 9099, Firestore 8080, Functions 5001). In class: the teacher\'s computer IP.';

  @override
  String get serverHostLabel => 'Host (IP or name)';

  @override
  String get serverHostInvalid =>
      'Enter an IP or host name, without http:// or port.';

  @override
  String serverCurrentCustom(String host) {
    return 'Current: $host (custom)';
  }

  @override
  String serverCurrentDefault(String host) {
    return 'Current: $host (default)';
  }

  @override
  String get serverTest => 'Test';

  @override
  String serverReset(String host) {
    return 'Reset to $host';
  }

  @override
  String get serverSaved => 'Server saved.';

  @override
  String get serverUnreachable => 'unreachable';

  @override
  String get serverAllOk => 'All services are responding.';

  @override
  String get serverSomeDown =>
      'Some services are not responding: the app still works offline.';

  @override
  String get serverHelpTitle => 'Help';

  @override
  String get serverHelpBody =>
      '10.0.2.2 is the host computer as seen from the Android emulator. On the classroom network, use the IP shown by the teacher\'s script.';

  @override
  String get kycTitle => 'Identity check';

  @override
  String get kycSimulationBanner =>
      'SIMULATION — no photo is taken, no document is uploaded.';

  @override
  String get kycIntro =>
      'Required before any deposit or withdrawal. Minors are refused.';

  @override
  String get kycDocType => 'Document type';

  @override
  String get kycIdCard => 'ID card';

  @override
  String get kycPassport => 'Passport';

  @override
  String get kycLicense => 'Licence';

  @override
  String get kycFullName => 'Full name';

  @override
  String get kycBirthDate => 'Date of birth';

  @override
  String get kycChooseDate => 'Pick a date';

  @override
  String get kycFormIncomplete => 'Enter your name and date of birth.';

  @override
  String get kycStartScan => 'Start scan';

  @override
  String get kycScanning => 'Scanning document…';

  @override
  String get kycStepEdges => 'Detecting edges';

  @override
  String get kycStepMrz => 'Reading MRZ';

  @override
  String get kycStepFace => 'Matching face';

  @override
  String get kycStepAge => 'Checking age';

  @override
  String get kycPending => 'Pending';

  @override
  String get kycPendingBody => 'Your file is being reviewed.';

  @override
  String get kycVerified => 'Verified';

  @override
  String get kycVerifiedBody =>
      'Identity verified. Deposits and withdrawals unlocked.';

  @override
  String get kycRejected => 'Rejected';

  @override
  String get kycRejectedBody => 'Check refused: you must be 18 or older.';

  @override
  String get kycNotStarted => 'Not verified';

  @override
  String get kycGoToWallet => 'Go to wallet';

  @override
  String get walletTitle => 'Wallet';

  @override
  String get walletBalance => 'Available balance';

  @override
  String get walletInPlay => 'In play';

  @override
  String get walletDepositLimit => 'Deposited today';

  @override
  String get walletHistory => 'History';

  @override
  String get walletKycNeeded => 'Verify your identity to deposit or withdraw.';

  @override
  String get deposit => 'Deposit';

  @override
  String get withdraw => 'Withdraw';

  @override
  String get depositConfirm => 'Confirm simulated deposit';

  @override
  String get withdrawConfirm => 'Confirm simulated withdrawal';

  @override
  String depositDone(String amount) {
    return 'Simulated deposit of $amount done.';
  }

  @override
  String withdrawDone(String amount) {
    return 'Simulated withdrawal of $amount done.';
  }

  @override
  String get paymentSimulationBanner =>
      'SIMULATION — pre-filled test number, not editable. No banking data is requested or sent.';

  @override
  String get paymentTestValue => 'Fixed test value';

  @override
  String get paymentAmountInvalid => 'Invalid amount (minimum \$1.00).';

  @override
  String get methodCard => 'Card';

  @override
  String get methodCrypto => 'Crypto';

  @override
  String get methodBank => 'Transfer';

  @override
  String get cardNumber => 'Card number (test)';

  @override
  String get cardExpiry => 'Expiry';

  @override
  String get cardCvc => 'CVC';

  @override
  String get cryptoAddress => 'Address (test)';

  @override
  String get iban => 'IBAN (test)';

  @override
  String get ledgerWelcome => 'Welcome bonus';

  @override
  String get ledgerDeposit => 'Simulated deposit';

  @override
  String get ledgerWithdrawal => 'Simulated withdrawal';

  @override
  String get ledgerBet => 'Bet';

  @override
  String get ledgerWin => 'Win';

  @override
  String get ledgerPush => 'Push';

  @override
  String get ledgerPower => 'Power purchase';

  @override
  String get ledgerTrade => 'Market order';

  @override
  String get ledgerMarketPayout => 'Market settlement';

  @override
  String get ledgerAd => 'Ad reward';

  @override
  String get navLobby => 'Lobby';

  @override
  String get navMarkets => 'Markets';

  @override
  String get navLeaderboard => 'Ranking';

  @override
  String get navWallet => 'Wallet';

  @override
  String get navProfile => 'Profile';

  @override
  String get lobbyHeroTitle => 'Live blackjack';

  @override
  String get lobbyHeroSubtitle =>
      '5 seats and a dealer who really deals. Blackjack pays 3 to 2.';

  @override
  String get lobbyQuickPlay => 'Quick play';

  @override
  String get lobbyDealerDemo => 'Dealer demo';

  @override
  String get lobbyStakes => 'Stakes';

  @override
  String get lobbyLiveTables => 'Live tables';

  @override
  String get lobbyAllTiers => 'All';

  @override
  String lobbyTierStats(int tables, int players) {
    return '$tables tables · $players players';
  }

  @override
  String get tierMicro => 'Micro';

  @override
  String get tierLow => 'Low';

  @override
  String get tierMid => 'Mid';

  @override
  String get tierHigh => 'High';

  @override
  String get tierVip => 'VIP';

  @override
  String get tableFull => 'Full';

  @override
  String get winKindBlackjack => 'blackjack';

  @override
  String get winKindDouble => 'double won';

  @override
  String get winKindSplit => 'split won';

  @override
  String get winKindMarket => 'spectator bet';

  @override
  String get winKindWin => 'hand won';

  @override
  String get feltPayout => 'BLACKJACK PAYS 3 TO 2';

  @override
  String get feltInsurance => 'INSURANCE PAYS 2 TO 1';

  @override
  String get feltRule => 'Dealer must stand on all 17s';

  @override
  String get seatOpen => 'Open';

  @override
  String get badgeBlackjack => 'BLACKJACK';

  @override
  String get badgeBust => 'BUST';

  @override
  String get badgeWin => 'WIN';

  @override
  String get badgeLose => 'LOSE';

  @override
  String get badgePush => 'PUSH';

  @override
  String get actionHit => 'Hit';

  @override
  String get actionStand => 'Stand';

  @override
  String get actionDouble => 'Double';

  @override
  String get actionSplit => 'Split';

  @override
  String get actionSurrender => 'Surrender';

  @override
  String get actionInsurance => 'Insurance';

  @override
  String actionSent(String action) {
    return 'Action sent: $action';
  }

  @override
  String get fairTitle => 'Provably fair';

  @override
  String get fairBody =>
      'SHA-256 fingerprint of the shoe seed, published before the hand. The seed is revealed when the shoe ends so you can verify it.';

  @override
  String get leaveTable => 'Leave table';

  @override
  String get powers => 'Powers';

  @override
  String get powersSheetTitle => 'Use a power';

  @override
  String get powersSheetHint => 'One power per hand, validated by the server.';

  @override
  String get dealerDemoTitle => 'Dealer demo';

  @override
  String get dealerIdle => 'Idle';

  @override
  String dealerQueue(int n, String seconds) {
    return '$n queued · ${seconds}s';
  }

  @override
  String get dealerSpeed => 'Speed';

  @override
  String get dealerLoop => 'Loop';

  @override
  String get dealerPlayRound => 'Play a hand';

  @override
  String get dealerShuffle => 'Shuffle';

  @override
  String get dealerReset => 'Reset';

  @override
  String dealerRounds(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n hands played',
      one: '1 hand played',
      zero: 'No hands played',
    );
    return '$_temp0';
  }

  @override
  String get shopTitle => 'Power shop';

  @override
  String get shopSubtitle => 'Free split, peek, second chance…';

  @override
  String get shopIntro =>
      'Paid with play money. One power per hand, always validated by the server.';

  @override
  String shopOwned(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n owned',
      one: '1 owned',
      zero: 'None owned',
    );
    return '$_temp0';
  }

  @override
  String shopBought(String name) {
    return '$name added to your inventory.';
  }

  @override
  String get powerFreeSplit => 'Free split';

  @override
  String get powerFreeSplitDesc => 'Split a pair without a second bet.';

  @override
  String get powerFreeDouble => 'Free double';

  @override
  String get powerFreeDoubleDesc => 'Double down without adding to your bet.';

  @override
  String get powerFreeInsurance => 'Free insurance';

  @override
  String get powerFreeInsuranceDesc =>
      'Free insurance when the dealer shows an ace.';

  @override
  String get powerPeek => 'Peek';

  @override
  String get powerPeekDesc => 'See the dealer\'s hole card (only you).';

  @override
  String get powerSecondChance => 'Second chance';

  @override
  String get powerSecondChanceDesc => 'Replaces the last card you drew.';

  @override
  String get customizeTitle => 'Customise';

  @override
  String get customizeSubtitle => 'Card backs, faces, felt';

  @override
  String get customizeFaces => 'Face style';

  @override
  String get customizeBacks => 'Back pattern';

  @override
  String get customizeBackColor => 'Back colour';

  @override
  String get customizeFelt => 'Felt';

  @override
  String get customizeEquip => 'Equip';

  @override
  String get customizeEquipped => 'Equipped';

  @override
  String get customizeSaved => 'Style equipped.';

  @override
  String get faceClassic => 'Classic';

  @override
  String get faceFourColor => 'Four-colour';

  @override
  String get faceNeon => 'Neon';

  @override
  String get backLattice => 'Lattice';

  @override
  String get backStripes => 'Stripes';

  @override
  String get backChevron => 'Chevron';

  @override
  String get backDots => 'Dots';

  @override
  String get backSunburst => 'Sunburst';

  @override
  String get feltGreen => 'Casino green';

  @override
  String get feltNavy => 'Navy';

  @override
  String get feltCrimson => 'Crimson';

  @override
  String get feltPurple => 'Purple';

  @override
  String get feltCharcoal => 'Charcoal';

  @override
  String get leaderboardTitle => 'Leaderboard';

  @override
  String get lbGlobal => 'Global';

  @override
  String get lbFriends => 'Friends';

  @override
  String get lbWeekly => 'Weekly';

  @override
  String get lbPointsRule =>
      'Win +10 · Blackjack +25 · Loss −5. Tiers: Bronze → Diamond.';

  @override
  String lbHandsWinRate(int hands, String rate) {
    final intl.NumberFormat handsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String handsString = handsNumberFormat.format(hands);

    return '$handsString hands · $rate won';
  }

  @override
  String lbPoints(String points) {
    return '$points pts';
  }

  @override
  String get tierBronze => 'Bronze';

  @override
  String get tierSilver => 'Silver';

  @override
  String get tierGold => 'Gold';

  @override
  String get tierPlatinum => 'Platinum';

  @override
  String get tierDiamond => 'Diamond';

  @override
  String get friendsTitle => 'Friends';

  @override
  String get friendsSearchHint => 'Search a username';

  @override
  String get friendsAdd => 'Add';

  @override
  String friendsRequestSent(String name) {
    return 'Request sent to $name.';
  }

  @override
  String friendsRequests(int n) {
    return 'Requests ($n)';
  }

  @override
  String get friendsWantsToAdd => 'wants to add you';

  @override
  String get friendsList => 'My friends';

  @override
  String friendsAtTable(String table) {
    return 'Playing at $table';
  }

  @override
  String get marketsTitle => 'Markets';

  @override
  String get marketsPortfolio => 'Portfolio value';

  @override
  String get marketsPnl => 'Profit / loss';

  @override
  String get filterAll => 'All';

  @override
  String get filterHand => 'Per hand';

  @override
  String get filterShoe => 'Per shoe';

  @override
  String get filterMine => 'My positions';

  @override
  String get mqDealerBusts => 'Will the dealer bust?';

  @override
  String mqPlayerWins(String player) {
    return 'Will $player win?';
  }

  @override
  String get mqNatural => 'Any natural blackjack?';

  @override
  String get mqShoe => 'Dealer busts 3+ times this shoe?';

  @override
  String get marketPerShoe => 'current shoe';

  @override
  String marketVolume(String volume) {
    return 'Vol. $volume';
  }

  @override
  String get marketResolvedYes => 'Resolved: YES';

  @override
  String get marketResolvedNo => 'Resolved: NO';

  @override
  String get marketTitle => 'Market';

  @override
  String marketChanceLabel(String pct) {
    return '$pct chance';
  }

  @override
  String get marketWatchTable => 'Watch table';

  @override
  String get marketClosedNotice => 'This market is closed.';

  @override
  String get marketYourPositions => 'Your positions';

  @override
  String positionShares(int n, String price) {
    return '$n shares · avg $price';
  }

  @override
  String positionValue(String value) {
    return 'Value: $value';
  }

  @override
  String get marketActivity => 'Activity';

  @override
  String get tradeBought => 'bought';

  @override
  String get tradeSold => 'sold';

  @override
  String get marketRules => 'Rules';

  @override
  String get marketRulesBody =>
      'Each winning share pays \$1.00 in play money. Prices are set by an automated market maker (LMSR). The market closes before the dealer reveals the hole card. Not allowed on your own table.';

  @override
  String get shares => 'Shares';

  @override
  String get ticketAvgPrice => 'Avg price';

  @override
  String get ticketCost => 'Cost';

  @override
  String get ticketProceeds => 'You receive';

  @override
  String get ticketPayout => 'Payout if right';

  @override
  String get ticketPriceAfter => 'Price after order';

  @override
  String ticketSubmit(String side, String outcome) {
    return '$side $outcome';
  }

  @override
  String get ticketDone => 'Order sent.';

  @override
  String get ticketDisclaimer =>
      'Estimate: the final price is computed by the server.';

  @override
  String get adLabel => 'AD';

  @override
  String get adsTitle => 'Fake ads';

  @override
  String get adsIntro =>
      'Parody ads, no links, no tracking: banner, interstitial and rewarded video.';

  @override
  String get adsShowInterstitial => 'Show an interstitial';

  @override
  String get adsShowRewarded => 'Watch a rewarded video';

  @override
  String get adCoinTagline =>
      'The crypto that never goes up. Guaranteed no surprises.';

  @override
  String get adCoinCta => 'Don\'t buy';

  @override
  String get adBankTagline => 'Imaginary interest on your imaginary money.';

  @override
  String get adBankCta => 'Open a fake account';

  @override
  String get adAiTagline => 'The toaster that answers your emails. Badly.';

  @override
  String get adAiCta => 'Toast';

  @override
  String get adNftTagline =>
      'Adopt a pixel. It does nothing, but it\'s unique.';

  @override
  String get adNftCta => 'Adopt';

  @override
  String get adParodyNotice => 'This is a parody. None of these brands exist.';

  @override
  String adCloseIn(int n) {
    return 'Close in ${n}s';
  }

  @override
  String get adRewardedTitle => 'Rewarded video';

  @override
  String get adRewardWatching => 'Watch to the end to get credited…';

  @override
  String adRewardReady(String amount) {
    return 'Reward ready: $amount';
  }

  @override
  String adRewardCredited(String amount) {
    return '$amount credited to your balance.';
  }

  @override
  String get adRewardCap => 'Daily reward cap reached.';

  @override
  String get adClaim => 'Claim';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsFeedback => 'Sound & haptics';

  @override
  String get settingsSound => 'Sounds';

  @override
  String get settingsHaptics => 'Haptic feedback';

  @override
  String get settingsServerHint => 'Firebase emulators address';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAboutBody =>
      'Vingt-Un is a teaching project: 100% play money, local server (Firebase emulators), no real data.';

  @override
  String get rulesSummary =>
      'Rules: 6 decks, dealer stands on all 17s, blackjack pays 3:2, insurance 2:1, double on any two cards (also after split), split up to 4 hands, split aces get one card each, late surrender.';
}
