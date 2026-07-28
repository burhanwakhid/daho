import 'package:daho/daho.dart';
import 'package:clurit/clurit.dart';

/// Extension to add view rendering to DahoResponse.
extension CluritResponseExtension on DahoResponse {
  /// Renders a Clurit template and sends it as HTML response.
  ///
  /// [template] is the template name (without .clurit extension).
  /// [data] is the template context data.
  DahoResponse view(String template, [Map<String, dynamic>? data]) {
    final engine = CluritEngine.instance;
    if (engine == null) {
      throw StateError(
        'CluritEngine not configured. Call app.configureClurit() first.',
      );
    }

    final html = engine.render(template, data ?? {});
    return header('Content-Type', 'text/html; charset=utf-8').send(html);
  }
}
