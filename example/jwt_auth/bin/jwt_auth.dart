import 'dart:isolate';

import 'package:daho/daho.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

// =====================================================================
// 1. KONFIGURASI & DATABASE SETUP
// =====================================================================
const String JWT_SECRET = 'daho_super_secret_key_2026';
late final Database db;

void initDatabase() {
  // Membuka atau membuat file database SQLite
  db = sqlite3.open('daho_api.sqlite');

  // =====================================================================
  // KEAJAIBAN SQLITE: Mengaktifkan WAL Mode untuk Multi-Worker Concurrency
  // =====================================================================
  db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA synchronous = NORMAL;');

  // 1. Membuat tabel users jika belum ada
  db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  // 2. Membuat tabel todos jika belum ada (Berelasi dengan user_id)
  db.execute('''
    CREATE TABLE IF NOT EXISTS todos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      is_completed INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    );
  ''');

  // 3. Seeding 10 Data Awal (INSERT OR IGNORE + Hardcoded ID)
  // Ini mencegah 10 data digandakan menjadi 100 data oleh 10 Worker Isolate
  db.execute('''
    INSERT OR IGNORE INTO todos (id, user_id, title, is_completed) VALUES 
      (1, 1, 'Mempelajari arsitektur Pointer FFI di C', 1),
      (2, 1, 'Membangun Core Daho Framework', 1),
      (3, 1, 'Mengimplementasi H2O Native Fast-Path', 1),
      (4, 1, 'Menghubungkan SQLite dengan WAL Mode', 1),
      (5, 1, 'Mengamankan API dengan JWT Bearer', 1),
      (6, 1, 'Membuat operasi CRUD untuk Todo', 0),
      (7, 1, 'Melakukan stress test dengan wrk (Target 50k RPS)', 0),
      (8, 1, 'Membersihkan kode (Code Refactoring)', 0),
      (9, 1, 'Menulis dokumentasi README.md', 0),
      (10, 1, 'Merilis Daho Framework v1.0 ke pub.dev', 0);
  ''');

  print(
    '📦 Database SQLite & Tabel Todo siap di Worker-${Isolate.current.debugName}',
  );
}

// Helper untuk Hashing Password murni
String hashPassword(String password) {
  final bytes = utf8.encode("${password}garam_daho"); // Menambahkan salt
  return sha256.convert(bytes).toString();
}

// =====================================================================
// 2. MIDDLEWARE: JWT AUTHENTICATION
// =====================================================================
Future<void> jwtAuthMiddleware(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  // Ambil header authorization (kuncinya otomatis di-lowercase oleh framework kita)
  final authHeader = req.headers['authorization'];

  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    res.unauthorized({
      "status": "error",
      "message":
          "Akses Ditolak: Token Bearer tidak ditemukan di Header Authorization!",
    });
    return; // Putus rantai eksekusi
  }

  // Ekstrak token dengan membuang kata "Bearer "
  final token = authHeader.substring(7);

  try {
    // Verifikasi Token
    final jwt = JWT.verify(token, SecretKey(JWT_SECRET));

    // Injeksi ID user
    req.params['user_id'] = jwt.payload['user_id'].toString();

    await next(); // Lolos!
  } on JWTExpiredException {
    res.unauthorized({"status": "error", "message": "Token sudah kadaluarsa!"});
  } on JWTException catch (e) {
    res.unauthorized({
      "status": "error",
      "message": "Token tidak valid: ${e.message}",
    });
  }
}

// =====================================================================
// 3. CONTROLLERS (Logika Bisnis)
// =====================================================================

DahoResponse registerController(DahoRequest req, DahoResponse res) {
  final body = req.body;
  if (body == null ||
      body['name'] == null ||
      body['email'] == null ||
      body['password'] == null) {
    return res.badRequest({
      "error": "Data name, email, dan password wajib diisi!",
    });
  }

  try {
    final hashedPassword = hashPassword(body['password']);

    // Prepare statement agar aman dari SQL Injection
    final stmt = db.prepare(
      'INSERT INTO users (name, email, password) VALUES (?, ?, ?)',
    );
    stmt.execute([body['name'], body['email'], hashedPassword]);
    stmt.dispose();

    return res.ok({
      "status": "success",
      "message": "Registrasi berhasil, silakan login.",
    });
  } catch (e) {
    // Menangkap error constraint UNIQUE email SQLite
    if (e.toString().contains('UNIQUE')) {
      return res.badRequest({"error": "Email sudah terdaftar!"});
    }
    return res.internalServerError({"error": "Terjadi kesalahan server"});
  }
}

DahoResponse loginController(DahoRequest req, DahoResponse res) {
  final body = req.body;
  if (body == null || body['email'] == null || body['password'] == null) {
    return res.badRequest({"error": "Email dan password wajib diisi!"});
  }

  final hashedPassword = hashPassword(body['password']);

  // Mencari user di database
  final ResultSet results = db.select(
    'SELECT id, name, password FROM users WHERE email = ?',
    [body['email']],
  );

  if (results.isEmpty) {
    return res.unauthorized({"error": "Email tidak ditemukan!"});
  }

  final user = results.first;
  if (user['password'] != hashedPassword) {
    return res.unauthorized({"error": "Password salah!"});
  }

  // Generate JWT Token
  final jwt = JWT({
    'user_id': user['id'],
    'email': body['email'],
    'role': 'user',
    'exp':
        DateTime.now().add(Duration(hours: 24)).millisecondsSinceEpoch ~/
        1000, // Berlaku 24 Jam
  });

  final token = jwt.sign(SecretKey(JWT_SECRET));

  return res.ok({
    "status": "success",
    "message": "Login berhasil!",
    "data": {"user_id": user['id'], "name": user['name'], "token": token},
  });
}

DahoResponse getProfileController(DahoRequest req, DahoResponse res) {
  // Mengambil user_id yang disuntikkan oleh jwtAuthMiddleware
  final userId = req.params['user_id'];

  final ResultSet results = db.select(
    'SELECT id, name, email, created_at FROM users WHERE id = ?',
    [userId],
  );

  if (results.isEmpty) {
    return res.notFound({"error": "User tidak ditemukan!"});
  }

  return res.ok({
    "status": "success",
    "data": results.first, // Kembalikan data user tanpa password
  });
}

DahoResponse fetchAllUsersController(DahoRequest req, DahoResponse res) {
  // Hanya ambil id dan nama untuk privasi
  final ResultSet results = db.select(
    'SELECT id, name, created_at FROM users ORDER BY id DESC',
  );

  return res.ok({
    "status": "success",
    "total": results.length,
    "data": results.toList(),
  });
}

DahoResponse fetchAllTodoController(DahoRequest req, DahoResponse res) {
  // Hanya ambil id dan nama untuk privasi
  final ResultSet results = db.select('SELECT * FROM todos');

  return res.ok({
    "status": "success",
    "total": results.length,
    "data": results.toList(),
  });
}

// =====================================================================
// 4. DAFTARKAN RUTE (ROUTING)
// =====================================================================
void setupRoutes(Daho app) {
  initDatabase();
  // --- GRUP AUTHENTICATION (Publik) ---
  final authGroup = app.group('/auth');
  authGroup.post('/register', registerController);
  authGroup.post('/login', loginController);

  // --- GRUP API (Terlindungi JWT) ---
  final apiGroup = app.group('/api');
  apiGroup.use(jwtAuthMiddleware); // Pasang gembok JWT di sini!

  apiGroup.get('/profile', getProfileController);
  apiGroup.get('/users', fetchAllUsersController);

  app.get('/todos', fetchAllTodoController);

  // Endpoint publik sebagai penanda server hidup
  app.fastPath(
    '/ping',
    '{"status": "Daho API is alive!"}',
    contentType: 'application/json',
  );
}

// =====================================================================
// 5. NYALAKAN MESIN
// =====================================================================
void main() {
  Daho.cluster(
    setupRoutes,
    8081,
    onStart: () {
      print("🚀 Daho Full REST API Aktif di http://localhost:8081");
      print("-----------------------------------------------------");
      print("📝 POST /auth/register -> Untuk mendaftar");
      print("🔑 POST /auth/login    -> Untuk mendapatkan Token JWT");
      print("🛡️  GET  /api/profile?token=YOUR_TOKEN -> Lihat profil");
      print("🛡️  GET  /api/users?token=YOUR_TOKEN   -> Lihat daftar user");
      print("-----------------------------------------------------");
    },
  );
}
