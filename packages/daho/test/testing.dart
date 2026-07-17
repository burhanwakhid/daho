/// In-process testing utilities for Daho apps.
///
/// ```dart
/// import 'package:daho/daho.dart';
/// import 'testing.dart';
///
/// void main() {
///   test('GET /ping', () async {
///     final t = DahoTester((app) => app.get('/ping', (req, res) => res.ok('pong')));
///     final res = await t.get('/ping');
///     expect(res.statusCode, 200);
///     expect(res.text, 'pong');
///   });
/// }
/// ```
library;

export 'test_client.dart' show DahoTester, TestResponse;
