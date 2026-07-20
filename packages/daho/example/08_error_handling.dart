/// 08 — Error Handling
///
/// Demonstrates custom error and not-found handlers:
/// - `DahoConfig.errorHandler` — invoked when a handler or middleware throws
/// - `DahoConfig.notFoundHandler` — invoked when no route matches
///
/// IMPORTANT: Both handlers must be top-level or static functions (not
/// closures), because the config is sent across Isolate boundaries.
///
/// Run:  dart run example/08_error_handling.dart
/// Test:
///   curl http://localhost:8080/ok                 # 200
///   curl http://localhost:8080/boom               # 500 (custom error handler)
///   curl http://localhost:8080/does-not-exist     # 404 (custom not-found handler)
library;

import 'dart:io';

import 'package:daho/daho.dart';

/// Custom error handler — logs the error and returns a JSON 500 response.
/// Must be a top-level or static function (Isolate constraint).
void myErrorHandler(
  DahoRequest req,
  DahoResponse res,
  Object error,
  StackTrace stackTrace,
) {
  stderr.writeln('[ERROR] ${req.method} ${req.path}: $error');
  stderr.writeln(stackTrace);
  res.status(500).json({
    'error': 'Internal Server Error',
    'path': req.path,
  });
}

/// Custom not-found handler — returns a JSON 404 with the requested path.
/// Must be a top-level or static function (Isolate constraint).
void myNotFoundHandler(DahoRequest req, DahoResponse res) {
  res.status(404).json({
    'error': 'Not Found',
    'path': req.path,
    'message': 'No route matches ${req.method} ${req.path}',
  });
}

void setupRoutes(Daho app) {
  app.get('/ok', (req, res) {
    return res.ok({'message': 'Everything is fine'});
  });

  app.get('/boom', (req, res) {
    throw Exception('Something went wrong!');
  });
}

void main() {
  final app = Daho(
    config: const DahoConfig(
      errorHandler: myErrorHandler,
      notFoundHandler: myNotFoundHandler,
    ),
  );

  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Server running at http://127.0.0.1:8080'),
  );
}
