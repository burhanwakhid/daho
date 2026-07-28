import 'token_pair_result.dart';

/// Storage for one-time OAuth token exchange codes.
///
/// After a successful OAuth callback, the issued [TokenPairResult] is stored
/// under an opaque, single-use `code` instead of being embedded directly in
/// the redirect URL (which would otherwise leak into browser history,
/// `Referer` headers, and server access logs). The frontend redirect target
/// receives only `?code=...` and exchanges it for the real tokens via
/// `POST /auth/oauth/exchange`.
abstract class OAuthExchangeRepository {
  /// Stores [result] under a fresh opaque code, valid until [expiresAt].
  /// Returns the code.
  Future<String> store(TokenPairResult result, DateTime expiresAt);

  /// Atomically consumes [code]: returns the stored [TokenPairResult] and
  /// deletes it so it cannot be exchanged again. Returns null if the code
  /// doesn't exist, was already consumed, or has expired.
  Future<TokenPairResult?> consume(String code);
}
