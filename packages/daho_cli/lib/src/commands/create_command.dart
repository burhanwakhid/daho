import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../auth_templates.dart';
import '../templates.dart';

/// `daho create <name>` — scaffolds a new Daho server project.
class CreateCommand extends Command<int> {
  CreateCommand() {
    argParser
      ..addOption(
        'local',
        help:
            'Use a path dependency to a local daho package (for development '
            'before daho is published). Value is the path to packages/daho.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Create into a non-empty directory, overwriting files.',
      )
      ..addFlag(
        'auth',
        negatable: false,
        help: 'Include daho_auth with JWT, sessions, OAuth2, and PostgreSQL.',
      );
  }

  @override
  final name = 'create';
  @override
  final description = 'Scaffold a new Daho server project.';
  @override
  String get invocation => 'daho create <project_name>';

  static final _validName = RegExp(r'^[a-z_][a-z0-9_]*$');

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      stderr.writeln('[daho] Missing project name.\nUsage: $invocation');
      return 64;
    }
    final projectName = rest.first;
    if (!_validName.hasMatch(projectName)) {
      stderr.writeln(
        "[daho] Invalid project name '$projectName'. Use lowercase letters, "
        'digits and underscores (a valid Dart package name).',
      );
      return 64;
    }

    final targetDir = Directory(p.join(Directory.current.path, projectName));
    final force = argResults!.flag('force');
    if (targetDir.existsSync() && targetDir.listSync().isNotEmpty && !force) {
      stderr.writeln(
        "[daho] Directory '$projectName' already exists and is not empty. "
        'Use --force to write into it.',
      );
      return 1;
    }

    String? localPath = argResults!.option('local');
    if (localPath != null) {
      localPath = p.absolute(localPath);
      if (!File(p.join(localPath, 'pubspec.yaml')).existsSync()) {
        stderr.writeln('[daho] --local path is not a package: $localPath');
        return 1;
      }
    }

    final useAuth = argResults!.flag('auth');

    _write(
      targetDir,
      'pubspec.yaml',
      useAuth
          ? authPubspecTemplate(
              projectName,
              localPath: localPath,
              dahoAuthLocalPath: siblingDahoAuthPath(localPath),
            )
          : pubspecTemplate(projectName, localPath: localPath),
    );
    _write(
      targetDir,
      p.join('bin', 'server.dart'),
      useAuth ? authServerTemplate(projectName) : serverTemplate(projectName),
    );
    _write(
      targetDir,
      p.join('lib', 'routes.dart'),
      useAuth ? authRoutesTemplate(projectName) : routesTemplate(projectName),
    );
    _write(targetDir, 'analysis_options.yaml', analysisOptionsTemplate());
    _write(targetDir, '.gitignore', gitignoreTemplate());
    _write(targetDir, 'README.md', readmeTemplate(projectName));

    if (useAuth) {
      _write(targetDir, 'Dockerfile', authDockerfileTemplate(projectName));
      _write(
        targetDir,
        'docker-compose.yml',
        dockerComposeTemplate(projectName),
      );
      _write(targetDir, '.env.example', envTemplate);
      _write(targetDir, 'lib/env.dart', envLoaderTemplate());
      _write(targetDir, 'lib/auth.dart', authConfigTemplate('all'));
      _write(targetDir, 'bin/migrate.dart', migrateTemplate(projectName));

      // Migrations
      final migrationsDir = Directory(p.join(targetDir.path, 'migrations'));
      migrationsDir.createSync(recursive: true);
      writeAuthMigrations(
        (filename, content) =>
            _write(targetDir, p.join('migrations', filename), content),
      );
    } else {
      _write(targetDir, 'Dockerfile', dockerfileTemplate(projectName));
    }

    stdout.writeln('\nCreated Daho project in ./$projectName\n');
    stdout.writeln('Next steps:');
    stdout.writeln('  cd $projectName');
    stdout.writeln('  dart pub get');
    if (useAuth) {
      stdout.writeln('  cp .env.example .env   # fill in secrets');
      stdout.writeln('  docker-compose up -d   # start PostgreSQL');
      stdout.writeln('  daho auth setup-db     # run migrations');
      stdout.writeln('  daho run');
    } else {
      stdout.writeln(
        '  daho run          # or: docker build -t $projectName . && docker run --rm -p 8080:8080 $projectName',
      );
    }
    return 0;
  }

  void _write(Directory root, String relativePath, String contents) {
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    stdout.writeln('  create ${p.join(p.basename(root.path), relativePath)}');
  }
}
