import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../auth_templates.dart';

/// `daho auth <subcommand>` — manage authentication setup.
class AuthCommand extends Command<int> {
  @override
  final name = 'auth';
  @override
  final description =
      'Manage authentication (add providers, setup DB, generate migrations).';

  AuthCommand() {
    addSubcommand(AuthAddCommand());
    addSubcommand(AuthSetupDbCommand());
  }
}

/// `daho auth add` — adds daho_auth dependency and generates boilerplate.
class AuthAddCommand extends Command<int> {
  @override
  final name = 'add';
  @override
  final description =
      'Add daho_auth to the current project and generate auth boilerplate.';

  AuthAddCommand() {
    argParser
      ..addOption(
        'provider',
        allowed: ['jwt', 'session', 'google', 'github', 'all'],
        defaultsTo: 'all',
        help: 'Which auth providers to enable.',
      )
      ..addOption(
        'local',
        help:
            'Use path dependencies to a local daho/daho_auth checkout (for '
            'development before daho_auth is published — it has '
            "publish_to: none, so the hosted 'daho_auth: ^0.1.0' dependency "
            'never resolves without this). Value is the path to '
            'packages/daho; packages/daho_auth is assumed to be its sibling.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Overwrite existing auth files.',
      );
  }

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;
    final pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      stderr.writeln(
        '[daho] No pubspec.yaml found. Run this inside a Daho project.',
      );
      return 1;
    }

    final provider = argResults!.option('provider')!;
    final force = argResults!.flag('force');

    String? localPath = argResults!.option('local');
    if (localPath != null) {
      localPath = p.absolute(localPath);
      if (!File(p.join(localPath, 'pubspec.yaml')).existsSync()) {
        stderr.writeln('[daho] --local path is not a package: $localPath');
        return 1;
      }
    }

    final projectName = _readPackageName(pubspec);
    if (projectName == null) {
      stderr.writeln("[daho] Could not find 'name:' in pubspec.yaml.");
      return 1;
    }

    // 1. Add daho_auth (and daho, if --local) dependency
    _addDependency(pubspec, localPath);

    // 2. Generate migrations directory + SQL files
    final migrationsDir = Directory(p.join(projectRoot, 'migrations'));
    migrationsDir.createSync(recursive: true);
    writeAuthMigrations(
      (filename, content) =>
          _writeIfAbsent(p.join(migrationsDir.path, filename), content, force),
    );

    // 3. Generate env loader + auth config file
    final libDir = Directory(p.join(projectRoot, 'lib'));
    libDir.createSync(recursive: true);
    _writeIfAbsent(p.join(libDir.path, 'env.dart'), envLoaderTemplate(), force);
    _writeIfAbsent(
      p.join(libDir.path, 'auth.dart'),
      authConfigTemplate(provider),
      force,
    );

    // 4. Generate .env template
    _writeIfAbsent(p.join(projectRoot, '.env.example'), envTemplate, force);

    // 5. Generate bin/migrate.dart — `daho auth setup-db` shells out to it.
    final binDir = Directory(p.join(projectRoot, 'bin'));
    binDir.createSync(recursive: true);
    _writeIfAbsent(
      p.join(binDir.path, 'migrate.dart'),
      migrateTemplate(projectName),
      force,
    );

    stdout.writeln('\ndaho_auth added. Next steps:');
    stdout.writeln('  1. Copy .env.example to .env and fill in secrets');
    stdout.writeln('  2. Run: dart pub get');
    stdout.writeln('  3. Run: daho auth setup-db');
    stdout.writeln('  4. Import lib/auth.dart in your server and use the middleware');
    return 0;
  }

  String? _readPackageName(File pubspec) {
    final match = RegExp(
      r'^name:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    return match?.group(1);
  }

  void _addDependency(File pubspec, String? localPath) {
    var content = pubspec.readAsStringSync();
    if (content.contains('daho_auth:')) {
      stdout.writeln('[daho] daho_auth already in pubspec.yaml');
      return;
    }
    final dahoAuthPath = siblingDahoAuthPath(localPath);
    final dependencyLine = dahoAuthPath != null
        ? '  daho_auth:\n    path: $dahoAuthPath\n'
        : '  daho_auth: ^0.1.0\n';
    // Insert right after the `dependencies:` header line. Note: `String`'s
    // replaceFirst does NOT support `$0`/`$1` backreferences in the
    // replacement (that requires replaceFirstMapped) — a naive
    // `replaceFirst(RegExp('...'), r'$0...')` silently replaces the whole
    // matched dependencies block with the LITERAL text "$0...", destroying
    // every existing dependency. Matching just the header line and
    // prepending avoids that trap entirely.
    content = content.replaceFirst('dependencies:\n', 'dependencies:\n$dependencyLine');
    pubspec.writeAsStringSync(content);
    stdout.writeln('  updated pubspec.yaml');
    if (dahoAuthPath == null) {
      stderr.writeln(
        "[daho] WARNING: daho_auth has 'publish_to: none' — it is not "
        "published to pub.dev, so 'daho_auth: ^0.1.0' will not resolve. "
        're-run with --local <path-to-packages/daho> if this is a '
        'monorepo checkout.',
      );
    }
  }

  void _writeIfAbsent(String path, String content, bool force) {
    final file = File(path);
    if (file.existsSync() && !force) {
      stdout.writeln('  skip ${p.basename(path)} (already exists)');
      return;
    }
    file.writeAsStringSync(content);
    stdout.writeln('  create ${p.basename(path)}');
  }
}

/// `daho auth setup-db` — runs migrations against the database.
class AuthSetupDbCommand extends Command<int> {
  @override
  final name = 'setup-db';
  @override
  final description = 'Run daho_auth database migrations.';

  @override
  Future<int> run() async {
    final envFile = File(p.join(Directory.current.path, '.env'));
    if (!envFile.existsSync()) {
      stderr.writeln(
        '[daho] .env file not found. Copy .env.example to .env first.',
      );
      return 1;
    }

    final env = _parseEnv(envFile);
    final databaseUrl = env['DATABASE_URL'];
    if (databaseUrl == null) {
      stderr.writeln('[daho] DATABASE_URL not set in .env');
      return 1;
    }

    stdout.writeln('[daho] Connecting to database...');
    stdout.writeln('[daho] Running migrations...');

    // Run migrations via dart
    final result = await Process.run('dart', [
      'run',
      'bin/migrate.dart',
    ], workingDirectory: Directory.current.path);

    if (result.exitCode != 0) {
      stderr.writeln('[daho] Migration failed:');
      stderr.writeln(result.stderr);
      return 1;
    }

    stdout.writeln(result.stdout);
    stdout.writeln('[daho] Migrations complete.');
    return 0;
  }

  Map<String, String> _parseEnv(File file) {
    final map = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('#') || !line.contains('=')) continue;
      final idx = line.indexOf('=');
      map[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
    return map;
  }
}
