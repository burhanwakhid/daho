import 'dart:convert';
import 'dart:io' show HttpDate;

/// The HTTP response builder handed to route handlers.
///
/// Every mutating method returns `this` so calls can be chained, e.g.
/// `res.status(201).json({...})`. Like [DahoRequest], instances are pooled and
/// reset between requests.
class DahoResponse {
  int statusCode = 200;
  Map<String, String> headers = {};

  /// Raw `Set-Cookie` header values. Stored separately from [headers] because
  /// a response may carry several `Set-Cookie` headers (a `Map` cannot).
  final List<String> setCookies = [];

  /// Response body as raw bytes. Takes precedence over [bodyText] when set.
  List<int>? bodyBytes;
  String _bodyText = '';

  /// Response body as text, used when [bodyBytes] is null.
  String get bodyText => _bodyText;

  /// Re-initializes this instance for reuse by the object pool.
  void reset() {
    statusCode = 200;
    headers.clear();
    setCookies.clear();
    bodyBytes = null;
    _bodyText = '';
  }

  /// Adds a `Set-Cookie` header. Call multiple times to set several cookies.
  ///
  /// [sameSite] should be one of `Strict`, `Lax`, or `None`.
  DahoResponse cookie(
    String name,
    String value, {
    Duration? maxAge,
    DateTime? expires,
    String? path = '/',
    String? domain,
    bool secure = false,
    bool httpOnly = false,
    String? sameSite,
  }) {
    final sb = StringBuffer('$name=${Uri.encodeComponent(value)}');
    if (maxAge != null) sb.write('; Max-Age=${maxAge.inSeconds}');
    if (expires != null) {
      sb.write('; Expires=${HttpDate.format(expires.toUtc())}');
    }
    if (path != null) sb.write('; Path=$path');
    if (domain != null) sb.write('; Domain=$domain');
    if (secure) sb.write('; Secure');
    if (httpOnly) sb.write('; HttpOnly');
    if (sameSite != null) sb.write('; SameSite=$sameSite');
    setCookies.add(sb.toString());
    return this;
  }

  /// Expires the cookie [name] on the client immediately.
  DahoResponse clearCookie(String name, {String path = '/'}) {
    return cookie(name, '', path: path, maxAge: Duration.zero);
  }

  // ---------------------------------------------------------------------------
  // Primitives
  // ---------------------------------------------------------------------------

  /// Sets the HTTP status code.
  DahoResponse status(int code) {
    statusCode = code;
    return this;
  }

  /// Sets a response header.
  DahoResponse header(String key, String value) {
    headers[key] = value;
    return this;
  }

  /// Sends a plain-text body.
  DahoResponse send(String data) {
    headers.putIfAbsent('Content-Type', () => 'text/plain; charset=utf-8');
    _bodyText = data;
    bodyBytes = null;
    return this;
  }

  /// Sends a raw byte body with the given [contentType].
  DahoResponse bytes(
    List<int> rawBytes, {
    String contentType = 'application/octet-stream',
  }) {
    headers.putIfAbsent('Content-Type', () => contentType);
    bodyBytes = rawBytes;
    _bodyText = '';
    return this;
  }

  /// Serializes [data] as JSON and sends it.
  DahoResponse json(dynamic data) {
    headers['Content-Type'] = 'application/json; charset=utf-8';
    bodyBytes = const JsonCodec().fuse(utf8).encode(data);
    _bodyText = '';
    return this;
  }

  /// Encodes [data] based on its runtime type: `String` -> text,
  /// `List<int>` -> raw bytes, `null` -> empty, anything else -> JSON.
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
      // Maps, Lists and other objects are treated as JSON.
      headers['Content-Type'] = 'application/json; charset=utf-8';
      bodyBytes = const JsonCodec().fuse(utf8).encode(data);
      _bodyText = '';
    }
  }

  // ---------------------------------------------------------------------------
  // Status helpers (the body type is inferred by [_applyData])
  // ---------------------------------------------------------------------------

  /// 200 OK
  DahoResponse ok([dynamic data]) => _reply(200, data);

  /// 400 Bad Request
  DahoResponse badRequest([dynamic data]) => _reply(400, data);

  /// 401 Unauthorized
  DahoResponse unauthorized([dynamic data]) => _reply(401, data);

  /// 403 Forbidden
  DahoResponse forbidden([dynamic data]) => _reply(403, data);

  /// 404 Not Found
  DahoResponse notFound([dynamic data]) => _reply(404, data);

  /// 500 Internal Server Error
  DahoResponse internalServerError([dynamic data]) => _reply(500, data);

  DahoResponse _reply(int code, dynamic data) {
    statusCode = code;
    _applyData(data);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Redirects
  // ---------------------------------------------------------------------------

  /// 301 Moved Permanently
  DahoResponse movedPermanently(String location, [dynamic data]) =>
      _redirect(301, location, data);

  /// 302 Found
  DahoResponse found(String location, [dynamic data]) =>
      _redirect(302, location, data);

  /// 303 See Other
  DahoResponse seeOther(String location, [dynamic data]) =>
      _redirect(303, location, data);

  /// 304 Not Modified
  DahoResponse notModified() => _reply(304, null);

  DahoResponse _redirect(int code, String location, dynamic data) {
    statusCode = code;
    headers['Location'] = location;
    _applyData(data);
    return this;
  }
}
