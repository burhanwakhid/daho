import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

import 'helpers/fake_auth_database.dart';

void main() {
  group('PostgresSessionStore', () {
    late FakeAuthDatabase db;
    late PostgresSessionStore store;

    setUp(() {
      db = FakeAuthDatabase();
      store = PostgresSessionStore(db);
    });

    test('create persists a row and returns a matching Session', () async {
      final session = await store.create(
        'u1',
        const Duration(days: 1),
        data: {'k': 'v'},
      );

      expect(db.sessions, hasLength(1));
      expect(session.userId, 'u1');
      expect(session.data, {'k': 'v'});
    });

    test('load returns the session by id', () async {
      final created = await store.create('u1', const Duration(days: 1));
      final loaded = await store.load(created.id);
      expect(loaded, isNotNull);
      expect(loaded!.userId, 'u1');
    });

    test('load returns null for an unknown id', () async {
      expect(await store.load('nope'), isNull);
    });

    test('load returns null for an expired session', () async {
      final created = await store.create('u1', const Duration(seconds: -1));
      expect(await store.load(created.id), isNull);
    });

    test('update replaces the session data', () async {
      final created = await store.create('u1', const Duration(days: 1));
      await store.update(created.id, {'updated': true});
      final loaded = await store.load(created.id);
      expect(loaded!.data, {'updated': true});
    });

    test('destroy removes only the targeted session', () async {
      final a = await store.create('u1', const Duration(days: 1));
      final b = await store.create('u1', const Duration(days: 1));
      await store.destroy(a.id);
      expect(await store.load(a.id), isNull);
      expect(await store.load(b.id), isNotNull);
    });

    test(
      'destroyAllForUser removes every session for that user, not others',
      () async {
        await store.create('u1', const Duration(days: 1));
        await store.create('u1', const Duration(days: 1));
        final other = await store.create('u2', const Duration(days: 1));

        await store.destroyAllForUser('u1');

        expect(db.sessions, hasLength(1));
        expect(await store.load(other.id), isNotNull);
      },
    );
  });
}
