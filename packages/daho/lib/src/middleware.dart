import 'dart:convert';
import 'dart:io';

import 'router.dart';

/// A collection of ready-to-use middleware.
///
/// Register them globally with `app.use(...)` or per route with the `use:`
/// parameter, e.g. `app.use(Middlewares.logger())`.
class Middlewares {
  Middlewares._();

  /// Logs one line per request: `METHOD path status durationms - ip`.
  static Middleware logger({IOSink? out}) {
    final sink = out ?? stdout;
    return (req, res, next) async {
      final sw = Stopwatch()..start();
      await next();
      sw.stop();
      final ms = (sw.elapsedMicroseconds / 1000).toStringAsFixed(2);
      sink.writeln(
        '${req.method} ${req.path} ${res.statusCode} ${ms}ms - ${req.ip}',
      );
    };
  }

  /// Adds CORS headers. Register it **globally** so that preflight `OPTIONS`
  /// requests (which match no route) are handled: when the method is `OPTIONS`
  /// it answers `204` immediately and does not run downstream handlers.
  static Middleware cors({
    String origin = '*',
    List<String> methods = const [
      'GET',
      'POST',
      'PUT',
      'DELETE',
      'PATCH',
      'OPTIONS',
    ],
    List<String> headers = const ['Content-Type', 'Authorization'],
    bool credentials = false,
    Duration maxAge = const Duration(hours: 24),
  }) {
    final methodsStr = methods.join(', ');
    final headersStr = headers.join(', ');
    return (req, res, next) async {
      res.header('Access-Control-Allow-Origin', origin);
      if (credentials) {
        res.header('Access-Control-Allow-Credentials', 'true');
      }
      if (req.method == 'OPTIONS') {
        res
            .header('Access-Control-Allow-Methods', methodsStr)
            .header('Access-Control-Allow-Headers', headersStr)
            .header('Access-Control-Max-Age', '${maxAge.inSeconds}')
            .status(204)
            .send('');
        return; // short-circuit the preflight
      }
      await next();
    };
  }

  /// Sets a conservative set of security-related response headers, similar to
  /// the defaults of Helmet.
  static Middleware secureHeaders() {
    return (req, res, next) async {
      res
          .header('X-Content-Type-Options', 'nosniff')
          .header('X-Frame-Options', 'DENY')
          .header('Referrer-Policy', 'no-referrer')
          .header('X-XSS-Protection', '0');
      await next();
    };
  }

  /// Gzip-compresses the response body when the client sends
  /// `Accept-Encoding: gzip` and the body is at least [minLength] bytes.
  static Middleware compress({int minLength = 1024}) {
    return (req, res, next) async {
      await next();

      final accept = req.header('accept-encoding') ?? '';
      if (!accept.contains('gzip')) return;
      if (res.headers.containsKey('Content-Encoding')) return;

      final body = res.bodyBytes ?? utf8.encode(res.bodyText);
      if (body.length < minLength) return;

      res.bodyBytes = gzip.encode(body);
      res.header('Content-Encoding', 'gzip').header('Vary', 'Accept-Encoding');
    };
  }
}
