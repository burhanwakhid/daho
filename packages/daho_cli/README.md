# daho_cli

Command-line tool for the [Daho](../daho) HTTP framework.

```bash
dart pub global activate daho_cli
```

## Commands

| Command | Description |
| --- | --- |
| `daho create <name> [--local <path>] [--force]` | Scaffold a new Daho project (server, routes, Dockerfile, README). |
| `daho doctor` | Check the toolchain (Dart, CMake, H2O) and report what's missing. |
| `daho build [--force]` | Compile the native H2O wrapper for the current platform. |
| `daho run [entrypoint] [--no-build]` | Build the native library if needed, then run the server (defaults to `bin/server.dart`). |

`build` and `run` locate the resolved `daho` package via the project's
`package_config.json` (walking up to the workspace root when needed), so run
them from within a project that depends on `daho`.

`create --local <path>` emits a `path` dependency on a local `daho` package —
useful while developing before `daho` is published to pub.dev.

## Platforms

H2O is a Unix server, so `build`/`run` work on macOS and Linux. On **Windows**,
use **WSL2** or the generated **Dockerfile** (Linux container). `daho doctor`
prints the right guidance per platform.

## Roadmap

- `daho run --watch` — hot reload on file changes during development.
- Prebuilt native binaries so `run` can skip compilation.
