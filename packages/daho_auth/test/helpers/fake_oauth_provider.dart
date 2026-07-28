import 'package:daho_auth/daho_auth.dart';

/// Scriptable [OAuthProvider] stand-in — no network calls.
class FakeOAuthProvider implements OAuthProvider {
  @override
  final String name;

  /// If set, [exchangeCode] throws this instead of returning tokens.
  Object? exchangeError;
  OAuthTokens tokens;
  OAuthUserProfile profile;
  String? lastCodeExchanged;

  FakeOAuthProvider({
    this.name = 'fake',
    OAuthTokens? tokens,
    OAuthUserProfile? profile,
  }) : tokens = tokens ?? const OAuthTokens(accessToken: 'fake-access-token'),
       profile =
           profile ??
           const OAuthUserProfile(
             providerUserId: 'fake-provider-id',
             email: 'oauth-user@example.com',
             name: 'OAuth User',
           );

  @override
  String getAuthorizationUrl(String state) =>
      'https://fake-provider.example.com/authorize?state=$state';

  @override
  Future<OAuthTokens> exchangeCode(String code) async {
    lastCodeExchanged = code;
    if (exchangeError != null) throw exchangeError!;
    return tokens;
  }

  @override
  Future<OAuthUserProfile> getUserProfile(String accessToken) async {
    return profile;
  }
}
