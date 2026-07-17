import 'dart:io';

import 'package:args/command_runner.dart';

import '../toolchain.dart';

/// `daho build` — compiles the native H2O wrapper for the current platform.
class BuildCommand extends Command<int> {
  BuildCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Rebuild even if the native library already exists.',
    );
  }

  @override
  final name = 'build';
  @override
  final description = 'Compile the native library for the current platform.';

  @override
  Future<int> run() async {
    final dahoDir = resolveDahoPackageDir(Directory.current.path);
    if (dahoDir == null) {
      stderr.writeln(
        "[daho] Could not locate the 'daho' package. Run this inside a Daho "
        "project after 'dart pub get'.",
      );
      return 1;
    }
    return buildNative(dahoDir, force: argResults!.flag('force'));
  }
}
