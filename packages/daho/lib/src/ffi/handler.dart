import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show stderr;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../config.dart';
import '../dispatcher.dart';
import '../pool.dart';
import '../profiler.dart';
import '../request.dart';
import '../router.dart';
import 'bindings.dart';
import 'multipart.dart';

/// The active configuration for this worker Isolate. Set by `startNativeServer`
/// before any request is handled.
DahoConfig activeConfig = const DahoConfig();

/// The top-level request dispatcher (global middleware + route matching + 404 /
/// 405 handling). Built once per Isolate on first use.
RouteHandler? _dispatch;

/// Entry point invoked by C for every non-fast-path request.
///
/// This runs on the Isolate that owns the [NativeCallable]. It marshals the
/// C-owned request data into Dart values and hands off to the async processor.
/// It must not block: response delivery happens asynchronously in
/// [_processRequest].
void dartRouteCallback(
  int reqPtr,
  Pointer<DahoStr> pathPtr,
  Pointer<DahoStr> methodPtr,
  Pointer<Uint8> bodyPtr,
  int bodyLen,
  Pointer<DahoStr> ipPtr,
  Pointer<Pointer<DahoStr>> headerKeysPtr,
  Pointer<Pointer<DahoStr>> headerValuesPtr,
  int headerCount,
  int workerId,
) {
  final path = pathPtr.toDartString();
  final method = methodPtr.toDartString();
  final ip = ipPtr.toDartString();

  final headers = <String, String>{};
  for (int i = 0; i < headerCount; i++) {
    final key = headerKeysPtr[i].toDartString().toLowerCase();
    headers[key] = headerValuesPtr[i].toDartString();
  }

  Uint8List bodyBytes = Uint8List(0);
  if (bodyLen > 0 && bodyPtr != nullptr) {
    bodyBytes = Uint8List.view(bodyPtr.asTypedList(bodyLen).buffer, 0, bodyLen);
  }

  _processRequest(reqPtr, path, method, headers, bodyBytes, ip, workerId);
}

/// Builds the lazy body parser, runs the matched route (or 404s), and writes
/// the response back to C.
Future<void> _processRequest(
  int reqPtr,
  String rawPath,
  String method,
  Map<String, String> headers,
  Uint8List bodyBytes,
  String ip,
  int workerId,
) async {
  final profileStart = Profiler.enabled
      ? DateTime.now().microsecondsSinceEpoch
      : 0;

  final uri = Uri.parse(rawPath);
  final contentType = headers['content-type'] ?? '';

  // Parsing is deferred until the handler actually reads `req.body`/`req.files`.
  void lazyParser(DahoRequest req) {
    final parsed = _parseBody(bodyBytes, contentType);
    req.setParsedData(parsed.body, parsed.files);
  }

  final request = requestPool.acquire(
    method: method,
    path: uri.path,
    query: uri.queryParameters,
    ip: _resolveIp(ip, headers),
    headers: headers,
    rawBody: bodyBytes,
    lazyParser: lazyParser,
  );
  final response = responsePool.acquire();

  int statusCode = 500;
  Map<String, String> finalHeaders = {'Content-Type': 'application/json'};
  List<String> setCookies = const [];
  List<int> responseBytes = const [];

  try {
    // Run the global middleware chain + route dispatch. Global middleware also
    // sees unmatched requests (404 / 405 / CORS preflight).
    await (_dispatch ??= buildDispatch(activeConfig))(request, response);

    statusCode = response.statusCode;
    finalHeaders = response.headers;
    setCookies = response.setCookies;
    responseBytes = response.bodyBytes ?? utf8.encode(response.bodyText);
  } catch (error, stackTrace) {
    // Delegate to the configured error handler, which decides what (if any)
    // detail is exposed to the client. Never leak the stack trace by default.
    response.reset();
    try {
      await activeConfig.errorHandler(request, response, error, stackTrace);
    } catch (handlerError) {
      // The error handler itself failed: fall back to a bare 500.
      response.status(500).json({'error': 'Internal Server Error'});
      stderr.writeln('[daho] errorHandler threw: $handlerError');
    }
    statusCode = response.statusCode;
    finalHeaders = response.headers;
    setCookies = response.setCookies;
    responseBytes = response.bodyBytes ?? utf8.encode(response.bodyText);
  } finally {
    requestPool.release(request);
    responsePool.release(response);
  }

  _sendResponse(
    reqPtr,
    statusCode,
    finalHeaders,
    setCookies,
    responseBytes,
    workerId,
  );

  if (Profiler.enabled) {
    final micros = DateTime.now().microsecondsSinceEpoch - profileStart;
    Profiler.forWorker(workerId).record(micros);
  }
}

/// Resolves the effective client IP. When [DahoConfig.trustProxy] is enabled,
/// prefers the `X-Forwarded-For` (leftmost) or `X-Real-IP` header; otherwise
/// uses the socket peer address.
String _resolveIp(String socketIp, Map<String, String> headers) {
  if (!activeConfig.trustProxy) return socketIp;

  final forwarded = headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) {
    final comma = forwarded.indexOf(',');
    return (comma == -1 ? forwarded : forwarded.substring(0, comma)).trim();
  }
  final realIp = headers['x-real-ip'];
  if (realIp != null && realIp.isNotEmpty) return realIp.trim();

  return socketIp;
}

/// Decodes the raw request body according to its content type.
_ParsedBody _parseBody(Uint8List bodyBytes, String contentType) {
  if (bodyBytes.isEmpty) return _ParsedBody(<String, dynamic>{}, const {});

  if (contentType.contains('application/json')) {
    final str = utf8.decode(bodyBytes, allowMalformed: true);
    try {
      return _ParsedBody(jsonDecode(str), const {});
    } catch (_) {
      return _ParsedBody(str, const {});
    }
  }

  if (contentType.contains('multipart/form-data')) {
    const marker = 'boundary=';
    final markerIndex = contentType.indexOf(marker);
    if (markerIndex != -1) {
      final boundary = contentType.substring(markerIndex + marker.length);
      final data = parseMultipart(bodyBytes, boundary);
      return _ParsedBody(data.fields, data.files);
    }
    return _ParsedBody(<String, dynamic>{}, const {});
  }

  if (contentType.contains('application/x-www-form-urlencoded')) {
    final str = utf8.decode(bodyBytes, allowMalformed: true);
    try {
      return _ParsedBody(Uri.splitQueryString(str), const {});
    } catch (_) {
      return _ParsedBody(str, const {});
    }
  }

  return _ParsedBody(utf8.decode(bodyBytes, allowMalformed: true), const {});
}

class _ParsedBody {
  final dynamic body;
  final Map<String, UploadedFile> files;
  _ParsedBody(this.body, this.files);
}

/// Copies the response headers and body into native memory, hands them to C,
/// then frees everything Dart owns.
///
/// [setCookies] are emitted as additional `Set-Cookie` headers (the C layer
/// accepts repeated header names, unlike the Dart [headers] map).
void _sendResponse(
  int reqPtr,
  int statusCode,
  Map<String, String> headers,
  List<String> setCookies,
  List<int> responseBytes,
  int workerId,
) {
  final headerCount = headers.length + setCookies.length;

  Pointer<Pointer<DahoStr>> headerKeysPtr = nullptr;
  Pointer<Pointer<DahoStr>> headerValuesPtr = nullptr;

  if (headerCount > 0) {
    headerKeysPtr = malloc.allocate(sizeOf<Pointer<DahoStr>>() * headerCount);
    headerValuesPtr = malloc.allocate(sizeOf<Pointer<DahoStr>>() * headerCount);

    int i = 0;
    headers.forEach((key, value) {
      headerKeysPtr[i] = allocateDahoStr(key);
      headerValuesPtr[i] = allocateDahoStr(value);
      i++;
    });
    for (final cookie in setCookies) {
      headerKeysPtr[i] = allocateDahoStr('Set-Cookie');
      headerValuesPtr[i] = allocateDahoStr(cookie);
      i++;
    }
  }

  Pointer<Uint8> bodyPtr = nullptr;
  if (responseBytes.isNotEmpty) {
    bodyPtr = malloc.allocate<Uint8>(responseBytes.length);
    bodyPtr.asTypedList(responseBytes.length).setAll(0, responseBytes);
  }

  nativeRespond(
    reqPtr,
    statusCode,
    headerKeysPtr,
    headerValuesPtr,
    headerCount,
    bodyPtr,
    responseBytes.length,
    workerId,
  );

  // Header strings are copied by C, so they are safe to free here.
  if (headerCount > 0) {
    for (int j = 0; j < headerCount; j++) {
      malloc.free(headerKeysPtr[j]);
      malloc.free(headerValuesPtr[j]);
    }
    malloc.free(headerKeysPtr);
    malloc.free(headerValuesPtr);
  }

  // The body buffer is NOT freed here: C takes ownership and frees it after
  // the zero-copy send completes (see `free_zero_copy_buffer` in the wrapper).
}
