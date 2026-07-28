/// 11 — Testing with DahoTester
///
/// Demonstrates how to write tests for Daho apps using the in-process test
/// harness. DahoTester runs requests through the real dispatch path (global
/// middleware, route matching, 404/405, error handler) without booting the
/// native server.
///
/// Note: DahoTester currently lives in test/test_client.dart. Exposing it
/// as a public `package:daho/testing.dart` library is on the roadmap.
///
/// To run this example, copy the test patterns into your test/ directory
/// and import from your local test setup.
///
/// Run:  dart test
library;

// This file demonstrates testing patterns for Daho apps.
// Copy these patterns into your project's test/ directory.

/// Example: How to write tests for a Daho application.
///
/// ```dart
/// import 'package:daho/daho.dart';
/// import 'package:daho/testing.dart'; // when available
/// import 'package:test/test.dart';
///
/// // Define your routes (must be top-level)
/// void testRoutes(Daho app) {
///   app.get('/ping', (req, res) => res.ok({'pong': true}));
///   app.post('/echo', (req, res) => res.ok(req.body));
///   app.get('/items/:id', (req, res) => res.ok({'id': req.params['id']}));
/// }
///
/// void main() {
///   group('Routing', () {
///     late DahoTester t;
///     setUp(() => t = DahoTester(testRoutes));
///
///     test('GET /ping returns 200 with JSON', () async {
///       final res = await t.get('/ping');
///       expect(res.statusCode, 200);
///       expect(res.json['pong'], true);
///     });
///
///     test('POST /echo echoes the request body', () async {
///       final res = await t.post('/echo', json: {'hello': 'world'});
///       expect(res.statusCode, 200);
///       expect(res.json['hello'], 'world');
///     });
///
///     test('GET /items/:id captures path parameters', () async {
///       final res = await t.get('/items/42');
///       expect(res.statusCode, 200);
///       expect(res.json['id'], '42');
///     });
///
///     test('Unknown route returns 404', () async {
///       final res = await t.get('/nonexistent');
///       expect(res.statusCode, 404);
///     });
///   });
///
///   group('Middleware', () {
///     test('middleware can short-circuit the request', () async {
///       void guardedRoutes(Daho app) {
///         app.get('/admin', (req, res) => res.ok({'ok': true}), use: [
///           (req, res, next) async {
///             res.unauthorized({'error': 'nope'});
///             // Don't call next() — short-circuit
///           },
///         ]);
///       }
///
///       final t = DahoTester(guardedRoutes);
///       final res = await t.get('/admin');
///       expect(res.statusCode, 401);
///     });
///   });
///
///   group('Custom Error Handler', () {
///     test('catches thrown exceptions', () async {
///       void riskyRoutes(Daho app) {
///         app.get('/boom', (req, res) => throw Exception('kaboom'));
///       }
///
///       final t = DahoTester(riskyRoutes);
///       final res = await t.get('/boom');
///       expect(res.statusCode, 500);
///     });
///   });
/// }
/// ```

/// Placeholder main (this file is a documentation example, not runnable).
void main() {
  print('See the doc comment above for testing patterns.');
  print(
    'DahoTester will be available as package:daho/testing.dart in the future.',
  );
}
