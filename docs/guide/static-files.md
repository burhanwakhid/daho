# Static Files

Daho provides two mechanisms for serving content without Dart route handlers.

## serveStatic()

Serve files from a local directory under a URL prefix. Files are served directly by the H2O kernel via zero-copy file serving — no Dart code runs.

```dart
void setupRoutes(Daho app) {
  // Serve files from ./public/ under the root URL path
  app.serveStatic('/', 'public');

  // Serve files from ./assets/ under /static
  app.serveStatic('/static', 'assets');

  // Regular Dart routes still work alongside static serving
  app.get('/api/data', (req, res) => res.ok({'key': 'value'}));
}
```

With the above setup:
- `GET /index.html` → serves `./public/index.html`
- `GET /static/logo.png` → serves `./assets/logo.png`
- `GET /api/data` → handled by Dart

::: info
Static files are served by H2O's built-in file handler with zero-copy I/O. This is the fastest way to serve files — the data goes directly from the filesystem to the network socket without entering Dart's heap.
:::

## fastPath()

Register a fixed response for a specific path, served entirely in C. The Dart route pipeline is never invoked.

```dart
void setupRoutes(Daho app) {
  // Health check — always returns the same JSON
  app.fastPath(
    '/health',
    '{"status": "ok"}',
    contentType: 'application/json',
  );

  // Simple text response
  app.fastPath('/ping', 'pong');

  // Regular routes still work
  app.get('/users', (req, res) => res.ok('users list'));
}
```

## When to Use Each

| Feature | Use Case | Performance |
|---------|----------|-------------|
| `serveStatic()` | Serving HTML, CSS, JS, images, any files from disk | Zero-copy, H2O handles directly |
| `fastPath()` | Health checks, status endpoints, fixed responses | Served from C memory, zero Dart |
| Regular routes | Dynamic content, API endpoints, anything that needs logic | Full Dart dispatch pipeline |

::: warning
Fast paths bypass the entire middleware chain. If you need middleware (auth, logging, CORS) on an endpoint, use a regular route instead.
:::

## Example: Full Setup

```dart
void setupRoutes(Daho app) {
  // Global middleware
  app.use(Middlewares.logger());
  app.use(Middlewares.cors());

  // Fast paths (no middleware, no Dart)
  app.fastPath('/health', '{"status": "ok"}', contentType: 'application/json');

  // Static files (served by H2O, no Dart)
  app.serveStatic('/', 'public');

  // API routes (full Dart pipeline)
  final api = app.group('/api');
  api.get('/users', listUsers);
  api.post('/users', createUser);
}

void main() {
  final app = Daho();
  app.listen(8080, routes: setupRoutes);
}
```
