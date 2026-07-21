## 0.1.0

- Initial release.
- Express/Fiber-style HTTP framework for Dart.
- Native H2O server via FFI with multi-core support (SO_REUSEPORT).
- O(1) static routing + radix trie for parameterized routes.
- Built-in middleware: logger, CORS, secure headers, gzip compression.
- Multipart file upload support.
- Cookie management.
- In-process test harness (DahoTester).
- Graceful shutdown with configurable drain period.
- `daho` CLI for scaffolding, building, and running projects.
