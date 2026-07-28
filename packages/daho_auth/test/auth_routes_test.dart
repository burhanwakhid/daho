import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

import 'helpers/capturing_group.dart';
import 'helpers/fake_auth_database.dart';
import 'helpers/fake_oauth_provider.dart';
import 'helpers/fake_token_repository.dart';
import 'helpers/fake_session_store.dart';
import 'helpers/request_helpers.dart';

/// Decodes the value out of a raw `Set-Cookie` header string, e.g.
/// `"name=value; Path=/; HttpOnly"` -> `"value"`.
String _cookieValue(String setCookieHeader) {
  final firstPair = setCookieHeader.split(';').first;
  final eq = firstPair.indexOf('=');
  return Uri.decodeComponent(firstPair.substring(eq + 1));
}

/// Drives `GET /oauth/google` and returns the `state` it minted, so a
/// subsequent callback test can present both the matching `state` cookie
/// and query parameter — exactly like a real browser redirect round trip.
Future<String> _startOAuthFlow(CapturingGroup routes) async {
  final req = buildRequest(path: '/auth/oauth/google');
  final res = DahoResponse();
  await routes['GET /oauth/google'](req, res);
  return _cookieValue(res.setCookies.single);
}

void main() {
  late FakeAuthDatabase db;
  late FakeTokenRepository tokenRepo;
  late FakeSessionStore sessionStore;
  late SessionManager sessionManager;
  late JwtService jwt;
  late BcryptHasher hasher;
  late FakeOAuthProvider google;
  late CapturingGroup routes;

  setUp(() {
    db = FakeAuthDatabase();
    tokenRepo = FakeTokenRepository();
    sessionStore = FakeSessionStore();
    sessionManager = SessionManager(sessionStore, const SessionConfig());
    jwt = JwtService(const JwtConfig(secret: 'test-secret'));
    hasher = BcryptHasher(logRounds: 4);
    google = FakeOAuthProvider(name: 'google');

    final authRoutes = AuthRoutes(
      config: AuthConfig(
        jwt: const JwtConfig(secret: 'test-secret'),
        databaseUrl: 'postgres://fake',
      ),
      db: db,
      hasher: hasher,
      jwt: jwt,
      tokenRepo: tokenRepo,
      sessionManager: sessionManager,
      googleProvider: google,
    );

    routes = CapturingGroup('/auth');
    authRoutes.register(routes);
  });

  group('POST /register', () {
    test('creates a user and returns 201 with a token pair', () async {
      final req = buildJsonRequest(
        path: '/auth/register',
        body: {
          'email': 'new@example.com',
          'password': 'password123',
          'name': 'New',
        },
      );
      final res = DahoResponse();
      await routes['POST /register'](req, res);

      expect(res.statusCode, 201);
      final json = jsonBodyOf(res) as Map;
      expect(json['user']['email'], 'new@example.com');
      expect(json['accessToken'], isNotEmpty);
      expect(json['refreshToken'], isNotEmpty);
      expect(db.users, hasLength(1));
      expect(db.users.first['password_hash'], isNot(equals('password123')));
    });

    test('400s when email or password is missing', () async {
      final req = buildJsonRequest(
        path: '/auth/register',
        body: {'email': 'a@b.com'},
      );
      final res = DahoResponse();
      await routes['POST /register'](req, res);
      expect(res.statusCode, 400);
    });

    test('400s when password is shorter than 8 characters', () async {
      final req = buildJsonRequest(
        path: '/auth/register',
        body: {'email': 'a@b.com', 'password': 'short'},
      );
      final res = DahoResponse();
      await routes['POST /register'](req, res);
      expect(res.statusCode, 400);
    });

    test('409s when the email is already registered', () async {
      db.seedUser(email: 'dup@example.com');
      final req = buildJsonRequest(
        path: '/auth/register',
        body: {'email': 'dup@example.com', 'password': 'password123'},
      );
      final res = DahoResponse();
      await routes['POST /register'](req, res);
      expect(res.statusCode, 409);
    });
  });

  group('POST /login (JWT)', () {
    test('returns a token pair for correct credentials', () async {
      final hash = await hasher.hash('password123');
      db.seedUser(email: 'a@example.com', passwordHash: hash);

      final req = buildJsonRequest(
        path: '/auth/login',
        body: {'email': 'a@example.com', 'password': 'password123'},
      );
      final res = DahoResponse();
      await routes['POST /login'](req, res);

      expect(res.statusCode, 200);
      final json = jsonBodyOf(res) as Map;
      expect(json['accessToken'], isNotEmpty);
      expect(json['refreshToken'], isNotEmpty);
      // The refresh token must be recorded so /refresh and /logout can act on it.
      final jti = jwt.verify(json['refreshToken'] as String)!['jti'] as String;
      expect(tokenRepo.contains(jti), isTrue);
    });

    test('401s for an unknown email', () async {
      final req = buildJsonRequest(
        path: '/auth/login',
        body: {'email': 'nope@example.com', 'password': 'password123'},
      );
      final res = DahoResponse();
      await routes['POST /login'](req, res);
      expect(res.statusCode, 401);
    });

    test('401s for the wrong password', () async {
      final hash = await hasher.hash('password123');
      db.seedUser(email: 'a@example.com', passwordHash: hash);

      final req = buildJsonRequest(
        path: '/auth/login',
        body: {'email': 'a@example.com', 'password': 'wrong'},
      );
      final res = DahoResponse();
      await routes['POST /login'](req, res);
      expect(res.statusCode, 401);
    });

    test('401s for an OAuth-only account (no password set)', () async {
      db.seedUser(email: 'oauth@example.com', passwordHash: null);

      final req = buildJsonRequest(
        path: '/auth/login',
        body: {'email': 'oauth@example.com', 'password': 'anything1'},
      );
      final res = DahoResponse();
      await routes['POST /login'](req, res);
      expect(res.statusCode, 401);
    });
  });

  group('POST /login/session', () {
    test('creates a session and sets the session cookie', () async {
      final hash = await hasher.hash('password123');
      db.seedUser(email: 'a@example.com', passwordHash: hash);

      final req = buildJsonRequest(
        path: '/auth/login/session',
        body: {'email': 'a@example.com', 'password': 'password123'},
      );
      final res = DahoResponse();
      await routes['POST /login/session'](req, res);

      expect(res.statusCode, 200);
      expect(res.setCookies, hasLength(1));
      expect(sessionStore.length, 1);
    });

    test('401s for the wrong password', () async {
      final hash = await hasher.hash('password123');
      db.seedUser(email: 'a@example.com', passwordHash: hash);

      final req = buildJsonRequest(
        path: '/auth/login/session',
        body: {'email': 'a@example.com', 'password': 'wrong'},
      );
      final res = DahoResponse();
      await routes['POST /login/session'](req, res);
      expect(res.statusCode, 401);
    });
  });

  group('POST /refresh', () {
    test(
      'rotates the refresh token: old jti is revoked, new pair issued',
      () async {
        final row = db.seedUser(email: 'a@example.com');
        final user = User.fromRow(row);
        final pair = jwt.issueTokenPair(user);
        final oldJti = jwt.verify(pair.refreshToken)!['jti'] as String;
        await tokenRepo.store(
          user.id,
          oldJti,
          DateTime.now().add(const Duration(days: 7)),
        );

        final req = buildJsonRequest(
          path: '/auth/refresh',
          body: {'refreshToken': pair.refreshToken},
        );
        final res = DahoResponse();
        await routes['POST /refresh'](req, res);

        expect(res.statusCode, 200);
        final json = jsonBodyOf(res) as Map;
        expect(json['refreshToken'], isNot(equals(pair.refreshToken)));
        expect(tokenRepo.isRevoked(oldJti), isTrue);

        final newJti =
            jwt.verify(json['refreshToken'] as String)!['jti'] as String;
        expect(tokenRepo.contains(newJti), isTrue);
        expect(tokenRepo.isRevoked(newJti), isFalse);
      },
    );

    test(
      '401s for a token that was never stored (e.g. already used once)',
      () async {
        final row = db.seedUser(email: 'a@example.com');
        final pair = jwt.issueTokenPair(User.fromRow(row));
        // Deliberately not stored in tokenRepo.

        final req = buildJsonRequest(
          path: '/auth/refresh',
          body: {'refreshToken': pair.refreshToken},
        );
        final res = DahoResponse();
        await routes['POST /refresh'](req, res);
        expect(res.statusCode, 401);
      },
    );

    test('401s for a revoked refresh token (replay protection)', () async {
      final row = db.seedUser(email: 'a@example.com');
      final user = User.fromRow(row);
      final pair = jwt.issueTokenPair(user);
      final jti = jwt.verify(pair.refreshToken)!['jti'] as String;
      await tokenRepo.store(
        user.id,
        jti,
        DateTime.now().add(const Duration(days: 7)),
      );
      await tokenRepo.revoke(jti);

      final req = buildJsonRequest(
        path: '/auth/refresh',
        body: {'refreshToken': pair.refreshToken},
      );
      final res = DahoResponse();
      await routes['POST /refresh'](req, res);
      expect(res.statusCode, 401);
    });

    test(
      '401s when an access token is presented instead of a refresh token',
      () async {
        final row = db.seedUser(email: 'a@example.com');
        final pair = jwt.issueTokenPair(User.fromRow(row));

        final req = buildJsonRequest(
          path: '/auth/refresh',
          body: {'refreshToken': pair.accessToken},
        );
        final res = DahoResponse();
        await routes['POST /refresh'](req, res);
        expect(res.statusCode, 401);
      },
    );

    test('400s when refreshToken is missing from the body', () async {
      final req = buildJsonRequest(path: '/auth/refresh', body: {});
      final res = DahoResponse();
      await routes['POST /refresh'](req, res);
      expect(res.statusCode, 400);
    });
  });

  group('POST /logout', () {
    test('revokes the refresh token jti when provided', () async {
      final row = db.seedUser(email: 'a@example.com');
      final user = User.fromRow(row);
      final pair = jwt.issueTokenPair(user);
      final jti = jwt.verify(pair.refreshToken)!['jti'] as String;
      await tokenRepo.store(
        user.id,
        jti,
        DateTime.now().add(const Duration(days: 7)),
      );

      final req = buildJsonRequest(
        path: '/auth/logout',
        body: {'refreshToken': pair.refreshToken},
      );
      final res = DahoResponse();
      await routes['POST /logout'](req, res);

      expect(res.statusCode, 200);
      expect(tokenRepo.isRevoked(jti), isTrue);
    });

    test('destroys the session when a session cookie is present', () async {
      final createRes = DahoResponse();
      final session = await sessionManager.createSession(
        buildRequest(),
        createRes,
        'u1',
      );

      final req = buildJsonRequest(
        path: '/auth/logout',
        cookies: {'daho_session': session.id},
        body: {},
      );
      final res = DahoResponse();
      await routes['POST /logout'](req, res);

      expect(res.statusCode, 200);
      expect(sessionStore.isEmpty, isTrue);
    });

    test('succeeds with no refresh token and no session', () async {
      final req = buildJsonRequest(path: '/auth/logout', body: {});
      final res = DahoResponse();
      await routes['POST /logout'](req, res);
      expect(res.statusCode, 200);
    });
  });

  group('GET /me', () {
    test('401s when unauthenticated', () async {
      final req = buildRequest(path: '/auth/me');
      final res = DahoResponse();
      await routes['GET /me'](req, res);
      expect(res.statusCode, 401);
    });

    test('returns the user when req.auth is populated', () async {
      final req = buildRequest(path: '/auth/me');
      req.auth.user = User(
        id: 'u1',
        email: 'a@example.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final res = DahoResponse();
      await routes['GET /me'](req, res);

      expect(res.statusCode, 200);
      expect((jsonBodyOf(res) as Map)['user']['email'], 'a@example.com');
    });
  });

  group('GET /oauth/google', () {
    test(
      'redirects to the provider authorization URL with a state param',
      () async {
        final req = buildRequest(path: '/auth/oauth/google');
        final res = DahoResponse();
        await routes['GET /oauth/google'](req, res);

        expect(res.statusCode, 302);
        final location = res.headers['Location']!;
        expect(
          location,
          startsWith('https://fake-provider.example.com/authorize'),
        );
        expect(Uri.parse(location).queryParameters['state'], isNotEmpty);
      },
    );

    test(
      'sets a short-lived, HttpOnly state cookie matching the URL state',
      () async {
        final req = buildRequest(path: '/auth/oauth/google');
        final res = DahoResponse();
        await routes['GET /oauth/google'](req, res);

        expect(res.setCookies, hasLength(1));
        final cookie = res.setCookies.single;
        expect(cookie, startsWith('oauth_state_google='));
        expect(cookie, contains('HttpOnly'));
        final location = Uri.parse(res.headers['Location']!);
        expect(_cookieValue(cookie), location.queryParameters['state']);
      },
    );
  });

  group('GET /oauth/google/cb', () {
    test('400s when the code parameter is missing', () async {
      final req = buildRequest(path: '/auth/oauth/google/cb');
      final res = DahoResponse();
      await routes['GET /oauth/google/cb'](req, res);
      expect(res.statusCode, 400);
    });

    test('redirects to the failure page when the state param does not match '
        'the cookie set by /oauth/google (CSRF protection)', () async {
      final req = buildRequest(
        path: '/auth/oauth/google/cb',
        query: {'code': 'auth-code-123', 'state': 'forged-by-attacker'},
        cookies: {'oauth_state_google': 'the-real-state'},
      );
      final res = DahoResponse();
      await routes['GET /oauth/google/cb'](req, res);

      expect(res.statusCode, 302);
      expect(res.headers['Location'], '/login');
      expect(
        db.users,
        isEmpty,
        reason: 'must not proceed past state validation',
      );
      expect(google.lastCodeExchanged, isNull);
    });

    test(
      'redirects to the failure page when no state cookie was set at all '
      '(e.g. the callback is hit directly, without going through /oauth/google)',
      () async {
        final req = buildRequest(
          path: '/auth/oauth/google/cb',
          query: {'code': 'auth-code-123', 'state': 'anything'},
        );
        final res = DahoResponse();
        await routes['GET /oauth/google/cb'](req, res);

        expect(res.headers['Location'], '/login');
        expect(db.users, isEmpty);
      },
    );

    test('creates a new user + oauth_account and redirects with a one-time '
        'exchange code (not the tokens themselves)', () async {
      final state = await _startOAuthFlow(routes);

      final req = buildRequest(
        path: '/auth/oauth/google/cb',
        query: {'code': 'auth-code-123', 'state': state},
        cookies: {'oauth_state_google': state},
      );
      final res = DahoResponse();
      await routes['GET /oauth/google/cb'](req, res);

      expect(res.statusCode, 302);
      expect(db.users, hasLength(1));
      expect(db.users.first['email'], 'oauth-user@example.com');
      expect(db.oauthAccounts, hasLength(1));
      expect(google.lastCodeExchanged, 'auth-code-123');

      final location = Uri.parse(res.headers['Location']!);
      expect(location.queryParameters.containsKey('accessToken'), isFalse);
      expect(location.queryParameters.containsKey('refreshToken'), isFalse);
      expect(location.queryParameters['code'], isNotEmpty);
      expect(db.oauthExchangeCodes, hasLength(1));
    });

    test('clears the state cookie after a successful callback', () async {
      final state = await _startOAuthFlow(routes);
      final req = buildRequest(
        path: '/auth/oauth/google/cb',
        query: {'code': 'auth-code-123', 'state': state},
        cookies: {'oauth_state_google': state},
      );
      final res = DahoResponse();
      await routes['GET /oauth/google/cb'](req, res);

      expect(res.setCookies, hasLength(1));
      expect(res.setCookies.single, contains('Max-Age=0'));
    });

    test(
      'links to an existing user found by email on first OAuth login',
      () async {
        final existing = db.seedUser(email: 'oauth-user@example.com');
        final state = await _startOAuthFlow(routes);

        final req = buildRequest(
          path: '/auth/oauth/google/cb',
          query: {'code': 'auth-code-123', 'state': state},
          cookies: {'oauth_state_google': state},
        );
        final res = DahoResponse();
        await routes['GET /oauth/google/cb'](req, res);

        expect(
          db.users,
          hasLength(1),
          reason: 'should link, not duplicate the user',
        );
        expect(db.oauthAccounts.single['user_id'], existing['id']);
      },
    );

    test(
      'reuses the existing oauth_account on a returning OAuth login',
      () async {
        final state1 = await _startOAuthFlow(routes);
        final req1 = buildRequest(
          path: '/auth/oauth/google/cb',
          query: {'code': 'first-code', 'state': state1},
          cookies: {'oauth_state_google': state1},
        );
        await routes['GET /oauth/google/cb'](req1, DahoResponse());
        expect(db.oauthAccounts, hasLength(1));

        final state2 = await _startOAuthFlow(routes);
        final req2 = buildRequest(
          path: '/auth/oauth/google/cb',
          query: {'code': 'second-code', 'state': state2},
          cookies: {'oauth_state_google': state2},
        );
        await routes['GET /oauth/google/cb'](req2, DahoResponse());

        expect(db.users, hasLength(1));
        expect(db.oauthAccounts, hasLength(1));
        expect(
          db.oauthAccounts.single['access_token'],
          google.tokens.accessToken,
        );
      },
    );

    test('redirects to the failure URL when token exchange fails', () async {
      google.exchangeError = Exception('provider rejected the code');
      final state = await _startOAuthFlow(routes);

      final req = buildRequest(
        path: '/auth/oauth/google/cb',
        query: {'code': 'bad-code', 'state': state},
        cookies: {'oauth_state_google': state},
      );
      final res = DahoResponse();
      await routes['GET /oauth/google/cb'](req, res);

      expect(res.statusCode, 302);
      expect(res.headers['Location'], '/login');
      expect(db.users, isEmpty);
    });
  });

  group('POST /oauth/exchange', () {
    Future<String> completeOAuthFlow() async {
      final state = await _startOAuthFlow(routes);
      final cbReq = buildRequest(
        path: '/auth/oauth/google/cb',
        query: {'code': 'auth-code-123', 'state': state},
        cookies: {'oauth_state_google': state},
      );
      final cbRes = DahoResponse();
      await routes['GET /oauth/google/cb'](cbReq, cbRes);
      return Uri.parse(cbRes.headers['Location']!).queryParameters['code']!;
    }

    test('returns the user + token pair for a valid code', () async {
      final code = await completeOAuthFlow();

      final req = buildJsonRequest(
        path: '/auth/oauth/exchange',
        body: {'code': code},
      );
      final res = DahoResponse();
      await routes['POST /oauth/exchange'](req, res);

      expect(res.statusCode, 200);
      final json = jsonBodyOf(res) as Map;
      expect(json['user']['email'], 'oauth-user@example.com');
      expect(json['accessToken'], isNotEmpty);
      expect(json['refreshToken'], isNotEmpty);
    });

    test(
      'the issued refresh token is usable at /refresh (regression guard: '
      'OAuth logins used to skip storing the refresh token jti entirely)',
      () async {
        final code = await completeOAuthFlow();
        final exchangeReq = buildJsonRequest(
          path: '/auth/oauth/exchange',
          body: {'code': code},
        );
        final exchangeRes = DahoResponse();
        await routes['POST /oauth/exchange'](exchangeReq, exchangeRes);
        final refreshToken =
            (jsonBodyOf(exchangeRes) as Map)['refreshToken'] as String;

        final refreshReq = buildJsonRequest(
          path: '/auth/refresh',
          body: {'refreshToken': refreshToken},
        );
        final refreshRes = DahoResponse();
        await routes['POST /refresh'](refreshReq, refreshRes);

        expect(refreshRes.statusCode, 200);
      },
    );

    test('400s for an unknown code', () async {
      final req = buildJsonRequest(
        path: '/auth/oauth/exchange',
        body: {'code': 'does-not-exist'},
      );
      final res = DahoResponse();
      await routes['POST /oauth/exchange'](req, res);
      expect(res.statusCode, 400);
    });

    test('a code can only be exchanged once (single-use)', () async {
      final code = await completeOAuthFlow();

      final firstReq = buildJsonRequest(
        path: '/auth/oauth/exchange',
        body: {'code': code},
      );
      await routes['POST /oauth/exchange'](firstReq, DahoResponse());

      final secondReq = buildJsonRequest(
        path: '/auth/oauth/exchange',
        body: {'code': code},
      );
      final secondRes = DahoResponse();
      await routes['POST /oauth/exchange'](secondReq, secondRes);
      expect(secondRes.statusCode, 400);
    });

    test('400s when code is missing from the body', () async {
      final req = buildJsonRequest(path: '/auth/oauth/exchange', body: {});
      final res = DahoResponse();
      await routes['POST /oauth/exchange'](req, res);
      expect(res.statusCode, 400);
    });
  });
}
