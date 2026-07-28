import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:uuid/uuid.dart';
import '../auth_config.dart';
import '../models/user.dart';
import 'token_pair.dart';

/// Handles JWT creation, verification, and token pair issuance.
class JwtService {
  final JwtConfig config;
  final _uuid = const Uuid();

  JwtService(this.config);

  /// Issues an access + refresh token pair for [user].
  TokenPair issueTokenPair(User user) {
    final accessToken = _sign(
      subject: user.id,
      lifetime: config.accessTokenLifetime,
      claims: {'email': user.email, 'type': 'access'},
    );
    final refreshToken = _sign(
      subject: user.id,
      lifetime: config.refreshTokenLifetime,
      claims: {'type': 'refresh', 'jti': _uuid.v4()},
    );
    return TokenPair(accessToken: accessToken, refreshToken: refreshToken);
  }

  /// Verifies [token] and returns its payload, or null if invalid/expired.
  Map<String, dynamic>? verify(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(config.secret));
      return jwt.payload as Map<String, dynamic>;
    } on JWTException {
      return null;
    }
  }

  String _sign({
    required String subject,
    required Duration lifetime,
    required Map<String, dynamic> claims,
  }) {
    final now = DateTime.now();
    final jwt = JWT({
      ...claims,
      'sub': subject,
      'iss': config.issuer,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(lifetime).millisecondsSinceEpoch ~/ 1000,
    });
    return jwt.sign(SecretKey(config.secret));
  }
}
