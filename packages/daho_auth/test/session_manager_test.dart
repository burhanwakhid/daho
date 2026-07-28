import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

import 'helpers/fake_session_store.dart';
import 'helpers/request_helpers.dart';

void main() {
  group('SessionManager', () {
    late FakeSessionStore store;
    late SessionManager manager;

    setUp(() {
      store = FakeSessionStore();
      manager = SessionManager(store, const SessionConfig());
    });

    test(
      'construction succeeds regardless of SessionConfig.secure '
      '(secure: false prints an insecure-cookie warning to stderr — '
      'verified manually; not asserted here since stderr can\'t be '
      'redirected without faking the full Stdout API)',
      () {
        expect(() => SessionManager(store, const SessionConfig()), returnsNormally);
        expect(
          () => SessionManager(store, const SessionConfig(secure: true)),
          returnsNormally,
        );
      },
    );

    test('createSession stores a session and sets a cookie', () async {
      final req = buildRequest();
      final res = DahoResponse();

      final session = await manager.createSession(req, res, 'u1');

      expect(session.userId, 'u1');
      expect(store.length, 1);
      expect(res.setCookies, hasLength(1));
      expect(res.setCookies.first, startsWith('daho_session=${session.id}'));
    });

    test('createSession cookie carries HttpOnly and configured SameSite', () async {
      final req = buildRequest();
      final res = DahoResponse();
      await manager.createSession(req, res, 'u1');

      final cookie = res.setCookies.first;
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('SameSite=Lax'));
      expect(cookie, contains('Path=/'));
      expect(cookie, isNot(contains('Secure')));
    });

    test('createSession honors secure=true from config', () async {
      final secureManager = SessionManager(
        store,
        const SessionConfig(secure: true),
      );
      final req = buildRequest();
      final res = DahoResponse();
      await secureManager.createSession(req, res, 'u1');
      expect(res.setCookies.first, contains('Secure'));
    });

    test('loadSession returns null when no cookie is present', () async {
      final req = buildRequest();
      expect(await manager.loadSession(req), isNull);
    });

    test('loadSession returns the session for a valid cookie', () async {
      final createReq = buildRequest();
      final createRes = DahoResponse();
      final created = await manager.createSession(createReq, createRes, 'u1');

      final loadReq = buildRequest(
        cookies: {'daho_session': created.id},
      );
      final loaded = await manager.loadSession(loadReq);
      expect(loaded, isNotNull);
      expect(loaded!.userId, 'u1');
    });

    test('loadSession returns null for an unknown session id', () async {
      final req = buildRequest(cookies: {'daho_session': 'does-not-exist'});
      expect(await manager.loadSession(req), isNull);
    });

    test('destroySession removes the session and clears the cookie', () async {
      final createReq = buildRequest();
      final createRes = DahoResponse();
      final created = await manager.createSession(createReq, createRes, 'u1');

      final destroyReq = buildRequest(cookies: {'daho_session': created.id});
      final destroyRes = DahoResponse();
      await manager.destroySession(destroyReq, destroyRes);

      expect(store.isEmpty, isTrue);
      expect(destroyRes.setCookies, hasLength(1));
      // Clearing a cookie re-sends it with Max-Age=0 so the browser expires it.
      expect(destroyRes.setCookies.first, contains('Max-Age=0'));
    });

    test('destroySession is a no-op (still clears cookie) when no session cookie present', () async {
      final req = buildRequest();
      final res = DahoResponse();
      await manager.destroySession(req, res);
      expect(res.setCookies, hasLength(1));
    });
  });
}
