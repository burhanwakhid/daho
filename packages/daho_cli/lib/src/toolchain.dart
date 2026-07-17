import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Platform-specific filename of the compiled native wrapper library.
String get nativeLibName {
  if (Platform.isMacOS) return 'libh2o_wrapper.dylib';
  if (Platform.isWindows) return 'h2o_wrapper.dll';
  return 'libh2o_wrapper.so';
}

/// Directories searched for the H2O headers (mirrors the CMake HINTS).
const List<String> h2oIncludeHints = [
  '/opt/homebrew/include',
  '/usr/local/include',
  '/usr/include',
];

/// Directories searched for the H2O evloop library.
const List<String> h2oLibHints = [
  '/opt/homebrew/lib',
  '/usr/local/lib',
  '/usr/lib',
  '/usr/lib/x86_64-linux-gnu',
  '/usr/lib/aarch64-linux-gnu',
];

/// Returns the path to `h2o.h` if found in a known location.
String? findH2oHeader() {
  for (final dir in h2oIncludeHints) {
    final f = p.join(dir, 'h2o.h');
    if (File(f).existsSync()) return f;
  }
  return null;
}

/// Returns the path to the H2O evloop shared library if found.
String? findH2oLib() {
  final names = Platform.isMacOS
      ? ['libh2o-evloop.dylib']
      : ['libh2o-evloop.so'];
  for (final dir in h2oLibHints) {
    for (final name in names) {
      final f = p.join(dir, name);
      if (File(f).existsSync()) return f;
    }
  }
  return null;
}

/// Whether an executable is on PATH.
bool commandExists(String cmd) {
  try {
    final which = Platform.isWindows ? 'where' : 'which';
    return Process.runSync(which, [cmd]).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// The command (or guidance) to obtain H2O on the current platform.
///
/// H2O is a Unix server (epoll/kqueue); there is no native Windows build, so on
/// Windows we point users at WSL2 or Docker instead of a package command.
String h2oInstallHint() {
  if (Platform.isMacOS) return 'brew install h2o';
  if (Platform.isLinux) {
    // Package name varies by distro; Debian/Ubuntu ship libh2o-evloop-dev.
    return 'sudo apt-get install -y libh2o-evloop-dev cmake '
        '(or build h2o from source)';
  }
  if (Platform.isWindows) {
    return 'H2O has no native Windows build. Use WSL2 '
        '(then: sudo apt-get install -y libh2o-evloop-dev cmake) '
        'or run in Docker (see the generated Dockerfile).';
  }
  return 'Install H2O (h2o-evloop) and CMake for your platform.';
}

/// Resolves the directory of the `daho` package as seen by the project at
/// [startDir], by reading `.dart_tool/package_config.json`.
///
/// Searches [startDir] and each parent directory, so it works both in a plain
/// project and from a subdirectory of a pub workspace (where the single
/// `package_config.json` lives at the workspace root). Returns null if no
/// config is found or the resolved project does not depend on `daho`.
String? resolveDahoPackageDir(String startDir) {
  final configFile = _findPackageConfig(startDir);
  if (configFile == null) return null;

  final json =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = (json['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  for (final pkg in packages) {
    if (pkg['name'] == 'daho') {
      // rootUri is relative to the .dart_tool directory.
      final base = configFile.parent.uri;
      final resolved = base.resolve(pkg['rootUri'] as String);
      return p.normalize(resolved.toFilePath());
    }
  }
  return null;
}

/// Walks up from [startDir] looking for `.dart_tool/package_config.json`.
File? _findPackageConfig(String startDir) {
  var dir = Directory(p.absolute(startDir));
  while (true) {
    final candidate = File(
      p.join(dir.path, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // reached filesystem root
    dir = parent;
  }
}

/// Absolute path to the built native library inside a daho package dir, whether
/// or not it exists yet.
String nativeLibPath(String dahoDir) =>
    p.join(dahoDir, 'c_src', 'build', nativeLibName);

/// Builds the native wrapper for the daho package at [dahoDir] using CMake.
///
/// Skips the build if the library already exists unless [force] is set.
/// Returns the process exit code (0 on success).
Future<int> buildNative(String dahoDir, {bool force = false}) async {
  final cSrc = p.join(dahoDir, 'c_src');
  final buildDir = p.join(cSrc, 'build');
  final lib = nativeLibPath(dahoDir);

  if (!force && File(lib).existsSync()) {
    stdout.writeln('[daho] native library already built: $lib');
    return 0;
  }

  if (!commandExists('cmake')) {
    stderr.writeln('[daho] cmake not found. Install it and re-run.');
    return 1;
  }
  if (findH2oHeader() == null || findH2oLib() == null) {
    stderr.writeln('[daho] H2O not found.');
    stderr.writeln('[daho] Try: ${h2oInstallHint()}');
    return 1;
  }

  Directory(buildDir).createSync(recursive: true);

  stdout.writeln('[daho] configuring (cmake)...');
  final configure = await _stream('cmake', ['..'], buildDir);
  if (configure != 0) return configure;

  stdout.writeln('[daho] building native library...');
  return _stream('cmake', ['--build', '.'], buildDir);
}

/// Runs a command in [workingDir], forwarding its output, and returns the code.
Future<int> _stream(String exe, List<String> args, String workingDir) async {
  final proc = await Process.start(
    exe,
    args,
    workingDirectory: workingDir,
    mode: ProcessStartMode.inheritStdio,
  );
  return proc.exitCode;
}
