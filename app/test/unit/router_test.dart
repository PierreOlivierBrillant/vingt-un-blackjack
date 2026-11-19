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
}
