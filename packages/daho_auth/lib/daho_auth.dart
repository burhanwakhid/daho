/// daho_auth — Authentication & authorization for Daho.
library;

// Config
export 'src/auth_config.dart'
    show AuthConfig, JwtConfig, SessionConfig, OAuthConfig;

// Per-request context
export 'src/auth_context.dart'
    show AuthContext, AuthRequestExtension, UnauthorizedException;

// Middleware
export 'src/auth_middleware.dart' show AuthMiddleware;

// Routes
export 'src/auth_routes.dart' show AuthRoutes;

// Password
export 'src/password/password_hasher.dart' show PasswordHasher;
export 'src/password/bcrypt_hasher.dart' show BcryptHasher;

// JWT
export 'src/token/jwt_service.dart' show JwtService;
export 'src/token/token_pair.dart' show TokenPair;
export 'src/token/token_repository.dart' show TokenRepository;
export 'src/token/postgres_token_repository.dart' show PostgresTokenRepository;

// Session
export 'src/session/session.dart' show Session;
export 'src/session/session_manager.dart' show SessionManager;
export 'src/session/session_store.dart' show SessionStore;
export 'src/session/postgres_session_store.dart' show PostgresSessionStore;

// OAuth
export 'src/oauth/oauth_provider.dart' show OAuthProvider, OAuthUserProfile;
export 'src/oauth/oauth_tokens.dart' show OAuthTokens;
export 'src/oauth/google_provider.dart' show GoogleOAuthProvider;
export 'src/oauth/github_provider.dart' show GitHubOAuthProvider;
export 'src/oauth/token_pair_result.dart' show TokenPairResult;
export 'src/oauth/oauth_exchange_repository.dart' show OAuthExchangeRepository;
export 'src/oauth/postgres_oauth_exchange_repository.dart'
    show PostgresOAuthExchangeRepository;

// Database
export 'src/db/database.dart' show AuthDatabase, SslMode;
export 'src/db/migration_runner.dart' show MigrationRunner;

// Models
export 'src/models/user.dart' show User;
export 'src/models/oauth_account.dart' show OAuthAccount;
