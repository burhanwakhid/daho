// lib/daho.dart
import 'dart:io';
import 'dart:isolate';
import 'src/router.dart';
import 'src/ffi_bridge.dart';

export 'src/router.dart'
    show DahoRequest, DahoResponse, Middleware, NextFunction;

// Tipe untuk menampung fungsi setup routes dari user
typedef AppBuilder = void Function(Daho app);

class DahoGroup {
  final String prefix;
  final List<Middleware> _groupMiddlewares = [];

  DahoGroup(this.prefix);

  // Menempelkan middleware HANYA berlaku di dalam grup ini
  void use(Middleware middleware) {
    _groupMiddlewares.add(middleware);
  }

  void get(String path, RouteHandler handler) {
    RouteRegistry.instance.addRoute(
      'GET',
      prefix,
      path,
      handler,
      _groupMiddlewares,
    );
  }

  void post(String path, RouteHandler handler) {
    RouteRegistry.instance.addRoute(
      'POST',
      prefix,
      path,
      handler,
      _groupMiddlewares,
    );
  }
}

class NativeFastPath {
  final String path;
  final String contentType;
  final String body;
  NativeFastPath(this.path, this.contentType, this.body);
}

class Daho {
  final Map<String, String> _staticDirs = {};
  final List<NativeFastPath> _fastPaths = []; // Menyimpan konfigurasi fast path

  void serveStatic(String virtualPath, String localDirectory) {
    _staticDirs[virtualPath] = localDirectory;
  }

  void use(Middleware middleware) =>
      RouteRegistry.instance.addGlobalMiddleware(middleware);
  void get(String path, RouteHandler handler) =>
      RouteRegistry.instance.addRoute('GET', '', path, handler, []);
  void post(String path, RouteHandler handler) =>
      RouteRegistry.instance.addRoute('POST', '', path, handler, []);

  DahoGroup group(String prefix) => DahoGroup(prefix);

  // API UNTUK NATIVE FAST-PATH
  void fastPath(String path, String body, {String contentType = 'text/plain'}) {
    _fastPaths.add(NativeFastPath(path, contentType, body));
  }

  static Future<void> cluster(
    AppBuilder setup,
    int port, {
    Function? onStart,
    int? maxBodySize,
  }) async {
    if (onStart != null) onStart();

    // KOMPILASI SEMUA RUTE DAN MIDDLEWARE SEKARANG!
    final tempApp = Daho();
    setup(tempApp);
    RouteRegistry.instance.compileAll();

    int cores = Platform.numberOfProcessors;
    print(
      "🔥 [Cluster Master] Membangkitkan $cores Worker dengan Fast Path & O(1) Routing...",
    );
    for (int i = 0; i < cores; i++) {
      await Isolate.spawn(
        _clusterWorker,
        _ClusterArgs(
          setup,
          port,
          i,
          maxBodySize ?? 2 * 1024 * 1024,
          tempApp._fastPaths,
        ),
      );
    }
    ProcessSignal.sigint.watch().listen((_) => exit(0));
  }
}

class _ClusterArgs {
  final AppBuilder setup;
  final int port;
  final int workerId;
  final int maxBodySize;
  final List<NativeFastPath> fastPaths;
  _ClusterArgs(
    this.setup,
    this.port,
    this.workerId,
    this.maxBodySize,
    this.fastPaths,
  );
}

void _clusterWorker(_ClusterArgs args) {
  final app = Daho();
  args.setup(app); // Re-register routes in Isolate
  RouteRegistry.instance.compileAll();

  startNativeServer(
    args.port,
    app._staticDirs,
    args.fastPaths,
    workerId: args.workerId,
    maxBodySize: args.maxBodySize,
  );
}
