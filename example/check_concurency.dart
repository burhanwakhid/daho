import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient();
  final stopwatch = Stopwatch()..start();

  print("🚀 Memulai Uji Coba Concurrency Asinkron...\n");

  // Fungsi helper untuk menembak API dan mencatat waktu
  Future<void> hitApi(String namaTask, String path) async {
    final start = stopwatch.elapsedMilliseconds;
    print("➡️ [$namaTask] Dikirim pada ${start}ms");

    try {
      final request = await client.get('127.0.0.1', 8081, path);
      final response = await request.close();

      // Membaca isi balasan agar koneksi benar-benar selesai
      await response.transform(utf8.decoder).join();

      final end = stopwatch.elapsedMilliseconds;
      final durasi = end - start;

      print("✅ [$namaTask] Selesai! Butuh waktu: ${durasi}ms");
    } catch (e) {
      print("❌ [$namaTask] Gagal: $e");
    }
  }

  // 1. Tembak request LAMBAT (Server akan menahannya selama 5 detik)
  final prosesLambat = hitApi("LAMBAT", "/lambat");

  // 2. Beri jeda 500 milidetik untuk memastikan request LAMBAT sudah masuk ke H2O
  await Future.delayed(const Duration(milliseconds: 500));

  print("\n--- 🔫 Menembakkan 5 Request Cepat secara bersamaan! ---\n");

  // 3. Tembakkan 5 request CEPAT saat server sedang sibuk menunggu request LAMBAT
  final prosesCepat = <Future>[];
  for (int i = 1; i <= 5; i++) {
    prosesCepat.add(hitApi("CEPAT-$i", "/cepat"));
  }

  // Tunggu semua proses selesai
  await Future.wait([prosesLambat, ...prosesCepat]);

  print(
    "\n🎉 Semua uji coba selesai. Total waktu eksekusi: ${stopwatch.elapsedMilliseconds}ms",
  );
  client.close();
}
