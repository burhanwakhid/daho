---
layout: home
hero:
  name: Daho
  text: Fast HTTP Framework for Dart
  tagline: Backed by native H2O server via FFI. Express-style API. Multi-core out of the box.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/nicholasnbg/daho
features:
  - icon: ⚡
    title: Native Core
    details: Request handling runs on H2O, a high-performance C HTTP server, connected via Dart FFI. One worker Isolate per CPU core sharing the socket via SO_REUSEPORT.
  - icon: 🛤️
    title: Fast Routing
    details: O(1) map lookup for static paths, radix trie for parameterized routes with :param segments. Automatic 405 Method Not Allowed with Allow header.
  - icon: 🧩
    title: Express-style API
    details: Familiar API inspired by Express.js and Fiber. app.get(), route groups, global/group/per-route middleware, and chainable responses.
  - icon: 🔀
    title: Multi-core
    details: Automatically spawns one worker Isolate per CPU core. Configurable concurrency for containers with CPU quotas.
  - icon: 🛡️
    title: Built-in Middleware
    details: Logger, CORS with preflight handling, Helmet-style security headers, and gzip compression — ready to use.
  - icon: 🧪
    title: In-process Testing
    details: DahoTester runs requests through the real dispatch path without booting the native server. Test middleware, routing, and error handling.
---

## Quick Start

```dart
import 'package:daho/daho.dart';

void setupRoutes(Daho app) {
  app.use(Middlewares.logger());
  app.get('/', (req, res) => res.ok({'hello': 'world'}));
  app.get('/users/:id', (req, res) => res.ok({'id': req.params['id']}));
  app.post('/users', (req, res) => res.status(201).json(req.body));
}

void main() {
  final app = Daho(config: const DahoConfig(bodyLimit: 8 * 1024 * 1024));
  app.listen(8080, routes: setupRoutes, onStart: () => print('http://127.0.0.1:8080'));
}
```

## Performance

~96k req/s on macOS M-series (single-worker due to macOS `SO_REUSEPORT` limitation). Multi-worker on Linux scales linearly with cores.
