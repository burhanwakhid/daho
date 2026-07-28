import 'package:daho_auth/daho_auth.dart';

class _StoredToken {
  final String userId;
  DateTime expiresAt;
  bool revoked = false;
  _StoredToken(this.userId, this.expiresAt);
}

/// In-memory [TokenRepository] for tests — no Postgres required.
class FakeTokenRepository implements TokenRepository {
  final Map<String, _StoredToken> _tokens = {};

  @override
  Future<String> store(String userId, String jti, DateTime expiresAt) async {
    _tokens[jti] = _StoredToken(userId, expiresAt);
    return jti;
  }

  @override
  Future<String?> validate(String jti) async {
    final token = _tokens[jti];
    if (token == null) return null;
    if (token.revoked) return null;
    if (token.expiresAt.isBefore(DateTime.now())) return null;
    return token.userId;
  }

  @override
  Future<void> revoke(String jti) async {
    _tokens[jti]?.revoked = true;
  }

  @override
  Future<void> revokeAllForUser(String userId) async {
    for (final token in _tokens.values.where((t) => t.userId == userId)) {
      token.revoked = true;
    }
  }

  bool isRevoked(String jti) => _tokens[jti]?.revoked ?? false;
  bool contains(String jti) => _tokens.containsKey(jti);
}
