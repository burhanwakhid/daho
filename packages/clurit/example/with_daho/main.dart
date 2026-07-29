import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:daho/daho.dart';
import 'package:clurit_daho/clurit_daho.dart';
import 'clurit_components.g.dart';

void setupRoutes(Daho app) {
  // Resolve views path
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final viewsPath = p.join(scriptDir, 'views');

  // Configure Clurit (still used for any plain, non-interactive templates).
  // `cluritComponents` is generated from every @code-bearing .clurit file
  // under views/ — see clurit_routes.yaml / CluritRoutesBuilder — so no
  // per-page `app.registerComponent(...)` call is needed by hand.
  app.configureClurit(
      viewsPath: viewsPath, debug: true, components: cluritComponents);

  // Serve static files (for the compiled client bundle). Mounted under
  // /js rather than '/' — daho's serveStatic and a `.get('/', ...)` route
  // can't share the same prefix (H2O's static file handler claims '/'
  // for every request before the Dart router ever runs, 404ing on the
  // root path since no index.html exists there).
  final webPath = p.join(scriptDir, 'web');
  app.serveStatic('/js', webPath);

  app.get('/', (req, res) {
    // 'index' resolves to the registered component factory above, so
    // this call site looks exactly like rendering a plain Blade template
    // — the backend can pass whatever data it wants, request-derived or
    // otherwise, without the route handler needing to know the
    // component's constructor shape.
    return res.view('index', data: {'message': 'Hello from the backend!'});
  });

  // A second interactive page, purely to demonstrate code-split client
  // bundles: web/main.dart deferred-imports each page's *.clurit.client.dart
  // so only the current page's component code is fetched on first load.
  app.get('/greeter', (req, res) {
    return res.view('greeter');
  });

  // Fetches https://jsonplaceholder.typicode.com/posts client-side on
  // mount (see posts.clurit's onInit), with loading/success/error $state.
  app.get('/posts', (req, res) {
    return res.view('posts');
  });
}

void main() {
  final app = Daho();

  print('Server starting on http://localhost:8088');
  app.listen(8088, routes: setupRoutes);
}
