# Daho (monorepo)

A fast, minimal HTTP framework for Dart, backed by a native [H2O](https://h2o.examp1e.net/) server over FFI — with an Express/Fiber-style API and multi-core support.

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) containing:

| Package | Description |
| --- | --- |
| [`packages/daho`](packages/daho) | The framework library. |
| [`packages/daho_cli`](packages/daho_cli) | The `daho` command-line tool (build / run / doctor). |

## Getting started

```bash
# 1. Toolchain
brew install h2o cmake          # macOS

# 2. Resolve the workspace
dart pub get

# 3. Build the native library and run an example
cd packages/daho
dart run ../daho_cli/bin/daho.dart doctor          # verify toolchain
dart run ../daho_cli/bin/daho.dart run example/routing.dart
```

Once published, the CLI installs as a global `daho` command:

```bash
dart pub global activate daho_cli
daho doctor
daho run
```

See [`packages/daho/README.md`](packages/daho/README.md) for the framework docs
and roadmap.

## License

MIT
