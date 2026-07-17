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

/// A Linux Docker image: the recommended way to run Daho on Windows (or any
/// host), since H2O has no native Windows build.
String dockerfileTemplate(String name) => '''
# Daho runs on a native H2O server (Unix only). On Windows, build/run via this
# Linux container (or WSL2).
FROM dart:stable AS build

# Native toolchain + H2O (Debian/Ubuntu package names).
RUN apt-get update && apt-get install -y --no-install-recommends \\
    cmake build-essential libh2o-evloop-dev \\
    && rm -rf /var/lib/apt/lists/*

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

Requires H2O and CMake (`brew install h2o cmake`, or
`sudo apt-get install -y libh2o-evloop-dev cmake`).

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
