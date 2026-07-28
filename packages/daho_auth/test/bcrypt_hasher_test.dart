import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

void main() {
  group('BcryptHasher', () {
    late BcryptHasher hasher;

    setUp(() {
      // Lower rounds than the 12-round default to keep the suite fast.
      hasher = BcryptHasher(logRounds: 4);
    });

    test('verify succeeds for the correct password', () async {
      final hash = await hasher.hash('correct horse battery staple');
      expect(await hasher.verify('correct horse battery staple', hash), isTrue);
    });

    test('verify fails for an incorrect password', () async {
      final hash = await hasher.hash('correct horse battery staple');
      expect(await hasher.verify('wrong password', hash), isFalse);
    });

    test('hash is salted: same password hashes differently each time', () async {
      final h1 = await hasher.hash('same-password');
      final h2 = await hasher.hash('same-password');
      expect(h1, isNot(equals(h2)));
      expect(await hasher.verify('same-password', h1), isTrue);
      expect(await hasher.verify('same-password', h2), isTrue);
    });

    test('hash is never the plaintext password', () async {
      final hash = await hasher.hash('super-secret');
      expect(hash, isNot(contains('super-secret')));
    });

    test('a hash produced by one hasher instance verifies on another', () async {
      final other = BcryptHasher(logRounds: 4);
      final hash = await hasher.hash('cross-instance');
      expect(await other.verify('cross-instance', hash), isTrue);
    });

    test('verify is case sensitive', () async {
      final hash = await hasher.hash('Password123');
      expect(await hasher.verify('password123', hash), isFalse);
    });
  });
}
