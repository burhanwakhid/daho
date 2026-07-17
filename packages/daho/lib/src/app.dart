import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'config.dart';
import 'ffi/server.dart';
import 'router.dart';

/// Function that registers routes and middleware on an [app] instance.
///
/// This must be a top-level (or static) function, not a closure: it is sent to
/// and re-run on every worker Isolate, and Dart cannot transfer closures across
/// Isolate boundaries.
typedef AppBuilder = void Function(Daho app);

/// A precomputed static response served entirely in C, bypassing Dart.
class NativeFastPath {
  final String path;
  final String contentType;
  final String body;
  NativeFastPath(this.path, this.contentType, this.body);
}

/// A group of routes sharing a common path [prefix] and middleware.
class DahoGroup {
  final String prefix;
  final List<Middleware> _groupMiddlewares = [];

  DahoGroup(this.prefix);

  /// Registers a middleware scoped to this group only.
  void use(Middleware middleware) => _groupMiddlewares.add(middleware);

  void get(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => _add('GET', path, handler, use);
  void post(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => _add('POST', path, handler, use);
  void put(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => _add('PUT', path, handler, use);
  void delete(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => _add('DELETE', path, handler, use);
  void patch(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => _add('PATCH', path, handler, use);

  void _add(
    String method,
    String path,
    RouteHandler handler,
    List<Middleware> routeMiddlewares,
  ) {
    RouteRegistry.instance.addRoute(method, prefix, path, handler, [
      ..._groupMiddlewares,
      ...routeMiddlewares,
    ]);
  }
}

/// The Daho application. Register routes and middleware on it, then call
/// [listen] to start serving.
///
/// ```dart
/// final app = Daho(config: const DahoConfig(bodyLimit: 10 * 1024 * 1024));
/// app.listen(8081, routes: setupRoutes);
/// ```
class Daho {
  /// Global configuration (see [DahoConfig]).
  final DahoConfig config;

  final Map<String, String> _staticDirs = {};
  final List<NativeFastPath> _fastPaths = [];

  Daho({this.config = const DahoConfig()});

  /// Serves files from [localDirectory] under the [virtualPath] URL prefix.
  void serveStatic(String virtualPath, String localDirectory) {
    _staticDirs[virtualPath] = localDirectory;
  }

  /// Registers a global middleware that runs for every request.
  void use(Middleware middleware) =>
      RouteRegistry.instance.addGlobalMiddleware(middleware);

  void get(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => RouteRegistry.instance.addRoute('GET', '', path, handler, use);
  void post(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => RouteRegistry.instance.addRoute('POST', '', path, handler, use);
  void put(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => RouteRegistry.instance.addRoute('PUT', '', path, handler, use);
  void delete(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => RouteRegistry.instance.addRoute('DELETE', '', path, handler, use);
  void patch(
    String path,
    RouteHandler handler, {
    List<Middleware> use = const [],
  }) => RouteRegistry.instance.addRoute('PATCH', '', path, handler, use);

  /// Creates a route group with the given path [prefix].
  DahoGroup group(String prefix) => DahoGroup(prefix);

  /// Registers a native fast path: a fixed [body] served directly from C for
  /// [path], never touching the Dart route pipeline.
  void fastPath(String path, String body, {String contentType = 'text/plain'}) {
    _fastPaths.add(NativeFastPath(path, contentType, body));
  }

  /// Starts the server (in the style of Express's `app.listen()` / Fiber's
  /// `app.Listen()`).
  ///
  /// One worker Isolate is spawned per worker (see [DahoConfig.concurrency],
  /// default one per CPU core); they share the listening socket via
  /// `SO_REUSEPORT`. [routes] is re-run on each worker to rebuild its route
  /// table — see [AppBuilder] for why it must be top-level.
  ///
  /// [onShutdown] runs on the master Isolate when a `SIGINT`/`SIGTERM` arrives,
  /// before the grace period ([DahoConfig.shutdownGracePeriod]) and exit. Note
  /// it cannot reach resources owned by worker Isolates (e.g. a database opened
  /// inside [routes]); per-worker cleanup is not yet supported.
  Future<void> listen(
    int port, {
    required AppBuilder routes,
    Function? onStart,
    FutureOr<void> Function()? onShutdown,
  }) async {
    if (onStart != null) onStart();

    // Compile routes once on the master to fail fast on registration errors.
    final master = Daho(config: config);
    routes(master);
    RouteRegistry.instance.compileAll();

    final workers = (config.concurrency ?? Platform.numberOfProcessors).clamp(
      1,
      maxWorkers,
    );
    if (!config.disableStartupMessage) {
      print(
        '🔥 [Daho] Spawning $workers worker(s) with fast paths & O(1) routing...',
      );
    }
    for (int i = 0; i < workers; i++) {
      await Isolate.spawn(
        _clusterWorker,
        _ClusterArgs(routes, port, i, config, master._fastPaths),
      );
    }

    _installShutdownHandlers(onShutdown);
  }

  void _installShutdownHandlers(FutureOr<void> Function()? onShutdown) {
    var shuttingDown = false;

    Future<void> shutdown(ProcessSignal signal) async {
      if (shuttingDown) return; // ignore repeated signals
      shuttingDown = true;

      if (!config.disableStartupMessage) {
        final secs = config.shutdownGracePeriod.inSeconds;
        print('\n⏳ [Daho] $signal received, draining for ${secs}s...');
      }
      try {
        await onShutdown?.call();
      } catch (e) {
        stderr.writeln('[daho] onShutdown error: $e');
      }
      // Let in-flight requests finish and flush before exiting.
      await Future.delayed(config.shutdownGracePeriod);
      exit(0);
    }

    ProcessSignal.sigint.watch().listen(shutdown);
    ProcessSignal.sigterm.watch().listen(shutdown);
  }

  @Deprecated(
    'Use Daho(config: ...).listen(port, routes: setup). '
    'Will be removed in a future release.',
  )
  static Future<void> cluster(
    AppBuilder setup,
    int port, {
    Function? onStart,
    DahoConfig config = const DahoConfig(),
  }) => Daho(config: config).listen(port, routes: setup, onStart: onStart);
}

/// Arguments passed to a worker Isolate. Every field must be sendable across
/// Isolates (which is why [setup] is a top-level function, not a closure).
class _ClusterArgs {
  final AppBuilder setup;
  final int port;
  final int workerId;
  final DahoConfig config;
  final List<NativeFastPath> fastPaths;

  _ClusterArgs(
    this.setup,
    this.port,
    this.workerId,
    this.config,
    this.fastPaths,
  );
}

/// Worker Isolate entry point: rebuilds the route table locally, then starts
/// this worker's native server.
void _clusterWorker(_ClusterArgs args) {
  final app = Daho(config: args.config);
  args.setup(app);
  RouteRegistry.instance.compileAll();

  startNativeServer(
    args.port,
    app._staticDirs,
    args.fastPaths,
    workerId: args.workerId,
    config: app.config,
  );
}
