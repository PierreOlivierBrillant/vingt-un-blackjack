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
  String get navLobby => 'Casino';

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
      'Before each hand the server publishes the SHA-256 of a secret seed. After the hand it reveals the seed, so anyone can recompute the exact card order.';

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
      'Win +10 · Blackjack +15 · Push +2 · Loss −4. Tiers: Bronze → Diamond.';

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
  String get mqShoe => 'Dealer busts in at least 28% of this shoe\'s hands?';

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

  @override
  String get errReasonInvalidArgument =>
      'Invalid request. Please check the values you entered.';

  @override
  String get errReasonUnauthenticated =>
      'Your session has expired. Please sign in again.';

  @override
  String get errReasonRateLimited =>
      'Too many requests. Wait a moment and try again.';

  @override
  String get errReasonRequestIdReused =>
      'Duplicate request rejected. Please try again.';

  @override
  String get errReasonProfileRequired =>
      'Please finish creating your profile first.';

  @override
  String get errReasonProfileExists => 'Your profile already exists.';

  @override
  String get errReasonUsernameTaken => 'This username is already taken.';

  @override
  String get errReasonKycRequired =>
      'Identity check required before any deposit or withdrawal.';

  @override
  String get errReasonKycAlreadyVerified =>
      'Your identity is already verified.';

  @override
  String get errReasonKycRejected =>
      'Identity check rejected (under 18). This decision is final.';

  @override
  String get errReasonInsufficientFunds => 'Insufficient balance.';

  @override
  String get errReasonDepositLimit =>
      'Amount out of limits: \$5 to \$1,000 per deposit, \$5,000 per day.';

  @override
  String get errReasonTableNotFound => 'This table does not exist.';

  @override
  String get errReasonTableClosed => 'This table is closed.';

  @override
  String get errReasonTableFull => 'This private table is full.';

  @override
  String get errReasonBadCode => 'Unknown table code.';

  @override
  String get errReasonAlreadySeated =>
      'You are already seated at another table. Leave it first.';

  @override
  String get errReasonNotSeated => 'You are not seated at this table.';

  @override
  String get errReasonBadPhase =>
      'This action is not allowed at this point of the hand.';

  @override
  String get errReasonStaleHand => 'The hand has moved on. Please try again.';

  @override
  String get errReasonAlreadyBet => 'You have already bet on this hand.';

  @override
  String get errReasonBetOutOfRange =>
      'Bet out of range (whole dollars, between the table minimum and maximum).';

  @override
  String get errReasonNotYourTurn => 'It is not your turn.';

  @override
  String get errReasonIllegalAction =>
      'This action is not allowed with this hand.';

  @override
  String get errReasonPowerNotOwned => 'You do not own this power.';

  @override
  String get errReasonPowerAlreadyUsed => 'Only one power per hand.';

  @override
  String get errReasonPowerNotApplicable =>
      'This power does not apply to this action.';

  @override
  String get errReasonInventoryFull => 'Inventory full (99 maximum).';

  @override
  String get errReasonMarketNotFound => 'This market does not exist.';

  @override
  String get errReasonMarketClosed => 'This market is closed.';

  @override
  String get errReasonOwnTableMarket =>
      'You cannot bet on the table you are playing at.';

  @override
  String get errReasonInsufficientShares =>
      'You do not have enough shares to sell.';

  @override
  String get errReasonSlippage =>
      'The price moved. Check the new price and try again.';

  @override
  String get errReasonMarketLimit =>
      'Order too large: the price would reach its limit.';

  @override
  String get errReasonUserNotFound => 'Player not found.';

  @override
  String get errReasonSelfFriend => 'You cannot add yourself.';

  @override
  String get errReasonAlreadyFriends => 'You are already friends.';

  @override
  String get errReasonRequestExists => 'Friend request already sent.';

  @override
  String get errReasonRequestNotFound =>
      'This friend request no longer exists.';

  @override
  String get errReasonNotFriends => 'You are not friends.';

  @override
  String get errReasonAdCooldown => 'Wait 30 seconds between two rewards.';

  @override
  String get errReasonAdDailyLimit =>
      'Daily reward limit reached (10 per day).';

  @override
  String get errReasonInternal => 'Server error. Please try again later.';

  @override
  String get errFailureUnavailable =>
      'Server unreachable. Check your connection and the server address.';

  @override
  String get errFailurePermissionDenied => 'Action not allowed.';

  @override
  String get errFailureInvalidArgument => 'Invalid request.';

  @override
  String get errFailureInsufficientFunds => 'Insufficient funds.';

  @override
  String get errFailureKycRequired => 'Identity check required.';

  @override
  String get errFailureLimitExceeded => 'Limit reached.';

  @override
  String get errFailureRateLimited =>
      'Too many requests, please wait a moment.';

  @override
  String get errFailureNotFound => 'Not found.';

  @override
  String get errFailureUnknown => 'Something went wrong. Please try again.';

  @override
  String get errAuthInvalidCredentials => 'Wrong email or password.';

  @override
  String get errAuthInvalidEmail => 'Invalid email address.';

  @override
  String get errAuthEmailInUse => 'This email is already in use.';

  @override
  String get errAuthWeakPassword =>
      'Password too weak (at least 8 characters).';

  @override
  String get errAuthUsernameTaken => 'This username is already taken.';

  @override
  String get errAuthInvalidUsername =>
      'Invalid username: 3 to 16 characters, letters, digits or _.';

  @override
  String get errAuthProfileExists => 'Your profile already exists.';

  @override
  String get errAuthTooManyRequests =>
      'Too many attempts. Try again in a few minutes.';

  @override
  String get errAuthNetwork =>
      'Cannot reach the server. Check your connection.';

  @override
  String get errAuthUnknown => 'Authentication error. Please try again.';

  @override
  String get commonRetry => 'Retry';

  @override
  String get completeProfileTitle => 'Complete your profile';

  @override
  String get completeProfileIntro =>
      'Pick a username and an avatar to finish signing up. The welcome bonus is credited right after.';

  @override
  String get completeProfileSubmit => 'Finish';

  @override
  String get authUsernameRule => '3 to 16 characters: letters, digits or _';

  @override
  String get authAvatarTitle => 'Avatar';

  @override
  String get authLanguageTitle => 'Language';

  @override
  String get actionPeek => 'Peek';

  @override
  String tableBetting(int seconds) {
    return 'Place your bets · $seconds s';
  }

  @override
  String tablePlaceBet(String amount) {
    return 'Bet $amount';
  }

  @override
  String tableBetPlaced(String amount) {
    return 'Bet placed: $amount';
  }

  @override
  String get tableClearBet => 'Clear';

  @override
  String get tableWaitingNextHand =>
      'Hand in progress: you will play the next one.';

  @override
  String get tableQueued => 'Queued: you get a seat at the next hand.';

  @override
  String get tableSpectating => 'Spectator mode';

  @override
  String get tableSpectatorHint =>
      'You are watching this table. Bet on its markets!';

  @override
  String get tableMarkets => 'Bets';

  @override
  String tableYourTurn(int seconds) {
    return 'Your turn · $seconds s';
  }

  @override
  String tableTurnOf(String name, int seconds) {
    return '$name\'s turn · $seconds s';
  }

  @override
  String get tableInsuranceTitle => 'Insurance?';

  @override
  String tableInsuranceBody(String amount) {
    return 'The dealer shows an Ace. Insure up to $amount (pays 2 to 1 if the dealer has blackjack).';
  }

  @override
  String tableInsuranceTake(String amount) {
    return 'Insure $amount';
  }

  @override
  String get tableInsuranceDecline => 'No thanks';

  @override
  String tableInsuranceWait(int seconds) {
    return 'Insurance · $seconds s';
  }

  @override
  String tableResult(String amount) {
    return 'Hand result: $amount';
  }

  @override
  String get tableSettled => 'Hand over';

  @override
  String get tableDealerPlays => 'The dealer plays…';

  @override
  String get tableIdle => 'Waiting for players…';

  @override
  String get tableClosedNotice => 'This table is closed.';

  @override
  String tablePowerArmed(String name) {
    return 'Power ready: $name';
  }

  @override
  String tablePowerUsed(String name) {
    return 'Power used: $name';
  }

  @override
  String get tablePowerNone => 'None';

  @override
  String get tablePowerHint => 'Applies to your next compatible action.';

  @override
  String get tablePowerShop => 'Buy powers';

  @override
  String tablePeekCard(String card) {
    return 'Peek: hole card $card';
  }

  @override
  String tablePrivateCode(String code) {
    return 'Code: $code';
  }

  @override
  String tableSecondChance(String card) {
    return 'Second chance: card $card was replaced.';
  }

  @override
  String get tableOffline => 'Offline: the view may be out of date.';

  @override
  String get tableLeaveConfirm =>
      'Leave the table? A hand in progress is auto-stood.';

  @override
  String tableShoeInfo(int n, int cards) {
    return 'Shoe #$n · $cards cards';
  }

  @override
  String get fairCurrentCommit =>
      'Current hand commitment (SHA-256 of the seed)';

  @override
  String fairLastHand(int n) {
    return 'Hand #$n: revealed seed';
  }

  @override
  String get fairVerify => 'Verify the last hand';

  @override
  String fairVerified(int n) {
    return 'Verified: SHA-256(seed) = commitment, and the $n dealt cards match the recomputed order.';
  }

  @override
  String get fairFailed => 'Verification failed: the proof does not match.';

  @override
  String get fairNoHistory => 'No finished hand on this table yet.';

  @override
  String get lobbyPrivate => 'Private table';

  @override
  String get privateIntro =>
      'Play with friends, no bots: create a table and share its code, or join a friend\'s.';

  @override
  String get privateCreate => 'Create a table';

  @override
  String get privateJoin => 'Join';

  @override
  String get privateCodeLabel => 'Table code (6 characters)';

  @override
  String get privateCodeInvalid => '6 letters or digits.';

  @override
  String privateCreated(String code) {
    return 'Private table created. Code: $code';
  }

  @override
  String get friendsSuggestions => 'Suggestions';

  @override
  String get friendsSent => 'Sent requests';

  @override
  String get friendsPending => 'Waiting for an answer';

  @override
  String get friendsRemove => 'Remove';

  @override
  String friendsRemoved(String name) {
    return '$name removed from your friends.';
  }

  @override
  String friendsAccepted(String name) {
    return 'You are now friends with $name.';
  }

  @override
  String get friendsEmpty => 'No friends yet: search a username above.';

  @override
  String walletWatchAd(String amount) {
    return 'Watch an ad (+$amount)';
  }

  @override
  String adRewardsLeft(int n) {
    return '$n rewards left today';
  }

  @override
  String get marketsEmpty => 'No open market right now.';

  @override
  String get positionOpen => 'Open';

  @override
  String get positionWon => 'Won';

  @override
  String get positionLost => 'Lost';

  @override
  String get positionVoid => 'Refunded';

  @override
  String get tableBetsHere => 'Bets on this table';

  @override
  String get settingsEffectsVolume => 'Effects volume';

  @override
  String get settingsAmbienceVolume => 'Ambience volume';

  @override
  String get settingsSoundHint => 'Master switch: no effects, no ambience.';

  @override
  String get settingsSoundTry => 'Try';

  @override
  String get celebrationWin => 'WINNER!';

  @override
  String get celebrationBigWin => 'BIG WIN!';

  @override
  String celebrationStreak(int count) {
    return '$count WINS IN A ROW!';
  }

  @override
  String get celebrationDealerBust => 'DEALER BUSTS!';

  @override
  String profileRankPoints(int points) {
    return '$points ranking points';
  }

  @override
  String profileRankNext(int missing, String tier) {
    return '$missing pts to $tier';
  }

  @override
  String get profileRankMax => 'Top tier reached';

  @override
  String get ledgerBuyIn => 'Hold\'em buy-in';

  @override
  String get ledgerCashOut => 'Cash-out';

  @override
  String get ledgerGift => 'Gift';

  @override
  String get ledgerReservation => 'Date reservation';

  @override
  String get winKindJackpot => 'big hit';

  @override
  String get powerZeroShield => 'Zero shield';

  @override
  String get powerZeroShieldDesc =>
      'Roulette: if zero comes up, half of your even-money bets is returned (one spin).';

  @override
  String get powerFreeCommission => 'Free commission';

  @override
  String get powerFreeCommissionDesc =>
      'Baccarat: your Banker win is paid without the 5% commission (one coup).';

  @override
  String get powerSafetyNet => 'Safety net';

  @override
  String get powerSafetyNetDesc =>
      'Craps: your Pass Line bet is refunded on a seven-out (once).';

  @override
  String get mqRouletteRed => 'Red?';

  @override
  String get mqRouletteZero => 'Zero?';

  @override
  String get mqRouletteDozen3 => 'Third dozen (25–36)?';

  @override
  String get mqRouletteZeroSeries => 'A zero within the next 37 spins?';

  @override
  String get mqBaccaratBanker => 'Banker wins?';

  @override
  String get mqBaccaratTie => 'Tie?';

  @override
  String get mqBaccaratPair => 'A pair (Player or Banker)?';

  @override
  String get mqBaccaratBankerShoe =>
      'Banker wins at least 46% of this shoe\'s coups?';

  @override
  String get mqHoldemBoardAce => 'An ace on the board?';

  @override
  String get mqHoldemBoardFlush =>
      'Three or more cards of one suit on the board?';

  @override
  String get mqCrapsSeven => 'Seven on the next roll?';

  @override
  String get mqCrapsPoint => 'Shooter makes the point?';

  @override
  String get errReasonBadBetSpot =>
      'That bet spot does not exist in this game.';

  @override
  String get errReasonBetIncrement =>
      'Invalid amount for this bet (use the required multiple).';

  @override
  String get errReasonBetNotRemovable =>
      'This bet can no longer be taken down.';

  @override
  String get errReasonWrongGame => 'Action or power of another game.';

  @override
  String get errReasonBuyInOutOfRange => 'Buy-in outside the table limits.';

  @override
  String get errReasonRebuyNotAllowed =>
      'Rebuy not allowed now (between hands, below the maximum).';

  @override
  String get errReasonSittingOut => 'You are sitting out: sit back in first.';

  @override
  String get errReasonNotShooter => 'You are not the shooter.';

  @override
  String get errReasonMustBetLine =>
      'The shooter must bet the Pass or Don\'t Pass line.';

  @override
  String get errReasonSceneNotAvailable =>
      'This scene is not available right now.';

  @override
  String get errReasonSceneInvalidPath => 'Invalid choices for this scene.';

  @override
  String get errReasonTalkDoneToday =>
      'You already talked with this character today.';

  @override
  String get errReasonGiftDailyLimit =>
      'At most three gifts per day for this character.';

  @override
  String get errReasonCosmeticLocked => 'Item not unlocked yet.';

  @override
  String get errReasonDatingDisabled =>
      'Player dating is turned off on this server.';

  @override
  String get errReasonDatingOptInRequired => 'Join Rencontres first.';

  @override
  String get errReasonLikeDailyLimit => 'No winks left today (10 per day).';

  @override
  String get errReasonMatchNotFound => 'This match no longer exists.';

  @override
  String get errReasonBlocked => 'Not possible with this player.';

  @override
  String get errReasonLineNotAllowed => 'That line is not available here.';

  @override
  String get errReasonNoPrivateTable =>
      'Open a private table first to invite someone.';

  @override
  String get navRomance => 'Dates';

  @override
  String get lobbyChooseGame => 'Pick your game';

  @override
  String get lobbyNoTables => 'No open table right now.';

  @override
  String get gameBlackjack => 'Blackjack';

  @override
  String get gameRoulette => 'Roulette';

  @override
  String get gameBaccarat => 'Baccarat';

  @override
  String get gameHoldem => 'Texas hold\'em';

  @override
  String get gameCraps => 'Craps';

  @override
  String get gameTaglineRoulette =>
      'European roulette: 37 pockets, a single zero, 7 seats.';

  @override
  String get gameTaglineBaccarat =>
      'Punto Banco, 8-deck shoe, 7 seats. Banker pays 0.95 to 1.';

  @override
  String get gameTaglineHoldem =>
      'No-limit, player vs player, 6 seats, no rake, no powers.';

  @override
  String get gameTaglineCraps =>
      '8 seats, rotating shooter, true odds behind the line.';

  @override
  String gameHeroTitle(String game) {
    return 'Live $game';
  }

  @override
  String gameDealer(String name) {
    return 'Your dealer: $name';
  }

  @override
  String get gameComingSoon => 'SOON';

  @override
  String get gameComingSoonBody =>
      'This game opens soon: you can already watch its tables.';

  @override
  String get gameRules => 'Rules';

  @override
  String get gameHistory => 'History';

  @override
  String get gameHistoryEmpty => 'No finished round yet.';

  @override
  String gameRoundNumber(int n) {
    return 'Round #$n';
  }

  @override
  String gamePhaseBetting(int seconds) {
    return 'Place your bets · ${seconds}s';
  }

  @override
  String get gamePhaseLive => 'Round in progress';

  @override
  String gamePhaseLiveSecs(int seconds) {
    return 'Round in progress · ${seconds}s';
  }

  @override
  String gamePhaseSettled(int seconds) {
    return 'Round over · next in ${seconds}s';
  }

  @override
  String get gameSeatFree => 'Free';

  @override
  String get gameBot => 'Bot';

  @override
  String get gameYou => 'You';

  @override
  String gameStack(String amount) {
    return 'Stack $amount';
  }

  @override
  String gameStake(String amount) {
    return 'Bet $amount';
  }

  @override
  String gameSeatedAt(int n) {
    return 'You are in seat $n.';
  }

  @override
  String gameQueuedAt(int n) {
    return 'In the queue (#$n): seated at the next round.';
  }

  @override
  String get gamePlayThis => 'Play this game';

  @override
  String get gameNotFound => 'This table no longer exists.';

  @override
  String get gameBackToLobby => 'Back to the casino';

  @override
  String get gamePlaceholderTitle => 'Table being set up';

  @override
  String get gamePlaceholderBody =>
      'The dealer is getting ready: this game\'s bets and animations are coming soon.';

  @override
  String gameRoundResult(String amount) {
    return 'Round result: $amount';
  }

  @override
  String get gameFairBody =>
      'Before each round the server publishes the SHA-256 fingerprint of a secret seed; after the round it reveals the seed. The draw is recomputed from it: nobody, not even the casino, can change it midway.';

  @override
  String get gameFairCurrentCommit =>
      'Current round\'s commitment (SHA-256 of the seed)';

  @override
  String gameFairLastRound(int n) {
    return 'Round #$n: seed revealed';
  }

  @override
  String get gameFairVerify => 'Verify the last round';

  @override
  String get gameFairVerified =>
      'Verified: SHA-256(seed) = the commitment published before the round, and the recomputed draw matches.';

  @override
  String get gameFairCommitOnly =>
      'Verified: SHA-256(seed) = the commitment published before the round.';

  @override
  String gameMinMax(String min, String max) {
    return 'Bets $min – $max';
  }

  @override
  String get shopNoPowers =>
      'No powers in this game: player vs player, everything is played fair.';

  @override
  String get shopGroupHint => 'A power only works at the tables of its game.';

  @override
  String get profileStatsTitle => 'Stats by game';

  @override
  String profileStatsRounds(int rounds, int won) {
    String _temp0 = intl.Intl.pluralLogic(
      rounds,
      locale: localeName,
      other: '$rounds rounds',
      one: '1 round',
      zero: 'No round',
    );
    return '$_temp0 · $won won';
  }

  @override
  String profileStatsBest(String amount) {
    return 'Best win $amount';
  }

  @override
  String get profileStatsNone => 'Not played yet';

  @override
  String get profileTitle => 'Title';

  @override
  String get profileNoTitle => 'No title yet: earn one in Dates.';

  @override
  String titleCharacter(String name) {
    return '$name\'s sweetheart';
  }

  @override
  String get titleDuo => 'Inseparable duo';

  @override
  String get filterAllGames => 'All games';

  @override
  String marketPerRound(int n) {
    return 'round #$n';
  }

  @override
  String get gameLeaveConfirm =>
      'Leave the table? Bets not yet locked are refunded.';

  @override
  String get rouletteRulesSummary =>
      'Single-zero European roulette: 37 pockets in the real wheel order. The winning number is drawn by seededRng(seed).nextInt(37).';

  @override
  String get rouletteRulesPayouts =>
      'Straight 35:1 · Split 17:1 · Street and trios 0-1-2 / 0-2-3 11:1 · Corner and first four 8:1 · Six line 5:1 · Dozen, column 2:1 · Even-money bets 1:1. No \"la partage\" by default (house edge 2.70%).';

  @override
  String get rouletteRulesRound =>
      '20 s of betting → \"No more bets\" (draw) → about 8 s of spin → payout → next round. Call bets (voisins du zéro, tiers, orphelins, jeu zéro), Undo, Clear, Repeat and Double are computed by the app, which sends your whole bet board. Limits per bet and per round.';

  @override
  String get rouletteSeats => '7 seats, one chip colour per player.';

  @override
  String get baccaratRulesSummary =>
      'Punto Banco, 8-deck shoe (416 cards), cut 16 cards from the end. Burn according to the first card, included in the fairness proof. Official drawing chart (Banker\'s third card against 0–9).';

  @override
  String get baccaratRulesPayouts =>
      'Player 1:1 · Banker 0.95:1 (exact to the cent) · Tie 8:1 (Player and Banker returned) · Player Pair, Banker Pair 11:1.';

  @override
  String get baccaratRulesRound =>
      '20 s of betting, then the deal: animated squeeze, third card laid sideways. Trends shown: Bead Plate and Big Road.';

  @override
  String get baccaratSeats => '7 seats.';

  @override
  String get holdemRulesSummary =>
      'No-Limit Texas hold\'em between players: no rake, no powers. Blinds per tier 1/2, 5/10, 25/50 \$; buy-in 40 to 100 big blinds, debited when you sit down, credited back when you leave (after the hand if you are in it).';

  @override
  String get holdemRulesRound =>
      'Rotating button, heads-up rules, newcomers wait for the big blind, minimum raise = last raise, an incomplete all-in does not reopen the betting, side pots, automatic showdown (best 5 of 7). 20 s per decision; two timeouts in a row → sitting out; three hands sitting out → stack credited back and seat freed.';

  @override
  String get holdemRulesFairness =>
      'Deliberate choice: the seed revealed after the hand makes folded cards verifiable, hence visible to everyone.';

  @override
  String get holdemSeats => '6 seats.';

  @override
  String get holdemBuyInTitle => 'Your buy-in';

  @override
  String holdemBuyInBody(String min, String max) {
    return 'Between $min and $max (40 to 100 big blinds), debited when you sit down.';
  }

  @override
  String get holdemBuyInSit => 'Sit down';

  @override
  String get crapsRulesSummary =>
      'Pass Line and Don\'t Pass (bar 12), Come and Don\'t Come, 3-4-5× odds (true odds) and lay odds. Place: 4/10 at 9:5, 5/9 at 7:5, 6/8 at 7:6. Field: 2 pays 2:1, 12 pays 3:1.';

  @override
  String get crapsRulesPayouts =>
      'Propositions: Any 7 4:1, Any Craps 7:1, Hardways 7:1 or 9:1, Yo 15:1, 2 and 12 30:1, 3 15:1. Whole-dollar bets; place 6/8 and lay 5/9 or 6/8 in multiples of \$3.';

  @override
  String get crapsRulesRound =>
      'Every roll is a round with its own seed (nextInt(6)+1 twice). Place bets are off on the come-out; contract bets cannot be removed. The shooter must bet Pass or Don\'t Pass, rolls with a gesture or automatically after 15 s; the dice pass on after a seven-out.';

  @override
  String get crapsSeats => '8 seats, rotating shooter.';

  @override
  String get romanceHubTitle => 'Dates';

  @override
  String get romanceHubIntro =>
      'The casino\'s dealers and regulars: chat, give gifts, play at their table… who knows? Everything stays PG-13, between adults.';

  @override
  String get romanceHubSoon => 'Soon: chats, gifts, dates and Memories.';

  @override
  String get romanceDealers => 'Dealers';

  @override
  String get romanceRegulars => 'Regulars';

  @override
  String get romanceDatingTitle => 'Meet players';

  @override
  String get romanceDatingBody =>
      'Player-to-player dating, opt-in and without free text: disabled on this server for now.';

  @override
  String get romanceTierStranger => 'Stranger';

  @override
  String romanceAge(int age) {
    return '$age years old';
  }

  @override
  String get romanceRoleLucas => 'Blackjack dealer';

  @override
  String get romanceRoleCamille => 'Roulette dealer';

  @override
  String get romanceRoleInes => 'Baccarat dealer';

  @override
  String get romanceRoleAlex => 'Hold\'em dealer (they/them)';

  @override
  String get romanceRoleMarco => 'Craps dealer';

  @override
  String get romanceRoleJade => 'Bar mixologist';

  @override
  String get romanceRoleTheo => 'Lounge pianist';

  @override
  String get romanceRoleNora => 'Magician';

  @override
  String get romanceRoleHugo => 'VIP concierge';
}
