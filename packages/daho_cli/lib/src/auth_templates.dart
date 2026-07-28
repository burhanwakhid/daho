// Auth-related templates for `daho auth add` and `daho create --auth`.

import 'templates.dart' show h2oFromSourceInstallStep;

/// The `daho` dependency line. When [localPath] is given, a path dependency is
/// emitted (for local development before publishing); otherwise a hosted one.
String _dahoDependency(String? localPath) {
  if (localPath != null) {
    return 'daho:\n    path: $localPath';
  }
  return 'daho: ^0.1.0';
}

/// The `daho_auth` dependency line. `daho_auth` has `publish_to: none` — it
/// is NOT published to pub.dev — so a hosted `^0.1.0` constraint will never
/// resolve on its own. When [daoAuthLocalPath] is given (derived as a sibling
/// of the `daho` [localPath] in the same monorepo checkout), a path
/// dependency is emitted instead.
String _dahoAuthDependency(String? daoAuthLocalPath) {
  if (daoAuthLocalPath != null) {
    return 'daho_auth:\n    path: $daoAuthLocalPath';
  }
  return 'daho_auth: ^0.1.0';
}

/// Derives the local `daho_auth` package path as a sibling of [dahoLocalPath]
/// (i.e. `.../packages/daho` -> `.../packages/daho_auth`), matching this
/// repo's layout. Returns null if [dahoLocalPath] is null.
String? siblingDahoAuthPath(String? dahoLocalPath) {
  if (dahoLocalPath == null) return null;
  final segments = dahoLocalPath.split('/')..removeLast();
  return [...segments, 'daho_auth'].join('/');
}

String authPubspecTemplate(
  String name, {
  String? localPath,
  String? dahoAuthLocalPath,
}) =>
    '''
name: $name
description: A Daho HTTP server with authentication.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.9.0

dependencies:
  ${_dahoDependency(localPath)}
  ${_dahoAuthDependency(dahoAuthLocalPath)}

dev_dependencies:
  lints: ^6.0.0
''';

// SQL migration templates — kept in sync with
// packages/daho_auth/lib/src/db/migrations/*.sql. There are two independent
// copies (there, and here as embedded strings) because this CLI writes files
// into a *new*, unrelated project rather than depending on daho_auth's
// package assets at codegen time — if you add a migration to daho_auth,
// mirror it here too.

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

const String oauthExchangeCodesMigration = '''
CREATE TABLE oauth_exchange_codes (
    code UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_oauth_exchange_codes_expires_at ON oauth_exchange_codes (expires_at);
''';

const String addRoleToUsersMigration =
    "ALTER TABLE users ADD COLUMN role VARCHAR(50) NOT NULL DEFAULT 'user';\n";

/// Writes every migration file (in order) into [migrationsDir] via
/// [write]. Centralizes the list so `create` and `auth add` can't drift.
void writeAuthMigrations(void Function(String filename, String content) write) {
  write('001_create_users.sql', usersMigration);
  write('002_create_sessions.sql', sessionsMigration);
  write('003_create_refresh_tokens.sql', refreshTokensMigration);
  write('004_create_oauth_accounts.sql', oauthAccountsMigration);
  write('005_create_oauth_exchange_codes.sql', oauthExchangeCodesMigration);
  write('006_add_role_to_users.sql', addRoleToUsersMigration);
}

/// `lib/env.dart` — loads config from real process environment variables,
/// with a local `.env` file (if present) filling in whatever isn't already
/// set. Deliberately NOT `String.fromEnvironment`: that only reads
/// compile-time `--define=KEY=VALUE` flags, not a `.env` file or a real
/// shell/Docker environment variable — using it here would make `.env`
/// silently ineffective and every secret would quietly fall back to its
/// default value.
String envLoaderTemplate() => '''
import 'dart:io';

/// Merged environment: real process env vars (e.g. set by `docker-compose`'s
/// `environment:` block, or `export FOO=bar` in your shell) take precedence;
/// a local `.env` file fills in whatever isn't already set — handy for
/// `dart run` / `daho run` during local development.
final Map<String, String> env = _loadEnv();

Map<String, String> _loadEnv() {
  final merged = <String, String>{};
  final file = File('.env');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      merged[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
    }
  }
  merged.addAll(Platform.environment);
  return merged;
}
''';

String authConfigTemplate(String provider) {
  final buffer = StringBuffer();
  buffer.writeln("import 'package:daho_auth/daho_auth.dart';");
  buffer.writeln("import 'env.dart';");
  buffer.writeln();
  buffer.writeln('/// Auth configuration for this application.');
  buffer.writeln('///');
  buffer.writeln(
    '/// Secrets come from `env` (real environment variables, with a local '
    "`.env` file filling in the rest — see env.dart), never hardcoded.",
  );
  buffer.writeln('final authConfig = AuthConfig(');
  buffer.writeln('  jwt: JwtConfig(');
  buffer.writeln(
    "    secret: env['JWT_SECRET'] ?? 'change-me-in-production', // TODO: set a real secret in .env / your deployment's env vars",
  );
  buffer.writeln('  ),');
  buffer.writeln(
    "  databaseUrl: env['DATABASE_URL'] ?? 'postgres://postgres:postgres@localhost:5432/daho_app',",
  );
  buffer.writeln(
    '  // session: SessionConfig(secure: true), // once served over HTTPS',
  );

  if (provider == 'google' || provider == 'all') {
    buffer.writeln('  oauth: OAuthConfig(');
    buffer.writeln("    googleClientId: env['GOOGLE_CLIENT_ID'],");
    buffer.writeln("    googleClientSecret: env['GOOGLE_CLIENT_SECRET'],");
    buffer.writeln(
      "    googleRedirectUri: env['GOOGLE_REDIRECT_URI'] ?? 'http://localhost:8080/auth/oauth/google/cb',",
    );
    if (provider == 'all') {
      buffer.writeln("    githubClientId: env['GITHUB_CLIENT_ID'],");
      buffer.writeln("    githubClientSecret: env['GITHUB_CLIENT_SECRET'],");
      buffer.writeln(
        "    githubRedirectUri: env['GITHUB_REDIRECT_URI'] ?? 'http://localhost:8080/auth/oauth/github/cb',",
      );
    }
    buffer.writeln('  ),');
  } else if (provider == 'github') {
    buffer.writeln('  oauth: OAuthConfig(');
    buffer.writeln("    githubClientId: env['GITHUB_CLIENT_ID'],");
    buffer.writeln("    githubClientSecret: env['GITHUB_CLIENT_SECRET'],");
    buffer.writeln(
      "    githubRedirectUri: env['GITHUB_REDIRECT_URI'] ?? 'http://localhost:8080/auth/oauth/github/cb',",
    );
    buffer.writeln('  ),');
  }

  buffer.writeln(');');
  return buffer.toString();
}

const String envTemplate = '''
# Database
DATABASE_URL=postgres://postgres:postgres@localhost:5432/daho_app
# For a remote/production Postgres, also set sslMode: SslMode.require on the
# AuthDatabase in bin/migrate.dart and lib/routes.dart (defaults to
# SslMode.disable so a plain local Postgres works out of the box).

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

String authServerTemplate(String name) =>
    '''
import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';
import 'package:$name/routes.dart';
import 'package:$name/auth.dart';

Future<void> main() async {
  // Migrations run exactly once, on a short-lived connection, before any
  // worker Isolate starts (see the isolate-safety note in lib/routes.dart).
  final migrationDb = AuthDatabase(authConfig.databaseUrl);
  await migrationDb.connect();
  await MigrationRunner(migrationDb, migrationsDir: 'migrations').migrate();
  await migrationDb.close();

  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('🚀 $name running on http://127.0.0.1:8080'),
    // No onShutdown DB cleanup: each worker Isolate builds and owns its own
    // AuthDatabase (see setupRoutes), and onShutdown only runs on the
    // master Isolate, which can't reach worker-owned resources.
  );
}
''';

String authRoutesTemplate(String name) =>
    '''
import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';
import 'package:$name/auth.dart';

/// Registers all routes and middleware.
///
/// This MUST be a top-level function: it is re-run fresh in every worker
/// Isolate (one per CPU core), and worker Isolates do NOT share state
/// constructed in `main()` — a top-level `late final` assigned there is
/// simply uninitialized inside a spawned Isolate. So everything routes
/// need (the DB connection, JWT service, session manager, OAuth providers)
/// is built here, from scratch, every time this function runs.
void setupRoutes(Daho app) {
  // `db.connect()` is intentionally not awaited — this function can't be
  // async. AuthDatabase queues queries internally until the connection is
  // ready, so the first request or two simply waits slightly longer.
  final db = AuthDatabase(authConfig.databaseUrl);
  db.connect();

  final jwtService = JwtService(authConfig.jwt);
  final sessionManager = SessionManager(PostgresSessionStore(db), authConfig.session);

  // OAuth providers are only created when their client id/secret are
  // actually configured (via .env) — leave them unset to skip that
  // provider entirely; AuthRoutes only registers /oauth/<provider> routes
  // for the providers you pass in.
  final googleClientId = authConfig.oauth.googleClientId;
  final googleProvider = (googleClientId != null && googleClientId.isNotEmpty)
      ? GoogleOAuthProvider(
          clientId: googleClientId,
          clientSecret: authConfig.oauth.googleClientSecret!,
          redirectUri: authConfig.oauth.googleRedirectUri!,
        )
      : null;

  final githubClientId = authConfig.oauth.githubClientId;
  final githubProvider = (githubClientId != null && githubClientId.isNotEmpty)
      ? GitHubOAuthProvider(
          clientId: githubClientId,
          clientSecret: authConfig.oauth.githubClientSecret!,
          redirectUri: authConfig.oauth.githubRedirectUri!,
        )
      : null;

  final authRoutes = AuthRoutes(
    config: authConfig,
    db: db,
    hasher: BcryptHasher(),
    jwt: jwtService,
    tokenRepo: PostgresTokenRepository(db),
    sessionManager: sessionManager,
    googleProvider: googleProvider,
    githubProvider: githubProvider,
  );

  app.use(Middlewares.logger());
  app.use(Middlewares.cors());

  // Auth routes (public)
  final authGroup = app.group('/auth');
  authRoutes.register(authGroup);

  // Protected routes using JWT middleware
  final api = app.group('/api');
  api.use(AuthMiddleware.jwt(jwtService: jwtService, db: db));

  api.get('/profile', (req, res) {
    return res.ok({'user': req.auth.user!.toJson()});
  });

  // Admin-only example: requireRole reads req.auth.user.role, loaded from
  // the users.role column (default 'user'). Promote a user directly in the
  // database — there's deliberately no self-service way to become
  // 'admin', since that would be a privilege-escalation bug:
  //   UPDATE users SET role = 'admin' WHERE email = '...';
  api.get(
    '/admin',
    (req, res) => res.ok({'message': 'Welcome, admin \${req.auth.user!.email}'}),
    use: [AuthMiddleware.requireRole(['admin'])],
  );

  app.get('/health', (req, res) => res.ok({'status': 'ok'}));
}
''';

String dockerComposeTemplate(String name) =>
    '''
version: '3.8'

services:
  app:
    build: .
    ports:
      - '8080:8080'
    environment:
      - DATABASE_URL=postgres://postgres:postgres@db:5432/$name
      - JWT_SECRET=\${JWT_SECRET:-change-me-in-production}
      - GOOGLE_CLIENT_ID=\${GOOGLE_CLIENT_ID:-}
      - GOOGLE_CLIENT_SECRET=\${GOOGLE_CLIENT_SECRET:-}
      - GITHUB_CLIENT_ID=\${GITHUB_CLIENT_ID:-}
      - GITHUB_CLIENT_SECRET=\${GITHUB_CLIENT_SECRET:-}
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: $name
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
''';

String authDockerfileTemplate(String name) =>
    '''
FROM dart:stable AS build

RUN apt-get update && apt-get install -y --no-install-recommends \\
    cmake build-essential git pkg-config libssl-dev zlib1g-dev \\
    && rm -rf /var/lib/apt/lists/*

$h2oFromSourceInstallStep
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline

RUN dart pub global activate daho_cli && ~/.pub-cache/bin/daho build

EXPOSE 8080

# Run migrations then start the server
CMD ["sh", "-c", "dart run bin/migrate.dart && dart run bin/server.dart"]
''';

String migrateTemplate(String name) =>
    '''
import 'package:daho_auth/daho_auth.dart';
import 'package:$name/auth.dart';

Future<void> main() async {
  final db = AuthDatabase(authConfig.databaseUrl);
  await db.connect();
  await MigrationRunner(db, migrationsDir: 'migrations').migrate();
  await db.close();
  print('Migrations complete.');
}
''';
