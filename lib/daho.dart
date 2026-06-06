// lib/daho.dart
import 'src/router.dart';
import 'src/ffi_bridge.dart';

export 'src/router.dart'
    show DahoRequest, DahoResponse, Middleware, NextFunction;

class Daho {
  final Map<String, String> _staticDirs = {};

  // FITUR BARU: Mendaftarkan folder static
  void serveStatic(String virtualPath, String localDirectory) {
    _staticDirs[virtualPath] = localDirectory;
  }

  void use(Middleware middleware) {
    RouteRegistry.instance.addMiddleware(middleware);
  }

  void get(String path, RouteHandler handler) {
    RouteRegistry.instance.addRoute('GET', path, handler);
  }

  void post(String path, RouteHandler handler) {
    RouteRegistry.instance.addRoute('POST', path, handler);
  }

  void listen(int port, {Function? onStart}) {
    if (onStart != null) onStart();

    // Kirim memori static dirs ke FFI
    startNativeServer(port, _staticDirs);
  }
}
