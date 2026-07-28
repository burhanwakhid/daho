import '../db/database.dart';
import 'token_repository.dart';

/// PostgreSQL-backed token repository for refresh tokens.
class PostgresTokenRepository implements TokenRepository {
  final AuthDatabase db;

  PostgresTokenRepository(this.db);

  @override
  Future<String> store(String userId, String jti, DateTime expiresAt) async {
    await db.execute(
      '''INSERT INTO refresh_tokens (jti, user_id, expires_at) 
         VALUES (@jti, @uid, @exp)''',
      {'jti': jti, 'uid': userId, 'exp': expiresAt},
    );
    return jti;
  }

  @override
  Future<String?> validate(String jti) async {
    final row = await db.queryOne(
      'SELECT user_id FROM refresh_tokens WHERE jti = @jti AND revoked = FALSE AND expires_at > NOW()',
      {'jti': jti},
    );
    return row?['user_id'] as String?;
  }

  @override
  Future<void> revoke(String jti) async {
    await db.execute(
      'UPDATE refresh_tokens SET revoked = TRUE WHERE jti = @jti',
      {'jti': jti},
    );
  }

  @override
  Future<void> revokeAllForUser(String userId) async {
    await db.execute(
      'UPDATE refresh_tokens SET revoked = TRUE WHERE user_id = @uid',
      {'uid': userId},
    );
  }
}
