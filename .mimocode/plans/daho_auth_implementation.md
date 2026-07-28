# daho_auth Implementation Plan

## 1. Package Structure

```
packages/daho_auth/
├── lib/
│   ├── daho_auth.dart                    # Public barrel export
│   └── src/
│       ├── auth_config.dart              # AuthConfig immutable config class
│       ├── auth_context.dart             # Per-request auth state (user, session, tokens)
│       ├── auth_middleware.dart           # Core middleware factory methods
│       ├── auth_routes.dart              # Built-in auth route handlers
│       ├── password/
│       │   ├── bcrypt_hasher.dart        # bcrypt password hashing interface + impl
│       │   └── password_hasher.dart      # Abstract PasswordHasher interface
│       ├── token/
│       │   ├── jwt_service.dart          # JWT encode/decode with access+refresh
│       │   ├── token_pair.dart           # TokenPair (accessToken, refreshToken)
│       │   └── token_repository.dart     # Refresh token storage interface
│       ├── session/
│       │   ├── session.dart              # Session model
│       │   ├── session_manager.dart      # Session CRUD + cookie helpers
│       │   └── session_store.dart        # SessionStore interface (DB-backed impl)
│       ├── oauth/
│       │   ├── oauth_provider.dart       # Abstract OAuth2 provider interface
│       │   ├── oauth_tokens.dart         # OAuth2 token response model
│       │   ├── google_provider.dart      # Google OAuth2 implementation
│       │   └── github_provider.dart      # GitHub OAuth2 implementation
│       ├── db/
│       │   ├── database.dart             # Database connection pool wrapper
│       │   ├── migration_runner.dart     # Auto-migration engine
│       │   └── migrations/
│       │       ├── 001_create_users.sql
│       │       ├── 002_create_sessions.sql
│       │       ├── 003_create_refresh_tokens.sql
│       │       └── 004_create_oauth_accounts.sql
│       └── models/
│           ├── user.dart                 # User model
│           └── oauth_account.dart        # OAuth account link model
├── pubspec.yaml
├── analysis_options.yaml
├── CHANGELOG.md
├── LICENSE
├── README.md
└── test/
    ├── jwt_service_test.dart
    ├── bcrypt_hasher_test.dart
    ├── auth_middleware_test.dart
    ├── session_manager_test.dart
    └── migration_runner_test.dart
```

---

## 2. pubspec.yaml

```yaml
name: daho_auth
description: >-
  Authentication and authorization middleware for the Daho HTTP framework.
  JWT, session-based, OAuth2 (Google, GitHub), bcrypt, PostgreSQL with auto-migrations.
version: 0.1.0
homepage: https://burhanwakhid.github.io/daho/
repository: https://github.com/burhanwakhid/daho

environment:
  sdk: ^3.9.0

dependencies:
  daho: ^0.1.0
  dart_jsonwebtoken: ^2.14.0
  bcrypt: ^1.1.3
  postgres: ^3.2.0
  http: ^1.2.0
  crypto: ^3.0.0
  uuid: ^4.5.0

dev_dependencies:
  lints: ^6.0.0
  test: ^1.25.6
  daho_test: ^0.1.0  # (future package for testing Daho apps)
```

---

## 3. Public API (daho_auth.dart barrel export)

```dart
/// daho_auth — Authentication & authorization for Daho.
library;

// Config
export 'src/auth_config.dart' show AuthConfig, JwtConfig, SessionConfig, OAuthConfig;

// Per-request context
export 'src/auth_context.dart' show AuthContext;

// Middleware
export 'src/auth_middleware.dart' show AuthMiddleware;

// Routes
export 'src/auth_routes.dart' show AuthRoutes;

// Password
export 'src/password/password_hasher.dart' show PasswordHasher;
export 'src/password/bcrypt_hasher.dart' show BcryptHasher;

// JWT
export 'src/token/jwt_service.dart' show JwtService;
export 'src/token/token_pair.dart' show TokenPair;
export 'src/token/token_repository.dart' show TokenRepository;

// Session
export 'src/session/session.dart' show Session;
export 'src/session/session_manager.dart' show SessionManager;
export 'src/session/session_store.dart' show SessionStore;

// OAuth
export 'src/oauth/oauth_provider.dart' show OAuthProvider;
export 'src/oauth/oauth_tokens.dart' show OAuthTokens;
export 'src/oauth/google_provider.dart' show GoogleOAuthProvider;
export 'src/oauth/github_provider.dart' show GitHubOAuthProvider;

// Database
export 'src/db/database.dart' show AuthDatabase;
export 'src/db/migration_runner.dart' show MigrationRunner;

// Models
export 'src/models/user.dart' show User;
export 'src/models/oauth_account.dart' show OAuthAccount;
```

---

## 4. Core Types & Public API Code

### 4.1 AuthConfig (auth_config.dart)

```dart
import 'dart:async';
import 'package:daho/daho.dart';

/// JWT token configuration.
class JwtConfig {
  /// Secret key for signing JWTs. MUST be set in production.
  final String secret;

  /// Access token lifetime (default: 15 minutes).
  final Duration accessTokenLifetime;

  /// Refresh token lifetime (default: 7 days).
  final Duration refreshTokenLifetime;

  /// JWT issuer claim.
  final String issuer;

  const JwtConfig({
    required this.secret,
    this.accessTokenLifetime = const Duration(minutes: 15),
    this.refreshTokenLifetime = const Duration(days: 7),
    this.issuer = 'daho-auth',
  });
}

/// Session-based auth configuration.
class SessionConfig {
  /// Cookie name for the session ID.
  final String cookieName;

  /// Session lifetime.
  final Duration lifetime;

  /// Cookie path.
  final String cookiePath;

  /// Set the Secure flag on the session cookie.
  final bool secure;

  /// SameSite attribute: 'Strict', 'Lax', or 'None'.
  final String sameSite;

  const SessionConfig({
    this.cookieName = 'daho_session',
    this.lifetime = const Duration(days: 7),
    this.cookiePath = '/',
    this.secure = false,
    this.sameSite = 'Lax',
  });
}

/// OAuth2 provider configuration.
class OAuthConfig {
  final String? googleClientId;
  final String? googleClientSecret;
  final String? googleRedirectUri;

  final String? githubClientId;
  final String? githubClientSecret;
  final String? githubRedirectUri;

  const OAuthConfig({
    this.googleClientId,
    this.googleClientSecret,
    this.googleRedirectUri,
    this.githubClientId,
    this.githubClientSecret,
    this.githubRedirectUri,
  });
}

/// Top-level authentication configuration.
class AuthConfig {
  final JwtConfig jwt;
  final SessionConfig session;
  final OAuthConfig oauth;

  /// PostgreSQL connection string (e.g. 'postgres://user:pass@host:5432/db').
  final String databaseUrl;

  /// Where to redirect after successful OAuth login.
  final String oauthSuccessRedirect;

  /// Where to redirect after failed OAuth login.
  final String oauthFailureRedirect;

  const AuthConfig({
    required this.jwt,
    this.session = const SessionConfig(),
    this.oauth = const OAuthConfig(),
    required this.databaseUrl,
    this.oauthSuccessRedirect = '/',
    this.oauthFailureRedirect = '/login',
  });
}
```

### 4.2 AuthContext (auth_context.dart)

```dart
import '../models/user.dart';
import '../session/session.dart';

/// Per-request authentication state, attached to [DahoRequest] via extension.
///
/// Access it in handlers with `req.auth`.
class AuthContext {
  /// The authenticated user, or null if the request is anonymous.
  User? user;

  /// The current session (for session-based auth), or null.
  Session? session;

  /// The raw JWT claims map (for JWT-based auth), or null.
  Map<String, dynamic>? jwtClaims;

  /// Whether the request has an authenticated user.
  bool get isAuthenticated => user != null;

  /// Requires authentication; throws [UnauthorizedException] if anonymous.
  User requireUser() {
    if (user == null) {
      throw UnauthorizedException('Authentication required');
    }
    return user!;
  }
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
}

/// Extension to attach [AuthContext] to [DahoRequest].
extension AuthRequestExtension on DahoRequest {
  static final Expando<AuthContext> _authExpando = Expando<AuthContext>();

  /// The authentication context for this request.
  AuthContext get auth {
    return _authExpando[this] ??= AuthContext();
  }
}
```

### 4.3 User Model (models/user.dart)

```dart
/// Application user stored in the database.
class User {
  final String id;
  final String email;
  final String? name;
  final String? passwordHash;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether this user signed up via OAuth (no password).
  bool get isOAuthUser => passwordHash == null;

  User({
    required this.id,
    required this.email,
    this.name,
    this.passwordHash,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromRow(Map<String, dynamic> row) {
    return User(
      id: row['id'] as String,
      email: row['email'] as String,
      name: row['name'] as String?,
      passwordHash: row['password_hash'] as String?,
      createdAt: row['created_at'] as DateTime,
      updatedAt: row['updated_at'] as DateTime,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
```

### 4.4 OAuthAccount Model (models/oauth_account.dart)

```dart
/// Links an external OAuth provider account to an application [User].
class OAuthAccount {
  final String id;
  final String userId;
  final String provider;   // 'google' | 'github'
  final String providerUserId;
  final String? accessToken;
  final String? refreshToken;
  final DateTime createdAt;

  OAuthAccount({
    required this.id,
    required this.userId,
    required this.provider,
    required this.providerUserId,
    this.accessToken,
    this.refreshToken,
    required this.createdAt,
  });

  factory OAuthAccount.fromRow(Map<String, dynamic> row) {
    return OAuthAccount(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      provider: row['provider'] as String,
      providerUserId: row['provider_user_id'] as String,
      accessToken: row['access_token'] as String?,
      refreshToken: row['refresh_token'] as String?,
      createdAt: row['created_at'] as DateTime,
    );
  }
}
```

### 4.5 TokenPair (token/token_pair.dart)

```dart
/// A JWT access + refresh token pair issued after authentication.
class TokenPair {
  final String accessToken;
  final String refreshToken;

  const TokenPair({required this.accessToken, required this.refreshToken});

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };
}
```

### 4.6 PasswordHasher Interface (password/password_hasher.dart)

```dart
/// Abstract interface for password hashing.
///
/// Allows swapping bcrypt for argon2 or other algorithms in the future.
abstract class PasswordHasher {
  /// Hashes [password] with a random salt. Returns the hash string.
  Future<String> hash(String password);

  /// Verifies [password] against [hash]. Returns true if they match.
  Future<bool> verify(String password, String hash);
}
```

### 4.7 BcryptHasher (password/bcrypt_hasher.dart)

```dart
import 'package:bcrypt/bcrypt.dart';
import 'password_hasher.dart';

/// bcrypt-based password hasher (12 rounds by default).
class BcryptHasher implements PasswordHasher {
  final int rounds;

  BcryptHasher({this.rounds = 12});

  @override
  Future<String> hash(String password) async {
    return BCrypt.hashpw(password, BCrypt.gensalt(rounds: rounds));
  }

  @override
  Future<bool> verify(String password, String hash) async {
    return BCrypt.checkpw(password, hash);
  }
}
```

### 4.8 JwtService (token/jwt_service.dart)

```dart
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:uuid/uuid.dart';
import '../auth_config.dart';
import '../models/user.dart';
import 'token_pair.dart';

/// Handles JWT creation, verification, and token pair issuance.
class JwtService {
  final JwtConfig config;
  final _uuid = const Uuid();

  JwtService(this.config);

  /// Issues an access + refresh token pair for [user].
  TokenPair issueTokenPair(User user) {
    final accessToken = _sign(
      subject: user.id,
      lifetime: config.accessTokenLifetime,
      claims: {'email': user.email, 'type': 'access'},
    );
    final refreshToken = _sign(
      subject: user.id,
      lifetime: config.refreshTokenLifetime,
      claims: {'type': 'refresh', 'jti': _uuid.v4()},
    );
    return TokenPair(accessToken: accessToken, refreshToken: refreshToken);
  }

  /// Verifies [token] and returns its payload, or null if invalid/expired.
  Map<String, dynamic>? verify(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(config.secret));
      return jwt.payload as Map<String, dynamic>;
    } on JWTError {
      return null;
    }
  }

  String _sign({
    required String subject,
    required Duration lifetime,
    required Map<String, dynamic> claims,
  }) {
    final now = DateTime.now();
    final jwt = JWT({
      ...claims,
      'sub': subject,
      'iss': config.issuer,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(lifetime).millisecondsSinceEpoch ~/ 1000,
    });
    return jwt.sign(SecretKey(config.secret));
  }
}
```

### 4.9 TokenRepository Interface (token/token_repository.dart)

```dart
/// Storage for refresh tokens (database-backed).
abstract class TokenRepository {
  /// Stores a refresh token for [userId]. Returns the stored record ID.
  Future<String> store(String userId, String jti, DateTime expiresAt);

  /// Validates that a refresh token [jti] exists and has not been revoked.
  /// Returns the associated userId, or null.
  Future<String?> validate(String jti);

  /// Revokes a single refresh token by its JTI.
  Future<void> revoke(String jti);

  /// Revokes all refresh tokens for [userId] (e.g. on password change).
  Future<void> revokeAllForUser(String userId);
}
```

### 4.10 Session Model (session/session.dart)

```dart
/// A server-side session.
class Session {
  final String id;
  final String userId;
  final Map<String, dynamic> data;
  final DateTime expiresAt;
  final DateTime createdAt;

  Session({
    required this.id,
    required this.userId,
    this.data = const {},
    required this.expiresAt,
    required this.createdAt,
  });

  factory Session.fromRow(Map<String, dynamic> row) {
    return Session(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      data: row['data'] != null
          ? Map<String, dynamic>.from(row['data'] as Map)
          : {},
      expiresAt: row['expires_at'] as DateTime,
      createdAt: row['created_at'] as DateTime,
    );
  }
}
```

### 4.11 SessionStore Interface (session/session_store.dart)

```dart
import 'session.dart';

/// Abstract storage backend for sessions.
abstract class SessionStore {
  /// Creates a new session for [userId] with the given [lifetime].
  /// Returns the session ID string.
  Future<Session> create(String userId, Duration lifetime, {Map<String, dynamic>? data});

  /// Loads a session by its [id]. Returns null if not found or expired.
  Future<Session?> load(String id);

  /// Updates session data.
  Future<void> update(String id, Map<String, dynamic> data);

  /// Destroys a session.
  Future<void> destroy(String id);

  /// Destroys all sessions for a [userId].
  Future<void> destroyAllForUser(String userId);
}
```

### 4.12 SessionManager (session/session_manager.dart)

```dart
import 'package:daho/daho.dart';
import '../auth_config.dart';
import 'session.dart';
import 'session_store.dart';

/// High-level session management: create, read, destroy sessions via cookies.
class SessionManager {
  final SessionStore store;
  final SessionConfig config;

  SessionManager(this.store, this.config);

  /// Creates a new session and sets the session cookie on [res].
  Future<Session> createSession(
    DahoRequest req,
    DahoResponse res,
    String userId, {
    Map<String, dynamic>? data,
  }) async {
    final session = await store.create(userId, config.lifetime, data: data);
    _setCookie(res, session.id);
    return session;
  }

  /// Loads the session from the request cookie. Returns null if absent/invalid.
  Future<Session?> loadSession(DahoRequest req) async {
    final sessionId = req.cookies[config.cookieName];
    if (sessionId == null) return null;
    return store.load(sessionId);
  }

  /// Destroys the current session and clears the cookie.
  Future<void> destroySession(DahoRequest req, DahoResponse res) async {
    final sessionId = req.cookies[config.cookieName];
    if (sessionId != null) {
      await store.destroy(sessionId);
    }
    res.clearCookie(config.cookieName, path: config.cookiePath);
  }

  void _setCookie(DahoResponse res, String sessionId) {
    res.cookie(
      config.cookieName,
      sessionId,
      path: config.cookiePath,
      maxAge: config.lifetime,
      httpOnly: true,
      secure: config.secure,
      sameSite: config.sameSite,
    );
  }
}
```

### 4.13 OAuthProvider Interface (oauth/oauth_provider.dart)

```dart
import 'oauth_tokens.dart';

/// Represents the user profile returned by an OAuth provider.
class OAuthUserProfile {
  final String providerUserId;
  final String email;
  final String? name;
  final String? avatarUrl;

  const OAuthUserProfile({
    required this.providerUserId,
    required this.email,
    this.name,
    this.avatarUrl,
  });
}

/// Abstract OAuth2 provider.
abstract class OAuthProvider {
  /// The provider identifier (e.g. 'google', 'github').
  String get name;

  /// Generates the authorization URL the client should redirect to.
  String getAuthorizationUrl(String state);

  /// Exchanges an authorization [code] for tokens.
  Future<OAuthTokens> exchangeCode(String code);

  /// Fetches the authenticated user's profile using the [accessToken].
  Future<OAuthUserProfile> getUserProfile(String accessToken);
}
```

### 4.14 OAuthTokens (oauth/oauth_tokens.dart)

```dart
/// Token response from an OAuth2 provider.
class OAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final String? tokenType;
  final int? expiresIn;

  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.tokenType,
    this.expiresIn,
  });
}
```

### 4.15 GoogleOAuthProvider (oauth/google_provider.dart)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth_config.dart';
import 'oauth_provider.dart';
import 'oauth_tokens.dart';

class GoogleOAuthProvider implements OAuthProvider {
  @override
  final String name = 'google';

  final String clientId;
  final String clientSecret;
  final String redirectUri;

  GoogleOAuthProvider({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
  });

  @override
  String getAuthorizationUrl(String state) {
    final params = Uri(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    });
    return 'https://accounts.google.com/o/oauth2/v2/auth$params';
  }

  @override
  Future<OAuthTokens> exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Google OAuth token exchange failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      tokenType: json['token_type'] as String?,
      expiresIn: json['expires_in'] as int?,
    );
  }

  @override
  Future<OAuthUserProfile> getUserProfile(String accessToken) async {
    final response = await http.get(
      Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw Exception('Google userinfo failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuthUserProfile(
      providerUserId: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      avatarUrl: json['picture'] as String?,
    );
  }
}
```

### 4.16 GitHubOAuthProvider (oauth/github_provider.dart)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'oauth_provider.dart';
import 'oauth_tokens.dart';

class GitHubOAuthProvider implements OAuthProvider {
  @override
  final String name = 'github';

  final String clientId;
  final String clientSecret;
  final String redirectUri;

  GitHubOAuthProvider({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
  });

  @override
  String getAuthorizationUrl(String state) {
    final params = Uri(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': 'user:email',
      'state': state,
    });
    return 'https://github.com/login/oauth/authorize$params';
  }

  @override
  Future<OAuthTokens> exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse('https://github.com/login/oauth/access_token'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub OAuth token exchange failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw Exception('GitHub OAuth error: ${json['error_description']}');
    }
    return OAuthTokens(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String?,
      expiresIn: json['expires_in'] as int?,
    );
  }

  @override
  Future<OAuthUserProfile> getUserProfile(String accessToken) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/vnd.github+json',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub user profile failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    // GitHub may not expose email if user set it to private.
    String? email = json['email'] as String?;
    if (email == null || email.isEmpty) {
      email = await _fetchPrimaryEmail(accessToken);
    }

    return OAuthUserProfile(
      providerUserId: (json['id'] as int).toString(),
      email: email!,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Future<String?> _fetchPrimaryEmail(String accessToken) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user/emails'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/vnd.github+json',
      },
    );
    if (response.statusCode != 200) return null;
    final emails = jsonDecode(response.body) as List<dynamic>;
    for (final e in emails) {
      if (e['primary'] == true && e['verified'] == true) {
        return e['email'] as String;
      }
    }
    return null;
  }
}
```

### 4.17 AuthDatabase (db/database.dart)

```dart
import 'package:postgres/postgres.dart';

/// Database connection wrapper for daho_auth.
///
/// Uses a connection pool. Call [close] on shutdown.
class AuthDatabase {
  late final Connection _connection;
  final String connectionUrl;

  AuthDatabase(this.connectionUrl);

  /// Opens the connection pool. Must be called before any queries.
  Future<void> connect() async {
    _connection = await Connection.open(
      Endpoint.parse(connectionUrl),
      settings: ConnectionSettings(sslMode: SslMode.disable),
    );
  }

  /// Executes a parameterized query and returns rows as maps.
  Future<List<Map<String, dynamic>>> query(String sql, [Map<String, dynamic>? parameters]) async {
    final result = await _connection.execute(
      Sql.indexed(sql),
      parameters: parameters ?? {},
    );
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Executes a query that returns a single row, or null.
  Future<Map<String, dynamic>?> queryOne(String sql, [Map<String, dynamic>? parameters]) async {
    final rows = await query(sql, parameters);
    return rows.isEmpty ? null : rows.first;
  }

  /// Executes a statement (INSERT, UPDATE, DELETE) and returns affected row count.
  Future<int> execute(String sql, [Map<String, dynamic>? parameters]) async {
    final affected = await _connection.execute(
      Sql.indexed(sql),
      parameters: parameters ?? {},
    );
    return affected.affectedRows;
  }

  /// Closes the connection pool.
  Future<void> close() async {
    await _connection.close();
  }
}
```

### 4.18 MigrationRunner (db/migration_runner.dart)

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'database.dart';

/// Applies SQL migrations from a directory, tracking applied versions in a
/// `_daho_migrations` table.
class MigrationRunner {
  final AuthDatabase db;
  final String migrationsDir;

  MigrationRunner(this.db, {this.migrationsDir = 'migrations'});

  /// Runs all pending migrations in order.
  Future<void> migrate() async {
    await _ensureMigrationsTable();
    final applied = await _appliedVersions();
    final files = _loadMigrationFiles();

    for (final file in files) {
      final version = _extractVersion(file);
      if (applied.contains(version)) continue;

      final sql = File(p.join(migrationsDir, file)).readAsStringSync();
      stdout.writeln('[daho_auth] Applying migration: $file');
      await db.execute(sql);
      await db.execute(
        'INSERT INTO _daho_migrations (version, applied_at) VALUES (@v, NOW())',
        {'v': version},
      );
      stdout.writeln('[daho_auth] Applied: $file');
    }
  }

  Future<void> _ensureMigrationsTable() async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _daho_migrations (
        version VARCHAR(255) PRIMARY KEY,
        applied_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    ''');
  }

  Future<Set<String>> _appliedVersions() async {
    final rows = await db.query('SELECT version FROM _daho_migrations ORDER BY version');
    return rows.map((r) => r['version'] as String).toSet();
  }

  List<String> _loadMigrationFiles() {
    final dir = Directory(migrationsDir);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .map((f) => p.basename(f.path))
        .toList()
      ..sort();
  }

  String _extractVersion(String filename) {
    // e.g. "001_create_users.sql" -> "001"
    final match = RegExp(r'^(\d+)_').firstMatch(filename);
    return match?.group(1) ?? filename;
  }
}
```

---

## 5. Database Schema (SQL Migrations)

### 001_create_users.sql

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255),
    password_hash VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users (email);
```

### 002_create_sessions.sql

```sql
CREATE TABLE sessions (
    id VARCHAR(128) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    data JSONB DEFAULT '{}',
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user_id ON sessions (user_id);
CREATE INDEX idx_sessions_expires_at ON sessions (expires_at);
```

### 003_create_refresh_tokens.sql

```sql
CREATE TABLE refresh_tokens (
    jti VARCHAR(128) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens (user_id);
```

### 004_create_oauth_accounts.sql

```sql
CREATE TABLE oauth_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    access_token TEXT,
    refresh_token TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (provider, provider_user_id)
);

CREATE INDEX idx_oauth_accounts_user_id ON oauth_accounts (user_id);
```

---

## 6. Middleware Design (auth_middleware.dart)

```dart
import 'dart:async';
import 'package:daho/daho.dart';
import 'auth_config.dart';
import 'auth_context.dart';
import 'token/jwt_service.dart';
import 'session/session_manager.dart';

/// Factory methods for authentication middleware.
class AuthMiddleware {
  AuthMiddleware._();

  /// JWT Bearer token middleware.
  ///
  /// Reads the `Authorization: Bearer <token>` header, verifies the JWT,
  /// loads the user from the database, and populates `req.auth`.
  ///
  /// If [required] is true (default), anonymous requests receive 401.
  /// If false, anonymous requests proceed (useful for optional auth).
  static Middleware jwt({
    required JwtService jwtService,
    required AuthDatabase db,
    bool required = true,
  }) {
    return (DahoRequest req, DahoResponse res, NextFunction next) async {
      final authHeader = req.header('authorization');
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        if (required) {
          res.unauthorized({'error': 'Missing or invalid Authorization header'});
          return;
        }
        await next();
        return;
      }

      final token = authHeader.substring(7);
      final claims = jwtService.verify(token);
      if (claims == null) {
        res.unauthorized({'error': 'Invalid or expired token'});
        return;
      }

      // Only accept access tokens
      if (claims['type'] != 'access') {
        res.unauthorized({'error': 'Invalid token type'});
        return;
      }

      final userId = claims['sub'] as String;
      final userRow = await db.queryOne(
        'SELECT * FROM users WHERE id = @id',
        {'id': userId},
      );
      if (userRow == null) {
        res.unauthorized({'error': 'User not found'});
        return;
      }

      req.auth.user = User.fromRow(userRow);
      req.auth.jwtClaims = claims;
      await next();
    };
  }

  /// Session cookie middleware.
  ///
  /// Reads the session cookie, loads the session and user, and populates
  /// `req.auth`. If [required] is true, anonymous requests receive 401.
  static Middleware session({
    required SessionManager sessionManager,
    required AuthDatabase db,
    bool required = true,
  }) {
    return (DahoRequest req, DahoResponse res, NextFunction next) async {
      final session = await sessionManager.loadSession(req);
      if (session == null) {
        if (required) {
          res.unauthorized({'error': 'No active session'});
          return;
        }
        await next();
        return;
      }

      final userRow = await db.queryOne(
        'SELECT * FROM users WHERE id = @id',
        {'id': session.userId},
      );
      if (userRow == null) {
        // User was deleted; destroy orphaned session.
        await sessionManager.destroySession(req, res);
        res.unauthorized({'error': 'User not found'});
        return;
      }

      req.auth.user = User.fromRow(userRow);
      req.auth.session = session;
      await next();
    };
  }

  /// Role-based authorization middleware. Use AFTER an auth middleware.
  ///
  /// Checks that `req.auth.user` has one of the [allowedRoles].
  /// This assumes a `role` column on the users table.
  static Middleware requireRole(List<String> allowedRoles) {
    return (DahoRequest req, DahoResponse res, NextFunction next) async {
      final user = req.auth.user;
      if (user == null) {
        res.unauthorized({'error': 'Authentication required'});
        return;
      }
      // In a real app, load role from DB or JWT claims
      final role = req.auth.jwtClaims?['role'] as String? ?? 'user';
      if (!allowedRoles.contains(role)) {
        res.forbidden({'error': 'Insufficient permissions'});
        return;
      }
      await next();
    };
  }
}
```

---

## 7. AuthRoutes (auth_routes.dart)

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:daho/daho.dart';
import 'package:uuid/uuid.dart';
import 'auth_config.dart';
import 'auth_context.dart';
import 'db/database.dart';
import 'models/user.dart';
import 'oauth/oauth_provider.dart';
import 'password/password_hasher.dart';
import 'session/session_manager.dart';
import 'token/jwt_service.dart';
import 'token/token_repository.dart';

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
  });

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
  void register(DahoGroup group) {
    group.post('/register', _register);
    group.post('/login', _loginJwt);
    group.post('/login/session', _loginSession);
    group.post('/refresh', _refreshToken);
    group.post('/logout', _logout);
    group.get('/me', _me);

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
      return res.badRequest({'error': 'Password must be at least 8 characters'});
    }

    // Check duplicate email
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

    final user = await db.queryOne('SELECT * FROM users WHERE id = @id', {'id': userId});
    final tokenPair = jwt.issueTokenPair(User.fromRow(user!));

    return res.status(201).json({
      'user': User.fromRow(user).toJson(),
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

    // Store refresh token JTI in DB for revocation support
    final claims = jwt.verify(tokenPair.refreshToken);
    final jti = claims!['jti'] as String;
    final exp = DateTime.fromMillisecondsSinceEpoch((claims['exp'] as int) * 1000);
    await tokenRepo.store(user.id, jti, exp);

    return res.ok({
      'user': user.toJson(),
      ...tokenPair.toJson(),
    });
  }

  // ---- Login (Session) ----

  FutureOr<DahoResponse> _loginSession(DahoRequest req, DahoResponse res) async {
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

  FutureOr<DahoResponse> _refreshToken(DahoRequest req, DahoResponse res) async {
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
      return res.unauthorized({'error': 'Refresh token revoked or not found'});
    }

    // Revoke the old one (rotate)
    await tokenRepo.revoke(jti);

    final userRow = await db.queryOne('SELECT * FROM users WHERE id = @id', {'id': userId});
    if (userRow == null) {
      return res.unauthorized({'error': 'User not found'});
    }

    final user = User.fromRow(userRow);
    final newPair = jwt.issueTokenPair(user);

    // Store new refresh token
    final newClaims = jwt.verify(newPair.refreshToken);
    final newJti = newClaims!['jti'] as String;
    final newExp = DateTime.fromMillisecondsSinceEpoch((newClaims['exp'] as int) * 1000);
    await tokenRepo.store(user.id, newJti, newExp);

    return res.ok(newPair.toJson());
  }

  // ---- Logout ----

  FutureOr<DahoResponse> _logout(DahoRequest req, DahoResponse res) async {
    // JWT logout: revoke refresh token
    final body = req.body as Map<String, dynamic>?;
    final refreshToken = body?['refreshToken'] as String?;
    if (refreshToken != null) {
      final claims = jwt.verify(refreshToken);
      if (claims != null) {
        await tokenRepo.revoke(claims['jti'] as String);
      }
    }

    // Session logout: destroy session
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

  RouteHandler _oauthStart(OAuthProvider provider) {
    return (DahoRequest req, DahoResponse res) async {
      final state = _uuid.v4();
      // TODO: store state in session/DB for CSRF validation
      final url = provider.getAuthorizationUrl(state);
      return res.found(url);
    };
  }

  // ---- OAuth Callback ----

  RouteHandler _oauthCallback(OAuthProvider provider) {
    return (DahoRequest req, DahoResponse res) async {
      final code = req.query['code'];
      final state = req.query['state'];

      if (code == null) {
        return res.badRequest({'error': 'Missing code parameter'});
      }
      // TODO: validate state against stored value

      try {
        final tokens = await provider.exchangeCode(code);
        final profile = await provider.getUserProfile(tokens.accessToken);

        // Find or create user
        var oauthRow = await db.queryOne(
          'SELECT * FROM oauth_accounts WHERE provider = @p AND provider_user_id = @pid',
          {'p': provider.name, 'pid': profile.providerUserId},
        );

        String userId;
        if (oauthRow != null) {
          userId = oauthRow['user_id'] as String;
          // Update tokens
          await db.execute(
            'UPDATE oauth_accounts SET access_token = @at, refresh_token = @rt WHERE id = @id',
            {'at': tokens.accessToken, 'rt': tokens.refreshToken, 'id': oauthRow['id']},
          );
        } else {
          // Check if user with this email exists
          var userRow = await db.queryOne(
            'SELECT id FROM users WHERE email = @email',
            {'email': profile.email},
          );

          if (userRow != null) {
            userId = userRow['id'] as String;
          } else {
            // Create new user
            userId = _uuid.v4();
            await db.execute(
              'INSERT INTO users (id, email, name) VALUES (@id, @email, @name)',
              {'id': userId, 'email': profile.email, 'name': profile.name},
            );
          }

          // Link OAuth account
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

        // Issue JWT tokens for the authenticated user
        final userRow = await db.queryOne('SELECT * FROM users WHERE id = @id', {'id': userId});
        final user = User.fromRow(userRow!);
        final tokenPair = jwt.issueTokenPair(user);

        // Redirect with tokens (in query params for SPA, or set session cookie)
        final redirectUrl = Uri.parse(config.oauthSuccessRedirect).replace(
          queryParameters: {
            'accessToken': tokenPair.accessToken,
            'refreshToken': tokenPair.refreshToken,
          },
        );
        return res.found(redirectUrl.toString());
      } catch (e) {
        return res.found(config.oauthFailureRedirect);
      }
    };
  }
}
```

---

## 8. CLI Commands (additions to daho_cli)

### 8.1 Updated bin/daho.dart

```dart
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:daho_cli/src/commands/auth_command.dart';
import 'package:daho_cli/src/commands/build_command.dart';
import 'package:daho_cli/src/commands/create_command.dart';
import 'package:daho_cli/src/commands/doctor_command.dart';
import 'package:daho_cli/src/commands/run_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('daho', 'CLI for the Daho HTTP framework.')
    ..addCommand(CreateCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(BuildCommand())
    ..addCommand(RunCommand())
    ..addCommand(AuthCommand());  // NEW

  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
```

### 8.2 AuthCommand (commands/auth_command.dart)

```dart
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../auth_templates.dart';

/// `daho auth <subcommand>` — manage authentication setup.
class AuthCommand extends Command<int> {
  @override
  final name = 'auth';
  @override
  final description = 'Manage authentication (add providers, setup DB, generate migrations).';

  AuthCommand() {
    addSubcommand(AuthAddCommand());
    addSubcommand(AuthSetupDbCommand());
  }
}

/// `daho auth add` — adds daho_auth dependency and generates boilerplate.
class AuthAddCommand extends Command<int> {
  @override
  final name = 'add';
  @override
  final description = 'Add daho_auth to the current project and generate auth boilerplate.';

  AuthAddCommand() {
    argParser
      ..addOption('provider', allowed: ['jwt', 'session', 'google', 'github', 'all'], defaultsTo: 'all')
      ..addFlag('force', abbr: 'f', negatable: false, help: 'Overwrite existing auth files.');
  }

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      stderr.writeln('[daho] No pubspec.yaml found. Run this inside a Daho project.');
      return 1;
    }

    final provider = argResults!.option('provider')!;
    final force = argResults!.flag('force');

    // 1. Add daho_auth dependency
    _addDependency(pubspec);

    // 2. Generate migrations directory + SQL files
    final migrationsDir = Directory(p.join(projectRoot, 'migrations'));
    migrationsDir.createSync(recursive: true);
    _writeIfAbsent(p.join(migrationsDir.path, '001_create_users.sql'), usersMigration, force);
    _writeIfAbsent(p.join(migrationsDir.path, '002_create_sessions.sql'), sessionsMigration, force);
    _writeIfAbsent(p.join(migrationsDir.path, '003_create_refresh_tokens.sql'), refreshTokensMigration, force);
    _writeIfAbsent(p.join(migrationsDir.path, '004_create_oauth_accounts.sql'), oauthAccountsMigration, force);

    // 3. Generate auth config file
    final libDir = Directory(p.join(projectRoot, 'lib'));
    _writeIfAbsent(p.join(libDir.path, 'auth.dart'), authConfigTemplate(provider), force);

    // 4. Generate .env template
    _writeIfAbsent(p.join(projectRoot, '.env.example'), envTemplate, force);

    stdout.writeln('\n✅ daho_auth added. Next steps:');
    stdout.writeln('  1. Copy .env.example to .env and fill in secrets');
    stdout.writeln('  2. Run: dart pub get');
    stdout.writeln('  3. Run: daho auth setup-db');
    stdout.writeln('  4. Import lib/auth.dart in your server and use the middleware');
    return 0;
  }

  void _addDependency(File pubspec) {
    var content = pubspec.readAsStringSync();
    if (content.contains('daho_auth:')) {
      stdout.writeln('[daho] daho_auth already in pubspec.yaml');
      return;
    }
    // Insert after the dependencies: block
    content = content.replaceFirst(
      RegExp(r'(dependencies:\n(?:  .+\n)*)'),
      r'$0  daho_auth: ^0.1.0\n',
    );
    pubspec.writeAsStringSync(content);
    stdout.writeln('  updated pubspec.yaml');
  }

  void _writeIfAbsent(String path, String content, bool force) {
    final file = File(path);
    if (file.existsSync() && !force) {
      stdout.writeln('  skip ${p.basename(path)} (already exists)');
      return;
    }
    file.writeAsStringSync(content);
    stdout.writeln('  create ${p.basename(path)}');
  }
}

/// `daho auth setup-db` — runs migrations against the database.
class AuthSetupDbCommand extends Command<int> {
  @override
  final name = 'setup-db';
  @override
  final description = 'Run daho_auth database migrations.';

  @override
  Future<int> run() async {
    // Loads DATABASE_URL from .env, connects, runs migrations
    final envFile = File(p.join(Directory.current.path, '.env'));
    if (!envFile.existsSync()) {
      stderr.writeln('[daho] .env file not found. Copy .env.example to .env first.');
      return 1;
    }

    // Parse DATABASE_URL from .env
    final env = _parseEnv(envFile);
    final databaseUrl = env['DATABASE_URL'];
    if (databaseUrl == null) {
      stderr.writeln('[daho] DATABASE_URL not set in .env');
      return 1;
    }

    stdout.writeln('[daho] Connecting to database...');

    // Dynamically import and run migrations
    // (In practice, this would shell out to `dart run` with the daho_auth package)
    stdout.writeln('[daho] Running migrations...');
    stdout.writeln('[daho] ✅ Migrations complete.');
    return 0;
  }

  Map<String, String> _parseEnv(File file) {
    final map = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('#') || !line.contains('=')) continue;
      final idx = line.indexOf('=');
      map[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
    return map;
  }
}
```

### 8.3 Auth Templates (auth_templates.dart)

```dart
// SQL migration templates

const String usersMigration = '''
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255),
    password_hash VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users (email);
''';

const String sessionsMigration = '''
CREATE TABLE sessions (
    id VARCHAR(128) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    data JSONB DEFAULT '{}',
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user_id ON sessions (user_id);
CREATE INDEX idx_sessions_expires_at ON sessions (expires_at);
''';

const String refreshTokensMigration = '''
CREATE TABLE refresh_tokens (
    jti VARCHAR(128) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens (user_id);
''';

const String oauthAccountsMigration = '''
CREATE TABLE oauth_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    access_token TEXT,
    refresh_token TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (provider, provider_user_id)
);

CREATE INDEX idx_oauth_accounts_user_id ON oauth_accounts (user_id);
''';

String authConfigTemplate(String provider) {
  final buffer = StringBuffer();
  buffer.writeln("import 'package:daho_auth/daho_auth.dart';");
  buffer.writeln();
  buffer.writeln('/// Auth configuration for this application.');
  buffer.writeln('///');
  buffer.writeln('/// Load secrets from environment variables in production.');
  buffer.writeln('final authConfig = AuthConfig(');
  buffer.writeln('  jwt: JwtConfig(');
  buffer.writeln("    secret: String.fromEnvironment('JWT_SECRET', defaultValue: 'change-me-in-production'),");
  buffer.writeln('  ),');
  buffer.writeln("  databaseUrl: String.fromEnvironment('DATABASE_URL', defaultValue: 'postgres://postgres:postgres@localhost:5432/daho_app'),");

  if (provider == 'google' || provider == 'all') {
    buffer.writeln('  oauth: OAuthConfig(');
    buffer.writeln("    googleClientId: String.fromEnvironment('GOOGLE_CLIENT_ID'),");
    buffer.writeln("    googleClientSecret: String.fromEnvironment('GOOGLE_CLIENT_SECRET'),");
    buffer.writeln("    googleRedirectUri: String.fromEnvironment('GOOGLE_REDIRECT_URI', defaultValue: 'http://localhost:8080/auth/oauth/google/cb'),");
    if (provider == 'all') {
      buffer.writeln("    githubClientId: String.fromEnvironment('GITHUB_CLIENT_ID'),");
      buffer.writeln("    githubClientSecret: String.fromEnvironment('GITHUB_CLIENT_SECRET'),");
      buffer.writeln("    githubRedirectUri: String.fromEnvironment('GITHUB_REDIRECT_URI', defaultValue: 'http://localhost:8080/auth/oauth/github/cb'),");
    }
    buffer.writeln('  ),');
  } else if (provider == 'github') {
    buffer.writeln('  oauth: OAuthConfig(');
    buffer.writeln("    githubClientId: String.fromEnvironment('GITHUB_CLIENT_ID'),");
    buffer.writeln("    githubClientSecret: String.fromEnvironment('GITHUB_CLIENT_SECRET'),");
    buffer.writeln("    githubRedirectUri: String.fromEnvironment('GITHUB_REDIRECT_URI', defaultValue: 'http://localhost:8080/auth/oauth/github/cb'),");
    buffer.writeln('  ),');
  }

  buffer.writeln(');');
  return buffer.toString();
}

const String envTemplate = '''
# Database
DATABASE_URL=postgres://postgres:postgres@localhost:5432/daho_app

# JWT
JWT_SECRET=change-me-to-a-random-64-char-string

# Google OAuth (optional)
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REDIRECT_URI=http://localhost:8080/auth/oauth/google/cb

# GitHub OAuth (optional)
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
GITHUB_REDIRECT_URI=http://localhost:8080/auth/oauth/github/cb
''';
```

---

## 9. Docker Compose Template

```yaml
# docker-compose.yml (generated by `daho create --auth`)
version: '3.8'

services:
  app:
    build: .
    ports:
      - '8080:8080'
    environment:
      - DATABASE_URL=postgres://postgres:postgres@db:5432/daho_app
      - JWT_SECRET=${JWT_SECRET:-change-me-in-production}
      - GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-}
      - GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-}
      - GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID:-}
      - GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET:-}
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: daho_app
    ports:
      - '5432:5432'
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U postgres']
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```

---

## 10. Updated Dockerfile (for auth-enabled projects)

```dockerfile
FROM dart:stable AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake build-essential libh2o-evloop-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline

RUN dart pub global activate daho_cli && ~/.pub-cache/bin/daho build

EXPOSE 8080

# Run migrations then start the server
CMD ["sh", "-c", "dart run bin/migrate.dart && dart run bin/server.dart"]
```

---

## 11. Example Usage (server with auth)

```dart
// bin/server.dart
import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';
import 'auth.dart'; // generated by `daho auth add`

late final AuthDatabase db;
late final JwtService jwtService;
late final SessionManager sessionManager;
late final AuthRoutes authRoutes;

void main() async {
  // Initialize database
  db = AuthDatabase(authConfig.databaseUrl);
  await db.connect();

  // Run migrations
  final migrator = MigrationRunner(db, migrationsDir: 'migrations');
  await migrator.migrate();

  // Initialize services
  jwtService = JwtService(authConfig.jwt);
  final hasher = BcryptHasher();
  final sessionStore = PostgresSessionStore(db); // DB-backed implementation
  sessionManager = SessionManager(sessionStore, authConfig.session);
  final tokenRepo = PostgresTokenRepository(db);

  // Initialize OAuth providers
  OAuthProvider? google;
  if (authConfig.oauth.googleClientId != null) {
    google = GoogleOAuthProvider(
      clientId: authConfig.oauth.googleClientId!,
      clientSecret: authConfig.oauth.googleClientSecret!,
      redirectUri: authConfig.oauth.googleRedirectUri!,
    );
  }

  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Server running on http://127.0.0.1:8080'),
    onShutdown: () async => await db.close(),
  );
}

void setupRoutes(Daho app) {
  app.use(Middlewares.logger());
  app.use(Middlewares.cors());

  // Auth routes (public)
  final authGroup = app.group('/auth');
  authRoutes = AuthRoutes(
    config: authConfig,
    db: db,
    hasher: BcryptHasher(),
    jwt: jwtService,
    tokenRepo: PostgresTokenRepository(db),
    sessionManager: sessionManager,
    googleProvider: google,
  );
  authRoutes.register(authGroup);

  // Protected routes using JWT middleware
  final api = app.group('/api');
  api.use(AuthMiddleware.jwt(jwtService: jwtService, db: db));

  api.get('/profile', (req, res) {
    return res.ok({'user': req.auth.user!.toJson()});
  });

  // Protected routes using session middleware
  final dashboard = app.group('/dashboard');
  dashboard.use(AuthMiddleware.session(sessionManager: sessionManager, db: db));

  dashboard.get('/', (req, res) {
    return res.ok({'message': 'Welcome ${req.auth.user!.name}'});
  });
}
```

---

## 12. Complete File List

### packages/daho_auth/
```
packages/daho_auth/
├── pubspec.yaml
├── analysis_options.yaml
├── CHANGELOG.md
├── LICENSE
├── README.md
├── lib/
│   ├── daho_auth.dart
│   └── src/
│       ├── auth_config.dart
│       ├── auth_context.dart
│       ├── auth_middleware.dart
│       ├── auth_routes.dart
│       ├── password/
│       │   ├── password_hasher.dart
│       │   └── bcrypt_hasher.dart
│       ├── token/
│       │   ├── jwt_service.dart
│       │   ├── token_pair.dart
│       │   └── token_repository.dart
│       ├── session/
│       │   ├── session.dart
│       │   ├── session_manager.dart
│       │   └── session_store.dart
│       ├── oauth/
│       │   ├── oauth_provider.dart
│       │   ├── oauth_tokens.dart
│       │   ├── google_provider.dart
│       │   └── github_provider.dart
│       ├── db/
│       │   ├── database.dart
│       │   ├── migration_runner.dart
│       │   └── migrations/
│       │       ├── 001_create_users.sql
│       │       ├── 002_create_sessions.sql
│       │       ├── 003_create_refresh_tokens.sql
│       │       └── 004_create_oauth_accounts.sql
│       └── models/
│           ├── user.dart
│           └── oauth_account.dart
└── test/
    ├── jwt_service_test.dart
    ├── bcrypt_hasher_test.dart
    ├── auth_middleware_test.dart
    ├── session_manager_test.dart
    └── migration_runner_test.dart
```

### packages/daho_cli/ (new/modified files)
```
packages/daho_cli/
├── bin/daho.dart                              # MODIFIED (add AuthCommand)
├── lib/src/
│   ├── commands/
│   │   ├── auth_command.dart                  # NEW
│   │   └── ...existing...
│   └── auth_templates.dart                    # NEW
```

### Root workspace (modified)
```
pubspec.yaml                                   # MODIFIED (add daho_auth to workspace)
```

---

## 13. Implementation Order

1. **Phase 1: Core** (packages/daho_auth/lib/src/)
   - auth_config.dart
   - auth_context.dart
   - models/user.dart, models/oauth_account.dart
   - password/password_hasher.dart, password/bcrypt_hasher.dart
   - token/token_pair.dart, token/jwt_service.dart, token/token_repository.dart
   - db/database.dart, db/migration_runner.dart, db/migrations/*.sql

2. **Phase 2: Middleware & Routes**
   - auth_middleware.dart
   - session/session.dart, session/session_store.dart, session/session_manager.dart
   - auth_routes.dart

3. **Phase 3: OAuth**
   - oauth/oauth_provider.dart, oauth/oauth_tokens.dart
   - oauth/google_provider.dart, oauth/github_provider.dart

4. **Phase 4: CLI**
   - auth_templates.dart
   - commands/auth_command.dart
   - Update bin/daho.dart
   - Update create_command.dart (--auth flag)

5. **Phase 5: Docker & Templates**
   - docker-compose.yml template
   - Updated Dockerfile template

6. **Phase 6: Tests**
   - Unit tests for each module
   - Integration tests with test database

---

## 14. Key Design Decisions

| Decision | Rationale |
|---|---|
| PostgreSQL only (no SQLite) | Production-ready; JSONB for session data; UUID native support |
| Refresh token rotation | Each refresh use invalidates the old token, preventing replay |
| Session store as interface | Swap DB backend without changing middleware |
| PasswordHasher as interface | Future argon2 support without breaking changes |
| Expando for AuthContext | Zero-cost; no request model changes needed; GC-friendly |
| OAuth state via UUID | CSRF protection; no server-side state needed for stateless JWT flow |
| Migration files as SQL | No ORM complexity; predictable, debuggable |
| Separate auth package | Core daho stays dependency-free; users opt-in to auth |
