# API Reference

Complete reference for Daho's public API.

## Daho

The main application class. Register routes and middleware, then call `listen()` to start serving.

```dart
final app = Daho(config: const DahoConfig());
```

### Constructor

```dart
Daho({DahoConfig config = const DahoConfig()})
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `config` | `DahoConfig` | Global configuration |

### Methods

| Method | Description |
|--------|-------------|
| `get(path, handler, {use:})` | Register a GET route |
| `post(path, handler, {use:})` | Register a POST route |
| `put(path, handler, {use:})` | Register a PUT route |
| `delete(path, handler, {use:})` | Register a DELETE route |
| `patch(path, handler, {use:})` | Register a PATCH route |
| `use(middleware)` | Register global middleware |
| `group(prefix)` | Create a route group |
| `serveStatic(virtualPath, localDir)` | Serve static files via H2O |
| `fastPath(path, body, {contentType:})` | Register a native fast path |
| `listen(port, {routes:, onStart:, onShutdown:})` | Start the server |

### listen()

```dart
Future<void> listen(
  int port, {
  required AppBuilder routes,
  Function? onStart,
  FutureOr<void> Function()? onShutdown,
})
```

Spawns one worker Isolate per CPU core (configurable via `DahoConfig.concurrency`). Each worker rebuilds the route table by calling `routes`.

---

## DahoGroup

A group of routes sharing a common path prefix and middleware.

```dart
final api = app.group('/api');
api.use(authMiddleware);
api.get('/users', listUsers);
api.post('/users', createUser);
```

### Methods

| Method | Description |
|--------|-------------|
| `use(middleware)` | Register middleware scoped to this group |
| `get(path, handler, {use:})` | Register a GET route in the group |
| `post(path, handler, {use:})` | Register a POST route in the group |
| `put(path, handler, {use:})` | Register a PUT route in the group |
| `delete(path, handler, {use:})` | Register a DELETE route in the group |
| `patch(path, handler, {use:})` | Register a PATCH route in the group |

---

## DahoConfig

Immutable, Isolate-safe configuration.

```dart
const DahoConfig({
  int bodyLimit = 4 * 1024 * 1024,
  int? concurrency,
  Duration requestTimeout = Duration.zero,
  Duration idleTimeout = Duration.zero,
  Duration shutdownGracePeriod = const Duration(seconds: 5),
  ErrorHandler errorHandler = defaultErrorHandler,
  NotFoundHandler notFoundHandler = defaultNotFoundHandler,
  bool trustProxy = false,
  bool disableStartupMessage = false,
})
```

See [Configuration](/guide/configuration) for detailed descriptions.

---

## DahoRequest

The incoming HTTP request.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `method` | `String` | HTTP method |
| `path` | `String` | Request path |
| `query` | `Map<String, String>` | Query parameters |
| `params` | `Map<String, String>` | Path parameters |
| `ip` | `String` | Client IP |
| `headers` | `Map<String, String>` | Request headers (lowercase keys) |
| `body` | `dynamic` | Parsed body (lazy) |
| `files` | `Map<String, UploadedFile>` | Uploaded files (lazy) |
| `cookies` | `Map<String, String>` | Parsed cookies (lazy) |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `header(name)` | `String?` | Case-insensitive header lookup |

---

## DahoResponse

The response builder. All methods return `this` for chaining.

### Sending Data

| Method | Description |
|--------|-------------|
| `send(text)` | Send plain text |
| `json(data)` | Send JSON |
| `bytes(raw, {contentType:})` | Send raw bytes |

### Status Helpers

| Method | Status |
|--------|--------|
| `ok(data)` | 200 |
| `badRequest(data)` | 400 |
| `unauthorized(data)` | 401 |
| `forbidden(data)` | 403 |
| `notFound(data)` | 404 |
| `internalServerError(data)` | 500 |

### Redirects

| Method | Status |
|--------|--------|
| `movedPermanently(location, data)` | 301 |
| `found(location, data)` | 302 |
| `seeOther(location, data)` | 303 |
| `notModified()` | 304 |

### Headers & Status

| Method | Description |
|--------|-------------|
| `status(code)` | Set HTTP status code |
| `header(key, value)` | Set a response header |

### Cookies

| Method | Description |
|--------|-------------|
| `cookie(name, value, {maxAge:, expires:, path:, domain:, secure:, httpOnly:, sameSite:})` | Set a cookie |
| `clearCookie(name, {path:})` | Clear a cookie |

---

## UploadedFile

A file from a `multipart/form-data` upload.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `filename` | `String` | Original filename |
| `contentType` | `String` | MIME type |
| `bytes` | `List<int>` | Raw file contents |

### Methods

| Method | Description |
|--------|-------------|
| `save(path)` | Write to disk (sync) |
| `saveAsync(path)` | Write to disk (async) |

---

## Middlewares

Built-in middleware factory.

| Method | Description |
|--------|-------------|
| `Middlewares.logger({out:})` | Access logging |
| `Middlewares.cors({origin:, methods:, headers:, credentials:, maxAge:})` | CORS + preflight |
| `Middlewares.secureHeaders()` | Security headers |
| `Middlewares.compress({minLength:})` | Gzip compression |

---

## Typedefs

```dart
/// Route setup function (must be top-level)
typedef AppBuilder = void Function(Daho app);

/// Middleware function
typedef Middleware = FutureOr<void> Function(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
);

/// Called by middleware to continue the chain
typedef NextFunction = Future<void> Function();

/// Terminal route handler
typedef RouteHandler = FutureOr<DahoResponse> Function(
  DahoRequest req,
  DahoResponse res,
);

/// Error handler
typedef ErrorHandler = FutureOr<void> Function(
  DahoRequest req,
  DahoResponse res,
  Object error,
  StackTrace stackTrace,
);

/// Not-found handler
typedef NotFoundHandler = FutureOr<void> Function(
  DahoRequest req,
  DahoResponse res,
);
```
