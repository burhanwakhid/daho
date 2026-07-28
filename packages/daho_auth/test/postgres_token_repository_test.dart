import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

import 'helpers/fake_auth_database.dart';

void main() {
  group('PostgresTokenRepository', () {
    late FakeAuthDatabase db;
    late PostgresTokenRepository repo;

    setUp(() {
      db = FakeAuthDatabase();
      repo = PostgresTokenRepository(db);
    });

    test('store persists a row and validate resolves the user id', () async {
      final exp = DateTime.now().add(const Duration(days: 7));
      await repo.store('u1', 'jti-1', exp);

      expect(db.refreshTokens, hasLength(1));
      expect(await repo.validate('jti-1'), 'u1');
    });

    test('validate returns null for an unknown jti', () async {
      expect(await repo.validate('does-not-exist'), isNull);
    });

    test('validate returns null for an expired token', () async {
      await repo.store(
        'u1',
        'jti-expired',
        DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(await repo.validate('jti-expired'), isNull);
    });

    test('revoke prevents future validation of that jti only', () async {
      final exp = DateTime.now().add(const Duration(days: 7));
      await repo.store('u1', 'jti-a', exp);
      await repo.store('u1', 'jti-b', exp);

      await repo.revoke('jti-a');

      expect(await repo.validate('jti-a'), isNull);
      expect(await repo.validate('jti-b'), 'u1');
    });

    test(
      'revokeAllForUser revokes every token for that user, not others',
      () async {
        final exp = DateTime.now().add(const Duration(days: 7));
        await repo.store('u1', 'jti-1', exp);
        await repo.store('u1', 'jti-2', exp);
        await repo.store('u2', 'jti-3', exp);

        await repo.revokeAllForUser('u1');

        expect(await repo.validate('jti-1'), isNull);
        expect(await repo.validate('jti-2'), isNull);
        expect(await repo.validate('jti-3'), 'u2');
      },
    );
  });
}
