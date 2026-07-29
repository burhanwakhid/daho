import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform, Directory, File;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../app.dart' show NativeFastPath;
import '../config.dart';
import 'bindings.dart';
import 'handler.dart';

late final NativeCallable<DartRouteCallbackC> _routeCallable;

/// Resolves the absolute path to the compiled native library for the current
/// platform. First tries the package's own `c_src/build` directory, then walks
/// up from the current working directory as a fallback.
Future<String> _getLibraryPath() async {
  String libName = 'libh2o_wrapper.dylib';
  if (Platform.isLinux) libName = 'libh2o_wrapper.so';
  if (Platform.isWindows) libName = 'h2o_wrapper.dll';

  final resolvedUri = await Isolate.resolvePackageUri(
    Uri.parse('package:daho/daho.dart'),
  );
  if (resolvedUri != null) {
    // resolvedUri points at lib/daho.dart; the package root is two levels up.
    final packageRoot = File(resolvedUri.toFilePath()).parent.parent.path;
    final dylibPath = '$packageRoot/c_src/build/$libName';
    if (File(dylibPath).existsSync()) return dylibPath;
  }

  Directory current = Directory.current;
  while (current.path != current.parent.path) {
    final fallbackPath = '${current.path}/c_src/build/$libName';
    if (File(fallbackPath).existsSync()) return fallbackPath;
    current = current.parent;
  }

  throw Exception(
    'Fatal: native library $libName not found.\n'
    'Build the Daho C sources first (run `make` inside c_src/build).',
  );
}

/// Boots the native H2O server on this Isolate.
///
/// The route callback is created here (so it runs on this Isolate) while the
/// blocking H2O event loop is spawned onto a dedicated background Isolate.
Future<void> startNativeServer(
  int port,
  Map<String, String> staticDirs,
  List<NativeFastPath> fastPaths, {
  int workerId = 0,
  DahoConfig config = const DahoConfig(),
}) async {
  // The request callback and error handling run on this Isolate, so the active
  // config must be visible here.
  activeConfig = config;

  final libraryPath = await _getLibraryPath();
  final dylib = DynamicLibrary.open(libraryPath);

  nativeRespond = dylib.lookupFunction<RespondFromDartC, RespondFromDartDart>(
    'h2o_respond_from_dart',
  );
  nativeMemmem = DynamicLibrary.process().lookupFunction<MemmemC, MemmemDart>(
    'memmem',
  );
  _routeCallable = NativeCallable<DartRouteCallbackC>.listener(
    dartRouteCallback,
  );

  // Only plain sendable values cross to the background Isolate (no closures).
  await Isolate.spawn(_runH2OBackgroundServer, [
    libraryPath,
    port,
    staticDirs,
    workerId,
    _routeCallable.nativeFunction.address,
    config.bodyLimit,
    fastPaths,
    config.requestTimeout.inMilliseconds,
    config.idleTimeout.inMilliseconds,
    config.tlsCertPath,
    config.tlsKeyPath,
  ]);
}

/// Runs on the background Isolate: registers fast paths and static directories
/// with C, then enters the (blocking) H2O event loop.
void _runH2OBackgroundServer(List<dynamic> args) {
  final libPath = args[0] as String;
  final port = args[1] as int;
  final staticDirs = args[2] as Map<String, String>;
  final workerId = args[3] as int;
  final cbAddress = args[4] as int;
  final maxBodySize = args[5] as int;
  final fastPaths = args[6] as List<NativeFastPath>;
  final reqTimeoutMs = args[7] as int;
  final idleTimeoutMs = args[8] as int;
  final tlsCertPath = args[9] as String?;
  final tlsKeyPath = args[10] as String?;

  final dylib = DynamicLibrary.open(libPath);

  _registerFastPaths(dylib, fastPaths, workerId);
  _registerStaticDirs(dylib, staticDirs, workerId);

  final startServer = dylib.lookupFunction<StartServerC, StartServerDart>(
    'start_h2o_server',
  );
  final cbPointer = Pointer<NativeFunction<DartRouteCallbackC>>.fromAddress(
    cbAddress,
  );

  // NULL (not just an empty string) means "no TLS" on the C side, so only
  // allocate a DahoStr when a path was actually configured.
  final certPtr = tlsCertPath != null ? allocateDahoStr(tlsCertPath) : nullptr;
  final keyPtr = tlsKeyPath != null ? allocateDahoStr(tlsKeyPath) : nullptr;

  startServer(
    port,
    cbPointer,
    workerId,
    maxBodySize,
    reqTimeoutMs,
    idleTimeoutMs,
    certPtr,
    keyPtr,
  );
}

/// Registers each fast path (a precomputed static response) directly in C
/// memory so it can be served without ever entering Dart.
void _registerFastPaths(
  DynamicLibrary dylib,
  List<NativeFastPath> fastPaths,
  int workerId,
) {
  final addFastPath = dylib.lookupFunction<AddFastPathC, AddFastPathDart>(
    'add_fast_path',
  );

  for (final fp in fastPaths) {
    final pathPtr = allocateDahoStr(fp.path);
    final ctypePtr = allocateDahoStr(fp.contentType);
    final bodyBytes = utf8.encode(fp.body);

    Pointer<Uint8> bodyPtr = nullptr;
    if (bodyBytes.isNotEmpty) {
      bodyPtr = malloc.allocate<Uint8>(bodyBytes.length);
      bodyPtr.asTypedList(bodyBytes.length).setAll(0, bodyBytes);
    }

    addFastPath(pathPtr, ctypePtr, bodyPtr, bodyBytes.length, workerId);

    malloc.free(pathPtr);
    malloc.free(ctypePtr);
    if (bodyPtr != nullptr) malloc.free(bodyPtr);
  }
}

/// Registers the static-file directories with C.
void _registerStaticDirs(
  DynamicLibrary dylib,
  Map<String, String> staticDirs,
  int workerId,
) {
  final addStaticPath = dylib.lookupFunction<AddStaticPathC, AddStaticPathDart>(
    'add_static_path',
  );

  staticDirs.forEach((virtualPath, localPath) {
    final vPtr = allocateDahoStr(virtualPath);
    final lPtr = allocateDahoStr(localPath);
    addStaticPath(vPtr, lPtr, workerId);
    malloc.free(vPtr);
    malloc.free(lPtr);
  });
}
