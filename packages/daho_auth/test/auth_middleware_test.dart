import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

import 'helpers/fake_auth_database.dart';
import 'helpers/fake_session_store.dart';
import 'helpers/request_helpers.dart';

void main() {
  group('AuthMiddleware.jwt', () {
    late FakeAuthDatabase db;
    late JwtService jwt;
    late Middleware mw;
    late Middleware mwOptional;

    setUp(() {
      db = FakeAuthDatabase();
      jwt = JwtService(const JwtConfig(secret: 'test-secret'));
      mw = AuthMiddleware.jwt(jwtService: jwt, db: db);
      mwOptional = AuthMiddleware.jwt(jwtService: jwt, db: db, required: false);
    });

    test('401s with no Authorization header when required', () async {
      final req = buildRequest();
      final res = DahoResponse();
      final result = await runMiddleware(mw, req, res);

      expect(result.nextCalled, isFalse);
      expect(res.statusCode, 401);
    });

    test('calls next() with no header when not required', () async {
      final req = buildRequest();
      final res = DahoResponse();
      final result = await runMiddleware(mwOptional, req, res);

      expect(result.nextCalled, isTrue);
      expect(req.auth.isAuthenticated, isFalse);
    });

    test('401s for a header without the Bearer scheme', () async {
      final req = buildRequest(headers: {'authorization': 'Basic abcdef'});
      final res = DahoResponse();
      final result = await runMiddleware(mw, req, res);

      expect(result.nextCalled, isFalse);
      expect(res.statusCode, 401);
    });

    test('401s for an invalid/garbage token', () async {
      final req = buildRequest(headers: {'authorization': 'Bearer not-a-jwt'});
      final res = DahoResponse();
      final result = await runMiddleware(mw, req, res);

      expect(result.nextCalled, isFalse);
      expect(res.statusCode, 401);
    });

    test('401s when a refresh token is presented as a Bearer token', () async {
      final row = db.seedUser(email: 'a@example.com');
      final user = User.fromRow(row);
      final pair = jwt.issueTokenPair(user);

      final req = buildRequest(
        headers: {'authorization': 'Bearer ${pair.refreshToken}'},
      );
      final res = DahoResponse();
      final result = await runMiddleware(mw, req, res);

      expect(result.nextCalled, isFalse);
      expect(res.statusCode, 401);
    });

    test('401s when the token subject has no matching user', () async {
      final ghost = User(
        id: 'does-not-exist',
        email: 'ghost@example.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final pair = jwt.issueTokenPair(ghost);

      final req = buildRequest(
        headers: {'authorization': 'Bearer ${pair.accessToken}'},
      );
      final res = DahoResponse();
      final result = await runMiddleware(mw, req, res);

      expect(result.nextCalled, isFalse);
      expect(res.statusCode, 401);
    });

    test(
      'populates req.auth and calls next() for a valid access token',
      () async {
        final row = db.seedUser(email: 'a@example.com');
        final user = User.fromRow(row);
        final pair = jwt.issueTokenPair(user);

        final req = buildRequest(
          headers: {'authorization': 'Bearer ${pair.accessToken}'},
        );
        final res = DahoResponse();
        final result = await runMiddleware(mw, req, res);

        expect(result.nextCalled, isTrue);
        expect(req.auth.isAuthenticated, isTrue);
        expect(req.auth.user!.email, 'a@example.com');
        expect(req.auth.jwtClaims!['type'], 'access');
      },
    );

    test('req.auth.user.role reflects the user\'s current DB role', () async {
      final row = db.seedUser(email: 'admin@example.com', role: 'admin');
      final pair = jwt.issueTokenPair(User.fromRow(row));

      final req = buildRequest(
        headers: {'authorization': 'Bearer ${pair.accessToken}'},
      );
      final res = DahoResponse();
      await runMiddleware(mw, req, res);

      expect(req.auth.user!.role, 'admin');
    });
  });

  group('AuthMiddleware.session', () {
    late FakeAuthDatabase db;
    late FakeSessionStore store;
    late SessionManager sessionManager;
    late Middleware mw;
    late Middleware mwOptional;

    setUp(() {
      db = FakeAuthDatabase();
      store = FakeSessionStore();
      sessionManager = SessionManager(store, const SessionConfig());
      mw = AuthMiddleware.session(sessionManager: sessionManager, db: db);
      mwOptional = AuthMiddleware.session(
        sessionManager: sessionManager,
        db: db,
        required: false,
      );
    });

    test('401s with no session cookie when required', () async {
      final req = buildRequest();
      final res = DahoResponse();
      final result = await runMiddleware(mw, req, res);

      expect(result.nextCalled, isFalse);
      expect(res.statusCode, 401);
    });

    test('calls next() with no session cookie when not required', () async {
      final req = buildRequest();
      final res = DahoResponse();
      final result = await runMiddleware(mwOptional, req, res);

      expect(result.nextCalled, isTrue);
      expect(req.auth.isAuthenticated, isFalse);
    });

    test('populates req.auth for a valid session', () async {
      final row = db.seedUser(email: 'a@example.com');
      final createRes = DahoResponse();
      final session = await sessionManager.createSession(
        buildRequest(),
        createRes,
        row['id'] as String,
      );

      final req = buildRequest(cookies: {'daho_session': session.id});
      final res = DahoResponse();
      final result = await runMiddleware(mw, req, res);

      expect(result.nextCalled, isTrue);
      expect(req.auth.isAuthenticated, isTrue);
      expect(req.auth.user!.email, 'a@example.com');
      expect(req.auth.session!.id, session.id);
    });

    test(
      '401s and destroys the session when its user no longer exists',
      () async {
        final createRes = DahoResponse();
        final session = await sessionManager.createSession(
          buildRequest(),
          createRes,
          'deleted-user-id',
        );

        final req = buildRequest(cookies: {'daho_session': session.id});
        final res = DahoResponse();
        final result = await runMiddleware(mw, req, res);

        expect(result.nextCalled, isFalse);
        expect(res.statusCode, 401);
        expect(store.isEmpty, isTrue);
      },
    );
  });

  group('AuthMiddleware.requireRole', () {
    test('401s when unauthenticated', () async {
      final req = buildRequest();
      final res = DahoResponse();
      final result = await runMiddleware(
        AuthMiddleware.requireRole(['admin']),
        req,
        res,
      );
      expect(result.nextCalled, isFalse);
      expect(res.statusCode, 401);
    });

    test('403s when the user role is not in the allow-list', () async {
      final req = buildRequest();
      req.auth.user = User(
        id: 'u1',
        email: 'a@example.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // No jwtClaims set -> role resolves to the 'user' default.
      final res = DahoResponse();
      final result = await runMiddleware(
        AuthMiddleware.requireRole(['admin']),
        req,
        res,
      );
      expect(result.nextCalled, isFalse);
      expect(res.statusCode, 403);
    });

    test('calls next() when the resolved role is allowed', () async {
      final req = buildRequest();
      req.auth.user = User(
        id: 'u1',
        email: 'a@example.com',
        role: 'admin',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final res = DahoResponse();
      final result = await runMiddleware(
        AuthMiddleware.requireRole(['admin']),
        req,
        res,
      );
      expect(result.nextCalled, isTrue);
    });

    test('role is read from user.role (populated from the DB by jwt/session '
        'middleware), not from JWT claims — so a role change in the database '
        'takes effect immediately for both JWT and session auth, without '
        'waiting for the access token to be reissued', () async {
      final req = buildRequest();
      req.auth.user = User(
        id: 'u1',
        email: 'a@example.com',
        role: 'admin',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // jwtClaims deliberately absent (as it always is for session auth,
      // and never carries a role for JWT auth either) — the role must
      // still resolve correctly from user.role alone.
      req.auth.jwtClaims = null;
      final res = DahoResponse();
      final result = await runMiddleware(
        AuthMiddleware.requireRole(['admin']),
        req,
        res,
      );
      expect(result.nextCalled, isTrue);
    });
  });
}
