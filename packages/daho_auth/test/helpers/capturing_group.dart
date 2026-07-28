import 'package:daho/daho.dart';

/// A [DahoGroup] stand-in that captures registered handlers instead of
/// wiring them into daho's global route trie.
///
/// daho's router internals (`RouteRegistry`, route dispatch) aren't part of
/// the framework's public API, and spinning up the real native HTTP server
/// per test is far too heavy for unit tests. `DahoGroup` is a plain
/// (non-`final`) class whose `get`/`post`/etc. methods are ordinary virtual
/// methods, so overriding them here lets us capture each handler as a plain
/// `Function` value — invoking it isn't a privacy violation even when the
/// underlying method (e.g. `AuthRoutes._register`) is library-private,
/// because we never reference the private name, only the function value
/// `register()` handed us through its public signature.
class CapturingGroup extends DahoGroup {
  CapturingGroup([super.prefix = '']);

  final Map<String, RouteHandler> handlers = {};
  final Map<String, List<Middleware>> middlewares = {};

  RouteHandler operator [](String key) {
    final handler = handlers[key];
    if (handler == null) {
      throw StateError(
        'No handler captured for "$key". Captured: ${handlers.keys}',
      );
    }
    return handler;
  }

  @override
  void get(String path, RouteHandler handler, {List<Middleware> use = const []}) {
    handlers['GET $path'] = handler;
    middlewares['GET $path'] = use;
  }

  @override
  void post(String path, RouteHandler handler, {List<Middleware> use = const []}) {
    handlers['POST $path'] = handler;
    middlewares['POST $path'] = use;
  }

  @override
  void put(String path, RouteHandler handler, {List<Middleware> use = const []}) {
    handlers['PUT $path'] = handler;
    middlewares['PUT $path'] = use;
  }

  @override
  void delete(String path, RouteHandler handler, {List<Middleware> use = const []}) {
    handlers['DELETE $path'] = handler;
    middlewares['DELETE $path'] = use;
  }

  @override
  void patch(String path, RouteHandler handler, {List<Middleware> use = const []}) {
    handlers['PATCH $path'] = handler;
    middlewares['PATCH $path'] = use;
  }
}
