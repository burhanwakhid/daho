import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'dart:io' show Platform;

typedef InitDartApiC = Void Function(Pointer<Void> data, Int64 port);
typedef InitDartApiDart = void Function(Pointer<Void> data, int port);

// Perhatikan: reqId sekarang Int64 (mewakili alamat memori C)
typedef SendResponseC = Void Function(Int64 reqId, Pointer<Utf8> body);
typedef SendResponseDart = void Function(int reqId, Pointer<Utf8> body);

typedef StartServerC = Void Function(Int32 port);
typedef StartServerDart = void Function(int port);

// Variabel global agar Isolate tahu lokasi dylib
late String libraryPath;

void main() async {
  // 1. Resolve path dylib yang akurat
  libraryPath = Platform.script
      .resolve('../c_src/build/libh2o_wrapper.dylib')
      .toFilePath();
  final dylib = DynamicLibrary.open(libraryPath);

  // 2. Setup FFI
  final initDartApi = dylib.lookupFunction<InitDartApiC, InitDartApiDart>(
    'initialize_dart_api',
  );
  final sendResponse = dylib.lookupFunction<SendResponseC, SendResponseDart>(
    'send_response_to_h2o',
  );

  // 3. Daftarkan Port untuk menerima request HTTP sungguhan dari h2o
  final receivePort = ReceivePort();
  initDartApi(NativeApi.initializeApiDLData, receivePort.sendPort.nativePort);

  receivePort.listen((dynamic message) async {
    final int reqId = message[0];
    final String path = message[1];
    final String method = message[2];

    print("[Dart] Mengamankan Request: $method $path");

    // Simulasi respons framework Dart
    String body =
        "Berhasil! Ini dibalas dari Dart, dieksekusi oleh h2o C Server.\nPath: $path\nMethod: $method";

    final pointerBody = body.toNativeUtf8();
    sendResponse(reqId, pointerBody);
    malloc.free(pointerBody);
  });

  // 4. Jalankan Server H2O di Isolate Background
  // Ini krusial agar event loop h2o tidak memblokir main event loop Dart
  print("[Dart] Menyiapkan Background Isolate untuk H2O...");
  await Isolate.spawn(runH2OBackgroundServer, 8080);
}

// Fungsi ini akan berjalan di thread terpisah (Isolate)
void runH2OBackgroundServer(int port) {
  final dylib = DynamicLibrary.open(libraryPath);
  final startServer = dylib.lookupFunction<StartServerC, StartServerDart>(
    'start_h2o_server',
  );

  // Fungsi ini tidak akan pernah berhenti (Infinite Event Loop)
  startServer(port);
}
