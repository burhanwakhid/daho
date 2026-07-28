import 'dart:async';
import 'package:daho/daho.dart';
import 'package:uuid/uuid.dart';
import 'auth_config.dart';
import 'auth_context.dart';
import 'db/database.dart';
import 'models/user.dart';
import 'oauth/oauth_exchange_repository.dart';
import 'oauth/oauth_provider.dart';
import 'oauth/postgres_oauth_exchange_repository.dart';
import 'oauth/token_pair_result.dart';
import 'password/password_hasher.dart';
import 'session/session_manager.dart';
import 'token/jwt_service.dart';
import 'token/token_pair.dart';
import 'token/token_repository.dart';

/// How long an OAuth `state` cookie / exchange code stays valid. Both are
/// meant to be consumed within seconds by the same browser flow.
const _oauthFlowLifetime = Duration(minutes: 10);

/// Built-in authentication route handlers.
///
/// Register them on your app or a route group:
/// ```dart
/// final auth = AuthRoutes(config: config, ...);
/// auth.register(app.group('/auth'));
/// ```
class AuthRoutes {
  final AuthConfig config;
  final AuthDatabase db;
  final PasswordHasher hasher;
  final JwtService jwt;
  final TokenRepository tokenRepo;
  final SessionManager sessionManager;
  final OAuthProvider? googleProvider;
  final OAuthProvider? githubProvider;
  final OAuthExchangeRepository exchangeRepo;
  final _uuid = const Uuid();

  AuthRoutes({
    required this.config,
    required this.db,
    required this.hasher,
    required this.jwt,
    required this.tokenRepo,
    required this.sessionManager,
    this.googleProvider,
    this.githubProvider,
    OAuthExchangeRepository? exchangeRepo,
  }) : exchangeRepo = exchangeRepo ?? PostgresOAuthExchangeRepository(db);

  /// Registers all auth routes on [group].
  ///
  /// Routes:
  ///   POST   /register         - Email/password registration
  ///   POST   /login            - Email/password login (JWT)
  ///   POST   /login/session    - Email/password login (session)
  ///   POST   /refresh          - Refresh access token
  ///   POST   /logout           - Revoke refresh token / destroy session
  ///   GET    /me               - Get current user (requires auth)
  ///   GET    /oauth/google     - Start Google OAuth flow
  ///   GET    /oauth/google/cb  - Google OAuth callback
  ///   GET    /oauth/github     - Start GitHub OAuth flow
  ///   GET    /oauth/github/cb  - GitHub OAuth callback
  ///   POST   /oauth/exchange   - Exchange a one-time OAuth code for tokens
  void register(DahoGroup group) {
    group.post('/register', _register);
    group.post('/login', _loginJwt);
    group.post('/login/session', _loginSession);
    group.post('/refresh', _refreshToken);
    group.post('/logout', _logout);
    group.get('/me', _me);
    group.post('/oauth/exchange', _oauthExchange);

    if (googleProvider != null) {
      group.get('/oauth/google', _oauthStart(googleProvider!));
      group.get('/oauth/google/cb', _oauthCallback(googleProvider!));
    }
    if (githubProvider != null) {
      group.get('/oauth/github', _oauthStart(githubProvider!));
      group.get('/oauth/github/cb', _oauthCallback(githubProvider!));
    }
  }

  // ---- Register ----

  FutureOr<DahoResponse> _register(DahoRequest req, DahoResponse res) async {
    final body = req.body as Map<String, dynamic>?;
    final email = body?['email'] as String?;
    final password = body?['password'] as String?;
    final name = body?['name'] as String?;

    if (email == null || password == null) {
      return res.badRequest({'error': 'email and password are required'});
    }
    if (password.length < 8) {
      return res.badRequest({
        'error': 'Password must be at least 8 characters',
      });
    }

    final existing = await db.queryOne(
      'SELECT id FROM users WHERE email = @email',
      {'email': email},
    );
    if (existing != null) {
      return res.status(409).json({'error': 'Email already registered'});
    }

    final hash = await hasher.hash(password);
    final userId = _uuid.v4();
    await db.execute(
      'INSERT INTO users (id, email, name, password_hash) VALUES (@id, @email, @name, @hash)',
      {'id': userId, 'email': email, 'name': name, 'hash': hash},
    );

    final user = await db.queryOne(
      'SELECT * FROM users WHERE id = @id',
      {'id': userId},
    );
    final registeredUser = User.fromRow(user!);
    final tokenPair = jwt.issueTokenPair(registeredUser);
    await _storeRefreshToken(registeredUser.id, tokenPair);

    return res.status(201).json({
      'user': registeredUser.toJson(),
      ...tokenPair.toJson(),
    });
  }

  // ---- Login (JWT) ----

  FutureOr<DahoResponse> _loginJwt(DahoRequest req, DahoResponse res) async {
    final body = req.body as Map<String, dynamic>?;
    final email = body?['email'] as String?;
    final password = body?['password'] as String?;

    if (email == null || password == null) {
      return res.badRequest({'error': 'email and password are required'});
    }

    final row = await db.queryOne(
      'SELECT * FROM users WHERE email = @email',
      {'email': email},
    );
    if (row == null) {
      return res.unauthorized({'error': 'Invalid credentials'});
    }

    final user = User.fromRow(row);
    if (user.passwordHash == null) {
      return res.unauthorized({'error': 'This account uses OAuth login'});
    }

    final valid = await hasher.verify(password, user.passwordHash!);
    if (!valid) {
      return res.unauthorized({'error': 'Invalid credentials'});
    }

    final tokenPair = jwt.issueTokenPair(user);
    await _storeRefreshToken(user.id, tokenPair);

    return res.ok({
      'user': user.toJson(),
      ...tokenPair.toJson(),
    });
  }

  // ---- Login (Session) ----

  FutureOr<DahoResponse> _loginSession(
    DahoRequest req,
    DahoResponse res,
  ) async {
    final body = req.body as Map<String, dynamic>?;
    final email = body?['email'] as String?;
    final password = body?['password'] as String?;

    if (email == null || password == null) {
      return res.badRequest({'error': 'email and password are required'});
    }

    final row = await db.queryOne(
      'SELECT * FROM users WHERE email = @email',
      {'email': email},
    );
    if (row == null) {
      return res.unauthorized({'error': 'Invalid credentials'});
    }

    final user = User.fromRow(row);
    if (user.passwordHash == null) {
      return res.unauthorized({'error': 'This account uses OAuth login'});
    }

    final valid = await hasher.verify(password, user.passwordHash!);
    if (!valid) {
      return res.unauthorized({'error': 'Invalid credentials'});
    }

    await sessionManager.createSession(req, res, user.id);
    return res.ok({'user': user.toJson()});
  }

  // ---- Refresh Token ----

  FutureOr<DahoResponse> _refreshToken(
    DahoRequest req,
    DahoResponse res,
  ) async {
    final body = req.body as Map<String, dynamic>?;
    final refreshToken = body?['refreshToken'] as String?;

    if (refreshToken == null) {
      return res.badRequest({'error': 'refreshToken is required'});
    }

    final claims = jwt.verify(refreshToken);
    if (claims == null || claims['type'] != 'refresh') {
      return res.unauthorized({'error': 'Invalid refresh token'});
    }

    final jti = claims['jti'] as String;
    final userId = await tokenRepo.validate(jti);
    if (userId == null) {
      return res.unauthorized({
        'error': 'Refresh token revoked or not found',
      });
    }

    await tokenRepo.revoke(jti);

    final userRow = await db.queryOne(
      'SELECT * FROM users WHERE id = @id',
      {'id': userId},
    );
    if (userRow == null) {
      return res.unauthorized({'error': 'User not found'});
    }

    final user = User.fromRow(userRow);
    final newPair = jwt.issueTokenPair(user);
    await _storeRefreshToken(user.id, newPair);

    return res.ok(newPair.toJson());
  }

  // ---- Logout ----

  FutureOr<DahoResponse> _logout(DahoRequest req, DahoResponse res) async {
    final body = req.body as Map<String, dynamic>?;
    final refreshToken = body?['refreshToken'] as String?;
    if (refreshToken != null) {
      final claims = jwt.verify(refreshToken);
      if (claims != null) {
        await tokenRepo.revoke(claims['jti'] as String);
      }
    }

    if (req.cookies[config.session.cookieName] != null) {
      await sessionManager.destroySession(req, res);
    }

    return res.ok({'message': 'Logged out'});
  }

  // ---- Me ----

  FutureOr<DahoResponse> _me(DahoRequest req, DahoResponse res) async {
    if (!req.auth.isAuthenticated) {
      return res.unauthorized({'error': 'Not authenticated'});
    }
    return res.ok({'user': req.auth.user!.toJson()});
  }

  // ---- OAuth Start ----

  String _stateCookieName(OAuthProvider provider) => 'oauth_state_${provider.name}';

  RouteHandler _oauthStart(OAuthProvider provider) {
    return (DahoRequest req, DahoResponse res) async {
      final state = _uuid.v4();
      // Stashed so the callback can confirm this exact browser started the
      // flow (CSRF protection — see reported finding: previously the state
      // was generated but never checked on the way back).
      res.cookie(
        _stateCookieName(provider),
        state,
        maxAge: _oauthFlowLifetime,
        httpOnly: true,
        secure: config.session.secure,
        sameSite: 'Lax',
      );
      final url = provider.getAuthorizationUrl(state);
      return res.found(url);
    };
  }

  // ---- OAuth Callback ----

  RouteHandler _oauthCallback(OAuthProvider provider) {
    return (DahoRequest req, DahoResponse res) async {
      final code = req.query['code'];
      if (code == null) {
        return res.badRequest({'error': 'Missing code parameter'});
      }

      final expectedState = req.cookies[_stateCookieName(provider)];
      res.clearCookie(_stateCookieName(provider));
      final state = req.query['state'];
      if (expectedState == null || state == null || state != expectedState) {
        return res.found(config.oauthFailureRedirect);
      }

      try {
        final tokens = await provider.exchangeCode(code);
        final profile = await provider.getUserProfile(tokens.accessToken);

        var oauthRow = await db.queryOne(
          'SELECT * FROM oauth_accounts WHERE provider = @p AND provider_user_id = @pid',
          {'p': provider.name, 'pid': profile.providerUserId},
        );

        String userId;
        if (oauthRow != null) {
          userId = oauthRow['user_id'] as String;
          await db.execute(
            'UPDATE oauth_accounts SET access_token = @at, refresh_token = @rt WHERE id = @id',
            {
              'at': tokens.accessToken,
              'rt': tokens.refreshToken,
              'id': oauthRow['id'],
            },
          );
        } else {
          var userRow = await db.queryOne(
            'SELECT id FROM users WHERE email = @email',
            {'email': profile.email},
          );

          if (userRow != null) {
            userId = userRow['id'] as String;
          } else {
            userId = _uuid.v4();
            await db.execute(
              'INSERT INTO users (id, email, name) VALUES (@id, @email, @name)',
              {'id': userId, 'email': profile.email, 'name': profile.name},
            );
          }

          await db.execute(
            '''INSERT INTO oauth_accounts (id, user_id, provider, provider_user_id, access_token, refresh_token)
               VALUES (@id, @uid, @p, @pid, @at, @rt)''',
            {
              'id': _uuid.v4(),
              'uid': userId,
              'p': provider.name,
              'pid': profile.providerUserId,
              'at': tokens.accessToken,
              'rt': tokens.refreshToken,
            },
          );
        }

        final userRow = await db.queryOne(
          'SELECT * FROM users WHERE id = @id',
          {'id': userId},
        );
        final user = User.fromRow(userRow!);
        final tokenPair = jwt.issueTokenPair(user);
        await _storeRefreshToken(user.id, tokenPair);

        // The token pair is handed off through a one-time server-side
        // exchange code rather than as redirect query parameters — putting
        // live tokens in a URL leaks them into browser history, the
        // Referer header of whatever page loads next, and server access
        // logs (see reported finding).
        final exchangeCode = await exchangeRepo.store(
          TokenPairResult(userId: user.id, tokenPair: tokenPair),
          DateTime.now().add(_oauthFlowLifetime),
        );

        final redirectUrl = Uri.parse(
          config.oauthSuccessRedirect,
        ).replace(queryParameters: {'code': exchangeCode});
        return res.found(redirectUrl.toString());
      } catch (e) {
        return res.found(config.oauthFailureRedirect);
      }
    };
  }

  // ---- OAuth Exchange ----

  /// Exchanges a one-time code (minted by [_oauthCallback]) for the actual
  /// access + refresh tokens. The code is deleted on first use, so a
  /// replayed or prefetched redirect can't obtain a second token pair.
  FutureOr<DahoResponse> _oauthExchange(DahoRequest req, DahoResponse res) async {
    final body = req.body as Map<String, dynamic>?;
    final code = body?['code'] as String?;
    if (code == null) {
      return res.badRequest({'error': 'code is required'});
    }

    final result = await exchangeRepo.consume(code);
    if (result == null) {
      return res.status(400).json({'error': 'Invalid or expired code'});
    }

    final userRow = await db.queryOne(
      'SELECT * FROM users WHERE id = @id',
      {'id': result.userId},
    );
    if (userRow == null) {
      return res.unauthorized({'error': 'User not found'});
    }

    return res.ok({
      'user': User.fromRow(userRow).toJson(),
      ...result.tokenPair.toJson(),
    });
  }

  // ---- Shared helpers ----

  Future<void> _storeRefreshToken(String userId, TokenPair tokenPair) async {
    final claims = jwt.verify(tokenPair.refreshToken);
    final jti = claims!['jti'] as String;
    final exp = DateTime.fromMillisecondsSinceEpoch((claims['exp'] as int) * 1000);
    await tokenRepo.store(userId, jti, exp);
  }
}
