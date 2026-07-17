import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../toolchain.dart';

/// `daho run [entrypoint]` — builds the native library if needed, then runs the
/// server. OS-aware: it checks for the compiled library and compiles it (after
/// verifying the toolchain) before starting the Dart entrypoint.
class RunCommand extends Command<int> {
  RunCommand() {
    argParser.addFlag(
      'no-build',
      negatable: false,
      help: 'Skip the native build step (assume the library is already built).',
    );
  }

  @override
  final name = 'run';
  @override
  final description = 'Build (if needed) and run the Daho server.';

  @override
  String get invocation => 'daho run [entrypoint]';

  /// Candidate entrypoints tried when none is given.
  static const _defaultEntrypoints = ['bin/server.dart', 'bin/main.dart'];

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;

    final dahoDir = resolveDahoPackageDir(projectRoot);
    if (dahoDir == null) {
      stderr.writeln(
        "[daho] Could not locate the 'daho' package. Run this inside a Daho "
        "project after 'dart pub get'.",
      );
      return 1;
    }

    if (!argResults!.flag('no-build')) {
      final code = await buildNative(dahoDir);
      if (code != 0) return code;
    }

    final entrypoint = _resolveEntrypoint(projectRoot);
    if (entrypoint == null) return 1;

    stdout.writeln('[daho] running $entrypoint\n');
    final proc = await Process.start(
      'dart',
      ['run', entrypoint],
      workingDirectory: projectRoot,
      mode: ProcessStartMode.inheritStdio,
    );
    return proc.exitCode;
  }

  String? _resolveEntrypoint(String projectRoot) {
    final rest = argResults!.rest;
    if (rest.isNotEmpty) {
      final path = rest.first;
      if (File(p.join(projectRoot, path)).existsSync()) return path;
      stderr.writeln('[daho] entrypoint not found: $path');
      return null;
    }
    for (final candidate in _defaultEntrypoints) {
      if (File(p.join(projectRoot, candidate)).existsSync()) return candidate;
    }
    stderr.writeln(
      '[daho] No entrypoint found (looked for ${_defaultEntrypoints.join(', ')}).\n'
      '       Pass one explicitly: daho run bin/my_server.dart',
    );
    return null;
  }
}
