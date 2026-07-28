import 'package:daho/daho.dart';
import 'auth_context.dart';
import 'db/database.dart';
import 'models/user.dart';
import 'session/session_manager.dart';
import 'token/jwt_service.dart';

/// Factory methods for authentication middleware.
class AuthMiddleware {
  AuthMiddleware._();

  /// JWT Bearer token middleware.
  ///
  /// Reads the `Authorization: Bearer <token>` header, verifies the JWT,
  /// loads the user from the database, and populates `req.auth`.
  ///
  /// If [required] is true (default), anonymous requests receive 401.
  /// If false, anonymous requests proceed (useful for optional auth).
  static Middleware jwt({
    required JwtService jwtService,
    required AuthDatabase db,
    bool required = true,
  }) {
    return (DahoRequest req, DahoResponse res, NextFunction next) async {
      final authHeader = req.header('authorization');
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        if (required) {
          res.unauthorized({
            'error': 'Missing or invalid Authorization header',
          });
          return;
        }
        await next();
        return;
      }

      final token = authHeader.substring(7);
      final claims = jwtService.verify(token);
      if (claims == null) {
        res.unauthorized({'error': 'Invalid or expired token'});
        return;
      }

      // Only accept access tokens
      if (claims['type'] != 'access') {
        res.unauthorized({'error': 'Invalid token type'});
        return;
      }

      final userId = claims['sub'] as String;
      final userRow = await db.queryOne('SELECT * FROM users WHERE id = @id', {
        'id': userId,
      });
      if (userRow == null) {
        res.unauthorized({'error': 'User not found'});
        return;
      }

      req.auth.user = User.fromRow(userRow);
      req.auth.jwtClaims = claims;
      await next();
    };
  }

  /// Session cookie middleware.
  ///
  /// Reads the session cookie, loads the session and user, and populates
  /// `req.auth`. If [required] is true, anonymous requests receive 401.
  static Middleware session({
    required SessionManager sessionManager,
    required AuthDatabase db,
    bool required = true,
  }) {
    return (DahoRequest req, DahoResponse res, NextFunction next) async {
      final session = await sessionManager.loadSession(req);
      if (session == null) {
        if (required) {
          res.unauthorized({'error': 'No active session'});
          return;
        }
        await next();
        return;
      }

      final userRow = await db.queryOne('SELECT * FROM users WHERE id = @id', {
        'id': session.userId,
      });
      if (userRow == null) {
        await sessionManager.destroySession(req, res);
        res.unauthorized({'error': 'User not found'});
        return;
      }

      req.auth.user = User.fromRow(userRow);
      req.auth.session = session;
      await next();
    };
  }

  /// Role-based authorization middleware. Use AFTER an auth middleware.
  ///
  /// Checks that `req.auth.user` has one of the [allowedRoles]. Reads the
  /// role directly from `user.role` (populated from the `users` table by
  /// both [jwt] and [session] above) rather than from JWT claims, so a role
  /// change in the database takes effect immediately instead of waiting for
  /// the access token to be reissued.
  static Middleware requireRole(List<String> allowedRoles) {
    return (DahoRequest req, DahoResponse res, NextFunction next) async {
      final user = req.auth.user;
      if (user == null) {
        res.unauthorized({'error': 'Authentication required'});
        return;
      }
      if (!allowedRoles.contains(user.role)) {
        res.forbidden({'error': 'Insufficient permissions'});
        return;
      }
      await next();
    };
  }
}
