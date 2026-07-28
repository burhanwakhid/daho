import 'dart:convert';
import 'package:daho/daho.dart';

/// Builds a [DahoRequest] for tests without going through daho's HTTP/FFI
/// stack. `DahoRequest` is a plain, publicly-constructible, mutable object
/// designed to be recycled by an object pool, which makes this
/// straightforward: [reset] populates the public fields and
/// [setParsedData] injects an already-decoded body, bypassing the lazy
/// multipart/JSON parser entirely.
DahoRequest buildRequest({
  String method = 'GET',
  String path = '/',
  Map<String, String> query = const {},
  Map<String, String> headers = const {},
  Map<String, String> cookies = const {},
  dynamic body,
}) {
  final req = DahoRequest();
  final mergedHeaders = {...headers};
  if (cookies.isNotEmpty) {
    mergedHeaders['cookie'] = cookies.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
  }
  req.reset(
    method: method,
    path: path,
    query: query,
    ip: '127.0.0.1',
    headers: mergedHeaders,
  );
  req.setParsedData(body, {});
  return req;
}

/// Convenience for a JSON body request: sets Content-Type and a decoded map,
/// mirroring what daho's body parser would have produced.
DahoRequest buildJsonRequest({
  String method = 'POST',
  String path = '/',
  Map<String, String> headers = const {},
  Map<String, String> cookies = const {},
  Map<String, dynamic>? body,
}) {
  return buildRequest(
    method: method,
    path: path,
    headers: {'content-type': 'application/json', ...headers},
    cookies: cookies,
    body: body,
  );
}

/// Decodes a [DahoResponse]'s JSON body back into a Dart value for assertions.
dynamic jsonBodyOf(DahoResponse res) {
  final bytes = res.bodyBytes;
  if (bytes == null) return null;
  return jsonDecode(utf8.decode(bytes));
}

/// Runs [middleware] and reports whether `next()` was invoked.
class MiddlewareResult {
  final bool nextCalled;
  MiddlewareResult(this.nextCalled);
}

Future<MiddlewareResult> runMiddleware(
  Middleware middleware,
  DahoRequest req,
  DahoResponse res,
) async {
  var nextCalled = false;
  await middleware(req, res, () async {
    nextCalled = true;
  });
  return MiddlewareResult(nextCalled);
}
