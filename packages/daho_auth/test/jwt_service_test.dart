import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

User _user({String id = 'u1', String email = 'a@example.com'}) => User(
  id: id,
  email: email,
  name: 'Test',
  passwordHash: 'hash',
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

void main() {
  group('JwtService', () {
    late JwtService jwt;

    setUp(() {
      jwt = JwtService(const JwtConfig(secret: 'test-secret'));
    });

    test('issues an access + refresh token pair', () {
      final pair = jwt.issueTokenPair(_user());
      expect(pair.accessToken, isNotEmpty);
      expect(pair.refreshToken, isNotEmpty);
      expect(pair.accessToken, isNot(equals(pair.refreshToken)));
    });

    test('access token verifies with correct claims', () {
      final pair = jwt.issueTokenPair(_user(id: 'u42', email: 'x@y.com'));
      final claims = jwt.verify(pair.accessToken);
      expect(claims, isNotNull);
      expect(claims!['sub'], 'u42');
      expect(claims['email'], 'x@y.com');
      expect(claims['type'], 'access');
      expect(claims['iss'], 'daho-auth');
    });

    test('refresh token carries a unique jti and type=refresh', () {
      final pair = jwt.issueTokenPair(_user());
      final claims = jwt.verify(pair.refreshToken);
      expect(claims!['type'], 'refresh');
      expect(claims['jti'], isNotEmpty);

      final pair2 = jwt.issueTokenPair(_user());
      final claims2 = jwt.verify(pair2.refreshToken);
      expect(claims2!['jti'], isNot(equals(claims['jti'])));
    });

    test('rejects a malformed token', () {
      expect(jwt.verify('not-a-jwt'), isNull);
    });

    test('rejects a token signed with a different secret', () {
      final other = JwtService(const JwtConfig(secret: 'other-secret'));
      final pair = other.issueTokenPair(_user());
      expect(jwt.verify(pair.accessToken), isNull);
    });

    test('rejects a tampered payload (signature no longer matches)', () {
      final pair = jwt.issueTokenPair(_user());
      final parts = pair.accessToken.split('.');
      expect(parts.length, 3);
      // Flip the signature so it can no longer verify against the payload.
      final tampered = '${parts[0]}.${parts[1]}.${parts[2]}x';
      expect(jwt.verify(tampered), isNull);
    });

    test('rejects an expired access token', () {
      final shortLived = JwtService(
        const JwtConfig(
          secret: 'test-secret',
          accessTokenLifetime: Duration(seconds: -1),
        ),
      );
      final pair = shortLived.issueTokenPair(_user());
      expect(jwt.verify(pair.accessToken), isNull);
    });

    test('access and refresh lifetimes are honored in exp claim', () {
      final custom = JwtService(
        const JwtConfig(
          secret: 'test-secret',
          accessTokenLifetime: Duration(minutes: 5),
          refreshTokenLifetime: Duration(days: 1),
        ),
      );
      final pair = custom.issueTokenPair(_user());
      final access = custom.verify(pair.accessToken)!;
      final refresh = custom.verify(pair.refreshToken)!;

      final accessExp = access['exp'] as int;
      final refreshExp = refresh['exp'] as int;
      final iat = access['iat'] as int;

      expect(accessExp - iat, closeTo(const Duration(minutes: 5).inSeconds, 2));
      expect(refreshExp - iat, closeTo(const Duration(days: 1).inSeconds, 2));
    });
  });
}
