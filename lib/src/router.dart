// lib/src/router.dart
import 'dart:async';
import 'dart:convert';

class DahoRequest {
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> params;
  final dynamic body;

  DahoRequest({
    required this.method,
    required this.path,
    this.query = const {},
    this.params = const {},
    this.body,
  });
}

class DahoResponse {
  int statusCode = 200;
  Map<String, String> headers = {'Content-Type': 'text/plain'};
  String bodyText = '';

  DahoResponse status(int code) {
    statusCode = code;
    return this;
  }

  DahoResponse header(String key, String value) {
    headers[key] = value;
    return this;
  }

  DahoResponse send(String data) {
    bodyText = data;
    return this;
  }

  DahoResponse json(dynamic data) {
    headers['Content-Type'] = 'application/json';
    bodyText = jsonEncode(data);
    return this;
  }
}

typedef NextFunction = Future<void> Function();
typedef Middleware =
    FutureOr<void> Function(
      DahoRequest req,
      DahoResponse res,
      NextFunction next,
    );
typedef RouteHandler =
    FutureOr<DahoResponse> Function(DahoRequest req, DahoResponse res);

class RouteEntry {
  final String method;
  final String originalPath;
  final RegExp regex;
  final List<String> paramNames;
  final RouteHandler handler;

  RouteEntry(
    this.method,
    this.originalPath,
    this.regex,
    this.paramNames,
    this.handler,
  );
}

class RouteMatch {
  final RouteHandler handler;
  final Map<String, String> params;

  RouteMatch(this.handler, this.params);
}

class RouteRegistry {
  static final RouteRegistry instance = RouteRegistry._internal();
  RouteRegistry._internal();

  final List<RouteEntry> _routes = [];
  final List<Middleware> _middlewares = [];

  void addMiddleware(Middleware mw) {
    _middlewares.add(mw);
  }

  void addRoute(String method, String path, RouteHandler handler) {
    List<String> paramNames = [];
    String regexString = path.replaceAllMapped(RegExp(r':([a-zA-Z0-9_]+)'), (
      match,
    ) {
      String paramName = match.group(1)!;
      paramNames.add(paramName);
      return '(?<$paramName>[^/]+)';
    });

    final regex = RegExp('^$regexString\$');
    _routes.add(RouteEntry(method, path, regex, paramNames, handler));
  }

  RouteMatch? findRoute(String method, String path) {
    for (var route in _routes) {
      if (route.method == method) {
        final match = route.regex.firstMatch(path);
        if (match != null) {
          Map<String, String> extractedParams = {};
          for (var paramName in route.paramNames) {
            extractedParams[paramName] = match.namedGroup(paramName) ?? '';
          }
          return RouteMatch(route.handler, extractedParams);
        }
      }
    }
    return null;
  }

  // FUNGSI INTI MIDDLEWARE: Menjalankan rantai dari ujung ke ujung
  Future<DahoResponse> executeChain(
    DahoRequest req,
    DahoResponse res,
    RouteHandler? handler,
  ) async {
    int index = 0;

    Future<void> next() async {
      if (index < _middlewares.length) {
        final mw = _middlewares[index++];
        await mw(req, res, next);
      } else {
        if (handler != null) {
          // AWAIT KODE BUATAN DEVELOPER!
          await handler(req, res);
        } else {
          res.status(404).json({
            "error": "Route ${req.method} ${req.path} not found",
          });
        }
      }
    }

    await next();
    return res;
  }
}
