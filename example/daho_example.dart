// example/main.dart
import 'dart:io';

import 'package:daho/daho.dart';

void main() {
  final app = Daho();

  // Endpoint sangat ringan (Instant)
  app.get('/cepat', (req, res) {
    return res.status(200).send("Wussss! Sangat cepat.");
  });

  final staticPath = '${Directory.current.path}/example/public';
  app.serveStatic('/assets', staticPath);

  // Endpoint yang mensimulasikan tugas sangat berat (contoh: Database Lambat)
  app.get('/lambat', (req, res) async {
    print("[Dart] Mulai memproses permintaan lambat...");

    // Tunggu 5 detik (Asinkron)
    await Future.delayed(const Duration(seconds: 5));

    print("[Dart] Permintaan lambat selesai diproses.");
    return res.status(200).send("Akhirnya selesai setelah menunggu 5 detik!");
  });

  app.listen(
    8081,
    onStart: () {
      print("🚀 Server Daho (Asinkron Penuh) menyala di http://127.0.0.1:8081");
      print("\n[CARA TEST CONCURRENCY]:");
      print(
        "1. Buka http://127.0.0.1:8081/lambat di Tab 1 Browser (Ia akan loading 5 detik)",
      );
      print(
        "2. DENGAN SEGERA buka http://127.0.0.1:8081/cepat di Tab 2 Browser",
      );
      print(
        "Tab 2 akan LANGSUNG memuat seketika, membuktikan bahwa Tab 1 TIDAK memblokir server!",
      );
    },
  );
}
