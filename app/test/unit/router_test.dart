import 'package:flutter_test/flutter_test.dart';
import 'package:vingtun/domain/models.dart';
import 'package:vingtun/router.dart';

void main() {
  const noProfile = AppUser(uid: 'u', email: 'a@b.c', username: '', profileComplete: false);
  const complete = AppUser(uid: 'u', email: 'a@b.c', username: 'Alice');

  test('signed out → login; public pages stay reachable', () {
    expect(authRedirect(null, '/lobby'), '/login');
    expect(authRedirect(null, '/signup'), isNull);
    expect(authRedirect(null, '/server'), isNull);
  });

  test('sign-up in flight (account without profile yet) stays on the sign-up screen', () {
    expect(authRedirect(noProfile, '/signup'), isNull);
    expect(authRedirect(noProfile, '/lobby'), '/complete-profile');
    expect(authRedirect(noProfile, '/complete-profile'), isNull);
  });

  test('profile done: sign-up continues to KYC, other auth pages to the lobby', () {
    expect(authRedirect(complete, '/signup'), '/kyc');
    expect(authRedirect(complete, '/login'), '/lobby');
    expect(authRedirect(complete, '/complete-profile'), '/lobby');
    expect(authRedirect(complete, '/wallet'), isNull);
  });

  test('router refresh key: only sign-in state and profile completion count', () {
    // A profile snapshot that changes anything else (avatar, rank, KYC, balance, current table)
    // must not refresh the router: a refresh during a pop pushed the popped page back.
    expect(authRedirectKey(complete), authRedirectKey(complete.copyWith(avatar: 'avatar07', kycStatus: KycStatus.verified)));
    expect(authRedirectKey(complete), authRedirectKey(complete.copyWith(rankTier: RankTier.gold, username: 'Bob')));
    expect(authRedirectKey(null), isNot(authRedirectKey(complete)));
    expect(authRedirectKey(noProfile), isNot(authRedirectKey(complete)));
    expect(authRedirectKey(complete), isNot(authRedirectKey(const AppUser(uid: 'v', email: 'v@b.c', username: 'Vic'))));
  });
}
