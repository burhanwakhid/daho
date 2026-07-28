import 'package:bcrypt/bcrypt.dart';
import 'password_hasher.dart';

/// bcrypt-based password hasher (12 rounds by default).
class BcryptHasher implements PasswordHasher {
  final int logRounds;

  BcryptHasher({this.logRounds = 12});

  @override
  Future<String> hash(String password) async {
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: logRounds));
  }

  @override
  Future<bool> verify(String password, String hash) async {
    return BCrypt.checkpw(password, hash);
  }
}
