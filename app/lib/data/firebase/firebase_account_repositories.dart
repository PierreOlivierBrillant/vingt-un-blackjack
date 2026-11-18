/// Wallet, shop, cosmetics/settings and ads on Firestore + callables.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/card_style.dart';
import '../../domain/models.dart';
import '../fake/fake_data.dart' show FakeData;
import '../repositories.dart';
import 'backend_api.dart';
import 'firebase_context.dart';

class FirebaseWalletRepository implements WalletRepository {
  FirebaseWalletRepository(this._ctx);
  final FirebaseContext _ctx;

  @override
  Stream<WalletSnapshot> watchWallet() => _ctx.perUser(
        (uid) => _ctx
            .docData(FirestorePaths.wallet(uid))
            .map((d) => d == null ? const WalletSnapshot(balanceCents: 0) : WalletSnapshot.fromDoc(d, now: _ctx.now())),
        const WalletSnapshot(balanceCents: 0),
      );

  /// `users/{uid}/ledger` orderBy createdAtMs desc; `detail` = table or
  /// market label (looked up once, cached).
  @override
  Stream<List<LedgerEntry>> watchLedger({int limit = 50}) => _ctx.perUser(
        (uid) => _ctx
            .queryDocs(_ctx.col(FirestorePaths.ledger(uid)).orderBy('createdAtMs', descending: true).limit(limit))
            .asyncMap((docs) async {
          final entries = [for (final (id, d) in docs) ?LedgerEntry.fromDoc(d, id: id)];
          final tables = await _ctx.tableNames.getAll(entries.map((e) => e.tableId).nonNulls);
          final markets = await _ctx.marketLabels.getAll(entries.map((e) => e.marketId).nonNulls);
          return [
            for (final e in entries)
              e.withDetail(e.tableId != null
                  ? (tables[e.tableId] == null ? null : '${tables[e.tableId]}${e.handNumber == null ? '' : ' #${e.handNumber}'}')
                  : e.marketId != null
                      ? markets[e.marketId]
                      : null),
          ];
        }),
        const [],
      );

  @override
  Future<WalletMoveResult> deposit({required int amountCents, required PaymentMethod method, required String idempotencyKey}) async =>
      WalletMoveResult.fromResponse(
          await _ctx.call('deposit', Payloads.deposit(amountCents, method), idempotencyKey: idempotencyKey));

  @override
  Future<WalletMoveResult> withdraw({required int amountCents, required PaymentMethod method, required String idempotencyKey}) async =>
      WalletMoveResult.fromResponse(
          await _ctx.call('withdraw', Payloads.withdraw(amountCents, method), idempotencyKey: idempotencyKey));
}

class FirebaseShopRepository implements ShopRepository {
  FirebaseShopRepository(this._ctx);
  final FirebaseContext _ctx;

  @override
  Stream<List<PowerOffer>> watchOffers() => _ctx.perUser(
        (uid) => _ctx.queryDocs(_ctx.col(FirestorePaths.inventory(uid))).map(
              (docs) => PowerOffer.fromInventory([for (final (id, d) in docs) ?InventoryItem.fromDoc(d, id: id)]),
            ),
        PowerOffer.fromInventory(const []),
      );

  @override
  Future<BuyPowerResult> buy(PowerType type, {int quantity = 1, required String idempotencyKey}) async =>
      BuyPowerResult.fromResponse(
          await _ctx.call('buyPower', Payloads.buyPower(type, quantity), idempotencyKey: idempotencyKey));
}

class FirebaseCosmeticsRepository implements CosmeticsRepository {
  FirebaseCosmeticsRepository(this._ctx);
  final FirebaseContext _ctx;

  @override
  Stream<UserSettings> watchSettings() => _ctx.perUser(
        (uid) => _ctx.docData(FirestorePaths.userSettings(uid)).map((d) => UserSettings.fromDoc(d ?? const {})),
        const UserSettings(),
      );

  @override
  Stream<CardStyle> watchEquipped() => watchSettings().map((s) => s.style);

  @override
  Future<CardStyle> equip(CardStyle style, {required String idempotencyKey}) async {
    final r = await _ctx.call('equipCardStyle', Payloads.equipCardStyle(style), idempotencyKey: idempotencyKey);
    return CardStyle.fromWire(cardBack: r['cardBack'], cardFace: r['cardFace'], felt: r['felt']);
  }

  @override
  Future<void> saveSettings({ThemePreference? theme, String? language}) async {
    final uid = _ctx.uid;
    if (uid == null) return;
    await _ctx
        .doc(FirestorePaths.userSettings(uid))
        .set(Payloads.userSettings(theme: theme, language: language, now: _ctx.now()), SetOptions(merge: true));
  }
}

class FirebaseAdsRepository implements AdsRepository {
  FirebaseAdsRepository(this._ctx);
  final FirebaseContext _ctx;

  /// Parody creatives are client-side content (no backend document).
  @override
  List<ParodyAd> inventory(AdFormat format) => FakeData.ads;

  @override
  Stream<AdState> watchAdState() => _ctx.perUser(
        (uid) => _ctx.docData(FirestorePaths.ads(uid)).map((d) => d == null ? const AdState() : AdState.fromDoc(d)),
        const AdState(),
      );

  @override
  Future<AdRewardResult> claimReward(String adId, {required String idempotencyKey}) async =>
      AdRewardResult.fromResponse(
          await _ctx.call('claimAdReward', Payloads.claimAdReward(adId), idempotencyKey: idempotencyKey));
}
