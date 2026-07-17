import 'dart:io';
import 'dart:typed_data';

/// A single file received through a `multipart/form-data` request.
class UploadedFile {
  /// Original file name as reported by the client.
  final String filename;

  /// MIME type declared in the part headers (e.g. `image/png`).
  final String contentType;

  /// Raw file contents.
  final List<int> bytes;

  UploadedFile({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  /// Writes the file to [path] synchronously.
  void save(String path) => File(path).writeAsBytesSync(bytes);

  /// Writes the file to [path] asynchronously.
  Future<void> saveAsync(String path) => File(path).writeAsBytes(bytes);
}

/// The incoming HTTP request handed to route handlers and middleware.
///
/// Instances are pooled and reused across requests (see `RequestPool`), so
/// fields are mutable and populated through [reset] rather than a constructor.
///
/// The request body is parsed lazily: [body] and [files] are only decoded the
/// first time they are accessed, avoiding the cost of parsing for routes that
/// never read the payload.
class DahoRequest {
  String method = '';
  String path = '';
  Map<String, String> query = {};
  Map<String, String> params = {};
  String ip = '';
  Map<String, String> headers = {};

  /// The undecoded request body, if any.
  Uint8List? rawBody;

  bool _isParsed = false;
  dynamic _parsedBody;
  Map<String, UploadedFile> _parsedFiles = {};
  void Function(DahoRequest)? _lazyParser;

  Map<String, String>? _cookies;

  DahoRequest();

  /// Re-initializes this instance for a new request. Used by the object pool
  /// to recycle allocations.
  void reset({
    required String method,
    required String path,
    required Map<String, String> query,
    required String ip,
    required Map<String, String> headers,
    Uint8List? rawBody,
    void Function(DahoRequest)? lazyParser,
  }) {
    this.method = method;
    this.path = path;
    this.query = query;
    params = {};
    this.ip = ip;
    this.headers = headers;
    this.rawBody = rawBody;
    _isParsed = false;
    _parsedBody = null;
    _parsedFiles = {};
    _lazyParser = lazyParser;
    _cookies = null;
  }

  /// Cookies sent by the client, parsed from the `Cookie` header on first
  /// access and cached for the request.
  Map<String, String> get cookies {
    var cookies = _cookies;
    if (cookies != null) return cookies;

    cookies = {};
    final raw = headers['cookie'];
    if (raw != null && raw.isNotEmpty) {
      for (final pair in raw.split(';')) {
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        final name = pair.substring(0, eq).trim();
        final value = pair.substring(eq + 1).trim();
        if (name.isNotEmpty) cookies[name] = value;
      }
    }
    return _cookies = cookies;
  }

  /// Returns the value of request header [name] (case-insensitive), or null.
  String? header(String name) => headers[name.toLowerCase()];

  /// The parsed request body. JSON payloads become a `Map`/`List`, form fields
  /// become a `Map<String, String>`, otherwise the raw decoded text.
  dynamic get body {
    if (!_isParsed) _parse();
    return _parsedBody;
  }

  /// Files uploaded via `multipart/form-data`, keyed by form field name.
  Map<String, UploadedFile> get files {
    if (!_isParsed) _parse();
    return _parsedFiles;
  }

  void _parse() {
    if (_isParsed) return;
    _isParsed = true;
    _lazyParser?.call(this);
  }

  /// Stores the decoded body and files. Called by the lazy parser.
  void setParsedData(dynamic body, Map<String, UploadedFile> files) {
    _parsedBody = body;
    _parsedFiles = files;
  }
}
