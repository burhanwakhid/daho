import 'dart:io';

import 'package:daho_auth/daho_auth.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/fake_auth_database.dart';

void main() {
  group('MigrationRunner', () {
    late Directory tempDir;
    late FakeAuthDatabase db;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('daho_auth_migrations_');
      db = FakeAuthDatabase();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    void writeMigration(String filename, String sql) {
      File(p.join(tempDir.path, filename)).writeAsStringSync(sql);
    }

    test('applies migrations in ascending numeric order', () async {
      writeMigration('002_add_index.sql', 'CREATE TABLE b (id INT);');
      writeMigration('001_init.sql', 'CREATE TABLE a (id INT);');

      final runner = MigrationRunner(db, migrationsDir: tempDir.path);
      await runner.migrate();

      // Migrations must run 001 before 002 regardless of directory listing
      // order (the source files were written 002 then 001).
      expect(db.migrations.map((m) => m['version']), ['001', '002']);
    });

    test('skips migrations that were already applied', () async {
      writeMigration('001_init.sql', 'CREATE TABLE a (id INT);');

      final runner = MigrationRunner(db, migrationsDir: tempDir.path);
      await runner.migrate();
      expect(db.migrations, hasLength(1));

      // Second run against the same (now-populated) tracking table.
      await runner.migrate();
      expect(db.migrations, hasLength(1), reason: 'already-applied migration must not re-run');
    });

    test('applies only newly-added migrations on a subsequent run', () async {
      writeMigration('001_init.sql', 'CREATE TABLE a (id INT);');
      final runner = MigrationRunner(db, migrationsDir: tempDir.path);
      await runner.migrate();

      writeMigration('002_add_b.sql', 'CREATE TABLE b (id INT);');
      await runner.migrate();

      expect(db.migrations.map((m) => m['version']), ['001', '002']);
    });

    test('ignores non-.sql files in the migrations directory', () async {
      writeMigration('001_init.sql', 'CREATE TABLE a (id INT);');
      writeMigration('README.md', 'not a migration');

      final runner = MigrationRunner(db, migrationsDir: tempDir.path);
      await runner.migrate();

      expect(db.migrations, hasLength(1));
    });

    test('does nothing when the migrations directory does not exist', () async {
      final runner = MigrationRunner(
        db,
        migrationsDir: p.join(tempDir.path, 'does-not-exist'),
      );
      await runner.migrate();
      expect(db.migrations, isEmpty);
    });
  });
}
