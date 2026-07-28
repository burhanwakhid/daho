# daho_auth

Authentication and authorization middleware for the [Daho](https://pub.dev/packages/daho) HTTP framework.

## Features

- **JWT Authentication** — Access + refresh token rotation
- **Session-based Authentication** — Server-side sessions with cookies
- **OAuth2** — Google and GitHub providers
- **bcrypt Password Hashing** — Industry standard, 12 rounds default
- **PostgreSQL** — Production-ready database with auto-migrations
- **Role-based Authorization** — `AuthMiddleware.requireRole()`

## Quick Start

```dart
import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';

void main() async {
  final db = AuthDatabase('postgres://postgres:postgres@localhost:5432/mydb');
  await db.connect();
  await MigrationRunner(db, migrationsDir: 'migrations').migrate();

  final jwtService = JwtService(JwtConfig(secret: 'my-secret'));
  final hasher = BcryptHasher();
  final sessionManager = SessionManager(PostgresSessionStore(db), SessionConfig());

  final app = Daho();
  app.listen(8080, routes: (app) {
    // Auth routes
    final auth = app.group('/auth');
    AuthRoutes(
      config: AuthConfig(jwt: JwtConfig(secret: 'my-secret'), databaseUrl: '...'),
      db: db, hasher: hasher, jwt: jwtService,
      tokenRepo: PostgresTokenRepository(db),
      sessionManager: sessionManager,
    ).register(auth);

    // Protected routes
    final api = app.group('/api');
    api.use(AuthMiddleware.jwt(jwtService: jwtService, db: db));
    api.get('/profile', (req, res) => res.ok({'user': req.auth.user!.toJson()}));
  });
}
```

## CLI Integration

```bash
# Add auth to existing project
daho auth add

# Add only JWT auth
daho auth add --provider jwt

# Run migrations
daho auth setup-db
```

## Docker

```bash
docker-compose up -d
```

## Security notes / known gaps

daho_auth handles the core authentication mechanics (password hashing, JWT
signing/rotation, session cookies, OAuth CSRF protection) but deliberately
leaves the following to the application, since they depend on your
deployment:

- **Rate limiting is not implemented.** `/auth/login`, `/auth/login/session`,
  `/auth/register`, and `/auth/refresh` have no built-in throttling, so
  they're brute-forceable as shipped. Add rate limiting in front of them —
  either your reverse proxy (nginx `limit_req`, Caddy `rate_limit`, an API
  gateway) or a `Middleware` registered on the `/auth` group — before
  exposing this to the internet.

- **No admin-management endpoint.** `User.role` defaults to `'user'` and is
  never settable from request input (registration/OAuth signup always
  create plain users, by design — self-service role escalation would be a
  privilege-escalation bug). To grant `'admin'`, update the row directly:

  ```sql
  UPDATE users SET role = 'admin' WHERE email = 'you@example.com';
  ```

  Bootstrapping the *first* admin has to happen this way (there's no
  chicken-and-egg-safe way to do it through an API route protected by
  `requireRole(['admin'])`). If you need self-service role management,
  build an endpoint for it yourself, gated behind
  `AuthMiddleware.requireRole(['admin'])`.

- **`SessionConfig.secure` defaults to `false`** (so cookies work over
  plain HTTP in local dev) and **`AuthDatabase`'s `sslMode` defaults to
  `SslMode.disable`** (so a plain local Postgres works out of the box).
  Both **must** be overridden once you're not on localhost:
  `SessionConfig(secure: true)` and
  `AuthDatabase(url, sslMode: SslMode.require)`. Constructing a
  `SessionManager` with `secure: false` prints a warning to stderr as a
  reminder, but there's no equivalent runtime check for the database TLS
  setting.

## License

MIT
