import 'dart:convert';
import 'package:http/http.dart' as http;
import 'oauth_provider.dart';
import 'oauth_tokens.dart';

class GitHubOAuthProvider implements OAuthProvider {
  @override
  final String name = 'github';

  final String clientId;
  final String clientSecret;
  final String redirectUri;

  GitHubOAuthProvider({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
  });

  @override
  String getAuthorizationUrl(String state) {
    final params = Uri(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': 'user:email',
      'state': state,
    });
    return 'https://github.com/login/oauth/authorize$params';
  }

  @override
  Future<OAuthTokens> exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse('https://github.com/login/oauth/access_token'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub OAuth token exchange failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw Exception('GitHub OAuth error: ${json['error_description']}');
    }
    return OAuthTokens(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String?,
      expiresIn: json['expires_in'] as int?,
    );
  }

  @override
  Future<OAuthUserProfile> getUserProfile(String accessToken) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/vnd.github+json',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub user profile failed: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    String? email = json['email'] as String?;
    if (email == null || email.isEmpty) {
      email = await _fetchPrimaryEmail(accessToken);
    }

    return OAuthUserProfile(
      providerUserId: (json['id'] as int).toString(),
      email: email!,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Future<String?> _fetchPrimaryEmail(String accessToken) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user/emails'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/vnd.github+json',
      },
    );
    if (response.statusCode != 200) return null;
    final emails = jsonDecode(response.body) as List<dynamic>;
    for (final e in emails) {
      if (e['primary'] == true && e['verified'] == true) {
        return e['email'] as String;
      }
    }
    return null;
  }
}
