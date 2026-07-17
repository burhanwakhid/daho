# Benchmarking & profiling Daho

Two instruments ship for measuring performance, plus the usual external load
generator (`wrk`).

## 1. Load + latency (client side) — `wrk`

```bash
wrk -t12 -c400 -d30s --latency http://127.0.0.1:8081/json
```

Gives throughput and the client-observed latency distribution (includes the
kernel/loopback and connection queueing, not just the framework).

## 2. Server-side cost (per worker) — built-in profiler

Set `DAHO_PROFILE=1` and each worker prints, every 2 s:

```
[daho-prof w9] 96881 req/s | p50=25us p99=25us max=1.4ms | rss=235MB | total=770k
```

- `req/s`   — requests this worker completed in the interval.
- `p50/p99` — time spent **in Dart** (dispatch + response marshalling). Excludes
  the kernel/network time that `wrk` also measures.
- `max`     — worst in-Dart time in the interval (GC pauses show up here).
- `rss`     — process resident memory.

```bash
DAHO_PROFILE=1 dart run example/daho_example.dart
```

The profiler uses integer-microsecond timestamps (no per-request allocation) so
it does not perturb the GC measurement.

## 3. GC / heap — `tool/gc_probe.dart`

Measures garbage-collection activity across all Isolates while a load test runs.

```bash
# 1. start the server with the VM service enabled
dart run --enable-vm-service=8181 --disable-service-auth-codes \
  example/daho_example.dart

# 2. run the load test, then sample GC for N seconds
dart run tool/gc_probe.dart http://127.0.0.1:8181/ 20
```

> Note: attaching the VM service perturbs latency; use it to study GC, and use
> `wrk` alone for clean throughput/latency numbers.

## Baseline (2026-07, macOS, M-series, 10 cores, `/json` dynamic handler)

| Metric | Value |
| --- | --- |
| Throughput | ~96k req/s |
| Latency p50 / p99 (wrk) | 3.9 ms / 6.8 ms |
| In-Dart time per request | < 25 µs (p50 = p99) |
| RSS | ~235 MB |

### Key finding: load is not distributed on macOS

The profiler shows **only one worker** receives connections — on macOS
`SO_REUSEPORT` does not load-balance across the per-worker listening sockets, so
the "cluster" effectively runs on a single worker (H2O evloop thread + one Dart
isolate ≈ 2 cores) while the other workers sit idle.

Consequences:
- The Dart request path is cheap (~25 µs); it is **not** the bottleneck.
- The latency tail comes mostly from kernel/loopback + that one worker's GC
  pauses (visible as `max` spikes), which stall all traffic because everything
  runs on one worker.
- There is large headroom: distributing accepts across workers should scale
  throughput several-fold. Linux `SO_REUSEPORT` load-balances in the kernel, so
  behaviour there must be measured separately before optimizing.
