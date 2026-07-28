# Authentication (daho_auth)

`daho_auth` is a comprehensive authentication package for Daho, providing JWT, session-based, and OAuth2 authentication out of the box.

## Features

- **JWT Authentication** — Access + refresh token rotation
- **Session-based Authentication** — Server-side sessions with cookies
- **OAuth2** — Google and GitHub providers, with CSRF-protected `state` handling and a one-time exchange code (tokens are never put in a redirect URL)
- **bcrypt Password Hashing** — Industry standard, 12 rounds default
- **PostgreSQL** — Production-ready database with auto-migrations
- **Role-based Authorization** — `AuthMiddleware.requireRole()`, backed by a real `users.role` column

## Installation

`daho_auth` has `publish_to: none` — it is **not published to pub.dev**, so a hosted `daho_auth: ^0.1.0` dependency will not resolve on its own. Use a path dependency to a local checkout:

```yaml
dependencies:
  daho:
    path: ../path/to/packages/daho
  daho_auth:
    path: ../path/to/packages/daho_auth
```

Or use the CLI, which wires this up for you:

```bash
# New project
daho create myapp --auth --local <path-to-packages/daho>

# Existing project
daho auth add --local <path-to-packages/daho>
```

(`--local` takes the path to `packages/daho`; `packages/daho_auth` is assumed to be its sibling directory, matching this repo's layout.)

## Quick Start

::: warning Isolate safety
Daho's `routes` builder (`setupRoutes` below) is re-run **fresh in every worker Isolate** — one per CPU core — and worker Isolates do **not** share state constructed in `main()`. A `late final AuthDatabase db;` assigned inside `main()` and referenced inside `setupRoutes` will throw `LateInitializationError` in every worker, because `main()` never runs again there. Build `AuthDatabase`, `JwtService`, `SessionManager`, and `AuthRoutes` **inside** `setupRoutes` itself, as shown below. Only the one-time migration run belongs in `main()`.
:::

```dart
import 'dart:io';
import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';

// Read from real environment variables (not `String.fromEnvironment`,
// which only sees compile-time --define flags, never a .env file or a
// real shell/Docker env var).
final authConfig = AuthConfig(
  jwt: JwtConfig(secret: Platform.environment['JWT_SECRET'] ?? 'change-me'),
  databaseUrl: Platform.environment['DATABASE_URL'] ??
      'postgres://postgres:postgres@localhost:5432/mydb',
);

Future<void> main() async {
  // Migrations run once, before any worker starts.
  final migrationDb = AuthDatabase(authConfig.databaseUrl);
  await migrationDb.connect();
  await MigrationRunner(migrationDb, migrationsDir: 'migrations').migrate();
  await migrationDb.close();

  final app = Daho();
  app.listen(8080, routes: setupRoutes);
}

/// MUST be top-level — see the isolate-safety note above.
void setupRoutes(Daho app) {
  // Fire-and-forget: AuthDatabase queues queries until the connection is
  // ready, so setupRoutes can stay synchronous.
  final db = AuthDatabase(authConfig.databaseUrl);
  db.connect();

  final jwtService = JwtService(authConfig.jwt);
  final hasher = BcryptHasher();
  final sessionManager = SessionManager(PostgresSessionStore(db), authConfig.session);

  // Auth routes (public)
  final authGroup = app.group('/auth');
  AuthRoutes(
    config: authConfig,
    db: db,
    hasher: hasher,
    jwt: jwtService,
    tokenRepo: PostgresTokenRepository(db),
    sessionManager: sessionManager,
  ).register(authGroup);

  // Protected routes (JWT)
  final api = app.group('/api');
  api.use(AuthMiddleware.jwt(jwtService: jwtService, db: db));
  api.get('/profile', (req, res) {
    return res.ok({'user': req.auth.user!.toJson()});
  });
}
```

See [`example/13_authentication.dart`](https://github.com/burhanwakhid/daho/blob/master/packages/daho/example/13_authentication.dart) for a complete, runnable version (including a role-gated `/api/admin` route).

## Built-in Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/register` | Register with email/password |
| POST | `/auth/login` | Login (JWT) |
| POST | `/auth/login/session` | Login (session cookie) |
| POST | `/auth/refresh` | Refresh access token (rotates the refresh token) |
| POST | `/auth/logout` | Logout |
| GET | `/auth/me` | Get current user |
| GET | `/auth/oauth/google` | Start Google OAuth |
| GET | `/auth/oauth/google/cb` | Google callback |
| GET | `/auth/oauth/github` | Start GitHub OAuth |
| GET | `/auth/oauth/github/cb` | GitHub callback |
| POST | `/auth/oauth/exchange` | Exchange a one-time OAuth `code` for the real token pair |

### OAuth flow

1. Redirect the user to `GET /auth/oauth/google` (or `/github`). This sets a short-lived, `HttpOnly` `state` cookie and redirects to the provider.
2. The provider redirects back to `/auth/oauth/google/cb`. The `state` query param is checked against the cookie — a mismatch (or a missing cookie) redirects to `oauthFailureRedirect` instead of proceeding, which is what makes this CSRF-safe.
3. On success, the callback redirects to `oauthSuccessRedirect` with **`?code=<opaque>`** — not the tokens themselves, since embedding live tokens in a URL leaks them into browser history, `Referer` headers, and server access logs.
4. Your frontend calls `POST /auth/oauth/exchange` with `{"code": "..."}` and gets back `{"user": ..., "accessToken": ..., "refreshToken": ...}`. The code is single-use and expires after 10 minutes.

## Configuration

### AuthConfig

```dart
final config = AuthConfig(
  jwt: JwtConfig(
    secret: 'your-secret-key',
    accessTokenLifetime: Duration(minutes: 15),
    refreshTokenLifetime: Duration(days: 7),
  ),
  session: SessionConfig(
    cookieName: 'daho_session',
    lifetime: Duration(days: 7),
    secure: true, // once served over HTTPS — see Security notes
    sameSite: 'Lax',
  ),
  oauth: OAuthConfig(
    googleClientId: 'your-client-id',
    googleClientSecret: 'your-client-secret',
    githubClientId: 'your-client-id',
    githubClientSecret: 'your-client-secret',
  ),
  databaseUrl: 'postgres://user:pass@host:5432/db',
);
```

`AuthDatabase` also takes an `sslMode` (from `package:postgres`), separate from `AuthConfig`:

```dart
final db = AuthDatabase(config.databaseUrl, sslMode: SslMode.require); // for any non-local Postgres
```

## Middleware

### JWT Middleware

```dart
// Required auth (returns 401 if not authenticated)
api.use(AuthMiddleware.jwt(jwtService: jwtService, db: db));

// Optional auth (continues if not authenticated)
api.use(AuthMiddleware.jwt(
  jwtService: jwtService,
  db: db,
  required: false,
));
```

### Session Middleware

```dart
dashboard.use(AuthMiddleware.session(
  sessionManager: sessionManager,
  db: db,
));
```

### Role-based Authorization

```dart
// After auth middleware
api.use(AuthMiddleware.requireRole(['admin', 'moderator']));
```

`requireRole` checks `req.auth.user.role`, which is loaded straight from the `users.role` column (default `'user'`) — for both JWT and session auth. That means a role change in the database takes effect immediately, without waiting for the access token to be reissued.

There is **no self-service way to become `'admin'`** — registration and OAuth signup never read a role from request input, since accepting a client-supplied role would be a privilege-escalation bug. Promote a user directly:

```sql
UPDATE users SET role = 'admin' WHERE email = 'you@example.com';
```

## Accessing User in Handlers

```dart
app.get('/profile', (req, res) {
  final user = req.auth.user;
  if (user == null) return res.unauthorized({'error': 'Not authenticated'});

  return res.ok({
    'id': user.id,
    'email': user.email,
    'name': user.name,
    'role': user.role,
  });
});
```

## Database Schema

The package auto-creates these tables (via `MigrationRunner`):

- `users` — User accounts, including a `role` column (default `'user'`)
- `sessions` — Server-side sessions
- `refresh_tokens` — JWT refresh tokens (revocable, single-use rotation)
- `oauth_accounts` — OAuth provider links
- `oauth_exchange_codes` — One-time codes backing the `/auth/oauth/exchange` step

## Security notes / known gaps

- **Rate limiting is not implemented.** `/auth/login`, `/auth/login/session`, `/auth/register`, and `/auth/refresh` have no built-in throttling. Add it in front of them — your reverse proxy (nginx `limit_req`, Caddy `rate_limit`, an API gateway) or a `Middleware` on the `/auth` group — before exposing this to the internet.
- **No admin-management endpoint** — see the Role-based Authorization section above.
- **`SessionConfig.secure` defaults to `false`** (works over plain HTTP for local dev) and **`AuthDatabase`'s `sslMode` defaults to `SslMode.disable`** (works with a plain local Postgres). Both **must** be overridden once you're not on localhost. Constructing a `SessionManager` with `secure: false` prints a warning to stderr as a reminder; there's no equivalent check for the database TLS setting.
- **Isolate safety** — see the warning in Quick Start above. Every piece of per-worker state (DB connection, JWT service, session manager, OAuth providers) must be built inside the `routes` builder, not in `main()`.

## Docker

```yaml
# docker-compose.yml
services:
  app:
    build: .
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/myapp
      JWT_SECRET: your-secret-key
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: postgres
    volumes:
      - pgdata:/var/lib/postgresql/data
```
