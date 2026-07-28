# Deployment

Daho runs anywhere Dart runs on a Unix host. This guide covers building a production binary, containerizing with Docker, running behind a reverse proxy, and shutting down gracefully.

## Platform support

| Platform | Status |
| --- | --- |
| **Linux** | ✅ Fully supported — multi-worker scales linearly with cores. |
| **macOS** | ✅ Supported for development. Single worker only (an `SO_REUSEPORT` limitation). |
| **Windows** | ⚠️ No native H2O build. Use **WSL2** or a **Docker** (Linux) container. |

For production, **deploy on Linux** — it's where multi-core scaling and `SO_REUSEPORT` socket sharing work as intended.

## Building for production

Daho's native library is compiled once per platform. In a build step:

```bash
# Resolve dependencies
dart pub get

# Compile the native H2O wrapper
daho build            # or: dart run daho_cli:daho build
```

You can optionally compile your Dart entry point to a self-contained executable:

```bash
dart compile exe bin/server.dart -o build/server
```

::: tip
`dart compile exe` produces a native executable for faster startup, but the compiled binary still loads Daho's native `.so`/`.dylib` at runtime — keep that library alongside it.
:::

## Docker

`daho create` scaffolds a ready-to-use `Dockerfile`. A typical multi-stage build for Debian/Ubuntu looks like this:

```dockerfile
# ---- build stage ----
FROM dart:stable AS build

# Native toolchain. There is no `libh2o-evloop-dev`/`libh2o-evloop0.13`
# package — H2O isn't in the Debian/Ubuntu archive — so it's built from
# source below instead of apt-installed.
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake build-essential git pkg-config libssl-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --recursive --depth 1 --branch v2.2.6 https://github.com/h2o/h2o.git /tmp/h2o \
    && cmake -S /tmp/h2o -B /tmp/h2o/build -DCMAKE_BUILD_TYPE=Release -DWITH_MRUBY=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    && cmake --build /tmp/h2o/build --target libh2o-evloop -- -j$(nproc) \
    && install -Dm644 /tmp/h2o/build/libh2o-evloop.a /usr/local/lib/libh2o-evloop.a \
    && cp -r /tmp/h2o/include/. /usr/local/include/ \
    && rm -rf /tmp/h2o

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline

# Build the native library
RUN dart run daho_cli:daho build

# ---- runtime stage ----
FROM debian:stable-slim
# H2O itself is statically linked into libh2o_wrapper.so at build time, so
# the runtime image only needs the shared libs that wrapper dynamically
# links against (OpenSSL, zlib) — not an H2O package.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 zlib1g && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app /app

EXPOSE 8080
CMD ["dart", "run", "bin/server.dart"]
```

Build and run:

```bash
docker build -t my_api .
docker run --rm -p 8080:8080 my_api
```

::: warning cgroup CPU limits
Inside a container, `Platform.numberOfProcessors` reports the **host's** core count, not the container's CPU quota. Set `concurrency` explicitly to match the CPUs you've allocated, or you'll spawn too many workers. See below.
:::

## Concurrency in containers

Match the worker count to the CPU quota you give the container:

```dart
// Container limited to 2 CPUs
final app = Daho(config: const DahoConfig(concurrency: 2));
```

Or read it from the environment so you can tune per deployment:

```dart
import 'dart:io';

final workers = int.tryParse(Platform.environment['WEB_CONCURRENCY'] ?? '');
final app = Daho(config: DahoConfig(concurrency: workers));
```

```bash
docker run --cpus 2 -e WEB_CONCURRENCY=2 -p 8080:8080 my_api
```

## Behind a reverse proxy

When running behind nginx, a cloud load balancer, or Cloudflare, enable `trustProxy` so `req.ip` reflects the real client address from `X-Forwarded-For` / `X-Real-IP`:

```dart
final app = Daho(config: const DahoConfig(trustProxy: true));
```

::: danger
Only enable `trustProxy` when a **trusted** proxy sets these headers. Exposed directly to the internet, clients can spoof their IP through them.
:::

A minimal nginx front:

```nginx
server {
  listen 80;
  server_name example.com;

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

## Graceful shutdown

On `SIGINT` or `SIGTERM` (e.g. `docker stop`, a Kubernetes rolling update), Daho stops accepting shutdown-signal noise, runs your `onShutdown` callback, waits `shutdownGracePeriod` for in-flight requests to drain, then exits.

```dart
void main() {
  final app = Daho(
    config: const DahoConfig(shutdownGracePeriod: Duration(seconds: 10)),
  );

  app.listen(
    8080,
    routes: setupRoutes,
    onShutdown: () async {
      // Flush metrics, close shared connections owned by the master Isolate.
      print('Draining...');
    },
  );
}
```

::: info Isolate scope
`onShutdown` runs on the **master** Isolate. It cannot reach resources owned by worker Isolates (e.g. a database opened inside your `routes` function) — per-worker cleanup is not yet supported. Design workers to tolerate abrupt termination after the grace period.
:::

Give orchestrators enough termination grace. In Kubernetes:

```yaml
spec:
  terminationGracePeriodSeconds: 15   # ≥ shutdownGracePeriod
```

## Health checks

Use a `fastPath` for liveness/readiness probes — it's served entirely in C, bypassing the Dart pipeline, so it stays responsive even under load:

```dart
void setupRoutes(Daho app) {
  app.fastPath('/healthz', '{"status":"ok"}', contentType: 'application/json');
}
```

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

## Production checklist

- ✅ Deploy on **Linux** for multi-core scaling.
- ✅ Set `concurrency` explicitly to match container CPU limits.
- ✅ Enable `trustProxy` **only** behind a trusted proxy.
- ✅ Provide a custom `errorHandler` that logs server-side and never leaks stack traces. See [Error Handling](/guide/error-handling).
- ✅ Set `shutdownGracePeriod` and orchestrator grace to match.
- ✅ Expose a `fastPath` health endpoint.
- ✅ Consider `disableStartupMessage: true` in production logs.

## Next Steps

- [Performance](/guide/performance) — benchmarks and tuning
- [Configuration](/guide/configuration) — every `DahoConfig` option
- [CLI](/guide/cli) — `daho build` and `daho run`
