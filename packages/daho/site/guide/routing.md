# Routing

Daho supports all standard HTTP methods with two routing strategies: O(1) map lookup for static paths and a radix trie for parameterized routes.

## HTTP Methods

Register handlers for any HTTP method:

```dart
void setupRoutes(Daho app) {
  app.get('/users', (req, res) => res.ok('list users'));
  app.post('/users', (req, res) => res.status(201).json(req.body));
  app.put('/users/:id', (req, res) => res.ok('update user'));
  app.patch('/users/:id', (req, res) => res.ok('partial update'));
  app.delete('/users/:id', (req, res) => res.status(204).send(''));
}
```

Supported methods: `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`.

## Query Parameters

Access query string parameters via `req.query`:

```dart
// GET /search?q=dart&limit=10
app.get('/search', (req, res) {
  final query = req.query['q'] ?? '';
  final limit = req.query['limit'] ?? '10';
  return res.ok({'query': query, 'limit': limit});
});
```

## Path Parameters

Use `:param` syntax for dynamic path segments. Captured values are available in `req.params`:

```dart
// GET /users/42
app.get('/users/:id', (req, res) {
  final userId = req.params['id'];
  return res.ok({'id': userId});
});

// GET /posts/42/comments/7
app.get('/posts/:postId/comments/:commentId', (req, res) {
  return res.ok({
    'postId': req.params['postId'],
    'commentId': req.params['commentId'],
  });
});
```

## Route Groups

Group routes under a shared prefix with `app.group()`:

```dart
void setupRoutes(Daho app) {
  // Public routes
  app.get('/login', (req, res) => res.ok('login page'));

  // Grouped routes — all prefixed with /api
  final api = app.group('/api');

  api.get('/users', (req, res) => res.ok('GET /api/users'));
  api.post('/users', (req, res) => res.ok('POST /api/users'));
  api.get('/items', (req, res) => res.ok('GET /api/items'));
}
```

Groups also support scoped middleware — see [Middleware](/guide/middleware#group-scoped-middleware).

## Per-Route Middleware

Attach middleware to specific routes via the `use:` parameter:

```dart
app.get('/admin', (req, res) => res.ok('admin panel'), use: [authGuard]);
app.post('/upload', handleUpload, use: [authGuard, rateLimiter]);
```

## 404 and 405 Handling

- **404 Not Found**: When no route matches the request path, Daho invokes the configured `notFoundHandler` (default: plain JSON 404).
- **405 Method Not Allowed**: When the path exists for *other* methods but not the requested one, Daho returns `405` with an `Allow` header listing the valid methods.

```dart
// Only GET is registered for /users
app.get('/users', (req, res) => res.ok('list'));

// POST /users → 405 with Allow: GET
// GET /users  → 200
```

## Fast Paths

Register native fast paths for responses that should bypass Dart entirely. These are served directly by the C H2O server:

```dart
app.fastPath('/health', '{"status": "ok"}', contentType: 'application/json');
app.fastPath('/ping', 'pong');
```

Fast paths are ideal for:
- Health check endpoints
- Static status responses
- Any response that never changes

::: info
Fast paths bypass the entire Dart route pipeline — no middleware runs, no route matching occurs. They're the fastest possible response.
:::
