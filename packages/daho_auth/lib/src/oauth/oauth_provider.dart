import 'oauth_tokens.dart';

/// Represents the user profile returned by an OAuth provider.
class OAuthUserProfile {
  final String providerUserId;
  final String email;
  final String? name;
  final String? avatarUrl;

  const OAuthUserProfile({
    required this.providerUserId,
    required this.email,
    this.name,
    this.avatarUrl,
  });
}

/// Abstract OAuth2 provider.
abstract class OAuthProvider {
  /// The provider identifier (e.g. 'google', 'github').
  String get name;

  /// Generates the authorization URL the client should redirect to.
  String getAuthorizationUrl(String state);

  /// Exchanges an authorization [code] for tokens.
  Future<OAuthTokens> exchangeCode(String code);

  /// Fetches the authenticated user's profile using the [accessToken].
  Future<OAuthUserProfile> getUserProfile(String accessToken);
}
