import '../token/token_pair.dart';

/// A [TokenPair] plus the user it was issued for, as stashed behind an
/// OAuth exchange code (see [OAuthExchangeRepository]).
class TokenPairResult {
  final String userId;
  final TokenPair tokenPair;

  const TokenPairResult({required this.userId, required this.tokenPair});
}
