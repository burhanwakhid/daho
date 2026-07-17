// example/main.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:daho/daho.dart';
import 'dart:io';

final Uint8List helloWorldBytes = utf8.encode(
  jsonEncode({
    'status': 'success',
    'pesan': 'Hello World! Diproses oleh mesin Cluster.',
  }),
);

void setupRoutes(Daho app) {
  app.fastPath('/health', '{"status": "ok"}', contentType: 'application/json');

  // 2. O(1) ROUTE & COMPILED MIDDLEWARE (Jalur Cepat Dart)
  app.get('/json', (req, res) {
    return res.json({"message": "Hello World"});
  });
  app.get('/coba', (req, res) {
    return res.ok({
      'status': 'success',
      'pesan': 'Hello World! Diproses oleh mesin Cluster.',
    });
  });

  app.get('/json-fast', (req, res) {
    return res
        .header('Content-Type', 'application/json')
        .bytes(helloWorldBytes); // Melempar byte mentah langsung ke kernel C!
  });

  // 1. Tampilkan halaman HTML Upload
  app.get('/', (req, res) {
    final html = '''
      <!DOCTYPE html>
      <html>
      <body style="font-family: sans-serif; padding: 40px;">
        <h2>Upload Foto ke Daho Framework</h2>
        <form action="/upload" method="POST" enctype="multipart/form-data">
          Pilih Foto: <input type="file" name="foto_profil" required><br><br>
          Nama User: <input type="text" name="nama_user"><br><br>
          <button type="submit">Upload Sekarang!</button>
        </form>
      </body>
      </html>
    ''';
    return res.header('Content-Type', 'text/html').send(html);
  });

  // 2. Tangkap Request Multipart/Form-Data
  app.post('/upload', (req, res) {
    // Membaca form text biasa
    final nama = req.body['nama_user'] ?? 'Anonim';

    // Membaca file yang diunggah
    final foto = req.files['foto_profil'];

    if (foto == null) {
      return res.status(400).json({
        "error": "File foto_profil tidak ditemukan!",
      });
    }

    // Pastikan folder uploads tersedia
    final uploadDir = Directory('./uploads');
    if (!uploadDir.existsSync()) {
      uploadDir.createSync();
    }

    // SIMPAN FILE KE HARDDISK DENGAN SANGAT MUDAH!
    final pathSimpan = '${uploadDir.path}/${foto.filename}';
    foto.save(pathSimpan);

    return res.status(201).json({
      "status": "sukses",
      "pesan": "Terima kasih $nama, file berhasil diunggah!",
      "nama_file": foto.filename,
      "tipe_file": foto.contentType,
      "ukuran_byte": foto.bytes.length,
      "lokasi_simpan": pathSimpan,
    });
  });
}

void main() {
  final app = Daho();
  app.listen(
    8081,
    routes: setupRoutes,
    onStart: () {
      print(
        "🚀 Daho Server (Multipart Support) Berjalan di http://127.0.0.1:8081",
      );
    },
  );
}
