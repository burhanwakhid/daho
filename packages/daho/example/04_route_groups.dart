/// 04 — Route Groups
///
/// Demonstrates route groups with shared prefix and scoped middleware:
/// - `app.group(prefix)` — create a group with a common URL prefix
/// - `group.use(middleware)` — middleware that only runs for routes in the group
/// - Public vs protected route separation
///
/// Run:  dart run example/04_route_groups.dart
/// Test:
///   curl http://localhost:8080/login
///   curl http://localhost:8080/register
///   curl http://localhost:8080/dashboard/profile                          # 401
///   curl "http://localhost:8080/dashboard/profile?token=secret123"        # 200
///   curl "http://localhost:8080/dashboard/settings?token=secret123"       # 200
library;

import 'package:daho/daho.dart';

/// Simple token-based auth middleware for demonstration.
/// In production, use JWT or session-based authentication.
Future<void> authMiddleware(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  final token = req.query['token'];
  if (token != 'secret123') {
    res.unauthorized({'error': 'Invalid or missing token'});
    return;
  }
  await next();
}

void setupRoutes(Daho app) {
  // =========================================================================
  // Public routes — accessible without authentication
  // =========================================================================
  app.get('/login', (req, res) {
    return res.ok({'message': 'Login page'});
  });

  app.get('/register', (req, res) {
    return res.ok({'message': 'Registration page'});
  });

  // =========================================================================
  // Protected routes — all require a valid token
  // =========================================================================
  final dashboard = app.group('/dashboard');

  // Apply auth middleware to the entire group
  dashboard.use(authMiddleware);

  // GET /dashboard/profile
  dashboard.get('/profile', (req, res) {
    return res.ok({
      'username': 'ada',
      'role': 'admin',
    });
  });

  // GET /dashboard/settings
  dashboard.get('/settings', (req, res) {
    return res.ok({
      'theme': 'dark',
      'notifications': true,
    });
  });
}

void main() {
  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () {
      print('Server running at http://127.0.0.1:8080');
      print('Public:    /login, /register');
      print('Protected: /dashboard/profile?token=secret123');
    },
  );
}
