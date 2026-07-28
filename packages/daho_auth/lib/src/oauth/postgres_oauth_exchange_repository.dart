import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../token/token_pair.dart';
import 'oauth_exchange_repository.dart';
import 'token_pair_result.dart';

/// PostgreSQL-backed [OAuthExchangeRepository].
class PostgresOAuthExchangeRepository implements OAuthExchangeRepository {
  final AuthDatabase db;
  final _uuid = const Uuid();

  PostgresOAuthExchangeRepository(this.db);

  @override
  Future<String> store(TokenPairResult result, DateTime expiresAt) async {
    final code = _uuid.v4();
    await db.execute(
      '''INSERT INTO oauth_exchange_codes
           (code, user_id, access_token, refresh_token, expires_at)
         VALUES (@code, @uid, @at, @rt, @exp)''',
      {
        'code': code,
        'uid': result.userId,
        'at': result.tokenPair.accessToken,
        'rt': result.tokenPair.refreshToken,
        'exp': expiresAt,
      },
    );
    return code;
  }

  @override
  Future<TokenPairResult?> consume(String code) async {
    // DELETE ... RETURNING makes the read-and-invalidate atomic: two
    // concurrent exchange attempts for the same code can't both succeed.
    final row = await db.queryOne(
      '''DELETE FROM oauth_exchange_codes
         WHERE code = @code AND expires_at > NOW()
         RETURNING *''',
      {'code': code},
    );
    if (row == null) return null;

    return TokenPairResult(
      userId: row['user_id'] as String,
      tokenPair: TokenPair(
        accessToken: row['access_token'] as String,
        refreshToken: row['refresh_token'] as String,
      ),
    );
  }
}
