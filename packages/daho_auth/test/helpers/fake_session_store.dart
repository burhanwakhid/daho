import 'package:daho_auth/daho_auth.dart';
import 'package:uuid/uuid.dart';

/// In-memory [SessionStore] for tests — no Postgres required.
class FakeSessionStore implements SessionStore {
  final Map<String, Session> _sessions = {};
  final _uuid = const Uuid();

  @override
  Future<Session> create(
    String userId,
    Duration lifetime, {
    Map<String, dynamic>? data,
  }) async {
    final session = Session(
      id: _uuid.v4(),
      userId: userId,
      data: data ?? const {},
      expiresAt: DateTime.now().add(lifetime),
      createdAt: DateTime.now(),
    );
    _sessions[session.id] = session;
    return session;
  }

  @override
  Future<Session?> load(String id) async {
    final session = _sessions[id];
    if (session == null) return null;
    if (session.expiresAt.isBefore(DateTime.now())) return null;
    return session;
  }

  @override
  Future<void> update(String id, Map<String, dynamic> data) async {
    final session = _sessions[id];
    if (session == null) return;
    _sessions[id] = Session(
      id: session.id,
      userId: session.userId,
      data: data,
      expiresAt: session.expiresAt,
      createdAt: session.createdAt,
    );
  }

  @override
  Future<void> destroy(String id) async {
    _sessions.remove(id);
  }

  @override
  Future<void> destroyAllForUser(String userId) async {
    _sessions.removeWhere((_, s) => s.userId == userId);
  }

  bool get isEmpty => _sessions.isEmpty;
  int get length => _sessions.length;
}
