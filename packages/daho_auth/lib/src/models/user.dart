/// Application user stored in the database.
class User {
  final String id;
  final String email;
  final String? name;
  final String? passwordHash;

  /// Authorization role, e.g. 'user' or 'admin'. Always defaults to 'user'
  /// — never settable by the user themselves (see [AuthRoutes]'s
  /// registration/OAuth handlers, which never read a role from request
  /// input). Change it out-of-band (e.g. directly in the database, or via
  /// an admin-only endpoint you add) to grant elevated roles.
  final String role;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether this user signed up via OAuth (no password).
  bool get isOAuthUser => passwordHash == null;

  User({
    required this.id,
    required this.email,
    this.name,
    this.passwordHash,
    this.role = 'user',
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromRow(Map<String, dynamic> row) {
    return User(
      id: row['id'] as String,
      email: row['email'] as String,
      name: row['name'] as String?,
      passwordHash: row['password_hash'] as String?,
      role: row['role'] as String? ?? 'user',
      createdAt: row['created_at'] as DateTime,
      updatedAt: row['updated_at'] as DateTime,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'role': role,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
