import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

void main() {
  group('User', () {
    test('fromRow parses a full row', () {
      final createdAt = DateTime(2026, 1, 1);
      final updatedAt = DateTime(2026, 1, 2);
      final user = User.fromRow({
        'id': 'u1',
        'email': 'a@example.com',
        'name': 'Alice',
        'password_hash': r'$2a$12$hash',
        'created_at': createdAt,
        'updated_at': updatedAt,
      });

      expect(user.id, 'u1');
      expect(user.email, 'a@example.com');
      expect(user.name, 'Alice');
      expect(user.passwordHash, r'$2a$12$hash');
      expect(user.createdAt, createdAt);
      expect(user.updatedAt, updatedAt);
      expect(user.isOAuthUser, isFalse);
    });

    test('isOAuthUser is true when password_hash is null', () {
      final user = User.fromRow({
        'id': 'u1',
        'email': 'a@example.com',
        'name': null,
        'password_hash': null,
        'created_at': DateTime.now(),
        'updated_at': DateTime.now(),
      });
      expect(user.isOAuthUser, isTrue);
    });

    test('toJson never includes the password hash', () {
      final user = User.fromRow({
        'id': 'u1',
        'email': 'a@example.com',
        'name': 'Alice',
        'password_hash': r'$2a$12$hash',
        'created_at': DateTime.now(),
        'updated_at': DateTime.now(),
      });
      final json = user.toJson();
      expect(json, isNot(contains('passwordHash')));
      expect(json, isNot(contains('password_hash')));
      expect(json.values, isNot(contains(r'$2a$12$hash')));
    });

    test('toJson encodes dates as ISO8601 strings', () {
      final createdAt = DateTime(2026, 3, 4, 5, 6, 7);
      final user = User.fromRow({
        'id': 'u1',
        'email': 'a@example.com',
        'name': null,
        'password_hash': null,
        'created_at': createdAt,
        'updated_at': createdAt,
      });
      expect(user.toJson()['createdAt'], createdAt.toIso8601String());
    });
  });

  group('OAuthAccount', () {
    test('fromRow parses a full row', () {
      final createdAt = DateTime(2026, 1, 1);
      final account = OAuthAccount.fromRow({
        'id': 'oa1',
        'user_id': 'u1',
        'provider': 'google',
        'provider_user_id': 'g-123',
        'access_token': 'at',
        'refresh_token': 'rt',
        'created_at': createdAt,
      });
      expect(account.id, 'oa1');
      expect(account.userId, 'u1');
      expect(account.provider, 'google');
      expect(account.providerUserId, 'g-123');
      expect(account.accessToken, 'at');
      expect(account.refreshToken, 'rt');
      expect(account.createdAt, createdAt);
    });
  });

  group('Session', () {
    test('fromRow parses data as a Map and defaults to empty when null', () {
      final expiresAt = DateTime(2026, 1, 1);
      final createdAt = DateTime(2025, 12, 31);

      final withData = Session.fromRow({
        'id': 's1',
        'user_id': 'u1',
        'data': {'theme': 'dark'},
        'expires_at': expiresAt,
        'created_at': createdAt,
      });
      expect(withData.data, {'theme': 'dark'});

      final withoutData = Session.fromRow({
        'id': 's2',
        'user_id': 'u1',
        'data': null,
        'expires_at': expiresAt,
        'created_at': createdAt,
      });
      expect(withoutData.data, isEmpty);
    });
  });

  group('TokenPair', () {
    test('toJson round-trips both tokens', () {
      const pair = TokenPair(accessToken: 'a', refreshToken: 'r');
      expect(pair.toJson(), {'accessToken': 'a', 'refreshToken': 'r'});
    });
  });
}
