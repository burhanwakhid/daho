# Testing

Daho ships with `DahoTester`, an in-process test harness that runs requests through the real dispatch path — global middleware, route matching, 404/405, and the configured error handler — without booting the native server.

## Setup

::: warning
`DahoTester` currently lives in the repo's `test/` directory. Exposing it as a public `package:daho/testing.dart` library is on the roadmap.
:::

For now, import it from the test directory:

```dart
import 'package:daho/daho.dart';
import 'package:daho/testing.dart'; // when available
import 'package:test/test.dart';
```

## Basic Usage

```dart
void testRoutes(Daho app) {
  app.get('/ping', (req, res) => res.ok({'pong': true}));
  app.post('/echo', (req, res) => res.ok(req.body));
}

void main() {
  group('Basic routes', () {
    late DahoTester t;
    setUp(() => t = DahoTester(testRoutes));

    test('GET /ping returns 200', () async {
      final res = await t.get('/ping');
      expect(res.statusCode, 200);
      expect(res.json['pong'], true);
    });

    test('POST /echo echoes the body', () async {
      final res = await t.post('/echo', json: {'hello': 'world'});
      expect(res.statusCode, 200);
      expect(res.json['hello'], 'world');
    });
  });
}
```

## TestResponse

The `TestResponse` object returned by `DahoTester`:

| Property | Type | Description |
|----------|------|-------------|
| `statusCode` | `int` | HTTP status code |
| `headers` | `Map<String, String>` | Response headers |
| `cookies` | `List<String>` | Raw `Set-Cookie` values |
| `bodyBytes` | `List<int>` | Raw response body |
| `text` | `String` | Body decoded as UTF-8 text |
| `json` | `dynamic` | Body decoded as JSON |

## HTTP Methods

```dart
final t = DahoTester(setupRoutes);

await t.get('/path');
await t.post('/path', json: {'key': 'value'});
await t.put('/path', json: {'key': 'value'});
await t.patch('/path', json: {'key': 'value'});
await t.delete('/path');
```

### Body Encoding

```dart
// JSON body
await t.post('/api/data', json: {'name': 'Ada'});

// Form-encoded body
await t.post('/form', form: 'name=Ada&email=ada@example.com');

// Plain text body
await t.post('/text', text: 'Hello, world!');
```

## Testing Middleware

Test that middleware correctly short-circuits requests:

```dart
void guardedRoutes(Daho app) {
  app.get('/admin', (req, res) => res.ok('admin'), use: [
    (req, res, next) async {
      if (req.header('x-api-key') != 'secret') {
        res.unauthorized({'error': 'Invalid key'});
        return;
      }
      await next();
    },
  ]);
}

void main() {
  test('rejects requests without API key', () async {
    final t = DahoTester(guardedRoutes);
    final res = await t.get('/admin');
    expect(res.statusCode, 401);
  });

  test('allows requests with valid API key', () async {
    final t = DahoTester(guardedRoutes);
    final res = await t.get('/admin', headers: {'x-api-key': 'secret'});
    expect(res.statusCode, 200);
  });
}
```

## Testing Error Handling

```dart
test('custom error handler catches exceptions', () async {
  void riskyRoutes(Daho app) {
    app.get('/boom', (req, res) => throw Exception('kaboom'));
  }

  final t = DahoTester(riskyRoutes);
  final res = await t.get('/boom');
  expect(res.statusCode, 500);
});
```

## Testing 404

```dart
test('unknown route returns 404', () async {
  final t = DahoTester((app) {
    app.get('/exists', (req, res) => res.ok('yes'));
  });

  final res = await t.get('/does-not-exist');
  expect(res.statusCode, 404);
});
```

## Limitations

- **No multipart parsing**: `DahoTester` does not parse `multipart/form-data` bodies (this requires the native fast path).
- **No native server features**: `serveStatic()` and `fastPath()` are not exercised by the tester.
- **Singleton registry**: Each `DahoTester` instance resets the route registry. Don't create multiple testers in parallel.

## Run Tests

```bash
dart test
```
