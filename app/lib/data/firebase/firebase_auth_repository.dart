import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/ids.dart';
import '../../domain/models.dart';
import '../live.dart';
import '../repositories.dart';
import 'backend_api.dart';
import 'firebase_context.dart';
import 'firebase_errors.dart';

/// Firebase Auth (email/password) + `completeProfile` + live
/// `profiles/{uid}` and `users/{uid}/private/kyc` composed into [AppUser].
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._ctx) {
    _authSub = _ctx.auth.authStateChanges().listen(_onAuth, onError: (Object e) => debugPrint('[auth] $e'));
  }

  final FirebaseContext _ctx;
  final _user = Live<AppUser?>(null);
  StreamSubscription<User?>? _authSub;
  StreamSubscription<Json?>? _profileSub;
  StreamSubscription<Json?>? _kycSub;
  String? _uid;
  PlayerProfile? _profile;
  bool _profileKnown = false;
  KycStatus _kyc = KycStatus.none;
  String _email = '';

  void _onAuth(User? u) {
    if (u?.uid == _uid) return;
    unawaited(_profileSub?.cancel());
    unawaited(_kycSub?.cancel());
    _uid = u?.uid;
    _profile = null;
    _profileKnown = false;
    _kyc = KycStatus.none;
    if (u == null) {
      _user.value = null;
      return;
    }
    _email = u.email ?? '';
    final uid = u.uid;
    _profileSub = _ctx.docData(FirestorePaths.profile(uid), reportCache: true).listen((d) {
      _profile = d == null ? null : PlayerProfile.fromDoc(d, id: uid);
      _profileKnown = true;
      _emit();
    }, onError: (Object e) => debugPrint('[auth] profile listener: $e'));
    _kycSub = _ctx.docData(FirestorePaths.kyc(uid)).listen((d) {
      _kyc = d == null ? KycStatus.none : KycState.fromDoc(d).status;
      _emit();
    }, onError: (Object e) => debugPrint('[auth] kyc listener: $e'));
  }

  /// Emits only once the profile snapshot is known, so a returning user is
  /// not briefly seen as "profile incomplete".
  void _emit() {
    final uid = _uid;
    if (uid == null || !_profileKnown) return;
    _user.value = AppUser.fromProfile(uid: uid, email: _email, profile: _profile, kycStatus: _kyc);
  }

  @override
  AppUser? get currentUser => _user.value;

  @override
  Stream<AppUser?> authStateChanges() => _user.stream;

  Future<AppUser> _waitFor(String uid, {bool needProfile = false}) async {
    try {
      final u = await _user.stream
          .firstWhere((u) => u != null && u.uid == uid && (!needProfile || u.profileComplete))
          .timeout(const Duration(seconds: 10));
      return u!;
    } on TimeoutException {
      return _user.value ?? AppUser.fromProfile(uid: uid, email: _email);
    }
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    final UserCredential cred;
    try {
      cred = await _ctx.auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(authFailureForCode(e.code), e.message);
    } on Exception catch (e) {
      throw AuthException(AuthFailure.network, e.toString());
    }
    return _waitFor(cred.user!.uid);
  }

  @override
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String username,
    String avatar = 'avatar01',
    String? language,
  }) async {
    final UserCredential cred;
    try {
      cred = await _ctx.auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(authFailureForCode(e.code), e.message);
    } on Exception catch (e) {
      throw AuthException(AuthFailure.network, e.toString());
    }
    try {
      await _ctx.call('completeProfile', Payloads.completeProfile(username: username, avatar: avatar, language: language),
          idempotencyKey: newIdempotencyKey());
    } on RepositoryException catch (e) {
      final form = authExceptionForProfileError(e);
      if (form != null && form.failure != AuthFailure.profileExists) {
        // Free the e-mail so the user can retry with another username.
        try {
          await cred.user?.delete();
        } on Object catch (d) {
          debugPrint('[auth] could not delete the new account: $d');
        }
      }
      throw form ?? e;
    }
    return _waitFor(cred.user!.uid, needProfile: true);
  }

  @override
  Future<AppUser> completeProfile({
    required String username,
    required String avatar,
    String? language,
    required String idempotencyKey,
  }) async {
    final uid = _ctx.requireUid();
    try {
      await _ctx.call('completeProfile', Payloads.completeProfile(username: username, avatar: avatar, language: language),
          idempotencyKey: idempotencyKey);
    } on RepositoryException catch (e) {
      throw authExceptionForProfileError(e) ?? e;
    }
    return _waitFor(uid, needProfile: true);
  }

  @override
  Stream<PlayerProfile?> watchProfile(String uid) =>
      _ctx.docData(FirestorePaths.profile(uid)).map((d) => d == null ? null : PlayerProfile.fromDoc(d, id: uid));

  @override
  Future<void> signOut() => _ctx.auth.signOut();

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _profileSub?.cancel();
    await _kycSub?.cancel();
    await _user.close();
  }
}

/// `users/{uid}/private/kyc` + callable `submitKyc`. While pending, a
/// `submitKyc{refresh:true}` is scheduled just after `verifyAfterMs`.
class FirebaseKycRepository implements KycRepository {
  FirebaseKycRepository(this._ctx);
  final FirebaseContext _ctx;
  Timer? _refreshTimer;
  DateTime? _scheduledFor;

  void _schedule(KycState s) {
    final at = s.verifyAfter;
    if (s.status != KycStatus.pending || at == null) {
      _refreshTimer?.cancel();
      _scheduledFor = null;
      return;
    }
    if (_scheduledFor == at && (_refreshTimer?.isActive ?? false)) return;
    _refreshTimer?.cancel();
    _scheduledFor = at;
    var delay = at.difference(_ctx.now()) + const Duration(milliseconds: 400);
    if (delay.isNegative) delay = Duration.zero;
    _refreshTimer = Timer(delay, () async {
      try {
        await refresh(idempotencyKey: newIdempotencyKey());
      } on Object catch (e) {
        debugPrint('[kyc] refresh failed: $e');
      }
    });
  }

  @override
  Stream<KycState> watchKyc() => _ctx.perUser(
        (uid) => _ctx.docData(FirestorePaths.kyc(uid)).map((d) {
          final s = d == null ? const KycState() : KycState.fromDoc(d);
          _schedule(s);
          return s;
        }),
        const KycState(),
      );

  @override
  Future<KycState> submit(KycSubmission submission, {required String idempotencyKey}) async {
    final s = KycState.fromResponse(await _ctx.call('submitKyc', Payloads.submitKyc(submission), idempotencyKey: idempotencyKey));
    _schedule(s);
    return s;
  }

  @override
  Future<KycState> refresh({required String idempotencyKey}) async {
    final s = KycState.fromResponse(await _ctx.call('submitKyc', Payloads.submitKycRefresh(), idempotencyKey: idempotencyKey));
    _schedule(s);
    return s;
  }

  void dispose() => _refreshTimer?.cancel();
}
