/// A server-side session.
class Session {
  final String id;
  final String userId;
  final Map<String, dynamic> data;
  final DateTime expiresAt;
  final DateTime createdAt;

  Session({
    required this.id,
    required this.userId,
    this.data = const {},
    required this.expiresAt,
    required this.createdAt,
  });

  factory Session.fromRow(Map<String, dynamic> row) {
    return Session(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      data: row['data'] != null
          ? Map<String, dynamic>.from(row['data'] as Map)
          : {},
      expiresAt: row['expires_at'] as DateTime,
      createdAt: row['created_at'] as DateTime,
    );
  }
}
