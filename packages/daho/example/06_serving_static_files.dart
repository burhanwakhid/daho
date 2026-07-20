/// 06 — Serving Static Files
///
/// Demonstrates two ways to serve content without Dart route handlers:
///
/// - `app.serveStatic(virtualPath, localDir)` — files served directly by H2O
///   (zero-copy, never touches Dart). Great for assets, images, HTML pages.
///
/// - `app.fastPath(path, body, contentType:)` — a fixed response served
///   entirely in C. Perfect for health checks and status endpoints.
///
/// Run:  dart run example/06_serving_static_files.dart
/// Test:
///   curl http://localhost:8080/                     # serves public/index.html
///   curl http://localhost:8080/health               # fast path, no Dart
///   curl http://localhost:8080/api/status           # fast path, no Dart
library;

import 'package:daho/daho.dart';

void setupRoutes(Daho app) {
  // Serve files from example/public/ under the root URL path.
  // H2O handles these directly — zero Dart involvement.
  app.serveStatic('/', 'example/public');

  // Native fast paths — served entirely in C, bypasses the Dart route pipeline.
  app.fastPath('/health', '{"status": "ok"}', contentType: 'application/json');
  app.fastPath(
    '/api/status',
    '{"service": "daho", "version": "0.1.0"}',
    contentType: 'application/json',
  );

  // Regular Dart route (still works alongside static/fast paths)
  app.get('/hello', (req, res) {
    return res.ok({'message': 'This is a regular Dart route'});
  });
}

void main() {
  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Server running at http://127.0.0.1:8080'),
  );
}
