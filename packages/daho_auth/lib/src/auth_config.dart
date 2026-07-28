/// JWT token configuration.
class JwtConfig {
  /// Secret key for signing JWTs. MUST be set in production.
  final String secret;

  /// Access token lifetime (default: 15 minutes).
  final Duration accessTokenLifetime;

  /// Refresh token lifetime (default: 7 days).
  final Duration refreshTokenLifetime;

  /// JWT issuer claim.
  final String issuer;

  const JwtConfig({
    required this.secret,
    this.accessTokenLifetime = const Duration(minutes: 15),
    this.refreshTokenLifetime = const Duration(days: 7),
    this.issuer = 'daho-auth',
  });
}

/// Session-based auth configuration.
class SessionConfig {
  /// Cookie name for the session ID.
  final String cookieName;

  /// Session lifetime.
  final Duration lifetime;

  /// Cookie path.
  final String cookiePath;

  /// Set the Secure flag on the session cookie.
  final bool secure;

  /// SameSite attribute: 'Strict', 'Lax', or 'None'.
  final String sameSite;

  const SessionConfig({
    this.cookieName = 'daho_session',
    this.lifetime = const Duration(days: 7),
    this.cookiePath = '/',
    this.secure = false,
    this.sameSite = 'Lax',
  });
}

/// OAuth2 provider configuration.
class OAuthConfig {
  final String? googleClientId;
  final String? googleClientSecret;
  final String? googleRedirectUri;

  final String? githubClientId;
  final String? githubClientSecret;
  final String? githubRedirectUri;

  const OAuthConfig({
    this.googleClientId,
    this.googleClientSecret,
    this.googleRedirectUri,
    this.githubClientId,
    this.githubClientSecret,
    this.githubRedirectUri,
  });
}

/// Top-level authentication configuration.
class AuthConfig {
  final JwtConfig jwt;
  final SessionConfig session;
  final OAuthConfig oauth;

  /// PostgreSQL connection string (e.g. 'postgres://user:pass@host:5432/db').
  final String databaseUrl;

  /// Where to redirect after successful OAuth login. Receives a one-time
  /// `?code=...` query parameter (not the tokens themselves) — exchange it
  /// via `POST /auth/oauth/exchange` to get the actual access/refresh
  /// tokens back in the response body.
  final String oauthSuccessRedirect;

  /// Where to redirect after failed OAuth login.
  final String oauthFailureRedirect;

  const AuthConfig({
    required this.jwt,
    this.session = const SessionConfig(),
    this.oauth = const OAuthConfig(),
    required this.databaseUrl,
    this.oauthSuccessRedirect = '/',
    this.oauthFailureRedirect = '/login',
  });
}
