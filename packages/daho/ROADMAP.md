# Daho Roadmap: Closing the Gap with H2O

Daho wraps H2O ([h2o/h2o](https://github.com/h2o/h2o)) over FFI, but only links
`h2o-evloop` (see `c_src/CMakeLists.txt`) — not H2O's standalone binary, not
mruby, not quicly/picotls, not brotli. This matters: several H2O features are a
small C+FFI addition away, others need a new library linked in, and a couple are
**not possible without rebuilding H2O itself** from a different source tree or
build flags. This document is written so a future AI agent (or human) can pick
up any single section and implement it directly, without re-deriving the H2O
API surface from scratch.

Every claim below was verified against the actual installed H2O headers
(`/opt/homebrew/opt/h2o/include/h2o.h` and `h2o/*.h`) and the actual linked
library (`nm libh2o-evloop.a`, `otool -L libh2o-evloop.dylib`) — not H2O's
documentation or changelog, which can describe features the installed build
doesn't actually contain.

Status legend: ✅ done · 🚧 partial/workaround · ❌ not started

## Already implemented (do not re-propose)

So a future agent doesn't waste time rediscovering these: middleware pipeline
(`app.use`, group `.use`, per-route `use:`, folded into one chain —
`lib/src/router.dart:231-245`), route groups (`app.group`, but see §11 for
nesting), request logger and gzip compression middleware
(`lib/src/middleware.dart`), panic/recovery (every request already wrapped in
try/catch → `DahoConfig.errorHandler`, `lib/src/ffi/handler.dart:101-124`),
cookies (`req.cookies`, `res.cookie/clearCookie`), lazy `req.body`/`req.files`,
`DahoTester` in-process test client, an internal `Profiler` class gated by
`DAHO_PROFILE=1` (`lib/src/profiler.dart`), native TLS termination with ALPN
(`DahoConfig.tlsCertPath`/`tlsKeyPath`, added this release), and `daho_cli`
commands `create`/`run`/`build`/`doctor`/`auth`.

---

## 1. Static directory listing

**Status: ❌ not started. Readily exposable, no new dependency.**

H2O's file handler already supports it — the flag just isn't set.

- **H2O API**: `H2O_FILE_FLAG_DIR_LISTING` (`h2o.h:1735`, value `0x2`), one of
  the bitmask flags passed as `h2o_file_register`'s last argument.
- **Current file**: `c_src/h2o_wrapper.c` — the `h2o_file_register(...)` call
  (inside `start_h2o_server`) currently passes only
  `H2O_FILE_FLAG_SEND_COMPRESSED`.
- **What to change**: make this opt-in **per static path**, not global — an
  accidentally-exposed directory listing is a real footgun. That means
  `Daho.serveStatic(virtualPath, localDirectory)` needs a new parameter (e.g.
  `enableDirectoryListing: bool`), threaded through `add_static_path`'s FFI
  call and the `static_dir_t` struct (`h2o_wrapper.h`) so each registered
  static dir can independently OR in `H2O_FILE_FLAG_DIR_LISTING`.
- **Verify**: `cmake --build c_src/build`, restart a test server with
  `serveStatic('/files', someDir, enableDirectoryListing: true)`, `curl
  http://localhost:PORT/files/` with no `index.html` present — should return
  an HTML directory index instead of 404.

## 2. TLS session resumption

**Status: ❌ not started. Readily exposable, no new dependency.**

- **H2O API**: `h2o_socket_ssl_async_resumption_setup_ctx(SSL_CTX *ctx)`
  (`h2o/socket.h:302`) for session-ticket-style resumption, or
  `h2o_socket_ssl_get_session_cache`/`h2o_socket_ssl_set_session_cache`
  (`h2o/socket.h:319,323`) for an explicit cache. Both confirmed exported in
  `libh2o-evloop.a`.
- **Current file**: `c_src/h2o_wrapper.c`'s `build_tls_context(cert_path,
  key_path)` function (added this release for native TLS) — call one of these
  right after `SSL_CTX_new`, before `h2o_ssl_register_alpn_protocols`.
- **Verify**: `openssl s_client -connect localhost:PORT -reconnect` (or two
  successive `curl -k` requests with `--tls-max` pinned) and confirm the
  second handshake resumes (look for `Reused, TLSv1.3` or a shorter handshake
  in `-debug` output) rather than a full renegotiation.

## 3. HTTP/2 server push

**Status: ❌ not started. Readily exposable, no new dependency.**

- **H2O API**: `h2o_push_path_in_link_header(h2o_req_t *req, const char
  *value, size_t len)` (`h2o.h:1491`), which parses a `Link:` response header
  for `rel=preload` entries and pushes them. Also requires
  `hostconf.http2.push_preload` (`h2o.h:284-286`) to be enabled on the
  hostconf.
- **Current file**: `c_src/h2o_wrapper.c`'s `dart_route_handler` (or the
  response-writing path in `on_pipe_read`) — call
  `h2o_push_path_in_link_header` when the Dart-supplied response headers
  include a `Link` header with `rel=preload`.
- **Gotcha**: push only activates over an HTTP/2 connection — it silently
  no-ops on HTTP/1.x, so this is naturally gated behind the TLS+ALPN work
  already shipped (H2O only negotiates `h2` over TLS in this setup; there's no
  h2c/cleartext-upgrade path configured).
- **Verify**: `curl -k --http2 -v` against a route that sets a `Link:
  </style.css>; rel=preload` header; H2O's own debug logging or a browser's
  Network tab (pushed resources show as "Push / Other") confirms it landed.

## 4. Reverse proxy

**Status: ❌ not started. Readily exposable, no new dependency — but H2O's
function is single-upstream, not a load balancer.**

- **H2O API**: `h2o_proxy_register_reverse_proxy(h2o_pathconf_t *pathconf,
  h2o_url_t *upstream, h2o_proxy_config_vars_t *config)` (`h2o.h:1825`),
  confirmed exported (`T _h2o_proxy_register_reverse_proxy` in the `.a`). This
  is H2O core's real proxy implementation (`lib/proxy.c`), not the
  mruby-scripted config-file feature — no mruby/libh2o-standalone needed.
- **Current file**: `c_src/h2o_wrapper.c` — register it against an
  `h2o_pathconf_t` the same way `h2o_file_register` is registered today
  (`h2o_config_register_path` first, then this instead of/alongside
  `h2o_file_register`).
- **Dart API shape to design**: something like `app.proxy('/api',
  'http://localhost:3000')`, needing a new FFI registration call analogous to
  `add_static_path`.
- **Known limitation to document, not solve here**: the wishlist asked for
  load balancing (round robin / least connections / IP hash) across multiple
  upstreams — `h2o_proxy_register_reverse_proxy` takes exactly **one**
  upstream URL. Load balancing would need daho's own selection logic choosing
  which upstream to register per request (not something H2O gives you for
  free here), or multiple path registrations with manual round-robin in Dart
  before each request. Treat as a separate, later design problem.
- **Verify**: run a second trivial server on `:3000`, register `app.proxy('/api',
  'http://localhost:3000')`, curl the proxying server and confirm the
  response body/headers match what the upstream on `:3000` returns.

## 5. Virtual host / Host-header routing

**Status: ❌ not started. H2O API exists; daho's current design needs
generalizing (not a new dependency).**

- **H2O API**: `h2o_config_register_host(h2o_globalconf_t *config,
  h2o_iovec_t host, uint16_t port)` (`h2o.h:1335`) can be called multiple
  times against the same `h2o_globalconf_t` — each call appends another
  `h2o_hostconf_t` to the `hosts` array (`h2o.h:310-312`). This is exactly how
  H2O's own config-file server implements multiple `hosts:` blocks.
- **Current file**: `c_src/h2o_wrapper.c:422` (inside `start_h2o_server`)
  currently calls this exactly **once** per worker, hardcoded to the literal
  string `"default"` — every request hits the same hostconf regardless of the
  `Host` header. Needs a real per-host registration path (new FFI call,
  analogous to `add_static_path`/`add_fast_path`, invoked before
  `h2o_context_init`) so multiple hostconfs can be built up per worker before
  the server starts.
- **Matching mechanism** (important, don't conflate the two): H2O matches
  *HTTP requests* to a hostconf via the **Host header / `:authority`
  pseudo-header** (`h2o_hostconf_t.authority.host/port`, `h2o.h:240-262`,
  `h2o_req_t.authority`, `h2o.h:918/947`) — this is a separate mechanism from
  **TLS SNI**, which only selects which **certificate** (`SSL_CTX`) is
  presented during the handshake (`h2o/socket.h:288-335`). A real multi-tenant
  HTTPS setup needs **both**: an SNI callback selecting the right `SSL_CTX`
  per hostname, *and* multiple hostconfs matched on the Host header — don't
  assume registering hostconfs alone handles HTTPS virtual hosting.
- **Dart API shape to design**: `app.host('api.example.com', (hostApp) {
  ... })`, mirroring `app.group(prefix)`'s nested-builder shape.
- **Verify**: register two hosts on one port, `curl -H "Host:
  a.example.com"` vs `curl -H "Host: b.example.com"` against the same
  `localhost:PORT` and confirm different route tables answer.

## 6. WebSocket

**Status: ❌ not started. H2O has a full C API; needs a new library
dependency (`libwslay`) and daho's biggest FFI design gap: long-lived
connections.**

- **H2O API**: `h2o/websocket.h` — confirmed present as a real header with a
  usable API, backed by `wslay`:
  - `int h2o_is_websocket_handshake(h2o_req_t *req, const char **client_key)`
    — call from a handler's `on_req` to detect an upgrade request.
  - `h2o_websocket_conn_t *h2o_upgrade_to_websocket(h2o_req_t *req, const char
    *client_key, void *user_data, h2o_websocket_msg_callback msg_cb)` —
    completes the handshake and hands control to H2O/wslay's frame
    parsing/masking.
  - `h2o_websocket_close`, `h2o_websocket_proceed`.
  - All confirmed exported in `libh2o-evloop.a` (`_on_websocket_upgrade_complete`,
    `_on_config_websocket`, `_on_config_websocket_timeout`).
- **New dependency**: the header `#include <wslay/wslay.h>` means `wslay` is
  a real link-time dependency — confirmed **not** currently linked
  (`otool -L libh2o-evloop.dylib` shows only libz/libssl/libcrypto/libSystem).
  It's installed alongside H2O via Homebrew already (H2O itself depends on
  it), so this is "add `find_library`/`find_package` for wslay to
  `c_src/CMakeLists.txt` and link it," not "build wslay from source."
- **The hard part, flagged explicitly for whoever picks this up**: daho's
  entire current FFI model is request/response-per-call — `dart_route_handler`
  calls into Dart once, Dart eventually calls `h2o_respond_from_dart` once,
  done. A WebSocket connection is long-lived and bidirectional: the C side
  needs to invoke into Dart on *every incoming frame* (not just once), and
  Dart needs a way to push frames back out at arbitrary times (not just in
  response to an incoming call) — this needs a genuinely new callback/queue
  mechanism, not a reuse of the existing `async_response_t` ring buffer (which
  is designed for "one pending response per request," not "many small
  messages over a connection's lifetime"). Scope this as its own dedicated
  design pass — don't try to bolt it onto the existing response ring buffer.
- **Dart API shape to design** (illustrative, not binding): `app.ws('/chat',
  (socket) { socket.onMessage(...); socket.send(...); })`.
- **Verify** (once built): a simple echo server + `websocat`/browser
  `WebSocket` client round-trip.

## 7. Compression — gzip done, Brotli blocked on H2O's own build

**Status: gzip ✅ done (`Middlewares.compress`, dynamic responses; H2O's
`H2O_FILE_FLAG_SEND_COMPRESSED` for precompressed static files). Brotli ❌ not
possible without rebuilding H2O itself.**

- **Why Brotli can't just be "added" from daho's side**: `h2o.h:54-56`
  hardcodes `#define H2O_USE_BROTLI 0` for any build except H2O's own
  standalone server ("disabled for all but the standalone server, since the
  encoder is written in C++"). `h2o_compress_brotli_open` (`h2o.h:1642`) is
  *declared* in the header regardless, but confirmed **absent** from the
  linked `libh2o-evloop.a` (`nm libh2o-evloop.a | grep -i brotli` → no
  matches) — calling it against the current build is an undefined-symbol
  link error, not a runtime failure.
- **What it would actually take**: H2O rebuilt from source with
  `H2O_USE_BROTLI=1`, which pulls in Google's C++ brotli encoder as a build
  dependency of H2O itself — this is a prerequisite change to how H2O is
  *built and distributed* for this project (no longer `brew install h2o`),
  not a change to `daho`'s own `c_src/CMakeLists.txt`. Document as
  blocked-on-external, revisit only if/when the project moves to building H2O
  from source anyway (e.g. for HTTP/3, see §8).

## 8. HTTP/3 / QUIC

**Status: ❌ not started. Blocked on an entirely different H2O build/version
— not a small addition.**

- **Confirmed absent**: zero QUIC/H3 symbols anywhere in the installed H2O
  2.2.6 headers or `.a` (`grep -i "quic\|http3\|h3\b"` across `h2o.h`/`h2o/*.h`
  → 0 matches; `nm libh2o-evloop.a | grep -i "quic|picotls|quicly"` → 0
  matches; `otool -L` shows no quicly/picotls linked). Homebrew's `h2o`
  formula (2.2.6) predates H2O's QUIC/HTTP3 support entirely.
- **What it would actually take**: sourcing/building a materially newer H2O
  from its git repo with `quicly`+`picotls` submodules enabled, then reworking
  `c_src/CMakeLists.txt`'s `find_library`/linking from scratch to pick up
  those new libraries plus whatever new headers/APIs that H2O version exposes
  for QUIC listener setup. Treat as a multi-week research-and-build
  undertaking on its own, not something to slot in alongside the other items
  in this document. **Not scheduled** until a newer H2O build is sourced.

## 9. Multipart streaming

**Status: 🚧 partial (buffered, not streamed). Bigger architectural change
than the H2O-native items above — not a quick win.**

- **Current behavior**: the *entire* request body is read by the C layer and
  handed to Dart as one `Uint8List` (`lib/src/ffi/handler.dart:53-58`) before
  `parseMultipart` (`lib/src/ffi/multipart.dart:29-82`) copies that whole
  buffer into native memory and scans it with `memmem`. Bounded only by
  `DahoConfig.bodyLimit` (default 4 MB), enforced by H2O *before* the body is
  even read (`413` rejected upstream of Dart entirely).
- **What true streaming would require**: H2O would need to hand body chunks
  to the C wrapper incrementally (via H2O's own streaming-request-body
  callback mechanism, not the current "wait for the whole body, then call
  Dart once" flow), and the multipart parser would need to become an
  incremental state machine consuming chunks rather than one-shot `memmem`
  scanning over a complete buffer. This touches the same request-lifecycle
  assumptions flagged in §6 (WebSocket) — both need "C can call into Dart more
  than once per request," which nothing in daho's current design supports.
  Consider designing that primitive once, for both features, rather than
  twice.

## 10. Rate limiter middleware

**Status: ❌ not started. Pure Dart, no H2O involvement.**

- Same shape as existing `Middlewares.logger`/`Middlewares.compress`
  (`lib/src/middleware.dart`) — a `Middleware` closure checking a per-key
  (e.g. `req.ip`) counter/token-bucket before calling `next()`, else
  `res.status(429).json(...)`.
- Start with an in-memory sliding-window or token-bucket store (a `Map<String,
  ...>` is enough for a first version); leave room for a pluggable store
  interface so a Redis-backed implementation can be swapped in later without
  changing the middleware's public shape (mirrors how `daho_auth`'s
  `TokenRepository`/`SessionStore` are already pluggable interfaces —
  `packages/daho_auth/lib/src/token/token_repository.dart`,
  `.../session/session_store.dart`).

## 11. Session middleware (daho core)

**Status: ❌ not started in `daho` core. Pure Dart — and most of the design
work is already done in `daho_auth`, just not exposed at the framework-core
level.**

- `packages/daho_auth` already has a full session subsystem: `SessionManager`
  (`lib/src/session/session_manager.dart`), an abstract `SessionStore`
  (`session_store.dart`), and `PostgresSessionStore`. Reuse this
  pattern/interface rather than designing a new one from scratch.
- What's missing for `daho` core: an in-memory `SessionStore` implementation
  for apps that want sessions without pulling in all of `daho_auth`
  (Postgres, JWT, OAuth), plus middleware wiring (`req.session`) at the core
  `daho` level.

## 12. Server-Sent Events (SSE)

**Status: ❌ not started. Blocked on a streaming response primitive that
doesn't exist yet — do not attempt before that lands.**

- `DahoResponse` (`lib/src/response.dart`) only ever builds one final
  `bodyBytes`/`_bodyText` value — there is no `res.write(chunk)` /
  flush-and-keep-connection-open primitive anywhere. SSE fundamentally needs
  one (a long-lived response the server keeps writing `event: ...\ndata:
  ...\n\n` chunks to). Building that primitive is a prerequisite for this
  item, not part of it — likely shares infrastructure with the "C can call
  into Dart / Dart can push out-of-band" problem flagged in §6 and §9.

## 13. OCSP stapling

**Status: ❌ not started. Plain OpenSSL — H2O has no API for this at all
(confirmed: zero matches for `ocsp`/`stapling`/`tlsext_status` anywhere in
`h2o.h`/`h2o/*.h`).**

- Implement directly against OpenSSL (already linked via `find_package(OpenSSL
  REQUIRED)` in `c_src/CMakeLists.txt`): `SSL_CTX_set_tlsext_status_cb` +
  `SSL_CTX_set_tlsext_status_arg`, added in `build_tls_context` alongside the
  existing cert/key loading. Lower priority than the H2O-native TLS items
  (§2) since there's no H2O convenience API to lean on here — it's standard,
  somewhat fiddly OpenSSL work end to end (fetching/caching the OCSP response
  from the CA, refreshing before expiry).

## 14. Pure-Dart framework ergonomics & DX (grouped — each independent, no native changes)

- **Named routes + URL generation** — no `name:`/`as:` param exists on any
  route-registration method today, no reverse-routing function anywhere.
  Add a `name` param to `get`/`post`/etc., store name→path in `RouteRegistry`,
  add a `router.url('name', {'id': 10})` helper that substitutes `:param`
  segments.
- **Route param type constraints / wildcards** — `RouterTrie` (`router.dart`)
  only has `staticChildren`/one untyped `paramChild` per node; no `<int>`
  syntax, no `*`/`**` catch-all segment. Both would extend `RouteNode`/`insert`/
  `_searchNode`.
- **Nested route groups** — `DahoGroup` (`app.dart:25-71`) has no `.group()`
  of its own; a group can't contain a sub-group today. Small addition:
  `DahoGroup.group(prefix)` returning a child `DahoGroup` that concatenates
  prefixes and merges middleware lists.
- **Per-route timeout middleware** — only global `DahoConfig.requestTimeout`/
  `idleTimeout` exist (forwarded straight to H2O). A per-route version would
  be pure Dart: a `Middleware` racing the downstream `next()` call against a
  `Future.delayed`.
- **Typed/validated request body decoding** — `req.body` is untyped `dynamic`
  today; no `@JsonSerializable`-driven decode/validate layer.
- **Minimal DI/service locator** — nothing like `ctx.get<T>()` exists;
  would be a new, fairly opinionated addition — worth a dedicated design
  discussion on scope (simple service locator vs. a fuller DI container)
  before implementing.
- **OpenAPI/swagger generation** — nothing exists; would likely be a
  `build_runner` generator (matching the pattern already used by `clurit`'s
  own generator) scanning route registrations/handler signatures.
- **`daho_cli` hot reload** — `daho run` has no `--watch`/reload flag today
  (`packages/daho_cli/lib/src/commands/run_command.dart`); already flagged in
  `packages/daho/README.md`'s Roadmap section as a known gap.
- **`daho bench` / `daho profile` CLI commands** — don't exist as CLI
  commands today, but the underlying instrumentation already exists: the
  internal `Profiler` class (`lib/src/profiler.dart`, gated by
  `DAHO_PROFILE=1`, printing req/s, p50/p99, RSS per worker) — a `daho
  profile` command could just be a thin CLI wrapper that sets that env var and
  runs the app, rather than building profiling from scratch.

---

## Summary table

| # | Feature | Native (H2O) or pure Dart | Blocked on external work? |
|---|---|---|---|
| 1 | Directory listing | Native, no new dep | No |
| 2 | TLS session resumption | Native, no new dep | No |
| 3 | HTTP/2 server push | Native, no new dep | No |
| 4 | Reverse proxy | Native, no new dep (single-upstream only) | No |
| 5 | Virtual hosts | Native, needs restructuring | No |
| 6 | WebSocket | Native, needs `libwslay` + new FFI model | No, but biggest lift here |
| 7 | Brotli | Native | **Yes** — needs H2O rebuilt with `H2O_USE_BROTLI=1` |
| 8 | HTTP/3 | Native | **Yes** — needs a materially different H2O build/version |
| 9 | Multipart streaming | Native, needs new FFI model | No, but big lift (shares design with §6) |
| 10 | Rate limiter | Pure Dart | No |
| 11 | Session (core) | Pure Dart (reuse `daho_auth` pattern) | No |
| 12 | SSE | Pure Dart | Blocked on a streaming-response primitive (shares design with §6/§9) |
| 13 | OCSP stapling | OpenSSL, not H2O | No |
| 14 | Named routes/wildcards/nested groups/timeouts/DI/OpenAPI/CLI | Pure Dart | No |
