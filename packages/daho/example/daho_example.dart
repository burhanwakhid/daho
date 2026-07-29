/// Minimal benchmark target — deliberately just one route, no logging/extra
/// middleware, so throughput numbers reflect the framework's own dispatch
/// cost rather than anything an app might add on top. Referenced by
/// `.github/workflows/benchmark.yml` and `BENCHMARK.md`.
///
/// Run:  dart run example/daho_example.dart
/// Test: curl http://127.0.0.1:8081/json
library;

import 'package:daho/daho.dart';

void setupRoutes(Daho app) {
  app.get('/json', (req, res) {
    return res.json({
      'status': 'ok',
      'items': [1, 2, 3],
    });
  });
}

void main() {
  final app = Daho();
  app.listen(
    8081,
    routes: setupRoutes,
    onStart: () => print('Server running at http://127.0.0.1:8081'),
  );
}
