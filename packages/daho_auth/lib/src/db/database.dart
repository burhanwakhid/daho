import 'package:postgres/postgres.dart';

export 'package:postgres/postgres.dart' show SslMode;

/// Database connection wrapper for daho_auth.
///
/// Uses a connection pool. Call [close] on shutdown.
class AuthDatabase {
  Connection? _connection;
  Future<Connection>? _connecting;
  final String connectionUrl;

  /// TLS mode for the Postgres connection. Defaults to [SslMode.disable] to
  /// keep local/dev setups (e.g. a plain `docker run postgres`) working out
  /// of the box. **Set this to [SslMode.require] (or [SslMode.verifyFull]
  /// with a CA configured) for any non-local database** — otherwise
  /// credentials, session data, and password hashes travel unencrypted.
  final SslMode sslMode;

  AuthDatabase(this.connectionUrl, {this.sslMode = SslMode.disable});

  /// Opens the connection pool.
  ///
  /// Safe to call without awaiting the result — [query], [execute], and
  /// [queryOne] all internally await the same in-flight connection attempt,
  /// so a fire-and-forget `db.connect()` followed immediately by queries
  /// simply makes the first request(s) wait slightly longer rather than
  /// crashing. This matters because `AuthDatabase` is typically constructed
  /// fresh inside a Daho `routes` builder (re-run once per worker Isolate —
  /// see daho's isolate constraint docs), which must stay a synchronous,
  /// non-async function.
  Future<void> connect() => _ensureConnected();

  Future<Connection> _ensureConnected() {
    return _connecting ??= _open();
  }

  Future<Connection> _open() async {
    final uri = Uri.parse(connectionUrl);
    return _connection = await Connection.open(
      Endpoint(
        host: uri.host,
        port: uri.port,
        database: uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : 'postgres',
        username: uri.userInfo.split(':').first,
        password: uri.userInfo.contains(':')
            ? uri.userInfo.split(':').last
            : null,
      ),
      settings: ConnectionSettings(sslMode: sslMode),
    );
  }

  /// Executes a parameterized query and returns rows as maps.
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    final connection = await _ensureConnected();
    final result = await connection.execute(
      Sql.named(sql),
      parameters: parameters ?? {},
    );
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Executes a query that returns a single row, or null.
  Future<Map<String, dynamic>?> queryOne(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    final rows = await query(sql, parameters);
    return rows.isEmpty ? null : rows.first;
  }

  /// Executes a statement (INSERT, UPDATE, DELETE) and returns affected row
  /// count.
  ///
  /// With no [parameters], this uses Postgres's *simple* query protocol
  /// (`QueryMode.simple`) instead of the package's default extended/
  /// prepared-statement protocol — the latter rejects multiple
  /// `;`-separated statements in one call ("cannot insert multiple commands
  /// into a prepared statement"), which [MigrationRunner] relies on to run
  /// a whole `.sql` migration file (e.g. a `CREATE TABLE` followed by a
  /// `CREATE INDEX`) in a single [execute] call. Passing a plain `String`
  /// query alone is not enough to get the simple protocol — the package
  /// still defaults to `QueryMode.extended` unless told otherwise.
  Future<int> execute(String sql, [Map<String, dynamic>? parameters]) async {
    final connection = await _ensureConnected();
    final affected = (parameters == null || parameters.isEmpty)
        ? await connection.execute(sql, queryMode: QueryMode.simple)
        : await connection.execute(Sql.named(sql), parameters: parameters);
    return affected.affectedRows;
  }

  /// Closes the connection pool. A no-op if [connect] was never called.
  Future<void> close() async {
    final connection = _connection;
    if (connection != null) await connection.close();
  }
}
