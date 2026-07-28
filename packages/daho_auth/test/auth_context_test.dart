import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

import 'helpers/request_helpers.dart';

User _user() => User(
  id: 'u1',
  email: 'a@example.com',
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

void main() {
  group('AuthContext', () {
    test('isAuthenticated is false and requireUser throws when anonymous', () {
      final ctx = AuthContext();
      expect(ctx.isAuthenticated, isFalse);
      expect(() => ctx.requireUser(), throwsA(isA<UnauthorizedException>()));
    });

    test('isAuthenticated is true and requireUser returns the user when set', () {
      final ctx = AuthContext()..user = _user();
      expect(ctx.isAuthenticated, isTrue);
      expect(ctx.requireUser().id, 'u1');
    });
  });

  group('AuthRequestExtension', () {
    test('req.auth lazily creates and memoizes one AuthContext per request', () {
      final req = buildRequest();
      final first = req.auth;
      final second = req.auth;
      expect(identical(first, second), isTrue);
    });

    test('different requests get independent AuthContext instances', () {
      final reqA = buildRequest();
      final reqB = buildRequest();
      reqA.auth.user = _user();
      expect(reqB.auth.isAuthenticated, isFalse);
    });
  });
}
