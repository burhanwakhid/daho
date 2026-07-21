---
layout: home
hero:
  name: Daho
  text: The fast HTTP framework for Dart
  tagline: A native H2O core over FFI, an Express-style API you already know, and multi-core scaling out of the box — build production backends in pure Dart.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: Why Daho?
      link: /guide/getting-started#why-daho
    - theme: alt
      text: View on GitHub
      link: https://github.com/burhanwakhid/daho
features:
  - icon: ⚡
    title: Native H2O Core
    details: Request handling runs on H2O — a high-performance C HTTP server — connected through Dart FFI. One worker Isolate per CPU core shares the socket via SO_REUSEPORT.
    link: /guide/getting-started#why-daho
    linkText: How it works
  - icon: 🛤️
    title: Blazing-Fast Routing
    details: O(1) map lookup for static paths and a radix trie for :param routes. Automatic 405 Method Not Allowed with a correct Allow header — no config needed.
    link: /guide/routing
    linkText: Routing guide
  - icon: 🧩
    title: Express-Style API
    details: A familiar API inspired by Express.js and Fiber — app.get(), route groups, global / group / per-route middleware, and chainable responses.
    link: /guide/request-response
    linkText: Request & Response
  - icon: 🔀
    title: Multi-Core by Default
    details: Automatically spawns one worker Isolate per CPU core, each running its own native server. Tune concurrency explicitly for containers with CPU quotas.
    link: /guide/configuration#concurrency
    linkText: Configuration
  - icon: 🛡️
    title: Batteries Included
    details: Logger, CORS with preflight handling, Helmet-style security headers, gzip compression, cookies, and body parsing (JSON, urlencoded, multipart) — ready to use.
    link: /guide/middleware
    linkText: Middleware
  - icon: 🧪
    title: In-Process Testing
    details: DahoTester drives requests through the real dispatch path — middleware, routing, 404 / 405, error handling — without booting the native server.
    link: /guide/testing
    linkText: Testing guide
  - icon: 📦
    title: Zero-Copy Static Files
    details: serveStatic() hands files to H2O's kernel-level file handler. Data goes straight from disk to socket, never touching Dart's heap.
    link: /guide/static-files
    linkText: Static files
  - icon: 🧰
    title: First-Class CLI
    details: Scaffold projects, build the native library, run servers, and diagnose your toolchain with the daho command — plus a ready-to-ship Dockerfile.
    link: /guide/cli
    linkText: CLI reference
  - icon: 🚀
    title: Container Ready
    details: Deploy anywhere Dart runs on Linux. A generated Dockerfile, graceful shutdown draining, and trust-proxy support make production deploys painless.
    link: /guide/deployment
    linkText: Deployment
---

<div class="daho-section" style="margin-top: 64px;">

<h2 class="daho-section-title">Hello, world — in ten lines</h2>
<p class="daho-section-subtitle">A familiar, ergonomic API. If you've used Express or Fiber, you already know Daho.</p>

```dart
import 'package:daho/daho.dart';

// Route setup MUST be a top-level function — it re-runs on every worker Isolate.
void setupRoutes(Daho app) {
  app.use(Middlewares.logger());                                   // access log
  app.get('/', (req, res) => res.ok({'hello': 'world'}));          // 200 JSON
  app.get('/users/:id', (req, res) => res.ok({'id': req.params['id']}));
  app.post('/users', (req, res) => res.status(201).json(req.body)); // echo body
}

void main() {
  final app = Daho(config: const DahoConfig(bodyLimit: 8 * 1024 * 1024));
  app.listen(8080, routes: setupRoutes, onStart: () => print('http://127.0.0.1:8080'));
}
```

</div>

<div class="daho-section" style="margin-top: 64px;">

<h2 class="daho-section-title">Up and running in three steps</h2>
<p class="daho-section-subtitle">Install the native toolchain once, add the package, and run.</p>

<div class="daho-steps">
  <div class="daho-step">
    <span class="num">1</span>
    <h4>Install the toolchain</h4>
    <p>Daho's core is native. On macOS: <code>brew install h2o cmake</code>. On Debian/Ubuntu: <code>apt-get install libh2o-evloop-dev cmake</code>.</p>
  </div>
  <div class="daho-step">
    <span class="num">2</span>
    <h4>Add the package</h4>
    <p>Run <code>dart pub add daho</code>, or scaffold a full project with the CLI: <code>daho create my_api</code>.</p>
  </div>
  <div class="daho-step">
    <span class="num">3</span>
    <h4>Build &amp; run</h4>
    <p>The CLI compiles the native library on first run: <code>daho run</code>. That's it — your server is live.</p>
  </div>
</div>

</div>

<div class="daho-section" style="margin-top: 64px;">

<h2 class="daho-section-title">Built for speed</h2>
<p class="daho-section-subtitle">A C event loop does the heavy lifting; Dart handles your logic.</p>

<div class="daho-stats">
  <div class="daho-stat">
    <div class="value">~96k</div>
    <div class="label">req/s on Apple M-series (single worker)</div>
  </div>
  <div class="daho-stat">
    <div class="value">O(1)</div>
    <div class="label">static route lookup</div>
  </div>
  <div class="daho-stat">
    <div class="value">1 : core</div>
    <div class="label">worker Isolate per CPU core</div>
  </div>
  <div class="daho-stat">
    <div class="value">0-copy</div>
    <div class="label">static file serving via H2O</div>
  </div>
</div>

<p class="daho-section-subtitle" style="margin-top:20px; font-size: 14px;">
Multi-worker scaling is linear with cores on Linux. On macOS a single worker is used because of an <code>SO_REUSEPORT</code> limitation.
<a href="/daho/guide/performance">See the performance guide →</a>
</p>

</div>

<div class="daho-section" style="margin: 72px auto 40px;">
  <div class="daho-cta">
    <h3>Ready to build?</h3>
    <p>Go from zero to a running API in minutes.</p>
    <div class="daho-cta-buttons">
      <a class="primary" href="/daho/guide/getting-started">Read the guide</a>
      <a class="secondary" href="/daho/guide/examples">Browse examples</a>
      <a class="secondary" href="https://github.com/burhanwakhid/daho">Star on GitHub</a>
    </div>
  </div>
</div>
