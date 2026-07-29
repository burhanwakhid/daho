// File templates used by `daho create`. Each returns the file contents for a
// project named `name`.

/// The `daho` dependency line. When [localPath] is given, a path dependency is
/// emitted (for local development before publishing); otherwise a hosted one.
String _dahoDependency(String? localPath) {
  if (localPath != null) {
    return 'daho:\n    path: $localPath';
  }
  return 'daho: ^0.1.0';
}

String pubspecTemplate(String name, {String? localPath}) =>
    '''
name: $name
description: A Daho HTTP server.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.9.0

dependencies:
  ${_dahoDependency(localPath)}

dev_dependencies:
  lints: ^6.0.0
''';

String serverTemplate(String name) =>
    '''
import 'package:daho/daho.dart';
import 'package:$name/routes.dart';

void main() {
  final app = Daho(
    config: const DahoConfig(
      // Adjust as needed; see DahoConfig for all options.
      bodyLimit: 4 * 1024 * 1024,
    ),
  );

  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('🚀 $name running on http://127.0.0.1:8080'),
    onShutdown: () async {
      // Close resources (DB connections, etc.) here.
    },
  );
}
''';

String routesTemplate(String name) =>
    '''
import 'package:daho/daho.dart';

/// Registers all routes and middleware.
///
/// This MUST be a top-level function: it is re-run on every worker Isolate,
/// and Dart cannot send closures across Isolates.
void setupRoutes(Daho app) {
  app.use(Middlewares.logger());

  app.get('/', (req, res) => res.ok({'message': 'Hello from $name!'}));

  app.get('/health', (req, res) => res.ok({'status': 'ok'}));

  app.get('/hello/:name', (req, res) {
    return res.ok({'hello': req.params['name']});
  });
}
''';

String analysisOptionsTemplate() => '''
include: package:lints/recommended.yaml
''';

String gitignoreTemplate() => '''
.dart_tool/
pubspec.lock
*.sqlite
*.sqlite-shm
*.sqlite-wal
''';

/// H2O has no Debian/Ubuntu package (there is no `libh2o-evloop-dev` — a
/// prior version of this template assumed one existed, and `apt-get
/// install` failed on every real Docker build). Build it from source
/// instead, mirroring what `brew install h2o` provides on macOS. Pinned to
/// a tag verified to build clean with these exact flags — bump deliberately.
///
/// Only the `libh2o-evloop` target is built (not the full `h2o` server
/// binary), which keeps the dependency list to `git`, `libssl-dev`, and
/// `zlib1g-dev`. It links as a *static* archive, which is why
/// `packages/daho/c_src/CMakeLists.txt` explicitly links OpenSSL/zlib
/// itself rather than assuming a shared `libh2o-evloop.so` will carry
/// those transitively (which is what Homebrew's package happens to do).
///
/// `-DCMAKE_POSITION_INDEPENDENT_CODE=ON` is required: without it this
/// static archive isn't `-fPIC` and fails to link into `libh2o_wrapper.so`
/// (`relocation R_X86_64_TPOFF32 ... can not be used when making a shared
/// object`) — Homebrew's macOS package sidesteps this by shipping a
/// pre-built *shared* `libh2o-evloop.dylib` instead.
const String h2oFromSourceInstallStep = '''
RUN git clone --recursive --depth 1 --branch v2.2.6 https://github.com/h2o/h2o.git /tmp/h2o \\
    && cmake -S /tmp/h2o -B /tmp/h2o/build -DCMAKE_BUILD_TYPE=Release -DWITH_MRUBY=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_POSITION_INDEPENDENT_CODE=ON \\
    && cmake --build /tmp/h2o/build --target libh2o-evloop -- -j\$(nproc) \\
    && install -Dm644 /tmp/h2o/build/libh2o-evloop.a /usr/local/lib/libh2o-evloop.a \\
    && cp -r /tmp/h2o/include/. /usr/local/include/ \\
    && rm -rf /tmp/h2o
''';

/// A Linux Docker image: the recommended way to run Daho on Windows (or any
/// host), since H2O has no native Windows build.
String dockerfileTemplate(String name) =>
    '''
# Daho runs on a native H2O server (Unix only). On Windows, build/run via this
# Linux container (or WSL2).
FROM dart:stable AS build

RUN apt-get update && apt-get install -y --no-install-recommends \\
    cmake build-essential git pkg-config libssl-dev zlib1g-dev \\
    && rm -rf /var/lib/apt/lists/*

$h2oFromSourceInstallStep
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline

# Build the native wrapper shipped inside the resolved `daho` package.
RUN dart pub global activate daho_cli && ~/.pub-cache/bin/daho build

EXPOSE 8080
CMD ["dart", "run", "bin/server.dart"]
''';

String readmeTemplate(String name) =>
    '''
# $name

A server built with the [Daho](https://pub.dev/packages/daho) HTTP framework.

## Run locally (macOS / Linux / WSL2)

Requires H2O and CMake:
- macOS: `brew install h2o cmake`
- Debian/Ubuntu: there's no `libh2o-evloop-dev` package — H2O isn't in the apt
  archive. Build it from source instead — see the "Native toolchain" step in
  this project's Dockerfile, or the
  [Daho getting-started guide](https://github.com/burhanwakhid/daho/blob/master/docs/guide/getting-started.md).

```bash
dart pub get
daho run            # builds the native library on first run, then starts
```

Or without the CLI:

```bash
dart pub get
dart run bin/server.dart   # requires the native library to be built already
```

## Run with Docker (recommended on Windows)

```bash
docker build -t $name .
docker run --rm -p 8080:8080 $name
```

Then open http://127.0.0.1:8080.
''';
