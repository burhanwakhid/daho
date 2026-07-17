import 'dart:convert';
import 'dart:typed_data';

import 'package:daho/src/app.dart';
import 'package:daho/src/config.dart';
import 'package:daho/src/dispatcher.dart';
import 'package:daho/src/pool.dart';
import 'package:daho/src/router.dart';

/// A captured response from [DahoTester].
class TestResponse {
  final int statusCode;
  final Map<String, String> headers;

  /// Raw `Set-Cookie` header values.
  final List<String> cookies;
  final List<int> bodyBytes;

  TestResponse(this.statusCode, this.headers, this.cookies, this.bodyBytes);

  /// The body decoded as UTF-8 text.
  String get text => utf8.decode(bodyBytes);

  /// The body decoded as JSON.
  dynamic get json => jsonDecode(text);
}

/// In-process test harness for exercising routes without booting the native
/// server. It runs requests through the exact same dispatch path (global
/// middleware, matching, 404 / 405, and the configured error handler).
///
/// ```dart
/// final t = DahoTester(setupRoutes);
/// final res = await t.get('/users/1');
/// expect(res.statusCode, 200);
/// ```
///
/// Body parsing covers JSON, `x-www-form-urlencoded`, and plain text.
/// Multipart bodies are not parsed here (they require the native fast path).
class DahoTester {
  final DahoConfig config;
  late final RouteHandler _dispatch;

  DahoTester(AppBuilder routes, {this.config = const DahoConfig()}) {
    // Rebuild the singleton registry from scratch for an isolated test app.
    RouteRegistry.instance.reset();
    routes(Daho(config: config));
    RouteRegistry.instance.compileAll();
    _dispatch = buildDispatch(config);
  }

  Future<TestResponse> get(String path, {Map<String, String>? headers}) =>
      request('GET', path, headers: headers);

  Future<TestResponse> post(
    String path, {
    Map<String, String>? headers,
    Object? json,
    String? form,
    String? text,
  }) => request(
    'POST',
    path,
    headers: headers,
    json: json,
    form: form,
    text: text,
  );

  Future<TestResponse> put(
    String path, {
    Map<String, String>? headers,
    Object? json,
    String? form,
    String? text,
  }) => request(
    'PUT',
    path,
    headers: headers,
    json: json,
    form: form,
    text: text,
  );

  Future<TestResponse> delete(String path, {Map<String, String>? headers}) =>
      request('DELETE', path, headers: headers);

  Future<TestResponse> patch(
    String path, {
    Map<String, String>? headers,
    Object? json,
    String? form,
    String? text,
  }) => request(
    'PATCH',
    path,
    headers: headers,
    json: json,
    form: form,
    text: text,
  );

  /// Dispatches a request and returns the captured [TestResponse].
  ///
  /// Provide at most one of [json], [form], or [text] as the body.
  Future<TestResponse> request(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? json,
    String? form,
    String? text,
  }) async {
    final uri = Uri.parse(path);
    final hdrs = <String, String>{};
    headers?.forEach((k, v) => hdrs[k.toLowerCase()] = v);

    Uint8List bodyBytes = Uint8List(0);
    if (json != null) {
      hdrs.putIfAbsent('content-type', () => 'application/json');
      bodyBytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    } else if (form != null) {
      hdrs.putIfAbsent(
        'content-type',
        () => 'application/x-www-form-urlencoded',
      );
      bodyBytes = Uint8List.fromList(utf8.encode(form));
    } else if (text != null) {
      hdrs.putIfAbsent('content-type', () => 'text/plain');
      bodyBytes = Uint8List.fromList(utf8.encode(text));
    }

    final contentType = hdrs['content-type'] ?? '';
    final req = requestPool.acquire(
      method: method.toUpperCase(),
      path: uri.path,
      query: uri.queryParameters,
      ip: '127.0.0.1',
      headers: hdrs,
      rawBody: bodyBytes,
      lazyParser: (r) =>
          r.setParsedData(_parseBody(bodyBytes, contentType), {}),
    );
    final res = responsePool.acquire();

    try {
      await _dispatch(req, res);
    } catch (error, stackTrace) {
      res.reset();
      await config.errorHandler(req, res, error, stackTrace);
    }

    final captured = TestResponse(
      res.statusCode,
      Map<String, String>.from(res.headers),
      List<String>.from(res.setCookies),
      res.bodyBytes ?? utf8.encode(res.bodyText),
    );

    requestPool.release(req);
    responsePool.release(res);
    return captured;
  }

  dynamic _parseBody(Uint8List bodyBytes, String contentType) {
    if (bodyBytes.isEmpty) return <String, dynamic>{};
    if (contentType.contains('application/json')) {
      try {
        return jsonDecode(utf8.decode(bodyBytes));
      } catch (_) {
        return utf8.decode(bodyBytes, allowMalformed: true);
      }
    }
    if (contentType.contains('application/x-www-form-urlencoded')) {
      return Uri.splitQueryString(utf8.decode(bodyBytes, allowMalformed: true));
    }
    return utf8.decode(bodyBytes, allowMalformed: true);
  }
}
