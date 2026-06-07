import 'dart:ffi';
import 'dart:isolate';
import 'dart:convert';
import 'dart:io' show Platform, Directory, File;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'router.dart';
import '../daho.dart'; // import NativeFastPath

typedef AddFastPathC =
    Void Function(
      Pointer<Utf8> path,
      Pointer<Utf8> contentType,
      Pointer<Uint8> body,
      Int32 bodyLen,
      Int32 workerId,
    );
typedef AddFastPathDart =
    void Function(
      Pointer<Utf8> path,
      Pointer<Utf8> contentType,
      Pointer<Uint8> body,
      int bodyLen,
      int workerId,
    );

typedef AddStaticPathC =
    Void Function(Pointer<Utf8> vpath, Pointer<Utf8> lpath, Int32 workerId);
typedef AddStaticPathDart =
    void Function(Pointer<Utf8> vpath, Pointer<Utf8> lpath, int workerId);

typedef DartRouteCallbackC =
    Void Function(
      Int64 reqPtr,
      Pointer<Utf8> path,
      Pointer<Utf8> method,
      Pointer<Uint8> body,
      Int32 bodyLen,
      Pointer<Utf8> ip,
      Pointer<Pointer<Utf8>> headerKeys,
      Pointer<Pointer<Utf8>> headerValues,
      Int32 headerCount, // INI YANG BARU
      Int32 workerId,
    );

typedef StartServerC =
    Void Function(
      Int32 port,
      Pointer<NativeFunction<DartRouteCallbackC>> callback,
      Int32 workerId,
      Int64 maxBodySize,
    );
typedef StartServerDart =
    void Function(
      int port,
      Pointer<NativeFunction<DartRouteCallbackC>> callback,
      int workerId,
      int maxBodySize,
    );

typedef RespondFromDartC =
    Void Function(
      Int64 reqPtr,
      Int32 statusCode,
      Pointer<Pointer<Utf8>> headerKeys,
      Pointer<Pointer<Utf8>> headerValues,
      Int32 headerCount,
      Pointer<Uint8> body,
      Int32 bodyLen,
      Int32 workerId,
    );
typedef RespondFromDartDart =
    void Function(
      int reqPtr,
      int statusCode,
      Pointer<Pointer<Utf8>> headerKeys,
      Pointer<Pointer<Utf8>> headerValues,
      int headerCount,
      Pointer<Uint8> body,
      int bodyLen,
      int workerId,
    );

typedef MemmemC =
    Pointer<Uint8> Function(
      Pointer<Uint8> haystack,
      IntPtr haystackLen,
      Pointer<Uint8> needle,
      IntPtr needleLen,
    );
typedef MemmemDart =
    Pointer<Uint8> Function(
      Pointer<Uint8> haystack,
      int haystackLen,
      Pointer<Uint8> needle,
      int needleLen,
    );

late RespondFromDartDart _h2oRespond;
late MemmemDart _memmem;
late final NativeCallable<DartRouteCallbackC> _routeCallable;

Future<String> _getLibraryPath() async {
  String libName = 'libh2o_wrapper.dylib';
  if (Platform.isLinux) libName = 'libh2o_wrapper.so';
  if (Platform.isWindows) libName = 'h2o_wrapper.dll';

  // 1. Cari file utama Daho sebagai jangkar (file ini PASTI ada di dalam folder lib/)
  final packageUri = Uri.parse('package:daho/daho.dart');
  final resolvedUri = await Isolate.resolvePackageUri(packageUri);

  if (resolvedUri != null) {
    // Hasilnya misal: /Users/.../daho/lib/daho.dart
    final dahoDartFile = File(resolvedUri.toFilePath());

    // Mundur ke parent 'lib', lalu mundur lagi ke root 'daho'
    final dahoRootDir = dahoDartFile.parent.parent.path;

    // Sekarang rakit path yang benar menuju c_src
    final dylibPath = '$dahoRootDir/c_src/build/$libName';

    if (File(dylibPath).existsSync()) {
      return dylibPath;
    }
  }

  // 2. Fallback darurat (Jika entah bagaimana resolvePackageUri gagal)
  // Coba cari dari current directory mundur ke atas
  Directory current = Directory.current;
  while (current.path != current.parent.path) {
    final fallbackPath = '${current.path}/c_src/build/$libName';
    if (File(fallbackPath).existsSync()) {
      return fallbackPath;
    }
    current = current.parent;
  }

  throw Exception(
    'Fatal Error: File $libName tidak ditemukan!\n'
    'Pastikan Anda sudah mengkompilasi kode C Daho dengan menjalankan `make` di folder c_src/build.',
  );
}

Future<void> startNativeServer(
  int port,
  Map<String, String> staticDirs,
  List<NativeFastPath> fastPaths, {
  int workerId = 0,
  int maxBodySize = 2097152,
}) async {
  final libraryPath =
      await _getLibraryPath(); // Gunakan fungsi pencari canggih ini
  final dylib = DynamicLibrary.open(libraryPath);
  _h2oRespond = dylib.lookupFunction<RespondFromDartC, RespondFromDartDart>(
    'h2o_respond_from_dart',
  );
  _memmem = DynamicLibrary.process().lookupFunction<MemmemC, MemmemDart>(
    'memmem',
  );
  _routeCallable = NativeCallable<DartRouteCallbackC>.listener(
    _dartRouteCallback,
  );

  await Isolate.spawn(_runH2OBackgroundServer, [
    libraryPath,
    port,
    staticDirs,
    workerId,
    _routeCallable.nativeFunction.address,
    maxBodySize,
    fastPaths,
  ]);
}

void _runH2OBackgroundServer(List<dynamic> args) {
  final String libPath = args[0] as String;
  final int port = args[1] as int;
  final Map<String, String> staticDirs = args[2] as Map<String, String>;
  final int workerId = args[3] as int;
  final int cbAddress = args[4] as int;
  final int maxBodySize = args[5] as int;
  final List<NativeFastPath> fastPaths = args[6] as List<NativeFastPath>;

  final dylib = DynamicLibrary.open(libPath);

  // Daftarkan Fast Paths langsung ke C Memory!
  final addFastPath = dylib.lookupFunction<AddFastPathC, AddFastPathDart>(
    'add_fast_path',
  );
  for (var fp in fastPaths) {
    final pathPtr = fp.path.toNativeUtf8();
    final ctypePtr = fp.contentType.toNativeUtf8();
    final bodyBytes = utf8.encode(fp.body);
    final bodyPtr = malloc.allocate<Uint8>(bodyBytes.length);
    bodyPtr.asTypedList(bodyBytes.length).setAll(0, bodyBytes);

    addFastPath(pathPtr, ctypePtr, bodyPtr, bodyBytes.length, workerId);

    malloc.free(pathPtr);
    malloc.free(ctypePtr);
    malloc.free(bodyPtr);
  }

  // ... [Daftarkan static path dan start h2o seperti biasa] ...
  final startServer = dylib.lookupFunction<StartServerC, StartServerDart>(
    'start_h2o_server',
  );
  final cbPointer = Pointer<NativeFunction<DartRouteCallbackC>>.fromAddress(
    cbAddress,
  );
  startServer(port, cbPointer, workerId, maxBodySize);
}

// -----------------------------------------------------------------
// OPTIMASI: ZERO-ALLOCATION ON REQUEST INBOUND
// -----------------------------------------------------------------
void _dartRouteCallback(
  int reqPtr,
  Pointer<Utf8> pathPtr,
  Pointer<Utf8> methodPtr,
  Pointer<Uint8> bodyPtr,
  int bodyLen,
  Pointer<Utf8> ipPtr,
  Pointer<Pointer<Utf8>> headerKeysPtr,
  Pointer<Pointer<Utf8>> headerValuesPtr,
  int headerCount,
  int workerId,
) {
  final String path = pathPtr.toDartString();
  final String method = methodPtr.toDartString();
  final String ip = ipPtr.toDartString();

  // Ambil semua header dan jadikan lowercase (Standar HTTP)
  final Map<String, String> headers = {};
  for (int i = 0; i < headerCount; i++) {
    final key = headerKeysPtr[i].toDartString().toLowerCase();
    final value = headerValuesPtr[i].toDartString();
    headers[key] = value;
  }

  Uint8List bodyBytes = Uint8List(0);
  if (bodyLen > 0 && bodyPtr != nullptr) {
    bodyBytes = Uint8List.view(bodyPtr.asTypedList(bodyLen).buffer, 0, bodyLen);
  }

  // Lempar Map headers ke prosesor
  _processRequestAsynchronously(
    reqPtr,
    path,
    method,
    headers,
    bodyBytes,
    ip,
    workerId,
  );
}

Future<void> _processRequestAsynchronously(
  int reqPtr,
  String rawPath,
  String method,
  Map<String, String> headers,
  Uint8List bodyBytes,
  String ip,
  int workerId,
) async {
  final uri = Uri.parse(rawPath);
  final normalizedPath = uri.path;
  final queryParams = uri.queryParameters;
  final contentType = headers['content-type'] ?? '';

  dynamic parsedBody = {};
  Map<String, UploadedFile> parsedFiles = {};

  if (bodyBytes.isNotEmpty) {
    if (contentType.contains('application/json')) {
      final str = utf8.decode(bodyBytes, allowMalformed: true);
      try {
        parsedBody = jsonDecode(str);
      } catch (_) {
        parsedBody = str;
      }
    } else if (contentType.contains('multipart/form-data')) {
      final boundaryPrefix = 'boundary=';
      final boundaryIndex = contentType.indexOf(boundaryPrefix);
      if (boundaryIndex != -1) {
        final boundaryStr = contentType.substring(
          boundaryIndex + boundaryPrefix.length,
        );
        final boundaryBytes = utf8.encode('--$boundaryStr');
        final headerEndBytes = [13, 10, 13, 10];

        final haystackPtr = malloc.allocate<Uint8>(bodyBytes.length);
        haystackPtr.asTypedList(bodyBytes.length).setAll(0, bodyBytes);
        final boundaryPtr = malloc.allocate<Uint8>(boundaryBytes.length);
        boundaryPtr.asTypedList(boundaryBytes.length).setAll(0, boundaryBytes);
        final headerEndPtr = malloc.allocate<Uint8>(4);
        headerEndPtr.asTypedList(4).setAll(0, headerEndBytes);

        int start = 0;
        Pointer<Uint8> currentMatch = _memmem(
          haystackPtr,
          bodyBytes.length,
          boundaryPtr,
          boundaryBytes.length,
        );
        if (currentMatch != nullptr) {
          start =
              (currentMatch.address - haystackPtr.address) +
              boundaryBytes.length;
          while (start < bodyBytes.length) {
            Pointer<Uint8> searchArea = Pointer<Uint8>.fromAddress(
              haystackPtr.address + start,
            );
            Pointer<Uint8> nextMatch = _memmem(
              searchArea,
              bodyBytes.length - start,
              boundaryPtr,
              boundaryBytes.length,
            );
            if (nextMatch == nullptr) break;
            int end = nextMatch.address - haystackPtr.address;
            final part = bodyBytes.sublist(start, end);
            if (part.length > 4) {
              Pointer<Uint8> partPtr = Pointer<Uint8>.fromAddress(
                haystackPtr.address + start,
              );
              Pointer<Uint8> headerMatch = _memmem(
                partPtr,
                part.length,
                headerEndPtr,
                4,
              );
              if (headerMatch != nullptr) {
                int headerEnd = headerMatch.address - partPtr.address;
                final headerStr = utf8.decode(part.sublist(0, headerEnd));
                final contentBytes = part.sublist(
                  headerEnd + 4,
                  part.length - 2,
                );
                String fieldName = '', filename = '', mimeType = 'text/plain';
                for (var line in headerStr.split('\r\n')) {
                  if (line.toLowerCase().startsWith('content-disposition:')) {
                    final nameMatch = RegExp(
                      r'name="([^"]+)"',
                    ).firstMatch(line);
                    if (nameMatch != null) fieldName = nameMatch.group(1)!;
                    final fileMatch = RegExp(
                      r'filename="([^"]+)"',
                    ).firstMatch(line);
                    if (fileMatch != null) filename = fileMatch.group(1)!;
                  } else if (line.toLowerCase().startsWith('content-type:')) {
                    mimeType = line.substring(13).trim();
                  }
                }
                if (fieldName.isNotEmpty) {
                  if (filename.isNotEmpty) {
                    parsedFiles[fieldName] = UploadedFile(
                      filename: filename,
                      contentType: mimeType,
                      bytes: contentBytes,
                    );
                  } else {
                    parsedBody[fieldName] = utf8.decode(contentBytes);
                  }
                }
              }
            }
            start = end + boundaryBytes.length;
          }
        }
        malloc.free(haystackPtr);
        malloc.free(boundaryPtr);
        malloc.free(headerEndPtr);
      }
    } else {
      parsedBody = utf8.decode(bodyBytes, allowMalformed: true);
    }
  }

  int statusCode = 500;
  Map<String, String> finalHeaders = {'Content-Type': 'application/json'};
  List<int> responseBytes = [];

  try {
    final routeMatch = RouteRegistry.instance.findRoute(
      method,
      Uri.parse(rawPath).path,
    );
    final request = DahoRequest(
      method: method,
      path: Uri.parse(rawPath).path,
      ip: ip,
      query: Uri.parse(rawPath).queryParameters,
      params: routeMatch?.params ?? {},
      body: parsedBody,
      files: parsedFiles,
      headers: headers,
    );
    final response = DahoResponse();

    // EKSEKUSI CHAIN YANG SUDAH TERKOMPILASI! Tidak ada lagi loop rekursif!
    if (routeMatch != null) {
      await routeMatch.compiledHandler(request, response);
    } else {
      response.status(404).json({"error": "Not Found"});
    }

    statusCode = response.statusCode;
    finalHeaders = response.headers;
    if (response.bodyBytes != null) {
      responseBytes = response.bodyBytes!;
    } else {
      responseBytes = utf8.encode(response.bodyText);
    }
  } catch (error, trace) {
    statusCode = 500;
    finalHeaders = {'Content-Type': 'application/json'};
    responseBytes = utf8.encode(
      jsonEncode({"error": "Internal Error", "trace": trace.toString()}),
    );
  }

  int headerCount = finalHeaders.length;
  final headerKeysPtr = calloc<Pointer<Utf8>>(headerCount);
  final headerValuesPtr = calloc<Pointer<Utf8>>(headerCount);

  int i = 0;
  finalHeaders.forEach((key, value) {
    headerKeysPtr[i] = key.toNativeUtf8();
    headerValuesPtr[i] = value.toNativeUtf8();
    i++;
  });

  Pointer<Uint8> bodyPtr = nullptr;
  if (responseBytes.isNotEmpty) {
    bodyPtr = calloc<Uint8>(responseBytes.length);
    bodyPtr.asTypedList(responseBytes.length).setAll(0, responseBytes);
  }

  _h2oRespond(
    reqPtr,
    statusCode,
    headerKeysPtr,
    headerValuesPtr,
    headerCount,
    bodyPtr,
    responseBytes.length,
    workerId,
  );

  for (int j = 0; j < headerCount; j++) {
    malloc.free(headerKeysPtr[j]);
    malloc.free(headerValuesPtr[j]);
  }
  calloc.free(headerKeysPtr);
  calloc.free(headerValuesPtr);
}
