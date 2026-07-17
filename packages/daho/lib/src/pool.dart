import 'dart:typed_data';

import 'request.dart';
import 'response.dart';

/// Maximum number of idle objects kept in each pool.
const int _maxPoolSize = 64;

/// Reuses [DahoRequest] instances to avoid a fresh allocation per request.
class RequestPool {
  final _pool = <DahoRequest>[];

  /// Returns a request initialized with the given values, reusing a pooled
  /// instance when one is available.
  DahoRequest acquire({
    required String method,
    required String path,
    required Map<String, String> query,
    required String ip,
    required Map<String, String> headers,
    Uint8List? rawBody,
    void Function(DahoRequest)? lazyParser,
  }) {
    return (_pool.isEmpty ? DahoRequest() : _pool.removeLast())..reset(
      method: method,
      path: path,
      query: query,
      ip: ip,
      headers: headers,
      rawBody: rawBody,
      lazyParser: lazyParser,
    );
  }

  /// Returns [req] to the pool for reuse.
  void release(DahoRequest req) {
    if (_pool.length < _maxPoolSize) _pool.add(req);
  }
}

/// Reuses [DahoResponse] instances to avoid a fresh allocation per request.
class ResponsePool {
  final _pool = <DahoResponse>[];

  /// Returns a freshly reset response, reusing a pooled instance when possible.
  DahoResponse acquire() {
    return (_pool.isEmpty ? DahoResponse() : _pool.removeLast())..reset();
  }

  /// Returns [res] to the pool for reuse.
  void release(DahoResponse res) {
    if (_pool.length < _maxPoolSize) _pool.add(res);
  }
}

/// Global pools, one instance per worker Isolate.
final requestPool = RequestPool();
final responsePool = ResponsePool();
