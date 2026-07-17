import 'dart:io';

import 'package:args/command_runner.dart';

import '../toolchain.dart';

/// `daho doctor` — checks that the toolchain needed to build and run Daho is
/// present, and reports how to fix anything missing.
class DoctorCommand extends Command<int> {
  @override
  final name = 'doctor';
  @override
  final description =
      'Check the toolchain (Dart, CMake, H2O) and report issues.';

  @override
  Future<int> run() async {
    stdout.writeln('Daho environment check\n');

    var ok = true;

    _line('Dart SDK', true, Platform.version.split(' ').first);

    final cmake = commandExists('cmake');
    ok &= cmake;
    _line('CMake', cmake, cmake ? null : 'install cmake');

    final header = findH2oHeader();
    final lib = findH2oLib();
    final h2o = header != null && lib != null;
    ok &= h2o;
    _line('H2O headers', header != null, header ?? h2oInstallHint());
    _line('H2O evloop lib', lib != null, lib ?? h2oInstallHint());

    // If run inside a daho project, report whether the native lib is built.
    final dahoDir = resolveDahoPackageDir(Directory.current.path);
    if (dahoDir != null) {
      final built = File(nativeLibPath(dahoDir)).existsSync();
      _line('Native library', built, built ? null : "run 'daho build'");
    }

    stdout.writeln();
    if (ok) {
      stdout.writeln('✅ All good.');
      return 0;
    }
    stdout.writeln('⚠️  Some dependencies are missing (see above).');
    return 1;
  }

  void _line(String label, bool pass, [String? note]) {
    final mark = pass ? '✓' : '✗';
    final suffix = note == null ? '' : '  ($note)';
    stdout.writeln('  $mark ${label.padRight(16)}$suffix');
  }
}
