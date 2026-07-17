import 'config.dart';
import 'router.dart';

/// Builds the top-level request dispatcher for a given [config].
///
/// The returned handler is the global middleware chain wrapped around route
/// matching. Because global middleware runs first, it also sees requests that
/// match no route (404 / 405 / CORS preflight). The terminal resolves the
/// route and, on a miss, returns `405` (with an `Allow` header) when the path
/// exists for other methods, or delegates to [DahoConfig.notFoundHandler].
///
/// Shared by the FFI request handler and the testing utilities so both take
/// exactly the same path.
RouteHandler buildDispatch(DahoConfig config) {
  final registry = RouteRegistry.instance;
  return registry.wrapGlobal((req, res) async {
    final match = registry.findRoute(req.method, req.path);
    if (match != null) {
      req.params = match.params;
      await match.compiledHandler(req, res);
    } else {
      final allowed = registry.allowedMethodsFor(req.path);
      if (allowed.isNotEmpty) {
        res.status(405).header('Allow', allowed.join(', ')).json({
          'error': 'Method Not Allowed',
        });
      } else {
        await config.notFoundHandler(req, res);
      }
    }
    return res;
  });
}
