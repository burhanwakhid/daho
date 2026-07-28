/// Abstract interface for password hashing.
///
/// Allows swapping bcrypt for argon2 or other algorithms in the future.
abstract class PasswordHasher {
  /// Hashes [password] with a random salt. Returns the hash string.
  Future<String> hash(String password);

  /// Verifies [password] against [hash]. Returns true if they match.
  Future<bool> verify(String password, String hash);
}
