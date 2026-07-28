/// Token response from an OAuth2 provider.
class OAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final String? tokenType;
  final int? expiresIn;

  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.tokenType,
    this.expiresIn,
  });
}
