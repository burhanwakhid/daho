import 'package:daho_auth/daho_auth.dart';
import 'package:test/test.dart';

void main() {
  group('JwtConfig defaults', () {
    test('defaults match documented values', () {
      const config = JwtConfig(secret: 's');
      expect(config.accessTokenLifetime, const Duration(minutes: 15));
      expect(config.refreshTokenLifetime, const Duration(days: 7));
      expect(config.issuer, 'daho-auth');
    });
  });

  group('SessionConfig defaults', () {
    test(
      'defaults are safe-by-default for local dev, not silently insecure',
      () {
        const config = SessionConfig();
        expect(config.cookieName, 'daho_session');
        expect(config.lifetime, const Duration(days: 7));
        expect(config.cookiePath, '/');
        expect(config.sameSite, 'Lax');
        // NOTE: `secure` defaults to false so the cookie works over plain
        // HTTP in local dev. Deployments MUST override this to `true` once
        // served over HTTPS — see reported finding.
        expect(config.secure, isFalse);
      },
    );
  });

  group('OAuthConfig defaults', () {
    test('all provider credentials are unset by default', () {
      const config = OAuthConfig();
      expect(config.googleClientId, isNull);
      expect(config.googleClientSecret, isNull);
      expect(config.googleRedirectUri, isNull);
      expect(config.githubClientId, isNull);
      expect(config.githubClientSecret, isNull);
      expect(config.githubRedirectUri, isNull);
    });
  });

  group('AuthConfig defaults', () {
    test('redirects default to root and /login', () {
      final config = AuthConfig(
        jwt: const JwtConfig(secret: 's'),
        databaseUrl: 'postgres://localhost/db',
      );
      expect(config.oauthSuccessRedirect, '/');
      expect(config.oauthFailureRedirect, '/login');
      expect(config.session, isA<SessionConfig>());
      expect(config.oauth, isA<OAuthConfig>());
    });
  });
}
