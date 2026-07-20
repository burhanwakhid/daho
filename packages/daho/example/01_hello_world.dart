/// 01 — Hello World
///
/// The simplest possible Daho server. Demonstrates:
/// - The `AppBuilder` pattern (top-level function for route setup)
/// - `app.get()` for registering a GET route
/// - `res.ok()` for sending a JSON response
/// - `app.listen()` to start the server
///
/// Run:  dart run example/01_hello_world.dart
/// Test: curl http://localhost:8080
library;

import 'package:daho/daho.dart';

/// Route setup MUST be a top-level function: it is re-run on every worker
/// Isolate, and Dart cannot send closures across Isolate boundaries.
void setupRoutes(Daho app) {
  app.get('/', (req, res) {
    return res.ok({'message': 'Hello, Daho!'});
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
