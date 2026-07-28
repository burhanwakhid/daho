/// 13 — Authentication with daho_auth
///
/// Demonstrates JWT authentication with daho_auth:
/// - User registration with bcrypt password hashing
/// - JWT login (access + refresh tokens)
/// - Protected routes with AuthMiddleware.jwt()
/// - Role-based authorization with AuthMiddleware.requireRole()
/// - Token refresh flow
/// - Accessing authenticated user via req.auth
///
/// Isolate note: `setupRoutes` below builds its OWN `AuthDatabase`,
/// `JwtService`, `SessionManager`, and `AuthRoutes` instead of reusing
/// anything constructed in `main()`. That's required, not just tidiness —
/// `setupRoutes` is re-run fresh in every worker Isolate (one per CPU core),
/// and worker Isolates do NOT share `main()`'s state: a `late final`
/// assigned in `main()` is simply never initialized inside a spawned
/// Isolate, so referencing it there throws `LateInitializationError`. Only
/// the one-time migration run belongs in `main()`, since it must happen
/// exactly once, before any worker starts.
///
/// Prerequisites:
///   - PostgreSQL running (or use docker-compose)
///   - Run migrations: daho auth setup-db
///
/// Run:  dart run example/13_authentication.dart
/// Test:
///   curl -X POST http://localhost:8080/auth/register \
///     -H "Content-Type: application/json" \
///     -d '{"email":"alice@example.com","password":"password123","name":"Alice"}'
///
///   curl -X POST http://localhost:8080/auth/login \
///     -H "Content-Type: application/json" \
///     -d '{"email":"alice@example.com","password":"password123"}'
///
///   curl http://localhost:8080/api/profile \
///     -H "Authorization: Bearer <access_token>"
///
///   # 403 unless you've promoted the user to admin directly in the DB:
///   #   UPDATE users SET role = 'admin' WHERE email = 'alice@example.com';
///   curl http://localhost:8080/api/admin \
///     -H "Authorization: Bearer <access_token>"
library;

import 'dart:io';

import 'package:daho/daho.dart';
import 'package:daho_auth/daho_auth.dart';

/// Auth configuration, read from real process environment variables (not
/// `String.fromEnvironment`, which only reads compile-time `--define`
/// flags — it would silently ignore a real `JWT_SECRET` env var or an
/// exported shell variable). Works as-is with docker-compose's
/// `environment:` block; for local (non-Docker) runs, `export` the vars in
/// your shell first, or use a package like `dotenv` to load a `.env` file
/// into `Platform.environment` before this line runs.
final authConfig = AuthConfig(
  jwt: JwtConfig(
    secret: Platform.environment['JWT_SECRET'] ?? 'change-me-in-production',
  ),
  databaseUrl: Platform.environment['DATABASE_URL'] ??
      'postgres://postgres:postgres@localhost:5432/daho_example',
  // session: SessionConfig(secure: true), // once served over HTTPS
  // For a remote/production Postgres, also pass:
  //   AuthDatabase(authConfig.databaseUrl, sslMode: SslMode.require)
  // (defaults to SslMode.disable so a plain local Postgres works out of the box)
);

Future<void> main() async {
  // Migrations run exactly once, on a short-lived connection, before any
  // worker Isolate starts.
  final migrationDb = AuthDatabase(authConfig.databaseUrl);
  await migrationDb.connect();
  await MigrationRunner(migrationDb, migrationsDir: 'example/migrations').migrate();
  await migrationDb.close();

  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () {
      print('Auth example running at http://127.0.0.1:8080');
      print('---');
      print('Public:  POST /auth/register, POST /auth/login');
      print('Protected: GET /api/profile, GET /api/users, GET /api/admin');
    },
    // No onShutdown DB cleanup here: each worker Isolate owns its own
    // AuthDatabase (built inside setupRoutes below) and onShutdown only
    // runs on the master Isolate, which can't reach worker-owned resources.
  );
}

/// Route setup — MUST be a top-level function (Isolate constraint, see the
/// note at the top of this file).
void setupRoutes(Daho app) {
  // Built fresh for this worker; `db.connect()` is intentionally not
  // awaited here (setupRoutes can't be async) — AuthDatabase queues
  // queries internally until the connection is ready, so the first
  // request or two just waits slightly longer rather than failing.
  final db = AuthDatabase(authConfig.databaseUrl);
  db.connect();

  final jwtService = JwtService(authConfig.jwt);
  final hasher = BcryptHasher();
  final sessionManager = SessionManager(PostgresSessionStore(db), authConfig.session);
  final authRoutes = AuthRoutes(
    config: authConfig,
    db: db,
    hasher: hasher,
    jwt: jwtService,
    tokenRepo: PostgresTokenRepository(db),
    sessionManager: sessionManager,
  );

  app.use(Middlewares.logger());
  app.use(Middlewares.cors());

  // ---- Public routes (no auth required) ----

  final authGroup = app.group('/auth');
  authRoutes.register(authGroup);

  // ---- Protected routes (JWT required) ----

  final api = app.group('/api');
  api.use(AuthMiddleware.jwt(jwtService: jwtService, db: db));

  // Get current user profile
  api.get('/profile', (req, res) {
    final user = req.auth.user!;
    return res.ok({'user': user.toJson(), 'jwt_claims': req.auth.jwtClaims});
  });

  // List all users (protected)
  api.get('/users', (req, res) async {
    final rows = await db.query(
      'SELECT id, email, name, created_at FROM users ORDER BY created_at DESC',
    );
    return res.ok({'users': rows});
  });

  // Admin-only route: requireRole checks req.auth.user.role, which is
  // loaded from the users.role column (default 'user'). There's no
  // self-service way to become 'admin' — and there shouldn't be, since a
  // registration/OAuth endpoint that accepted a client-supplied role would
  // be a privilege-escalation bug. Promote a user directly in the
  // database: UPDATE users SET role = 'admin' WHERE email = '...';
  api.get(
    '/admin',
    (req, res) => res.ok({'message': 'Welcome, admin ${req.auth.user!.email}'}),
    use: [AuthMiddleware.requireRole(['admin'])],
  );

  // ---- Optional auth route ----

  app.get(
    '/public-or-private',
    (req, res) {
      if (req.auth.isAuthenticated) {
        return res.ok({
          'message': 'Hello, ${req.auth.user!.name ?? "User"}!',
          'authenticated': true,
        });
      }
      return res.ok({'message': 'Hello, Guest!', 'authenticated': false});
    },
    use: [AuthMiddleware.jwt(jwtService: jwtService, db: db, required: false)],
  );
}
