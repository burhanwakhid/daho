import 'dart:convert';
import 'package:daho/daho.dart';
import 'package:clurit/clurit.dart';
import 'daho_extension.dart';

/// Extension to add view rendering to DahoResponse.
extension CluritResponseExtension on DahoResponse {
  /// Renders [template] and sends it as an HTML response.
  ///
  /// If a compiled `@code` component was registered under [template] via
  /// `app.registerComponent(...)`, it's constructed from [data] and
  /// rendered directly (bypassing the Blade engine) — this is how backend
  /// route handlers pass request-derived values into a reactive
  /// component, the same way they would for a plain Blade template.
  /// Otherwise, [template] is looked up as a `.clurit` file and rendered
  /// through the Blade engine as before, with [data] as its context and
  /// [state] as its hydration state.
  DahoResponse view(
    String template, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? state,
  }) {
    final factory = CluritDahoExtension.factoryFor(template);
    if (factory != null) {
      return viewComponent(factory(data ?? const {}));
    }

    final engine = CluritEngine.instance;
    if (engine == null) {
      throw StateError(
        'CluritEngine not configured. Call app.configureClurit() first.',
      );
    }

    final renderData = <String, dynamic>{...?data};

    // We try to get the request from the response context if possible.
    // In Daho, DahoResponse usually has a reference to DahoRequest or we can pass it.
    // For now, let's keep it simple and just use the passed state.

    if (state != null) {
      renderData['state'] = state;
    }

    final html = engine.render(template, renderData);
    return header('Content-Type', 'text/html; charset=utf-8').send(html);
  }

  /// Renders a compiled [CluritComponent] directly — bypassing the Blade
  /// engine entirely. Injects the component's initial state (and any
  /// `$props` values) into the page's
  /// `<script id="clurit-state" type="application/json"></script>` tag so
  /// the client can hydrate from the same values the server rendered.
  DahoResponse viewComponent(CluritComponent component) {
    final html = component.renderInitial().replaceFirst(
      '<script id="clurit-state" type="application/json"></script>',
      '<script id="clurit-state" type="application/json">'
          '${jsonEncode(component.initialStateJson())}</script>',
    );
    return header('Content-Type', 'text/html; charset=utf-8').send(html);
  }
}
