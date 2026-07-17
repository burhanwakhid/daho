// Connects to a running Daho server's VM service and reports GC activity and
// heap usage across all Isolates over a time window. Use it to establish a
// baseline (or measure a change) while a load generator like `wrk` runs.
//
// Usage:
//   1. Start the server with the VM service enabled:
//        dart run --enable-vm-service=8181 --disable-service-auth-codes \
//          example/routing.dart
//      Copy the printed service URI (http://127.0.0.1:8181/<token>/).
//   2. In another terminal, run the load test, then:
//        dart run tool/gc_probe.dart http://127.0.0.1:8181/<token>/ 20
//      (20 = seconds to sample; default 20).
import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/gc_probe.dart <vm-service-uri> [seconds]',
    );
    exitCode = 64;
    return;
  }
  final seconds = args.length > 1 ? int.parse(args[1]) : 20;
  final wsUri = _toWebSocket(args.first);

  stdout.writeln('Connecting to $wsUri ...');
  final service = await vmServiceConnectUri(wsUri);

  await service.streamListen(EventStreams.kGC);
  final gcByIsolate = <String, int>{};
  var totalEvents = 0; // authoritative count across all isolates
  final sub = service.onGCEvent.listen((e) {
    totalEvents++;
    final id = e.isolate?.id ?? '?';
    gcByIsolate.update(id, (v) => v + 1, ifAbsent: () => 1);
  });

  stdout.writeln('Sampling GC for ${seconds}s — run your load test now...\n');
  await Future<void>.delayed(Duration(seconds: seconds));
  await sub.cancel();

  final vm = await service.getVM();
  final isolates = vm.isolates ?? [];

  var totalGc = 0;
  var totalHeap = 0;
  var totalCapacity = 0;
  var totalExternal = 0;

  stdout.writeln('Per-isolate:');
  for (final ref in isolates) {
    final id = ref.id!;
    final gc = gcByIsolate[id] ?? 0;
    totalGc += gc;

    final mem = await service.getMemoryUsage(id);
    final heap = mem.heapUsage ?? 0;
    final cap = mem.heapCapacity ?? 0;
    final ext = mem.externalUsage ?? 0;
    totalHeap += heap;
    totalCapacity += cap;
    totalExternal += ext;

    stdout.writeln(
      '  ${(ref.name ?? id).padRight(22)} '
      'gc=${gc.toString().padLeft(5)}  '
      'heap=${_mb(heap)}  cap=${_mb(cap)}  ext=${_mb(ext)}',
    );
  }

  // Prefer the raw stream count; per-isolate attribution is best-effort.
  final gcTotal = totalEvents > totalGc ? totalEvents : totalGc;
  final gcPerSec = (gcTotal / seconds).toStringAsFixed(1);
  stdout.writeln(
    '\nTotals over ${seconds}s across ${isolates.length} isolates:',
  );
  stdout.writeln('  GC events   : $gcTotal  ($gcPerSec/s)');
  stdout.writeln('  heap in use : ${_mb(totalHeap)}');
  stdout.writeln('  heap cap    : ${_mb(totalCapacity)}');
  stdout.writeln('  external    : ${_mb(totalExternal)}');
  stdout.writeln(
    '\nHint: high GC/s with a long wrk p99 tail points at per-request '
    'allocations as the bottleneck.',
  );

  await service.dispose();
}

String _toWebSocket(String uri) {
  var u = uri.trim();
  if (u.startsWith('ws://') || u.startsWith('wss://')) return u;
  u = u.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
  if (!u.endsWith('/')) u += '/';
  return '${u}ws';
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
