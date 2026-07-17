import 'dart:async';

import 'request.dart';
import 'response.dart';

/// Called by a middleware to pass control to the next handler in the chain.
typedef NextFunction = Future<void> Function();

/// A middleware runs before the route handler and may short-circuit the chain
/// by not calling [next].
typedef Middleware =
    FutureOr<void> Function(
      DahoRequest req,
      DahoResponse res,
      NextFunction next,
    );

/// A terminal route handler that produces the response.
typedef RouteHandler =
    FutureOr<DahoResponse> Function(DahoRequest req, DahoResponse res);

// -----------------------------------------------------------------------------
// Radix trie for dynamic (parameterized) routes
// -----------------------------------------------------------------------------

/// A single node in the routing trie.
class RouteNode {
  /// Children matched by an exact path segment.
  final Map<String, RouteNode> staticChildren = {};

  /// Child that matches any segment and binds it to [paramName].
  RouteNode? paramChild;

  /// Name of the path parameter captured by [paramChild].
  String? paramName;

  /// Handler registered at this node, if it terminates a route.
  RouteHandler? compiledHandler;
}

/// A prefix trie that matches request paths and captures `:param` segments.
class RouterTrie {
  final RouteNode root = RouteNode();

  /// Registers [handler] for [path]. Segments starting with `:` are treated as
  /// path parameters.
  void insert(String path, RouteHandler handler) {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    RouteNode current = root;

    for (final segment in segments) {
      if (segment.startsWith(':')) {
        current.paramName = segment.substring(1);
        current.paramChild ??= RouteNode();
        current = current.paramChild!;
      } else {
        current.staticChildren[segment] ??= RouteNode();
        current = current.staticChildren[segment]!;
      }
    }
    current.compiledHandler = handler;
  }

  /// Finds the handler for [path], returning it together with any captured
  /// path parameters, or null if no route matches.
  RouteMatch? search(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final params = <String, String>{};
    final matchNode = _searchNode(root, segments, 0, params);

    if (matchNode?.compiledHandler != null) {
      return RouteMatch(matchNode!.compiledHandler!, params);
    }
    return null;
  }

  RouteNode? _searchNode(
    RouteNode node,
    List<String> segments,
    int index,
    Map<String, String> params,
  ) {
    if (index == segments.length) return node;
    final segment = segments[index];

    // Prefer an exact (static) match, which is O(1) at each node.
    final staticChild = node.staticChildren[segment];
    if (staticChild != null) {
      final res = _searchNode(staticChild, segments, index + 1, params);
      if (res != null) return res;
    }

    // Fall back to the parameterized child, backtracking on failure.
    if (node.paramChild != null) {
      params[node.paramName!] = segment;
      final res = _searchNode(node.paramChild!, segments, index + 1, params);
      if (res != null) return res;
      params.remove(node.paramName);
    }
    return null;
  }
}

/// A route as registered by the user, before middleware chains are compiled.
class RouteEntry {
  final String method;
  final String path;
  final bool hasParams;
  final RouteHandler baseHandler;
  final List<Middleware> groupMiddlewares;

  /// The handler wrapped with its middleware chain. Populated by
  /// [RouteRegistry.compileAll].
  late RouteHandler compiledHandler;

  RouteEntry(
    this.method,
    this.path,
    this.hasParams,
    this.baseHandler,
    this.groupMiddlewares,
  );
}

/// The result of a successful route lookup.
class RouteMatch {
  final RouteHandler compiledHandler;
  final Map<String, String> params;

  RouteMatch(this.compiledHandler, this.params);
}

/// Central registry of all routes and global middleware.
///
/// Routes are collected via [addRoute] and then [compileAll] splits them into
/// two lookup structures: an O(1) map for fully static paths and a radix trie
/// for parameterized paths.
class RouteRegistry {
  static final RouteRegistry instance = RouteRegistry._internal();
  RouteRegistry._internal();

  static const _methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD'];

  final Map<String, Map<String, RouteMatch>> _staticRoutes = {
    for (final m in _methods) m: {},
  };

  final Map<String, RouterTrie> _dynamicTries = {
    for (final m in _methods) m: RouterTrie(),
  };

  final List<RouteEntry> _rawEntries = [];
  final List<Middleware> _globalMiddlewares = [];

  /// Clears all registered routes and middleware. Intended for tests that build
  /// several independent app configurations against the singleton.
  void reset() {
    for (final table in _staticRoutes.values) {
      table.clear();
    }
    for (final method in _methods) {
      _dynamicTries[method] = RouterTrie();
    }
    _rawEntries.clear();
    _globalMiddlewares.clear();
  }

  /// Registers a middleware that runs for every request.
  void addGlobalMiddleware(Middleware mw) => _globalMiddlewares.add(mw);

  /// Registers a route. [prefix] is the group prefix (may be empty) and [path]
  /// the route path; the two are joined and normalized.
  void addRoute(
    String method,
    String prefix,
    String path,
    RouteHandler handler,
    List<Middleware> groupMiddlewares,
  ) {
    String fullPath = '$prefix$path'.replaceAll(RegExp(r'//+'), '/');
    if (fullPath.endsWith('/') && fullPath.length > 1) {
      fullPath = fullPath.substring(0, fullPath.length - 1);
    }

    _rawEntries.add(
      RouteEntry(
        method,
        fullPath,
        fullPath.contains(':'),
        handler,
        List.from(groupMiddlewares),
      ),
    );
  }

  /// Compiles every registered route: wraps each handler in its group- and
  /// route-level middleware chain and files it under the static map or the
  /// dynamic trie. Must be called once after all routes are registered and
  /// before serving requests.
  ///
  /// Global middleware is applied separately via [wrapGlobal] so that it also
  /// runs for unmatched requests (404 / 405 / preflight).
  void compileAll() {
    for (final route in _rawEntries) {
      route.compiledHandler = _buildChain(
        route.groupMiddlewares,
        route.baseHandler,
      );

      if (!route.hasParams) {
        // Purely static route -> O(1) map lookup.
        _staticRoutes[route.method]?[route.path] = RouteMatch(
          route.compiledHandler,
          const {},
        );
      } else {
        // Parameterized route -> O(k) radix trie.
        _dynamicTries[route.method]?.insert(route.path, route.compiledHandler);
      }
    }
  }

  /// Wraps [terminal] in the global middleware chain. Used once per Isolate to
  /// build the top-level dispatcher, so global middleware runs for every
  /// request — including those that match no route.
  RouteHandler wrapGlobal(RouteHandler terminal) =>
      _buildChain(_globalMiddlewares, terminal);

  /// Folds [middlewares] around [baseHandler] into a single handler, so that
  /// invoking the result runs the middleware chain and then the handler.
  RouteHandler _buildChain(
    List<Middleware> middlewares,
    RouteHandler baseHandler,
  ) {
    RouteHandler next = baseHandler;
    for (int i = middlewares.length - 1; i >= 0; i--) {
      final mw = middlewares[i];
      final downstream = next;
      next = (req, res) async {
        await mw(req, res, () async => await downstream(req, res));
        return res;
      };
    }
    return next;
  }

  /// Looks up the handler for [method] and [path]. Tries the static map first,
  /// then the dynamic trie.
  RouteMatch? findRoute(String method, String path) {
    final staticMatch = _staticRoutes[method]?[path];
    if (staticMatch != null) return staticMatch;
    return _dynamicTries[method]?.search(path);
  }

  /// Returns the set of HTTP methods registered for [path]. Used to build the
  /// `Allow` header for a `405 Method Not Allowed` response. Only called on the
  /// (rare) no-match path, so the per-method scan is acceptable.
  Set<String> allowedMethodsFor(String path) {
    final allowed = <String>{};
    for (final method in _methods) {
      if (findRoute(method, path) != null) allowed.add(method);
    }
    return allowed;
  }
}
