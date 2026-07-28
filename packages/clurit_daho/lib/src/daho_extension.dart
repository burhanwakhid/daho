import 'package:daho/daho.dart';
import 'package:clurit/clurit.dart';

/// Extension to add Clurit template engine support to Daho.
extension CluritDahoExtension on Daho {
  /// Configures the Clurit template engine.
  ///
  /// [viewsPath] is the directory containing .clurit template files.
  /// [cachePath] is the directory for compiled template cache (optional).
  /// [debug] enables recompilation on every request (default: false).
  void configureClurit({
    required String viewsPath,
    String? cachePath,
    bool debug = false,
  }) {
    CluritEngine.instance = CluritEngine(
      viewsPath: viewsPath,
      cachePath: cachePath,
      debug: debug,
    );
  }
}
