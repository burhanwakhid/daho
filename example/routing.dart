import 'package:daho/daho.dart';

void setupRoutes(Daho app) {
  // 1. Rute Get Biasa
  app.get('/', (req, res) {
    return res.send('Selamat datang di Daho Framework!');
  });

  // 2. Mengambil Query Parameter (misal: /search?q=dart&limit=10)
  app.get('/search', (req, res) {
    final query = req.query['q'] ?? 'kosong';
    final limit = req.query['limit'] ?? '5';

    return res.ok({
      "pesan": "Mencari data...",
      "kata_kunci": query,
      "batas_pencarian": limit,
    });
  });

  // 3. Mengambil Path Parameter (Dinamic Route)
  app.get('/user/:id', (req, res) {
    final userId = req.params['id'];
    return res.ok({"id_pengguna": userId, "nama": "Pengguna $userId"});
  });
}

void main() {
  Daho.cluster(
    setupRoutes,
    8081,
    onStart: () {
      print("🚀 Server Basic Routing berjalan di http://localhost:8081");
    },
  );
}
