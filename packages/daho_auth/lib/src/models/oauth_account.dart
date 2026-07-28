/// Links an external OAuth provider account to an application [User].
class OAuthAccount {
  final String id;
  final String userId;
  final String provider; // 'google' | 'github'
  final String providerUserId;
  final String? accessToken;
  final String? refreshToken;
  final DateTime createdAt;

  OAuthAccount({
    required this.id,
    required this.userId,
    required this.provider,
    required this.providerUserId,
    this.accessToken,
    this.refreshToken,
    required this.createdAt,
  });

  factory OAuthAccount.fromRow(Map<String, dynamic> row) {
    return OAuthAccount(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      provider: row['provider'] as String,
      providerUserId: row['provider_user_id'] as String,
      accessToken: row['access_token'] as String?,
      refreshToken: row['refresh_token'] as String?,
      createdAt: row['created_at'] as DateTime,
    );
  }
}
