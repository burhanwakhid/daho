# Middleware

Middleware functions run before the route handler and can short-circuit the request by not calling `next()`.

## How Middleware Works

```dart
Future<void> myMiddleware(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  // Do something before the handler
  print('Request: ${req.method} ${req.path}');

  await next(); // Continue to the next middleware / handler

  // Do something after the handler
  print('Response: ${res.statusCode}');
}
```

- Call `await next()` to pass control to the next middleware or route handler.
- **Don't call `next()`** to short-circuit the chain (e.g., for auth rejection).

## Three Scopes

### Global Middleware

Runs for **every** request, including unmatched ones (404, 405, CORS preflight):

```dart
app.use(Middlewares.logger());
app.use(Middlewares.cors());
```

### Group-Scoped Middleware

Runs only for routes within a group:

```dart
final admin = app.group('/admin');
admin.use(authGuard); // Only runs for /admin/* routes

admin.get('/dashboard', (req, res) => res.ok('admin dashboard'));
admin.get('/settings', (req, res) => res.ok('admin settings'));
```

### Per-Route Middleware

Attach middleware to a specific route:

```dart
app.get('/protected', handler, use: [authGuard, rateLimiter]);
```

## Built-in Middleware

### Logger

Logs one line per request: `METHOD path status durationms - ip`

```dart
app.use(Middlewares.logger());

// Output: GET /users 200 0.45ms - 127.0.0.1
```

### CORS

Adds CORS headers and handles preflight `OPTIONS` requests automatically:

```dart
app.use(Middlewares.cors(
  origin: '*',                            // Allowed origins
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  headers: ['Content-Type', 'Authorization'],
  credentials: false,                     // Allow credentials
  maxAge: Duration(hours: 24),            // Preflight cache duration
));
```

Register CORS **globally** so preflight `OPTIONS` requests (which match no route) are handled.

### Secure Headers

Sets Helmet-style security headers:

```dart
app.use(Middlewares.secureHeaders());
```

Headers set:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: no-referrer`
- `X-XSS-Protection: 0`

### Compression

Gzip-compresses response bodies when the client accepts gzip and the body exceeds `minLength`:

```dart
app.use(Middlewares.compress(minLength: 1024)); // Default: 1024 bytes
```

## Writing Custom Middleware

### Authentication Guard

```dart
Future<void> authGuard(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  final token = req.header('authorization');
  if (token == null || !token.startsWith('Bearer ')) {
    res.unauthorized({'error': 'Missing token'});
    return; // Short-circuit
  }
  // Attach user info for downstream handlers
  req.params['user_id'] = decodeToken(token);
  await next();
}
```

### Request Timing

```dart
Future<void> timingMiddleware(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  final sw = Stopwatch()..start();
  await next();
  sw.stop();
  res.header('X-Response-Time', '${sw.elapsedMilliseconds}ms');
}
```

### Rate Limiting

```dart
final _requests = <String, List<DateTime>>{};

Future<void> rateLimiter(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  final ip = req.ip;
  final now = DateTime.now();
  final window = _requests[ip] ?? [];

  // Remove entries older than 1 minute
  window.removeWhere((t) => now.difference(t).inMinutes > 1);

  if (window.length >= 60) {
    res.status(429).json({'error': 'Too many requests'});
    return;
  }

  window.add(now);
  _requests[ip] = window;
  await next();
}
```

## Execution Order

Middleware executes in the order it's registered:

```dart
app.use(A);  // Runs 1st
app.use(B);  // Runs 2nd
app.use(C);  // Runs 3rd

app.get('/path', handler); // Runs 4th (the handler)
```

With `next()`:
1. A runs → calls `next()`
2. B runs → calls `next()`
3. C runs → calls `next()`
4. Handler runs → returns
5. C continues after `next()`
6. B continues after `next()`
7. A continues after `next()`
