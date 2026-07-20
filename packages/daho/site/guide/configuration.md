# Configuration

`DahoConfig` controls the server's behavior. Pass it when creating the `Daho` instance:

```dart
final app = Daho(
  config: const DahoConfig(
    bodyLimit: 8 * 1024 * 1024,
    concurrency: 4,
    trustProxy: true,
  ),
);
```

## Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `bodyLimit` | `int` | 4 MB | Max request body in bytes. Oversized requests get `413` before the body is read. |
| `concurrency` | `int?` | CPU cores | Worker Isolate count. Clamped to `[1, 64]`. |
| `requestTimeout` | `Duration` | `Duration.zero` | Per-request timeout. Zero keeps H2O's default. |
| `idleTimeout` | `Duration` | `Duration.zero` | Keep-alive idle timeout. Zero keeps H2O's default. |
| `shutdownGracePeriod` | `Duration` | 5 seconds | Drain time after `SIGINT`/`SIGTERM`. |
| `errorHandler` | `ErrorHandler` | `defaultErrorHandler` | Called when a handler/middleware throws. |
| `notFoundHandler` | `NotFoundHandler` | `defaultNotFoundHandler` | Called when no route matches. |
| `trustProxy` | `bool` | `false` | Use `X-Forwarded-For` / `X-Real-IP` for `req.ip`. |
| `disableStartupMessage` | `bool` | `false` | Silence startup/shutdown log lines. |

## Body Limit

Controls the maximum request body size. Enforced by H2O *before* the body is read, so oversized requests are rejected early with `413 Payload Too Large`.

```dart
// 8 MB body limit (for file uploads)
config: const DahoConfig(bodyLimit: 8 * 1024 * 1024)
```

## Concurrency

By default, Daho spawns one worker per CPU core. In containers with CPU quotas, `Platform.numberOfProcessors` may report the host's core count rather than the cgroup limit — set `concurrency` explicitly:

```dart
// 4 workers regardless of host core count
config: const DahoConfig(concurrency: 4)
```

## Trust Proxy

When running behind a reverse proxy (nginx, Cloudflare, AWS ALB), enable `trustProxy` so `req.ip` reflects the real client IP from `X-Forwarded-For` or `X-Real-IP`:

```dart
config: const DahoConfig(trustProxy: true)
```

::: warning
Only enable `trustProxy` behind a **trusted** reverse proxy. Without a proxy, clients can spoof their IP via these headers.
:::

## Custom Error Handler

Define a custom error handler to control what clients see when a handler throws:

```dart
void myErrorHandler(
  DahoRequest req,
  DahoResponse res,
  Object error,
  StackTrace stackTrace,
) {
  // Log the error server-side
  stderr.writeln('[ERROR] ${req.method} ${req.path}: $error');

  // Return a safe response to the client
  res.status(500).json({'error': 'Internal Server Error'});
}

final app = Daho(
  config: DahoConfig(errorHandler: myErrorHandler),
);
```

::: info
Error and not-found handlers **must** be top-level or static functions — not closures. The config is sent across Isolate boundaries, and Dart cannot transfer closures.
:::

## Custom Not-Found Handler

```dart
void myNotFoundHandler(DahoRequest req, DahoResponse res) {
  res.status(404).json({
    'error': 'Not Found',
    'path': req.path,
  });
}

final app = Daho(
  config: DahoConfig(notFoundHandler: myNotFoundHandler),
);
```

## Shutdown Grace Period

When the server receives `SIGINT` or `SIGTERM`, it waits this duration for in-flight requests to finish before exiting:

```dart
config: const DahoConfig(shutdownGracePeriod: Duration(seconds: 10))
```

You can also run cleanup logic via the `onShutdown` callback:

```dart
app.listen(
  8080,
  routes: setupRoutes,
  onShutdown: () async {
    print('Cleaning up...');
    // Close database connections, flush buffers, etc.
  },
);
```
