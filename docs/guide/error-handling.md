# Error Handling

Daho gives you three layers of control over failures: a global **error handler** for uncaught exceptions, a **not-found handler** for unmatched routes, and per-handler control over status codes. All of them keep internal details away from clients by default.

## How errors flow

When a route handler or middleware throws — synchronously or from a rejected `Future` — Daho catches it and invokes the configured `errorHandler`. Your handler populates the response; the client never sees a stack trace unless you choose to send one.

```dart
app.get('/boom', (req, res) {
  throw StateError('something went wrong');
});
// → errorHandler runs → client gets a clean 500
```

The default handler logs the error and stack trace to `stderr` and returns a generic `500`:

```json
{ "error": "Internal Server Error" }
```

::: tip
This is deliberate: leaking stack traces or exception messages to clients is a security risk. Log server-side, respond generically.
:::

## Custom error handler

Provide your own `errorHandler` via `DahoConfig` to control logging and the client-facing response.

```dart
import 'dart:io';
import 'package:daho/daho.dart';

void myErrorHandler(
  DahoRequest req,
  DahoResponse res,
  Object error,
  StackTrace stackTrace,
) {
  // Log everything server-side.
  stderr.writeln('[ERROR] ${req.method} ${req.path}: $error');
  stderr.writeln(stackTrace);

  // Respond with something safe.
  res.status(500).json({'error': 'Internal Server Error'});
}

void setupRoutes(Daho app) {
  app.get('/boom', (req, res) => throw Exception('kaboom'));
}

void main() {
  final app = Daho(config: const DahoConfig(errorHandler: myErrorHandler));
  app.listen(8080, routes: setupRoutes);
}
```

::: warning Isolate constraint
`errorHandler` and `notFoundHandler` **must** be top-level or static functions — never closures or instance methods. `DahoConfig` is sent across Isolate boundaries, and Dart cannot transfer closures. This is the same rule as your `routes` setup function.
:::

## Not-found handler

When a request matches no registered route, Daho calls `notFoundHandler`. The default returns a plain JSON `404`:

```json
{ "error": "Not Found" }
```

Override it to add context or match your API's error shape:

```dart
void myNotFoundHandler(DahoRequest req, DahoResponse res) {
  res.status(404).json({
    'error': 'Not Found',
    'path': req.path,
    'method': req.method,
  });
}

final app = Daho(config: const DahoConfig(notFoundHandler: myNotFoundHandler));
```

## Method not allowed (405)

If a path exists for *other* HTTP methods but not the one requested, Daho automatically returns `405 Method Not Allowed` with an `Allow` header listing the valid methods — you don't write anything for this.

```dart
app.get('/users', listUsers);

// GET  /users → 200
// POST /users → 405, Allow: GET
```

## Returning error responses from handlers

For *expected* errors — validation failures, missing resources, auth rejection — don't throw. Return the appropriate status directly using the response helpers:

```dart
app.post('/users', (req, res) {
  final body = req.body;
  if (body is! Map || body['email'] == null) {
    return res.badRequest({'error': 'email is required'});
  }
  if (userExists(body['email'])) {
    return res.status(409).json({'error': 'email already registered'});
  }
  return res.status(201).json(createUser(body));
});
```

Available status helpers:

| Method | Status | Typical use |
| --- | --- | --- |
| `res.badRequest(data)` | 400 | Invalid input |
| `res.unauthorized(data)` | 401 | Missing / invalid credentials |
| `res.forbidden(data)` | 403 | Authenticated but not allowed |
| `res.notFound(data)` | 404 | Resource doesn't exist |
| `res.status(code).json(...)` | any | Anything else (409, 422, 429, …) |
| `res.internalServerError(data)` | 500 | Unexpected server failure |

::: info Throw vs. return
**Return** a status for anticipated, business-logic errors — they aren't exceptional. **Throw** only for genuinely unexpected failures, and let the `errorHandler` turn them into a safe `500`.
:::

## Rejecting requests from middleware

Middleware can short-circuit the chain by responding and simply **not** calling `next()`:

```dart
Future<void> authGuard(DahoRequest req, DahoResponse res, NextFunction next) async {
  final token = req.header('authorization');
  if (token == null || !token.startsWith('Bearer ')) {
    res.unauthorized({'error': 'Missing or invalid token'});
    return; // no next() → downstream handlers never run
  }
  await next();
}
```

## Testing error paths

`DahoTester` runs requests through the same dispatch path, including your error and not-found handlers, so you can assert on failure behavior without a live server:

```dart
test('throwing handler yields a 500', () async {
  final t = DahoTester((app) {
    app.get('/boom', (req, res) => throw Exception('kaboom'));
  });
  final res = await t.get('/boom');
  expect(res.statusCode, 500);
});
```

See the [Testing guide](/guide/testing) for more.

## Next Steps

- [Configuration](/guide/configuration) — all `DahoConfig` options
- [Middleware](/guide/middleware) — short-circuiting and custom guards
- [Testing](/guide/testing) — assert on error responses
