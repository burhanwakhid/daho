/// Dart `shelf` equivalent of `packages/daho/example/daho_example.dart` —
/// same `/json` route, same response body, no logging/extra middleware, so
/// this is a fair same-language baseline for `.github/workflows/benchmark.yml`.
///
/// `shelf` has no built-in multi-isolate clustering (unlike Daho, which
/// spawns one worker Isolate per core by default) — this manually clusters
/// across `Platform.numberOfProcessors` isolates via `shelf_io.serve`'s
/// `shared: true` (SO_REUSEPORT), so the comparison isn't stacking a
/// single-core baseline against Daho's multi-core one.
///
/// Run:  dart run bin/server.dart
/// Test: curl http://127.0.0.1:8082/json
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _port = 8082;

Response _handler(Request request) {
  if (request.url.path == 'json') {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'items': [1, 2, 3],
      }),
      headers: {'content-type': 'application/json'},
    );
  }
  return Response.notFound('');
}

void _worker(_) async {
  try {
    await shelf_io.serve(
      _handler,
      InternetAddress.anyIPv4,
      _port,
      shared: true,
    );
  } catch (e, st) {
    print('worker failed: $e\n$st');
  }
}

void main() async {
  final workers = Platform.numberOfProcessors;
  for (var i = 0; i < workers; i++) {
    await Isolate.spawn(_worker, null);
  }
  print('shelf running at http://127.0.0.1:$_port ($workers workers)');

  // Spawned isolates don't keep the process alive by themselves — `dart run`
  // exits as soon as main() returns, regardless of other isolates' pending
  // work. Keep the main isolate parked forever with an open ReceivePort.
  ReceivePort().listen((_) {});
}
