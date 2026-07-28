## 0.1.0

- Initial release.
- JWT authentication with access + refresh token rotation.
- Session-based authentication with server-side sessions.
- OAuth2 support for Google and GitHub providers.
- bcrypt password hashing (12 rounds default).
- PostgreSQL database with auto-migrations.
- Built-in auth route handlers (register, login, refresh, logout, OAuth callback).
- Role-based authorization middleware.
- CLI integration: `daho auth add`, `daho auth setup-db`.
- Docker Compose template with PostgreSQL.
