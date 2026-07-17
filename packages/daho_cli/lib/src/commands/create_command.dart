import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

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

    _write(
      targetDir,
      'pubspec.yaml',
      pubspecTemplate(projectName, localPath: localPath),
    );
    _write(
      targetDir,
      p.join('bin', 'server.dart'),
      serverTemplate(projectName),
    );
    _write(
      targetDir,
      p.join('lib', 'routes.dart'),
      routesTemplate(projectName),
    );
    _write(targetDir, 'analysis_options.yaml', analysisOptionsTemplate());
    _write(targetDir, '.gitignore', gitignoreTemplate());
    _write(targetDir, 'Dockerfile', dockerfileTemplate(projectName));
    _write(targetDir, 'README.md', readmeTemplate(projectName));

    stdout.writeln('✅ Created Daho project in ./$projectName\n');
    stdout.writeln('Next steps:');
    stdout.writeln('  cd $projectName');
    stdout.writeln('  dart pub get');
    stdout.writeln(
      '  daho run          # or: docker build -t $projectName . && docker run --rm -p 8080:8080 $projectName',
    );
    return 0;
  }

  void _write(Directory root, String relativePath, String contents) {
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    stdout.writeln('  create ${p.join(p.basename(root.path), relativePath)}');
  }
}
