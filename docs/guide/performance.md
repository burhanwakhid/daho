# Performance

Daho is fast because most of the work happens in C. This page explains where the speed comes from, the numbers we've measured, and how to get the most out of it.

## Where the speed comes from

```
        ┌─────────────────────────────────────────────┐
        │                Your Dart code                │
        │      routes · middleware · handlers          │
        └───────────────────▲─────────────────────────┘
                            │ FFI
        ┌───────────────────┴─────────────────────────┐
        │           Native H2O event loop (C)          │
        │  socket accept · HTTP parsing · file serving │
        └───────────────────▲─────────────────────────┘
                            │ SO_REUSEPORT
        ┌───────────────────┴─────────────────────────┐
        │   N worker processes/Isolates — one per CPU  │
        └─────────────────────────────────────────────┘
```

- **Native core** — connection accept, HTTP parsing, and I/O run on [H2O](https://h2o.examp1e.net/), a mature high-performance C server. Dart is only invoked for your route logic.
- **Multi-core by default** — one worker Isolate per CPU core, each with its own native server, all sharing the listening socket via `SO_REUSEPORT`. The kernel load-balances connections across workers.
- **O(1) routing** — static paths resolve through a hash map; parameterized (`:param`) routes use a radix trie.
- **Lazy body parsing** — the request body is decoded only when you first touch `req.body` or `req.files`. Routes that ignore the payload pay nothing.
- **Pooled request/response objects** — `DahoRequest` and `DahoResponse` instances are recycled between requests to cut allocation churn and GC pressure.
- **Zero-copy static files** — `serveStatic()` hands files to H2O's kernel-level file handler; bytes go from disk to socket without entering Dart's heap.

## Measured throughput

~**96k req/s** on an Apple M-series laptop with a single worker (macOS is limited to one worker by an `SO_REUSEPORT` restriction).

On **Linux**, throughput scales close to linearly with core count because each core runs an independent worker over a shared socket.

::: info
Numbers depend heavily on hardware, payload size, and what your handler does. Always benchmark your own workload before drawing conclusions.
:::

## How Daho compares

A [manually-triggered CI benchmark](https://github.com/burhanwakhid/daho/blob/master/.github/workflows/benchmark.yml) load-tests Daho against Dart `shelf` and Go Fiber on identical terms — same `/json` route, same response body, no logging/extra middleware, all three AOT-compiled (not JIT'd), all three clustered across every core (Daho/`shelf` via one-Isolate-per-core, Fiber via `Prefork`). Latest run, GitHub Actions `ubuntu-latest` (4 cores), 250 connections, 15s per target:

| Target | Requests/sec | p50 | p99 | RSS (before → after) | OS processes / threads |
| --- | --- | --- | --- | --- | --- |
| **Daho** | 124,149 | 1.78 ms | 4.98 ms | 10.1 → 25.2 MB | 1 / 15 |
| `shelf` | 35,394 | 6.66 ms | 11.96 ms | 9.5 → 45.3 MB | 1 / 9 |
| Go Fiber | 169,741 | 1.23 ms | 5.36 ms | 55.8 → 73.4 MB | 5 / 32 |

Takeaways:

- **~3.5× faster than `shelf`**, with roughly a third of the latency — Daho's native H2O core gives it a request-handling fast path pure-Dart frameworks don't have.
- **Fiber is still faster in raw throughput** (~37% more req/s), consistent with fasthttp's maturity — but Daho reaches ~73% of Fiber's throughput while using **2–3× less resident memory** and a single OS process (15 threads) versus Fiber's 5 forked processes (`Prefork`, 32 threads total). Which matters more depends on your deployment — raw req/s, or memory/process footprint per container.

Full methodology, RSS accounting details, and how to run it yourself: [`BENCHMARK.md`](https://github.com/burhanwakhid/daho/blob/master/packages/daho/BENCHMARK.md).

### Same `SO_REUSEPORT` trick, cheaper execution model

Go Fiber's `Prefork` mode forks one OS process per core, each binding the same port with `SO_REUSEPORT` — the kernel then load-balances incoming connections across all of them. Daho reaches for the exact same kernel feature (`c_src/h2o_wrapper.c`, `setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, ...)`), but applies it per **worker Isolate** instead of per **forked process**. `SO_REUSEPORT` doesn't care which of the two it's given — it load-balances across every socket registered on that port, whether they belong to separate processes or separate threads within one process.

That's the whole story behind the benchmark table above: Daho gets Fiber's kernel-level connection distribution **without forking**. One OS process, N Isolates, N native H2O event loops sharing one listening socket — versus Fiber's N separate OS processes doing the same job. It's why Daho reaches ~73% of Fiber's throughput while using 2-3× less resident memory and a fifth of the OS process count: both are paying for the same mechanism, but Daho's unit cost per worker is lower.

Nothing stops running Daho the Fiber way too — the socket-level plumbing already sets `SO_REUSEPORT`, so launching several separate `daho_example`-style binaries against the same port would coexist and load-balance identically. There's just no evidence yet that doing so would beat the current Isolate model, given it already gets the same kernel benefit for less.

## Native fast paths

For responses that never change — health checks, status endpoints, fixed payloads — register a `fastPath`. It's served entirely in C and never enters the Dart pipeline (no routing, no middleware):

```dart
app.fastPath('/healthz', '{"status":"ok"}', contentType: 'application/json');
app.fastPath('/ping', 'pong');
```

This is the single fastest response Daho can produce. Use it for anything hot and static.

::: warning
Fast paths skip **all** middleware — no auth, logging, or CORS runs. If an endpoint needs any of those, use a regular route.
:::

## Tuning concurrency

By default Daho spawns one worker per CPU core. Two cases where you should override it:

**Containers with a CPU quota** — `Platform.numberOfProcessors` reports host cores, not the cgroup limit. Set `concurrency` to your allocation:

```dart
final app = Daho(config: const DahoConfig(concurrency: 4));
```

**CPU-bound handlers** — if handlers do heavy synchronous work, more workers than cores won't help and may hurt. Start at core count and measure.

The value is clamped to `[1, 64]`.

## Handler-level tips

- **Avoid blocking the event loop.** Long synchronous work stalls a worker. Keep handlers async and offload CPU-heavy tasks.
- **Don't read the body you don't need.** Body parsing is lazy — leave `req.body` untouched on routes that don't use it.
- **Prefer `res.json(...)` for JSON.** It encodes straight to UTF-8 bytes in one pass.
- **Enable compression selectively.** `Middlewares.compress()` saves bandwidth but costs CPU. It only kicks in above `minLength` (default 1 KB) and when the client accepts gzip — tune the threshold for your payloads.
- **Serve assets with `serveStatic()`,** not by reading files in a handler — you'll get zero-copy I/O for free.

## Benchmarking your app

Use a load generator like [`wrk`](https://github.com/wg/wrk) or [`oha`](https://github.com/hatoo/oha):

```bash
# 4 threads, 128 connections, 30 seconds
wrk -t4 -c128 -d30s http://127.0.0.1:8080/

# with oha
oha -z 30s -c 128 http://127.0.0.1:8080/
```

Run the load generator on a **different machine** (or at least separate cores) from the server so they don't contend, and warm up before measuring.

## Next Steps

- [Configuration](/guide/configuration) — `concurrency`, timeouts, body limits
- [Static Files](/guide/static-files) — `serveStatic()` and `fastPath()`
- [Deployment](/guide/deployment) — production sizing and containers
