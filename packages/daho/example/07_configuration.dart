/// 07 — Configuration
///
/// Demonstrates all DahoConfig options:
/// - bodyLimit — max request body size (default 4 MB)
/// - concurrency — number of worker Isolates (default: CPU cores)
/// - requestTimeout — per-request HTTP timeout
/// - idleTimeout — keep-alive idle timeout
/// - shutdownGracePeriod — drain time after SIGINT/SIGTERM
/// - trustProxy — use X-Forwarded-For for client IP
/// - disableStartupMessage — silence startup logs
///
/// Run:  dart run example/07_configuration.dart
library;

import 'package:daho/daho.dart';

void setupRoutes(Daho app) {
  app.get('/', (req, res) {
    return res.ok({'message': 'Configured server'});
  });
}

void main() {
  final app = Daho(
    config: const DahoConfig(
      // Max request body: 8 MB (default is 4 MB)
      bodyLimit: 8 * 1024 * 1024,

      // Worker count: set explicitly in CPU-limited containers
      // where Platform.numberOfProcessors reports host cores, not cgroup limit.
      concurrency: 4,

      // Per-request timeout (Duration.zero keeps H2O's default)
      requestTimeout: Duration(seconds: 30),

      // Keep-alive idle timeout (Duration.zero keeps H2O's default)
      idleTimeout: Duration(seconds: 120),

      // How long to drain in-flight requests after SIGINT/SIGTERM
      shutdownGracePeriod: Duration(seconds: 10),

      // Use X-Forwarded-For / X-Real-IP for req.ip
      // Enable ONLY behind a trusted reverse proxy
      trustProxy: true,

      // Silence startup/shutdown log lines
      disableStartupMessage: false,
    ),
  );

  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Configured server at http://127.0.0.1:8080'),
    onShutdown: () async {
      print('Shutting down gracefully...');
    },
  );
}
