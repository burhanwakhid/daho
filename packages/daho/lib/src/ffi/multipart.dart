import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../request.dart';
import 'bindings.dart';

/// The decoded contents of a `multipart/form-data` body.
class MultipartData {
  /// Plain (non-file) form fields.
  final Map<String, dynamic> fields;

  /// Uploaded files, keyed by form field name.
  final Map<String, UploadedFile> files;

  MultipartData(this.fields, this.files);
}

const List<int> _headerSeparator = [13, 10, 13, 10]; // \r\n\r\n

/// Parses a `multipart/form-data` [body] delimited by [boundary].
///
/// Boundary scanning is delegated to libc `memmem` over native memory, which
/// is dramatically faster than iterating the byte list in Dart. A single copy
/// of the body is made into a native buffer; the boundary and header-separator
/// needles are copied too. All three buffers are freed before returning.
MultipartData parseMultipart(Uint8List body, String boundary) {
  final fields = <String, dynamic>{};
  final files = <String, UploadedFile>{};

  final boundaryBytes = utf8.encode('--$boundary');

  final haystackPtr = malloc.allocate<Uint8>(body.length);
  haystackPtr.asTypedList(body.length).setAll(0, body);
  final boundaryPtr = malloc.allocate<Uint8>(boundaryBytes.length);
  boundaryPtr.asTypedList(boundaryBytes.length).setAll(0, boundaryBytes);
  final headerEndPtr = malloc.allocate<Uint8>(4);
  headerEndPtr.asTypedList(4).setAll(0, _headerSeparator);

  try {
    final firstBoundary = nativeMemmem(
      haystackPtr,
      body.length,
      boundaryPtr,
      boundaryBytes.length,
    );
    if (firstBoundary == nullptr) return MultipartData(fields, files);

    int start =
        (firstBoundary.address - haystackPtr.address) + boundaryBytes.length;

    while (start < body.length) {
      // Find the boundary that closes the current part.
      final searchArea = Pointer<Uint8>.fromAddress(
        haystackPtr.address + start,
      );
      final nextBoundary = nativeMemmem(
        searchArea,
        body.length - start,
        boundaryPtr,
        boundaryBytes.length,
      );
      if (nextBoundary == nullptr) break;

      final end = nextBoundary.address - haystackPtr.address;
      final part = body.sublist(start, end);

      if (part.length > 4) {
        _parsePart(part, haystackPtr, start, headerEndPtr, fields, files);
      }
      start = end + boundaryBytes.length;
    }
  } finally {
    malloc.free(haystackPtr);
    malloc.free(boundaryPtr);
    malloc.free(headerEndPtr);
  }

  return MultipartData(fields, files);
}

/// Parses a single multipart part: splits its headers from its content and
/// records it either as a file (when a filename is present) or a plain field.
void _parsePart(
  Uint8List part,
  Pointer<Uint8> haystackPtr,
  int start,
  Pointer<Uint8> headerEndPtr,
  Map<String, dynamic> fields,
  Map<String, UploadedFile> files,
) {
  final partPtr = Pointer<Uint8>.fromAddress(haystackPtr.address + start);
  final headerMatch = nativeMemmem(partPtr, part.length, headerEndPtr, 4);
  if (headerMatch == nullptr) return;

  final headerEnd = headerMatch.address - partPtr.address;
  final headerStr = utf8.decode(part.sublist(0, headerEnd));
  // Skip the \r\n\r\n separator, and drop the trailing \r\n before the boundary.
  final content = part.sublist(headerEnd + 4, part.length - 2);

  String fieldName = '';
  String filename = '';
  String mimeType = 'text/plain';

  for (final line in headerStr.split('\r\n')) {
    final lower = line.toLowerCase();
    if (lower.startsWith('content-disposition:')) {
      fieldName =
          RegExp(r'name="([^"]+)"').firstMatch(line)?.group(1) ?? fieldName;
      filename =
          RegExp(r'filename="([^"]+)"').firstMatch(line)?.group(1) ?? filename;
    } else if (lower.startsWith('content-type:')) {
      mimeType = line.substring(13).trim();
    }
  }

  if (fieldName.isEmpty) return;

  if (filename.isNotEmpty) {
    files[fieldName] = UploadedFile(
      filename: filename,
      contentType: mimeType,
      bytes: content,
    );
  } else {
    fields[fieldName] = utf8.decode(content);
  }
}
