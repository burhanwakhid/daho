import 'dart:convert';
import 'package:http/http.dart' as http;
import 'oauth_provider.dart';
import 'oauth_tokens.dart';

class GoogleOAuthProvider implements OAuthProvider {
  @override
  final String name = 'google';

  final String clientId;
  final String clientSecret;
  final String redirectUri;

  GoogleOAuthProvider({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
  });

  @override
  String getAuthorizationUrl(String state) {
    final params = Uri(
      queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      },
    );
    return 'https://accounts.google.com/o/oauth2/v2/auth$params';
  }

  @override
  Future<OAuthTokens> exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Google OAuth token exchange failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      tokenType: json['token_type'] as String?,
      expiresIn: json['expires_in'] as int?,
    );
  }

  @override
  Future<OAuthUserProfile> getUserProfile(String accessToken) async {
    final response = await http.get(
      Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode != 200) {
      throw Exception('Google userinfo failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuthUserProfile(
      providerUserId: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      avatarUrl: json['picture'] as String?,
    );
  }
}
