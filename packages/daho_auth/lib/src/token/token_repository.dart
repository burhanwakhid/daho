/// Storage for refresh tokens (database-backed).
abstract class TokenRepository {
  /// Stores a refresh token for [userId]. Returns the stored record ID.
  Future<String> store(String userId, String jti, DateTime expiresAt);

  /// Validates that a refresh token [jti] exists and has not been revoked.
  /// Returns the associated userId, or null.
  Future<String?> validate(String jti);

  /// Revokes a single refresh token by its JTI.
  Future<void> revoke(String jti);

  /// Revokes all refresh tokens for [userId] (e.g. on password change).
  Future<void> revokeAllForUser(String userId);
}
