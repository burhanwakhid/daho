## 0.1.2

- Add native TLS support: `DahoConfig.tlsCertPath`/`tlsKeyPath` (PEM cert
  chain + private key) make H2O terminate TLS itself and negotiate
  `h2`/`http/1.1` via ALPN — previously there was no cert/key API anywhere
  in the stack and the native wrapper never set up an `SSL_CTX`, so TLS was
  only possible behind a reverse proxy. An invalid/missing cert or key logs
  to stderr and falls back to plain HTTP for that worker rather than
  crashing. One `Daho` instance is still all-HTTP or all-HTTPS (no
  redirect/dual-port yet — see README's "HTTPS / TLS" section).
- Fix: response header **names** were sent with whatever casing the route
  handler used (e.g. `Content-Type`) — harmless over HTTP/1.1 (case
  -insensitive) but a protocol violation over HTTP/2, which requires
  lowercase header names (RFC 7540 §8.1.2) and made clients reject every
  response with `PROTOCOL_ERROR`. This was unreachable before native TLS
  existed (no ALPN, so `h2` could never be negotiated) and surfaced
  immediately once it did. `c_src/h2o_wrapper.c` now lowercases header
  names before handing them to H2O, for both HTTP/1.1 and HTTP/2.
- Fix: `serveStatic`/H2O's file handler served **every** static file as
  `application/octet-stream`, regardless of extension — `h2o_file_register`
  was passed a `NULL` mimemap, which H2O initializes as an *empty* map (no
  built-in extension table). Harmless for a classic `<script src>` (no MIME
  enforcement), but broke ES module scripts and `WebAssembly.compileStreaming()`
  outright, since both enforce strict MIME checking. `c_src/h2o_wrapper.c` now
  builds a shared mimemap (`.js`/`.mjs` → `text/javascript`, `.wasm` →
  `application/wasm`, plus `.css`/`.json`/`.svg`/images/fonts/etc.) and passes
  it to every static directory's file handler. Requires rebuilding the native
  wrapper (`daho build --force` or `cmake --build c_src/build`).

## 0.1.1

- Fix: `c_src/CMakeLists.txt` now explicitly links OpenSSL and zlib. The native wrapper only linked cleanly before because Homebrew's `h2o` formula happens to ship a *shared* `libh2o-evloop.dylib` that carries those dependencies transitively — a from-source build (e.g. in Docker, since H2O has no Debian/Ubuntu package) produces a *static* `libh2o-evloop.a`, which doesn't, and failed to link with undefined `SSL_*`/`X509_*`/`deflate`/`inflate` symbols.
- Fix: `example/13_authentication.dart` no longer builds `AuthDatabase`/`JwtService`/`SessionManager`/`AuthRoutes` in `main()` and references them from the top-level `routes` builder — worker Isolates don't share state constructed in `main()`, so every worker crashed with `LateInitializationError`. Everything routes need is now built fresh inside `setupRoutes`, with only the one-time migration run left in `main()`. Also adds a role-gated `/api/admin` example route.


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
