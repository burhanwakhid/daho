# CLI

The `daho` command-line tool scaffolds projects, compiles the native library, runs your server, and diagnoses your toolchain. It ships in the `daho_cli` package.

## Installation

```bash
dart pub global activate daho_cli
```

This installs a global `daho` command. Make sure Dart's `pub global` bin directory is on your `PATH`:

```bash
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

If you haven't published or activated the CLI globally yet, you can always invoke it from a checkout:

```bash
dart run daho_cli:daho <command>
```

## Commands

| Command | Description |
| --- | --- |
| `daho create <name>` | Scaffold a new Daho project (server, routes, Dockerfile, README). |
| `daho doctor` | Check the toolchain (Dart, CMake, H2O) and report what's missing. |
| `daho build` | Compile the native H2O wrapper for the current platform. |
| `daho run [entrypoint]` | Build the native library if needed, then run the server. |

`build` and `run` locate the resolved `daho` package via your project's `package_config.json` (walking up to the workspace root when needed), so run them from inside a project that depends on `daho`.

## `daho create`

Scaffold a ready-to-run project with a server entry point, a top-level routes file, a `Dockerfile`, and a `README`.

```bash
daho create my_api
cd my_api
daho run
```

### Options

| Flag | Description |
| --- | --- |
| `--local <path>` | Emit a `path` dependency on a local `daho` package (useful while developing before `daho` is on pub.dev). |
| `--force` | Overwrite an existing directory. |

```bash
# Point at a local checkout of the framework
daho create my_api --local ../daho/packages/daho
```

## `daho doctor`

Verify your toolchain and get platform-specific guidance on anything missing.

```bash
daho doctor
```

It checks for the Dart SDK, CMake, and H2O, and prints exactly what to install on your platform — including WSL2 / Docker guidance on Windows, where there is no native H2O build.

## `daho build`

Compile the native H2O wrapper for the current platform. The compiled library is cached, so this normally runs only once per machine (or after upgrading Daho).

```bash
daho build          # build if not already built
daho build --force  # force a clean rebuild
```

## `daho run`

Build the native library if needed, then run your server. Defaults to `bin/server.dart`.

```bash
daho run                      # runs bin/server.dart
daho run bin/api.dart         # run a specific entrypoint
daho run --no-build           # skip the build step (library already compiled)
```

## Platforms

H2O is a Unix server, so `build` and `run` work on **macOS** and **Linux**. On **Windows**, use **WSL2** (treat it as Linux) or the generated **Dockerfile** (a Linux container). `daho doctor` prints the right guidance for your platform.

## Roadmap

These are on the roadmap and not yet available:

- `daho run --watch` — hot reload on file changes during development.
- Prebuilt native binaries so `run` can skip compilation entirely.

## Next Steps

- [Getting Started](/guide/getting-started) — install and write your first server
- [Deployment](/guide/deployment) — ship to production with Docker
- [Configuration](/guide/configuration) — tune `DahoConfig`
