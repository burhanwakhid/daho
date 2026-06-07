// example/05_route_grouping.dart
import 'package:daho/daho.dart';

// Middleware Autentikasi Tiruan
Future<void> authMiddleware(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  final token = req.query['token'];
  if (token != 'super-secret-token') {
    res.status(401).json({
      "error": "Unauthorized",
      "message": "Token tidak valid!",
    });
    return; // Stop di sini, jangan panggil next()
  }
  await next(); // Lanjutkan jika token benar
}

void setupRoutes(Daho app) {
  // =====================================================================
  // 1. RUTE PUBLIK (Bebas diakses siapapun tanpa Middleware)
  // =====================================================================
  app.get('/login', (req, res) {
    return res.json({"message": "Halaman Login - Publik"});
  });

  app.get('/register', (req, res) {
    return res.json({"message": "Halaman Register - Publik"});
  });

  final dashboardGroup = app.group('/dashboard');

  // Pasang pelindung Auth HANYA ke grup dashboard
  dashboardGroup.use(authMiddleware);

  // Rute ini otomatis menjadi: GET /dashboard/profile
  dashboardGroup.get('/profile', (req, res) {
    return res.json({
      "status": "success",
      "data": {"username": "burhanudin", "role": "admin"},
      "info": "Diakses dengan aman menggunakan Route Group Middleware!",
    });
  });

  // Rute ini otomatis menjadi: GET /dashboard/settings
  dashboardGroup.get('/settings', (req, res) {
    return res.json({
      "status": "success",
      "settings": {"theme": "dark", "notifications": true},
    });
  });
}

void main() {
  Daho.cluster(
    setupRoutes,
    8081,
    onStart: () {
      print("🚀 Server Daho (Route Grouping) Aktif di http://localhost:8081");
      print("🔒 Rute Publik : http://localhost:8081/login");
      print(
        "🔒 Rute Terproteksi : http://localhost:8081/dashboard/profile?token=super-secret-token",
      );
    },
  );
}
