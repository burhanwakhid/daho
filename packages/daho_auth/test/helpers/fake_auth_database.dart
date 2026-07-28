import 'package:daho_auth/src/db/database.dart';

/// In-memory stand-in for [AuthDatabase], covering the exact query/execute
/// patterns used by daho_auth's own code (auth_routes, auth_middleware,
/// postgres_token_repository, postgres_session_store, migration_runner).
///
/// This is a small hand-written fake rather than a generic SQL engine: the
/// set of statements is fixed and known, so pattern-matching on the SQL text
/// keeps each case obvious and easy to audit.
class FakeAuthDatabase extends AuthDatabase {
  FakeAuthDatabase() : super('postgres://fake');

  final List<Map<String, dynamic>> users = [];
  final List<Map<String, dynamic>> oauthAccounts = [];
  final List<Map<String, dynamic>> refreshTokens = [];
  final List<Map<String, dynamic>> sessions = [];
  final List<Map<String, dynamic>> oauthExchangeCodes = [];
  final List<Map<String, dynamic>> migrations = [];

  /// Every SQL statement executed, in order (for assertions on call counts).
  final List<String> executedSql = [];

  int _autoId = 0;
  String _nextId() => 'row-${_autoId++}';

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async {}

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    executedSql.add(sql);
    final p = parameters ?? {};
    final s = sql.trim();

    if (s.contains('_daho_migrations')) {
      return List.of(migrations);
    }
    if (s.contains('FROM users')) {
      var rows = List<Map<String, dynamic>>.from(users);
      if (s.contains('WHERE id =')) {
        rows = rows.where((r) => r['id'] == p['id']).toList();
      } else if (s.contains('WHERE email =')) {
        rows = rows.where((r) => r['email'] == p['email']).toList();
      }
      if (s.contains('SELECT id ')) {
        rows = rows.map((r) => {'id': r['id']}).toList();
      }
      return rows;
    }
    if (s.contains('FROM oauth_accounts')) {
      return oauthAccounts
          .where(
            (r) => r['provider'] == p['p'] && r['provider_user_id'] == p['pid'],
          )
          .toList();
    }
    if (s.contains('FROM refresh_tokens')) {
      final now = DateTime.now();
      return refreshTokens
          .where(
            (r) =>
                r['jti'] == p['jti'] &&
                r['revoked'] == false &&
                (r['expires_at'] as DateTime).isAfter(now),
          )
          .toList();
    }
    if (s.contains('FROM sessions')) {
      final now = DateTime.now();
      return sessions
          .where(
            (r) =>
                r['id'] == p['id'] &&
                (r['expires_at'] as DateTime).isAfter(now),
          )
          .toList();
    }
    if (s.contains('FROM oauth_exchange_codes')) {
      final now = DateTime.now();
      final match = oauthExchangeCodes
          .where(
            (r) =>
                r['code'] == p['code'] &&
                (r['expires_at'] as DateTime).isAfter(now),
          )
          .toList();
      if (s.trimLeft().startsWith('DELETE') && match.isNotEmpty) {
        // Mirrors the real `DELETE ... RETURNING` used by
        // PostgresOAuthExchangeRepository.consume: a matched code is
        // atomically removed so it can't be exchanged twice.
        oauthExchangeCodes.remove(match.first);
      }
      return match;
    }
    throw UnimplementedError('FakeAuthDatabase.query: unhandled SQL: $sql');
  }

  @override
  Future<Map<String, dynamic>?> queryOne(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    final rows = await query(sql, parameters);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<int> execute(String sql, [Map<String, dynamic>? parameters]) async {
    executedSql.add(sql);
    final p = parameters ?? {};
    final s = sql.trim();

    if (s.startsWith('CREATE TABLE')) {
      return 0;
    }
    if (s.contains('INSERT INTO _daho_migrations')) {
      migrations.add({'version': p['v'], 'applied_at': DateTime.now()});
      return 1;
    }
    if (s.contains('INSERT INTO users')) {
      users.add({
        'id': p['id'],
        'email': p['email'],
        'name': p['name'],
        'password_hash': p['hash'],
        'role': 'user',
        'created_at': DateTime.now(),
        'updated_at': DateTime.now(),
      });
      return 1;
    }
    if (s.contains('INSERT INTO oauth_accounts')) {
      oauthAccounts.add({
        'id': p['id'],
        'user_id': p['uid'],
        'provider': p['p'],
        'provider_user_id': p['pid'],
        'access_token': p['at'],
        'refresh_token': p['rt'],
        'created_at': DateTime.now(),
      });
      return 1;
    }
    if (s.contains('UPDATE oauth_accounts')) {
      final row = oauthAccounts.firstWhere((r) => r['id'] == p['id']);
      row['access_token'] = p['at'];
      row['refresh_token'] = p['rt'];
      return 1;
    }
    if (s.contains('INSERT INTO refresh_tokens')) {
      refreshTokens.add({
        'jti': p['jti'],
        'user_id': p['uid'],
        'expires_at': p['exp'],
        'revoked': false,
      });
      return 1;
    }
    if (s.contains('UPDATE refresh_tokens SET revoked = TRUE WHERE jti')) {
      for (final r in refreshTokens.where((r) => r['jti'] == p['jti'])) {
        r['revoked'] = true;
      }
      return 1;
    }
    if (s.contains('UPDATE refresh_tokens SET revoked = TRUE WHERE user_id')) {
      for (final r in refreshTokens.where((r) => r['user_id'] == p['uid'])) {
        r['revoked'] = true;
      }
      return 1;
    }
    if (s.contains('INSERT INTO sessions')) {
      sessions.add({
        'id': p['id'],
        'user_id': p['uid'],
        'data': p['data'],
        'expires_at': p['exp'],
        'created_at': DateTime.now(),
      });
      return 1;
    }
    if (s.contains('UPDATE sessions SET data')) {
      final row = sessions.firstWhere((r) => r['id'] == p['id']);
      row['data'] = p['data'];
      return 1;
    }
    if (s.contains('DELETE FROM sessions WHERE id')) {
      final before = sessions.length;
      sessions.removeWhere((r) => r['id'] == p['id']);
      return before - sessions.length;
    }
    if (s.contains('DELETE FROM sessions WHERE user_id')) {
      final before = sessions.length;
      sessions.removeWhere((r) => r['user_id'] == p['uid']);
      return before - sessions.length;
    }
    if (s.contains('INSERT INTO oauth_exchange_codes')) {
      oauthExchangeCodes.add({
        'code': p['code'],
        'user_id': p['uid'],
        'access_token': p['at'],
        'refresh_token': p['rt'],
        'expires_at': p['exp'],
        'created_at': DateTime.now(),
      });
      return 1;
    }
    throw UnimplementedError('FakeAuthDatabase.execute: unhandled SQL: $sql');
  }

  /// Convenience: seeds a user row directly (bypassing SQL) for test setup.
  Map<String, dynamic> seedUser({
    String? id,
    required String email,
    String? name,
    String? passwordHash,
    String role = 'user',
  }) {
    final row = {
      'id': id ?? _nextId(),
      'email': email,
      'name': name,
      'password_hash': passwordHash,
      'role': role,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };
    users.add(row);
    return row;
  }
}
