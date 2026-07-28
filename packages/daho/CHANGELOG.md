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

## 0.1.1

- Fix: `c_src/CMakeLists.txt` now explicitly links OpenSSL and zlib. The native wrapper only linked cleanly before because Homebrew's `h2o` formula happens to ship a *shared* `libh2o-evloop.dylib` that carries those dependencies transitively — a from-source build (e.g. in Docker, since H2O has no Debian/Ubuntu package) produces a *static* `libh2o-evloop.a`, which doesn't, and failed to link with undefined `SSL_*`/`X509_*`/`deflate`/`inflate` symbols.
- Fix: `example/13_authentication.dart` no longer builds `AuthDatabase`/`JwtService`/`SessionManager`/`AuthRoutes` in `main()` and references them from the top-level `routes` builder — worker Isolates don't share state constructed in `main()`, so every worker crashed with `LateInitializationError`. Everything routes need is now built fresh inside `setupRoutes`, with only the one-time migration run left in `main()`. Also adds a role-gated `/api/admin` example route.
