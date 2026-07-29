import 'package:daho/daho.dart';
import 'package:clurit/clurit.dart';

typedef CluritStateProvider = Map<String, dynamic> Function(DahoRequest req);

/// Builds a compiled `@code` component from the same `data` map an author
/// would otherwise pass to `res.view(name, data: {...})` for a plain Blade
/// template — the backend's way of sending request-derived values (a
/// `$props` field, an id looked up from `data['id']`, etc.) into a
/// component, without route handlers each needing to know that component's
/// constructor shape.
typedef CluritComponentFactory = CluritComponent Function(Map<String, dynamic> data);

/// Extension to add Clurit template engine support to Daho.
extension CluritDahoExtension on Daho {
  static CluritStateProvider? _stateProvider;
  static final Map<String, CluritComponentFactory> _componentFactories = {};

  /// Configures the Clurit template engine.
  ///
  /// [viewsPath] is the directory containing .clurit template files.
  /// [cachePath] is the directory for compiled template cache (optional).
  /// [debug] enables recompilation on every request (default: false).
  /// [stateProvider] is an optional function to provide global state from request.
  /// [components] bulk-registers compiled `@code` component factories —
  /// pass the generated `cluritComponents` map from `clurit_components.g.dart`
  /// (see `CluritRoutesBuilder`) instead of calling [registerComponent] once
  /// per page by hand.
  void configureClurit({
    required String viewsPath,
    String? cachePath,
    bool debug = false,
    CluritStateProvider? stateProvider,
    Map<String, CluritComponentFactory>? components,
  }) {
    CluritEngine.instance = CluritEngine(
      viewsPath: viewsPath,
      cachePath: cachePath,
      debug: debug,
    );
    _stateProvider = stateProvider;
    components?.forEach(registerComponent);
  }

  /// Gets the registered state provider.
  CluritStateProvider? get cluritStateProvider => _stateProvider;

  /// Registers a compiled `@code` component under [name], so
  /// `res.view(name, data: {...})` renders it directly (bypassing the
  /// Blade engine) instead of looking for a `.clurit` template on disk —
  /// the same call site works whether [name] turns out to be a plain
  /// template or a reactive component.
  void registerComponent(String name, CluritComponentFactory factory) {
    _componentFactories[name] = factory;
  }

  /// Looks up a factory registered via [registerComponent].
  CluritComponentFactory? cluritComponentFactory(String name) => _componentFactories[name];

  /// Same lookup as [cluritComponentFactory], callable without a [Daho]
  /// instance in hand (the registry is a single process-wide singleton,
  /// matching [CluritEngine.instance]) — used by
  /// `CluritResponseExtension.view` to check for a registered component
  /// before falling back to the Blade engine.
  static CluritComponentFactory? factoryFor(String name) => _componentFactories[name];
}
