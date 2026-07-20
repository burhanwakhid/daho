/// 12 — Concurrency Test Client
///
/// This is a CLIENT script (not a server) that demonstrates Daho's concurrent
/// request handling. It sends a slow request, then fires multiple fast requests
/// while the slow one is still in flight, proving the server handles them
/// concurrently (not sequentially).
///
/// Prerequisites: Start a Daho server with these routes:
///
///   app.get('/slow', (req, res) async {
///     await Future.delayed(Duration(seconds: 5));
///     return res.ok({'message': 'done'});
///   });
///   app.get('/fast', (req, res) => res.ok({'message': 'fast'}));
///
/// Run:  dart run example/12_concurrency_client.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient();
  final stopwatch = Stopwatch()..start();

  print('Starting concurrency test...\n');

  Future<void> hitApi(String label, String path) async {
    final start = stopwatch.elapsedMilliseconds;
    print('[$label] Sent at ${start}ms');

    try {
      final request = await client.get('127.0.0.1', 8080, path);
      final response = await request.close();
      await response.transform(utf8.decoder).join();

      final end = stopwatch.elapsedMilliseconds;
      print('[$label] Done! Took ${end - start}ms');
    } catch (e) {
      print('[$label] Failed: $e');
    }
  }

  // 1. Send a slow request (server holds it for 5 seconds)
  final slowRequest = hitApi('SLOW', '/slow');

  // 2. Wait 500ms to ensure the slow request has reached the server
  await Future.delayed(Duration(milliseconds: 500));

  print('\n--- Firing 5 fast requests concurrently ---\n');

  // 3. Fire 5 fast requests while the slow one is in flight
  final fastRequests = <Future>[];
  for (int i = 1; i <= 5; i++) {
    fastRequests.add(hitApi('FAST-$i', '/fast'));
  }

  // Wait for everything to finish
  await Future.wait([slowRequest, ...fastRequests]);

  print(
    '\nAll done. Total time: ${stopwatch.elapsedMilliseconds}ms',
  );
  print('(If fast requests finished in ~0ms while slow took 5000ms,');
  print(' the server handled them concurrently!)');

  client.close();
}
