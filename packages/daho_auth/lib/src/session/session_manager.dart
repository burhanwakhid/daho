import 'dart:io';
import 'package:daho/daho.dart';
import '../auth_config.dart';
import 'session.dart';
import 'session_store.dart';

/// High-level session management: create, read, destroy sessions via cookies.
class SessionManager {
  final SessionStore store;
  final SessionConfig config;

  SessionManager(this.store, this.config) {
    if (!config.secure) {
      // SessionConfig.secure defaults to false so cookies still work over
      // plain HTTP in local dev. There's no "environment" concept in daho
      // to gate this on, so we warn unconditionally instead of silently
      // shipping an insecure default to production.
      stderr.writeln(
        '[daho_auth] WARNING: SessionConfig.secure is false — the session '
        'cookie will be sent over plain HTTP. Set secure: true once this '
        'app is served over HTTPS (e.g. behind a TLS-terminating reverse '
        'proxy); otherwise the session ID can be intercepted in transit.',
      );
    }
  }

  /// Creates a new session and sets the session cookie on [res].
  Future<Session> createSession(
    DahoRequest req,
    DahoResponse res,
    String userId, {
    Map<String, dynamic>? data,
  }) async {
    final session = await store.create(userId, config.lifetime, data: data);
    _setCookie(res, session.id);
    return session;
  }

  /// Loads the session from the request cookie. Returns null if absent/invalid.
  Future<Session?> loadSession(DahoRequest req) async {
    final sessionId = req.cookies[config.cookieName];
    if (sessionId == null) return null;
    return store.load(sessionId);
  }

  /// Destroys the current session and clears the cookie.
  Future<void> destroySession(DahoRequest req, DahoResponse res) async {
    final sessionId = req.cookies[config.cookieName];
    if (sessionId != null) {
      await store.destroy(sessionId);
    }
    res.clearCookie(config.cookieName, path: config.cookiePath);
  }

  void _setCookie(DahoResponse res, String sessionId) {
    res.cookie(
      config.cookieName,
      sessionId,
      path: config.cookiePath,
      maxAge: config.lifetime,
      httpOnly: true,
      secure: config.secure,
      sameSite: config.sameSite,
    );
  }
}
