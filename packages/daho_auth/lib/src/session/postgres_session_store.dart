import 'package:uuid/uuid.dart';
import '../db/database.dart';
import 'session.dart';
import 'session_store.dart';

/// PostgreSQL-backed session store.
class PostgresSessionStore implements SessionStore {
  final AuthDatabase db;
  final _uuid = const Uuid();

  PostgresSessionStore(this.db);

  @override
  Future<Session> create(
    String userId,
    Duration lifetime, {
    Map<String, dynamic>? data,
  }) async {
    final id = _uuid.v4();
    final expiresAt = DateTime.now().add(lifetime);

    await db.execute(
      '''INSERT INTO sessions (id, user_id, data, expires_at) 
         VALUES (@id, @uid, @data, @exp)''',
      {'id': id, 'uid': userId, 'data': data ?? {}, 'exp': expiresAt},
    );

    return Session(
      id: id,
      userId: userId,
      data: data ?? {},
      expiresAt: expiresAt,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<Session?> load(String id) async {
    final row = await db.queryOne(
      'SELECT * FROM sessions WHERE id = @id AND expires_at > NOW()',
      {'id': id},
    );
    if (row == null) return null;
    return Session.fromRow(row);
  }

  @override
  Future<void> update(String id, Map<String, dynamic> data) async {
    await db.execute('UPDATE sessions SET data = @data WHERE id = @id', {
      'id': id,
      'data': data,
    });
  }

  @override
  Future<void> destroy(String id) async {
    await db.execute('DELETE FROM sessions WHERE id = @id', {'id': id});
  }

  @override
  Future<void> destroyAllForUser(String userId) async {
    await db.execute('DELETE FROM sessions WHERE user_id = @uid', {
      'uid': userId,
    });
  }
}
