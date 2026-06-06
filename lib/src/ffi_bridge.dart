// lib/src/ffi_bridge.dart
import 'dart:ffi';
import 'dart:isolate';
import 'dart:convert';
import 'dart:io' show Platform, Directory;
import 'package:ffi/ffi.dart';
import 'router.dart';

typedef InitDartApiC = Void Function(Pointer<Void> data, Int64 port);
typedef InitDartApiDart = void Function(Pointer<Void> data, int port);

typedef RespondFromDartC = Void Function(Int64 reqPtr, Pointer<Utf8> response);
typedef RespondFromDartDart = void Function(int reqPtr, Pointer<Utf8> response);

// FFI BARU UNTUK STATIC FILES
typedef AddStaticPathC =
    Void Function(Pointer<Utf8> vpath, Pointer<Utf8> lpath);
typedef AddStaticPathDart =
    void Function(Pointer<Utf8> vpath, Pointer<Utf8> lpath);

typedef StartServerC = Void Function(Int32 port);
typedef StartServerDart = void Function(int port);

late RespondFromDartDart _h2oRespond;

// UPDATE: Menerima staticDirs dari Daho App
Future<void> startNativeServer(int port, Map<String, String> staticDirs) async {
  String libraryPath =
      '${Directory.current.path}/c_src/build/libh2o_wrapper.dylib';
  if (Platform.isLinux) {
    libraryPath = '${Directory.current.path}/c_src/build/libh2o_wrapper.so';
  }

  final dylib = DynamicLibrary.open(libraryPath);

  final initDartApi = dylib.lookupFunction<InitDartApiC, InitDartApiDart>(
    'init_dart_api',
  );
  _h2oRespond = dylib.lookupFunction<RespondFromDartC, RespondFromDartDart>(
    'h2o_respond_from_dart',
  );

  final receivePort = ReceivePort();
  initDartApi(NativeApi.initializeApiDLData, receivePort.sendPort.nativePort);

  receivePort.listen((dynamic message) async {
    final int reqPtr = message[0];
    final String path = message[1];
    final String method = message[2];
    final String body = message[3];

    _processRequestAsynchronously(reqPtr, path, method, body);
  });

  // Kirim staticDirs ke Background Isolate
  await Isolate.spawn(_runH2OBackgroundServer, [libraryPath, port, staticDirs]);
}

void _runH2OBackgroundServer(List<dynamic> args) {
  final String libPath = args[0] as String;
  final int port = args[1] as int;
  final Map<String, String> staticDirs = args[2] as Map<String, String>;

  final dylib = DynamicLibrary.open(libPath);

  // Daftarkan Static Files sebelum menyalakan server
  final addStaticPath = dylib.lookupFunction<AddStaticPathC, AddStaticPathDart>(
    'add_static_path',
  );

  for (var entry in staticDirs.entries) {
    final vpath = entry.key.toNativeUtf8();
    final lpath = entry.value.toNativeUtf8();

    addStaticPath(vpath, lpath);

    malloc.free(vpath);
    malloc.free(lpath);
  }

  final startServer = dylib.lookupFunction<StartServerC, StartServerDart>(
    'start_h2o_server',
  );
  startServer(port);
}

Future<void> _processRequestAsynchronously(
  int reqPtr,
  String rawPath,
  String method,
  String rawBody,
) async {
  // ... [Kode eksekusi request ini sama persis seperti sebelumnya] ...
  final uri = Uri.parse(rawPath);
  final normalizedPath = uri.path;
  final queryParams = uri.queryParameters;

  dynamic parsedBody;
  if (rawBody.isNotEmpty) {
    try {
      parsedBody = jsonDecode(rawBody);
    } catch (e) {
      parsedBody = rawBody;
    }
  }

  final sb = StringBuffer();

  try {
    final routeMatch = RouteRegistry.instance.findRoute(method, normalizedPath);
    final request = DahoRequest(
      method: method,
      path: normalizedPath,
      query: queryParams,
      params: routeMatch?.params ?? {},
      body: parsedBody,
    );
    final response = DahoResponse();

    final finalResponse = await RouteRegistry.instance.executeChain(
      request,
      response,
      routeMatch?.handler,
    );

    sb.write('${finalResponse.statusCode}\n');
    finalResponse.headers.forEach((key, value) {
      sb.write('$key: $value\n');
    });
    sb.write('\n');
    sb.write(finalResponse.bodyText);
  } catch (error) {
    sb.clear();
    sb.write('500\nContent-Type: application/json\n\n');
    sb.write(jsonEncode({"error": "Internal Server Error"}));
  }

  final pointerResponse = sb.toString().toNativeUtf8();
  _h2oRespond(reqPtr, pointerResponse);
  malloc.free(pointerResponse);
}
