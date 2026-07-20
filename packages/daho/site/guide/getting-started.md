# Getting Started

## Prerequisites

- **Dart SDK** `^3.9`
- **H2O** + **CMake** — the native HTTP server library

## Installation

### macOS

```bash
brew install h2o cmake
```

### Linux (Debian/Ubuntu)

```bash
sudo apt-get install -y libh2o-evloop-dev cmake
```

### Windows

Windows has no native H2O build. Use **WSL2** (treat as Linux) or run in **Docker**:

```bash
docker build -t my_api . && docker run --rm -p 8080:8080 my_api
```

### Add Daho to your project

```yaml
# pubspec.yaml
dependencies:
  daho: ^0.1.0
```

Or use the CLI:

```bash
dart pub add daho
```

## Build the Native Library

Daho ships with C source code that needs to be compiled once per platform.

### Using the Daho CLI

```bash
dart run daho_cli:bin/daho.dart build
```

### Manual build

```bash
cd packages/daho/c_src
mkdir -p build && cd build
cmake ..
cmake --build .
```

## Hello World

Create `bin/server.dart`:

```dart
import 'package:daho/daho.dart';

/// Route setup — must be a top-level function (Isolate constraint).
void setupRoutes(Daho app) {
  app.get('/', (req, res) => res.ok({'message': 'Hello, Daho!'}));
}

void main() {
  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Server running at http://127.0.0.1:8080'),
  );
}
```

Run it:

```bash
dart run bin/server.dart
```

Test it:

```bash
curl http://localhost:8080
# {"message":"Hello, Daho!"}
```

## Why top-level functions?

Daho spawns one worker Isolate per CPU core. Each worker rebuilds the route table by calling your `setupRoutes` function. Dart cannot send closures across Isolate boundaries, so `setupRoutes` **must** be a top-level or static function — never a closure or instance method.

This applies to:
- `AppBuilder` (the `routes:` parameter of `app.listen()`)
- `ErrorHandler` and `NotFoundHandler` in `DahoConfig`

## Project Structure

A typical Daho project:

```
my_api/
├── bin/
│   └── server.dart          # Entry point
├── lib/
│   ├── src/
│   │   ├── handlers/        # Route handlers
│   │   ├── middleware/       # Custom middleware
│   │   └── services/        # Business logic
│   └── routes.dart          # Route setup (top-level function)
├── test/
│   └── routes_test.dart     # Tests using DahoTester
├── pubspec.yaml
└── analysis_options.yaml
```

## Using the Daho CLI

The `daho` CLI scaffolds projects and manages the native build:

```bash
# Create a new project
daho create my_api

# Build the native library
daho build

# Run the server
daho run

# Check toolchain
daho doctor
```

## Next Steps

- [Routing](/guide/routing) — HTTP methods, parameters, route groups
- [Middleware](/guide/middleware) — Built-in and custom middleware
- [Configuration](/guide/configuration) — DahoConfig options
- [Examples](/guide/examples) — Progressive examples from basic to advanced
