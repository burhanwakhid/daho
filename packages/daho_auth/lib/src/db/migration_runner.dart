import 'dart:io';
import 'package:path/path.dart' as p;
import 'database.dart';

/// Applies SQL migrations from a directory, tracking applied versions in a
/// `_daho_migrations` table.
class MigrationRunner {
  final AuthDatabase db;
  final String migrationsDir;

  MigrationRunner(this.db, {this.migrationsDir = 'migrations'});

  /// Runs all pending migrations in order.
  Future<void> migrate() async {
    await _ensureMigrationsTable();
    final applied = await _appliedVersions();
    final files = _loadMigrationFiles();

    for (final file in files) {
      final version = _extractVersion(file);
      if (applied.contains(version)) continue;

      final sql = File(p.join(migrationsDir, file)).readAsStringSync();
      stdout.writeln('[daho_auth] Applying migration: $file');
      await db.execute(sql);
      await db.execute(
        'INSERT INTO _daho_migrations (version, applied_at) VALUES (@v, NOW())',
        {'v': version},
      );
      stdout.writeln('[daho_auth] Applied: $file');
    }
  }

  Future<void> _ensureMigrationsTable() async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _daho_migrations (
        version VARCHAR(255) PRIMARY KEY,
        applied_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    ''');
  }

  Future<Set<String>> _appliedVersions() async {
    final rows = await db.query(
      'SELECT version FROM _daho_migrations ORDER BY version',
    );
    return rows.map((r) => r['version'] as String).toSet();
  }

  List<String> _loadMigrationFiles() {
    final dir = Directory(migrationsDir);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .map((f) => p.basename(f.path))
        .toList()
      ..sort();
  }

  String _extractVersion(String filename) {
    final match = RegExp(r'^(\d+)_').firstMatch(filename);
    return match?.group(1) ?? filename;
  }
}
