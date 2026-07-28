import 'session.dart';

/// Abstract storage backend for sessions.
abstract class SessionStore {
  /// Creates a new session for [userId] with the given [lifetime].
  Future<Session> create(
    String userId,
    Duration lifetime, {
    Map<String, dynamic>? data,
  });

  /// Loads a session by its [id]. Returns null if not found or expired.
  Future<Session?> load(String id);

  /// Updates session data.
  Future<void> update(String id, Map<String, dynamic> data);

  /// Destroys a session.
  Future<void> destroy(String id);

  /// Destroys all sessions for a [userId].
  Future<void> destroyAllForUser(String userId);
}
