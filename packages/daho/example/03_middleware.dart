/// 03 — Middleware
///
/// Demonstrates Daho's built-in middleware:
/// - `Middlewares.logger()` — access log with method, path, status, duration, IP
/// - `Middlewares.cors()` — CORS headers + automatic OPTIONS preflight handling
/// - `Middlewares.secureHeaders()` — Helmet-style security headers
/// - `Middlewares.compress()` — gzip compression for large responses
///
/// Also shows how to write a custom middleware (API key check).
///
/// Run:  dart run example/03_middleware.dart
/// Test:
///   curl http://localhost:8080/users            # see logger output in terminal
///   curl -H "Origin: example.com" http://localhost:8080/users  # see CORS headers
///   curl -X OPTIONS http://localhost:8080/users  # preflight handled automatically
library;

import 'package:daho/daho.dart';

/// A custom middleware that checks for a valid API key header.
Future<void> apiKeyMiddleware(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  final apiKey = req.header('x-api-key');
  if (apiKey != 'my-secret-key') {
    res.unauthorized({'error': 'Invalid or missing API key'});
    return; // Short-circuit — do not call next()
  }
  await next(); // Valid key — continue to the route handler
}

void setupRoutes(Daho app) {
  // Global middleware — runs for EVERY request
  app.use(Middlewares.logger());
  app.use(Middlewares.cors(origin: '*'));
  app.use(Middlewares.secureHeaders());
  app.use(Middlewares.compress(minLength: 512));

  // Public route — no API key needed (CORS middleware handles OPTIONS preflight)
  app.get('/', (req, res) {
    return res.ok({'message': 'Public endpoint — no API key required'});
  });

  // Protected route — requires X-Api-Key header
  app.get('/secret', (req, res) {
    return res.ok({'message': 'You have access to the secret data'});
  }, use: [apiKeyMiddleware]);
}

void main() {
  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Server running at http://127.0.0.1:8080'),
  );
}
