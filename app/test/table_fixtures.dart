/// Builders of `tables/{id}` documents in the exact backend shape
/// (`TableDoc` of `firebase/functions/src/shared/types.ts`), card codes with
/// `T` for ten, for director / rules / table screen tests.
library;

const kT0 = 1795000000000;

Map<String, Object?> handDoc(
  List<String> cards, {
  int bet = 1000,
  int? staked,
  bool done = false,
  String? result,
  int? ret,
  bool doubled = false,
  bool fromSplit = false,
  bool splitAces = false,
  int total = 0,
  bool soft = false,
}) =>
    {
      'cards': cards, 'total': total, 'soft': soft, 'betCents': bet, 'stakedCents': staked ?? bet, 'doubled': doubled,
      'fromSplit': fromSplit, 'splitAces': splitAces, 'surrendered': result == 'surrender', 'busted': result == 'bust',
      'blackjack': result == 'blackjack', 'done': done, 'result': result, 'returnCents': ret,
    };

Map<String, Object?> seatDoc(
  int i,
  String uid, {
  int bet = 0,
  List<Map<String, Object?>> hands = const [],
  bool bot = false,
  Map<String, Object?>? insurance,
  String? powerUsed,
  int? net,
  String status = 'active',
}) =>
    {
      'seatIndex': i, 'uid': uid, 'username': uid == 'me' ? 'Moi' : 'P$i', 'avatar': 'avatar01', 'isBot': bot,
      'rankTier': 'bronze', 'status': status, 'joinedAtMs': kT0, 'betCents': bet, 'hands': hands,
      'insurance': insurance, 'powerUsed': powerUsed, 'roundNetCents': net, 'missedRounds': 0,
    };

Map<String, Object?> ev(
  int seq,
  String type, {
  int? seat,
  int? hand,
  String? card,
  int? amount,
  String? result,
  String? power,
  bool? dealerBlackjack,
}) =>
    {
      'seq': seq, 'type': type, 'seatIndex': seat, 'handIndex': hand, 'card': card, 'amountCents': amount,
      'result': result, 'power': power, 'dealerBlackjack': dealerBlackjack, 'atMs': kT0 + seq,
    };

Map<String, Object?> tableDoc({
  String id = 'tbl',
  int hand = 1,
  String phase = 'betting',
  List<Map<String, Object?>?> seats = const [null, null, null, null, null],
  List<String> dealerCards = const [],
  bool holeHidden = false,
  Map<String, int>? turn,
  int? deadlineMs,
  List<Map<String, Object?>> events = const [],
  int? eventSeq,
  bool isPrivate = false,
  List<Map<String, Object?>> queue = const [],
}) {
  final padded = [...seats, for (var i = seats.length; i < 5; i++) null];
  return {
    'tableId': id, 'name': 'Table $id', 'stakeTier': 'low', 'minBetCents': 100, 'maxBetCents': 10000,
    'isPrivate': isPrivate, 'simManaged': false, 'status': 'open', 'phase': phase, 'phaseStartedAtMs': kT0,
    'deadlineMs': deadlineMs, 'handNumber': hand,
    'shoe': {'shoeNumber': 1, 'totalCards': 312, 'cardsRemaining': 300, 'handsDealt': 0, 'dealerBusts': 0, 'naturals': 0},
    'seats': padded,
    'dealer': {'cards': dealerCards, 'holeHidden': holeHidden, 'total': null, 'soft': false, 'blackjack': false, 'busted': false},
    'turn': turn,
    'fairness': {'currentCommit': 'abc', 'currentHandNumber': hand, 'lastHandNumber': null, 'lastCommit': null, 'lastSeed': null},
    'events': events,
    'eventSeq': eventSeq ?? (events.isEmpty ? 0 : events.map((e) => e['seq']! as int).reduce((a, b) => a > b ? a : b)),
    'humanCount': 1, 'botCount': 0, 'seatedUids': <String>[], 'queue': queue,
    'markets': {'dealerBust': null, 'natural': null, 'shoe': null, 'players': <String, String>{}},
    'rankTier': 'bronze', 'createdAtMs': kT0, 'updatedAtMs': kT0,
  };
}
