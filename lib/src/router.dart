import 'dart:async';
import 'dart:convert';
import 'dart:io';

class UploadedFile {
  final String filename;
  final String contentType;
  final List<int> bytes;

  UploadedFile({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  void save(String path) => File(path).writeAsBytesSync(bytes);
  Future<void> saveAsync(String path) async =>
      await File(path).writeAsBytes(bytes);
}

class DahoRequest {
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> params;
  final dynamic body;
  final String ip;
  final Map<String, UploadedFile> files;

  // TAMBAHAN: Map untuk menyimpan semua HTTP Request Headers
  final Map<String, String> headers;

  DahoRequest({
    required this.method,
    required this.path,
    this.query = const {},
    this.params = const {},
    this.body,
    this.ip = '',
    this.files = const {},
    this.headers = const {}, // Inisialisasi
  });
}

class DahoResponse {
  int statusCode = 200;
  Map<String, String> headers = {};

  List<int>? bodyBytes;
  String _bodyText = '';

  String get bodyText => _bodyText;

  // =====================================================================
  // FUNGSI DASAR
  // =====================================================================
  DahoResponse status(int code) {
    statusCode = code;
    return this;
  }

  DahoResponse header(String key, String value) {
    headers[key] = value;
    return this;
  }

  DahoResponse send(String data) {
    headers.putIfAbsent('Content-Type', () => 'text/plain; charset=utf-8');
    _bodyText = data;
    bodyBytes = null;
    return this;
  }

  DahoResponse bytes(
    List<int> rawBytes, {
    String contentType = 'application/octet-stream',
  }) {
    headers.putIfAbsent('Content-Type', () => contentType);
    bodyBytes = rawBytes;
    _bodyText = '';
    return this;
  }

  DahoResponse json(dynamic data) {
    headers['Content-Type'] = 'application/json; charset=utf-8';
    bodyBytes = const JsonCodec().fuse(utf8).encode(data);
    _bodyText = '';
    return this;
  }

  // =====================================================================
  // HELPER PINTAR (MAGIC FORMATTER)
  // =====================================================================
  void _applyData(dynamic data) {
    if (data == null) {
      bodyBytes = [];
      _bodyText = '';
    } else if (data is String) {
      headers.putIfAbsent('Content-Type', () => 'text/plain; charset=utf-8');
      bodyBytes = utf8.encode(data);
      _bodyText = '';
    } else if (data is List<int>) {
      headers.putIfAbsent('Content-Type', () => 'application/octet-stream');
      bodyBytes = data;
      _bodyText = '';
    } else {
      // Jika Map, List, atau Object, otomatis anggap sebagai JSON
      headers['Content-Type'] = 'application/json; charset=utf-8';
      bodyBytes = const JsonCodec().fuse(utf8).encode(data);
      _bodyText = '';
    }
  }

  // =====================================================================
  // METODE ALA SHELF DART
  // =====================================================================

  /// 200 OK
  DahoResponse ok([dynamic data]) {
    statusCode = 200;
    _applyData(data);
    return this;
  }

  /// 400 Bad Request
  DahoResponse badRequest([dynamic data]) {
    statusCode = 400;
    _applyData(data);
    return this;
  }

  /// 401 Unauthorized
  DahoResponse unauthorized([dynamic data]) {
    statusCode = 401;
    _applyData(data);
    return this;
  }

  /// 403 Forbidden
  DahoResponse forbidden([dynamic data]) {
    statusCode = 403;
    _applyData(data);
    return this;
  }

  /// 404 Not Found
  DahoResponse notFound([dynamic data]) {
    statusCode = 404;
    _applyData(data);
    return this;
  }

  /// 500 Internal Server Error
  DahoResponse internalServerError([dynamic data]) {
    statusCode = 500;
    _applyData(data);
    return this;
  }

  // =====================================================================
  // METODE REDIRECT
  // =====================================================================

  /// 301 Moved Permanently
  DahoResponse movedPermanently(String location, [dynamic data]) {
    statusCode = 301;
    headers['Location'] = location;
    _applyData(data);
    return this;
  }

  /// 302 Found
  DahoResponse found(String location, [dynamic data]) {
    statusCode = 302;
    headers['Location'] = location;
    _applyData(data);
    return this;
  }

  /// 303 See Other
  DahoResponse seeOther(String location, [dynamic data]) {
    statusCode = 303;
    headers['Location'] = location;
    _applyData(data);
    return this;
  }

  /// 304 Not Modified
  DahoResponse notModified() {
    statusCode = 304;
    _applyData(null);
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
  final RouteHandler baseHandler;
  final List<Middleware> groupMiddlewares;

  late RouteHandler compiledHandler; // Disimpan setelah kompilasi

  RouteEntry(
    this.method,
    this.originalPath,
    this.regex,
    this.paramNames,
    this.baseHandler,
    this.groupMiddlewares,
  );
}

class RouteMatch {
  final RouteHandler compiledHandler;
  final Map<String, String> params;

  RouteMatch(this.compiledHandler, this.params);
}

class RouteRegistry {
  static final RouteRegistry instance = RouteRegistry._internal();
  RouteRegistry._internal();

  final Map<String, Map<String, RouteMatch>> _staticRoutes = {
    'GET': {},
    'POST': {},
    'PUT': {},
    'DELETE': {},
  };
  final List<RouteEntry> _dynamicRoutes = [];
  final List<Middleware> _globalMiddlewares = [];

  void addGlobalMiddleware(Middleware mw) => _globalMiddlewares.add(mw);

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

    if (!fullPath.contains(':')) {
      _staticRoutes[method]?[fullPath] = RouteMatch(
        handler,
        {},
      ); // Placeholder, dicompile nanti
      // Kita tambahkan juga ke array bayangan untuk dikompilasi
      _dynamicRoutes.add(
        RouteEntry(
          method,
          fullPath,
          RegExp(''),
          [],
          handler,
          List.from(groupMiddlewares),
        ),
      );
    } else {
      List<String> paramNames = [];
      String regexString = fullPath.replaceAllMapped(
        RegExp(r':([a-zA-Z0-9_]+)'),
        (match) {
          String paramName = match.group(1)!;
          paramNames.add(paramName);
          return '(?<$paramName>[^/]+)';
        },
      );
      final regex = RegExp('^$regexString\$');
      _dynamicRoutes.add(
        RouteEntry(
          method,
          fullPath,
          regex,
          paramNames,
          handler,
          List.from(groupMiddlewares),
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // KEAJAIBAN BARU: KOMPILASI MIDDLEWARE CHAIN (DIPANGGIL 1X SAAT STARTUP)
  // ---------------------------------------------------------
  void compileAll() {
    for (var route in _dynamicRoutes) {
      final allMws = [..._globalMiddlewares, ...route.groupMiddlewares];
      route.compiledHandler = _buildChain(allMws, route.baseHandler);

      // Jika ini rute statis, perbarui Map O(1) dengan Handler yang sudah dikompilasi
      if (route.paramNames.isEmpty) {
        _staticRoutes[route.method]?[route.originalPath] = RouteMatch(
          route.compiledHandler,
          {},
        );
      }
    }
  }

  RouteHandler _buildChain(
    List<Middleware> middlewares,
    RouteHandler baseHandler,
  ) {
    RouteHandler nextHandler = baseHandler;
    // Lipat array dari belakang ke depan menjadi satu fungsi raksasa
    for (int i = middlewares.length - 1; i >= 0; i--) {
      final mw = middlewares[i];
      final currentNext = nextHandler;
      nextHandler = (req, res) async {
        bool nextCalled = false;
        await mw(req, res, () async {
          nextCalled = true;
          await currentNext(req, res);
        });
        return res;
      };
    }
    return nextHandler;
  }

  RouteMatch? findRoute(String method, String path) {
    final staticMatch = _staticRoutes[method]?[path];
    if (staticMatch != null) return staticMatch;

    for (var route in _dynamicRoutes) {
      if (route.paramNames.isNotEmpty && route.method == method) {
        final match = route.regex.firstMatch(path);
        if (match != null) {
          Map<String, String> extractedParams = {};
          for (var paramName in route.paramNames) {
            extractedParams[paramName] = match.namedGroup(paramName) ?? '';
          }
          return RouteMatch(route.compiledHandler, extractedParams);
        }
      }
    }
    return null;
  }
}
