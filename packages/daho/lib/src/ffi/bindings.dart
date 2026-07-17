import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

// =============================================================================
// Daho bounded string (FFI mapping of `daho_str_t`)
// =============================================================================
//
// Memory layout, matching the C side:
//
//   [ u32 charLen | u32 byteLen | bytes... \0 ]
//
// Only the two length fields are declared as struct members; the payload bytes
// follow immediately after them and are accessed by pointer arithmetic.

final class DahoStr extends Struct {
  @Uint32()
  external int charLen;

  @Uint32()
  external int byteLen;
}

/// Reads a Dart string straight out of the C-owned [DahoStr] buffer.
extension DahoStrPointerExt on Pointer<DahoStr> {
  String toDartString() {
    if (this == nullptr) return '';

    final length = ref.byteLen;
    if (length == 0) return '';

    // The payload starts right after the two u32 length fields (8 bytes).
    final bytesPtr = Pointer<Uint8>.fromAddress(address + 8);
    return utf8.decode(bytesPtr.asTypedList(length));
  }
}

/// Allocates a [DahoStr] in native memory holding [str]. The caller owns the
/// returned pointer and must `malloc.free` it.
Pointer<DahoStr> allocateDahoStr(String str) {
  final encoded = utf8.encode(str);
  final byteLen = encoded.length;

  // 8 bytes of header (two u32 fields) + payload + null terminator.
  final ptr = malloc.allocate<Uint8>(8 + byteLen + 1).cast<DahoStr>();
  ptr.ref.charLen = str.runes.length;
  ptr.ref.byteLen = byteLen;

  final bytesPtr = Pointer<Uint8>.fromAddress(ptr.address + 8);
  bytesPtr.asTypedList(byteLen).setAll(0, encoded);
  bytesPtr[byteLen] = 0;

  return ptr;
}

// =============================================================================
// FFI function signatures
// =============================================================================

typedef AddStaticPathC =
    Void Function(
      Pointer<DahoStr> vpath,
      Pointer<DahoStr> lpath,
      Int32 workerId,
    );
typedef AddStaticPathDart =
    void Function(Pointer<DahoStr> vpath, Pointer<DahoStr> lpath, int workerId);

typedef AddFastPathC =
    Void Function(
      Pointer<DahoStr> path,
      Pointer<DahoStr> contentType,
      Pointer<Uint8> body,
      Int32 bodyLen,
      Int32 workerId,
    );
typedef AddFastPathDart =
    void Function(
      Pointer<DahoStr> path,
      Pointer<DahoStr> contentType,
      Pointer<Uint8> body,
      int bodyLen,
      int workerId,
    );

/// Invoked by C for every request that is not served by a fast path.
typedef DartRouteCallbackC =
    Void Function(
      Int64 reqPtr,
      Pointer<DahoStr> path,
      Pointer<DahoStr> method,
      Pointer<Uint8> body,
      Int32 bodyLen,
      Pointer<DahoStr> ip,
      Pointer<Pointer<DahoStr>> headerKeys,
      Pointer<Pointer<DahoStr>> headerValues,
      Int32 headerCount,
      Int32 workerId,
    );

typedef StartServerC =
    Void Function(
      Int32 port,
      Pointer<NativeFunction<DartRouteCallbackC>> callback,
      Int32 workerId,
      Int64 maxBodySize,
      Int64 reqTimeoutMs,
      Int64 idleTimeoutMs,
    );
typedef StartServerDart =
    void Function(
      int port,
      Pointer<NativeFunction<DartRouteCallbackC>> callback,
      int workerId,
      int maxBodySize,
      int reqTimeoutMs,
      int idleTimeoutMs,
    );

typedef RespondFromDartC =
    Void Function(
      Int64 reqPtr,
      Int32 statusCode,
      Pointer<Pointer<DahoStr>> headerKeys,
      Pointer<Pointer<DahoStr>> headerValues,
      Int32 headerCount,
      Pointer<Uint8> body,
      Int32 bodyLen,
      Int32 workerId,
    );
typedef RespondFromDartDart =
    void Function(
      int reqPtr,
      int statusCode,
      Pointer<Pointer<DahoStr>> headerKeys,
      Pointer<Pointer<DahoStr>> headerValues,
      int headerCount,
      Pointer<Uint8> body,
      int bodyLen,
      int workerId,
    );

/// Signature of libc `memmem`, used for fast substring search over raw bytes.
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

// =============================================================================
// Native functions resolved at startup and shared across this Isolate
// =============================================================================

/// Sends a completed response back to H2O. Bound in `startNativeServer`.
late final RespondFromDartDart nativeRespond;

/// libc `memmem`. Bound in `startNativeServer`, used by the multipart parser.
late final MemmemDart nativeMemmem;
