/// 09 — Cookies
///
/// Demonstrates cookie management:
/// - `res.cookie()` — set a cookie with attributes (maxAge, httpOnly, secure, sameSite)
/// - `req.cookies` — read cookies from the request (lazy-parsed from Cookie header)
/// - `res.clearCookie()` — expire a cookie on the client
///
/// Run:  dart run example/09_cookies.dart
/// Test:
///   curl -c cookies.txt http://localhost:8080/login
///   curl -b cookies.txt http://localhost:8080/dashboard
///   curl -b cookies.txt http://localhost:8080/logout
library;

import 'package:daho/daho.dart';

void setupRoutes(Daho app) {
  // Set a session cookie
  app.get('/login', (req, res) {
    return res
        .cookie(
          'session_id',
          'user-ada-123',
          httpOnly: true,
          maxAge: Duration(hours: 1),
          sameSite: 'Lax',
        )
        .ok({'message': 'Logged in — session cookie set'});
  });

  // Read the session cookie
  app.get('/dashboard', (req, res) {
    final sessionId = req.cookies['session_id'];
    if (sessionId == null) {
      return res.unauthorized({'error': 'No session — please log in'});
    }
    return res.ok({
      'message': 'Welcome to the dashboard',
      'session_id': sessionId,
    });
  });

  // Clear the session cookie
  app.get('/logout', (req, res) {
    return res.clearCookie('session_id').ok({
      'message': 'Logged out — cookie cleared',
    });
  });

  // Set multiple cookies at once
  app.get('/preferences', (req, res) {
    return res
        .cookie('theme', 'dark', maxAge: Duration(days: 365))
        .cookie('lang', 'en', maxAge: Duration(days: 365))
        .ok({'message': 'Preferences saved'});
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
