import 'package:daho/daho.dart';
import 'models/user.dart';
import 'session/session.dart';

/// Per-request authentication state, attached to [DahoRequest] via extension.
///
/// Access it in handlers with `req.auth`.
class AuthContext {
  /// The authenticated user, or null if the request is anonymous.
  User? user;

  /// The current session (for session-based auth), or null.
  Session? session;

  /// The raw JWT claims map (for JWT-based auth), or null.
  Map<String, dynamic>? jwtClaims;

  /// Whether the request has an authenticated user.
  bool get isAuthenticated => user != null;

  /// Requires authentication; throws [UnauthorizedException] if anonymous.
  User requireUser() {
    if (user == null) {
      throw UnauthorizedException('Authentication required');
    }
    return user!;
  }
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
}

/// Extension to attach [AuthContext] to [DahoRequest].
extension AuthRequestExtension on DahoRequest {
  static final Expando<AuthContext> _authExpando = Expando<AuthContext>();

  /// The authentication context for this request.
  AuthContext get auth {
    return _authExpando[this] ??= AuthContext();
  }
}
