/// 05 — Request & Response
///
/// Comprehensive demonstration of DahoRequest and DahoResponse APIs:
///
/// Request properties:
///   req.method, req.path, req.query, req.params, req.ip
///   req.headers, req.header(name), req.body, req.cookies
///
/// Response methods:
///   res.send(text), res.json(data), res.bytes(raw)
///   res.status(code), res.header(key, value)
///   Status helpers: res.ok(), res.badRequest(), res.unauthorized(),
///     res.forbidden(), res.notFound(), res.internalServerError()
///   Redirects: res.found(url), res.movedPermanently(url),
///     res.seeOther(url), res.notModified()
///   Cookies: res.cookie(), res.clearCookie()
///
/// Run:  dart run example/05_request_response.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:daho/daho.dart';

/// Pre-encoded bytes for the fast response example.
final Uint8List greetingBytes = utf8.encode(jsonEncode({'greeting': 'Hello'}));

void setupRoutes(Daho app) {
  // --- Request inspection ---
  app.get('/inspect', (req, res) {
    return res.ok({
      'method': req.method,
      'path': req.path,
      'ip': req.ip,
      'query': req.query,
      'headers': req.headers,
      'user_agent': req.header('user-agent'),
    });
  });

  // --- Plain text response ---
  app.get('/text', (req, res) {
    return res.send('This is a plain text response');
  });

  // --- JSON response ---
  app.get('/json', (req, res) {
    return res.json({
      'status': 'ok',
      'items': [1, 2, 3],
    });
  });

  // --- Raw bytes response ---
  app.get('/bytes', (req, res) {
    return res.header('Content-Type', 'application/json').bytes(greetingBytes);
  });

  // --- Fluent chaining ---
  app.post('/items', (req, res) {
    return res.status(201).header('X-Custom-Header', 'my-value').json({
      'created': true,
      'data': req.body,
    });
  });

  // --- Status helpers ---
  app.get('/forbidden', (req, res) {
    return res.forbidden({'error': 'You shall not pass'});
  });

  app.get('/not-here', (req, res) {
    return res.notFound({'error': 'Resource not found'});
  });

  app.get('/broken', (req, res) {
    return res.internalServerError({'error': 'Something went wrong'});
  });

  // --- Redirects ---
  app.get('/old-page', (req, res) {
    return res.movedPermanently('/new-page');
  });

  app.get('/redirect', (req, res) {
    return res.found('/json');
  });

  app.get('/new-page', (req, res) {
    return res.ok({'message': 'Welcome to the new page'});
  });

  // --- Cookies ---
  app.get('/set-cookie', (req, res) {
    return res
        .cookie('session', 'abc123', httpOnly: true, maxAge: Duration(hours: 1))
        .ok({'message': 'Cookie set'});
  });

  app.get('/read-cookie', (req, res) {
    return res.ok({'session': req.cookies['session'] ?? 'none'});
  });

  app.get('/clear-cookie', (req, res) {
    return res.clearCookie('session').ok({'message': 'Cookie cleared'});
  });
}

void main() {
  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Server running at http://127.0.0.1:8080'),
  );
}
