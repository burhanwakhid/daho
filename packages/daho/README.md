# Daho

A fast, minimal HTTP framework for Dart, backed by a native [H2O](https://h2o.examp1e.net/) server over FFI. Express/Fiber-style API, multi-core out of the box.

- **Native core** — request handling runs on H2O; one worker Isolate per CPU core sharing the socket via `SO_REUSEPORT`.
- **Fast routing** — O(1) map for static paths, radix trie for parameterized ones.
- **Familiar API** — `app.get`, groups, global / group / per-route middleware.
- **Batteries included** — body parsing (JSON, urlencoded, multipart), cookies, CORS, gzip, logging, security headers, graceful shutdown, in-process test client.

> **Status:** experimental. APIs may change.

## Requirements

- Dart SDK `^3.9`
- H2O + CMake. The native library is built once, per platform (CMake discovers
  H2O automatically on macOS/Linux):

```bash
brew install h2o cmake                          # macOS
```

Debian/Ubuntu has no `libh2o-evloop-dev` package — H2O isn't in the apt archive. Build it from source instead (this is what the CLI's generated Dockerfile does):

```bash
sudo apt-get install -y cmake build-essential git pkg-config libssl-dev zlib1g-dev
git clone --recursive --depth 1 --branch v2.2.6 https://github.com/h2o/h2o.git /tmp/h2o
cmake -S /tmp/h2o -B /tmp/h2o/build -DCMAKE_BUILD_TYPE=Release -DWITH_MRUBY=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build /tmp/h2o/build --target libh2o-evloop
sudo install -Dm644 /tmp/h2o/build/libh2o-evloop.a /usr/local/lib/libh2o-evloop.a
sudo cp -r /tmp/h2o/include/. /usr/local/include/
rm -rf /tmp/h2o
```

Build it with the CLI (`daho build`) or manually:

```bash
cd c_src && mkdir -p build && cd build && cmake .. && cmake --build .
```

### Platforms

macOS and Linux are supported. **Windows has no native H2O build** — use
**WSL2** (treat as Linux) or run in **Docker** (a Linux container). `daho create`
scaffolds a ready-to-use `Dockerfile`:

```bash
docker build -t my_api . && docker run --rm -p 8080:8080 my_api
```

## Quick start

```dart
import 'package:daho/daho.dart';

// Route setup MUST be a top-level function: it is re-run on every worker
// Isolate, and Dart cannot send closures across Isolates.
void setupRoutes(Daho app) {
  app.use(Middlewares.logger());

  app.get('/', (req, res) => res.ok({'hello': 'world'}));
  app.get('/users/:id', (req, res) => res.ok({'id': req.params['id']}));
  app.post('/users', (req, res) => res.status(201).json(req.body));
}

void main() {
  final app = Daho(config: const DahoConfig(bodyLimit: 8 * 1024 * 1024));
  app.listen(8080, routes: setupRoutes, onStart: () => print('http://127.0.0.1:8080'));
}
```

## Configuration

`DahoConfig` mirrors Fiber's `fiber.Config`:

| Option | Default | Description |
| --- | --- | --- |
| `bodyLimit` | 4 MB | Max request body; larger → `413` before the body is read. |
| `concurrency` | CPU cores | Worker count (clamp `[1, 64]`). Set explicitly in CPU-limited containers. |
| `requestTimeout` | H2O default | Per-request timeout. |
| `idleTimeout` | H2O default | Keep-alive idle timeout. |
| `shutdownGracePeriod` | 5 s | Drain time after `SIGINT`/`SIGTERM`. |
| `errorHandler` | generic 500 | Handle uncaught errors (no stack-trace leak). |
| `notFoundHandler` | generic 404 | Handle unmatched routes. |
| `trustProxy` | `false` | Use `X-Forwarded-For` / `X-Real-IP` for `req.ip`. |
| `disableStartupMessage` | `false` | Silence startup/shutdown logs. |

Handler-typed options (`errorHandler`, `notFoundHandler`) must be top-level or static functions.

## Middleware

```dart
app.use(Middlewares.logger());          // access log
app.use(Middlewares.cors());            // CORS + preflight
app.use(Middlewares.secureHeaders());   // Helmet-style headers
app.use(Middlewares.compress());        // gzip responses

// per-route
app.get('/admin', adminHandler, use: [authGuard]);
```

Global middleware runs for **every** request, including unmatched ones (404 / 405 / CORS preflight).

## Testing

Daho ships an in-process harness, `DahoTester`, that runs requests through the
real dispatch path — global middleware, route matching, 404 / 405, and the
configured error handler — without booting the native server. It currently
lives in the repo's `test/` directory (see `test/daho_test.dart`); exposing it
as a public `package:daho/testing.dart` library is on the roadmap.

```dart
final t = DahoTester(setupRoutes);
final res = await t.post('/users', json: {'name': 'ada'});
expect(res.statusCode, 201);
expect(res.json['name'], 'ada');
```

## HTTPS / TLS

Daho can terminate TLS natively — H2O performs the handshake and negotiates `h2`/`http/1.1` via ALPN — by pointing `DahoConfig` at a certificate and private key (PEM):

```dart
final app = Daho(
  config: const DahoConfig(
    tlsCertPath: '/etc/ssl/example.crt',
    tlsKeyPath: '/etc/ssl/example.key',
  ),
);
app.listen(443, routes: setupRoutes);
```

Setting both switches *every* connection on that port to HTTPS — there is no automatic HTTP→HTTPS redirect or dual-port listener yet (run a second `Daho` on another port for that, or keep terminating at a proxy for that case). An invalid or missing cert/key logs to stderr and that worker falls back to plain HTTP rather than crashing, so double-check your logs after changing paths.

If you'd rather not manage certificates in the app at all, terminating TLS at a reverse proxy still works exactly as before — the standard deployment for many Dart/Node services:

```nginx
server {
    listen 443 ssl;
    server_name example.com;
    ssl_certificate     /etc/ssl/example.crt;
    ssl_certificate_key /etc/ssl/example.key;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Set `trustProxy: true` so `req.ip` reflects the real client behind the proxy.

## Examples

See [`example/`](example/): basic routing, middleware/groups, multipart uploads, and a JWT-authenticated REST API.

## Roadmap

Tooling planned to make Daho a batteries-included, zero-friction framework.

### `daho` CLI

- **`daho create <name>`** — scaffold a new Daho server project: directory
  layout, example routes, `pubspec.yaml`, and the native/CMake wiring, ready to
  run.
- **`daho run`** — OS-aware runner. Detects the platform, checks whether H2O is
  installed; if not, installs it (Homebrew / apt / …) and builds the native
  library, then starts the Dart server. One command from clone to running.
- **`daho build`** — compile the native library for the current platform.
- **`daho doctor`** — verify the toolchain (Dart, CMake, H2O) and report what is
  missing and how to fix it.

### Developer experience

- **Hot reload** — watch source files during development and reload
  routes/handlers on change, without restarting the native server.

### Core

- HTTP→HTTPS redirect / serving both plaintext and TLS from one process (today: one `Daho` instance is either all-HTTP or all-HTTPS, based on `DahoConfig.tlsCertPath`/`tlsKeyPath`; run two instances on two ports for both).
- Response streaming / chunked responses and WebSocket support.
- Per-worker lifecycle hooks to manage worker-owned resources on shutdown.
- Public `package:daho/testing.dart` testing library.

## License

MIT
