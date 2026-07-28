/// JWT-authenticated REST API example using Daho.
///
/// Demonstrates:
/// - JWT authentication with Bearer tokens
/// - SQLite database with WAL mode
/// - Layered architecture: Entity → DTO → Repository → Service → Handler
/// - Route groups with scoped middleware
/// - DahoConfig with custom body limit
///
/// Endpoints:
///   POST /auth/register   — Register a new user
///   POST /auth/login      — Login and receive a JWT token
///   GET  /api/profile     — Get current user profile (auth required)
///   GET  /api/users       — List all users (auth required)
///   GET  /api/todos       — List all todos (auth required)
///   GET  /ping            — Health check (fast path, no Dart)
library;

import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:daho/daho.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:sqlite3/sqlite3.dart';

// =============================================================================
// 1. CONFIGURATION & DATABASE
// =============================================================================

const String jwtSecret = 'daho_super_secret_key_2026';

class AppDatabase {
  static late final Database db;

  static void init() {
    db = sqlite3.open('daho_api.sqlite');
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    _runMigrations();
    _seedData();
    print('Database ready on Worker-${Isolate.current.debugName}');
  }

  static void _runMigrations() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
    ''');

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
  }

  static void _seedData() {
    db.execute('''
      INSERT OR IGNORE INTO todos (id, user_id, title, is_completed) VALUES
        (1, 1, 'Learn FFI pointer architecture in C', 1),
        (2, 1, 'Build Daho Framework core', 1),
        (3, 1, 'Implement Controller-Service-Repository pattern', 1);
    ''');
  }
}

// =============================================================================
// 2. ENTITY LAYER — Pure database representation
// =============================================================================

class User {
  final int id;
  final String name;
  final String email;
  final String password;
  final String createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.createdAt,
  });

  factory User.fromMap(Map<String, dynamic> map) => User(
    id: map['id'],
    name: map['name'],
    email: map['email'],
    password: map['password'],
    createdAt: map['created_at']?.toString() ?? '',
  );
}

class Todo {
  final int id;
  final int userId;
  final String title;
  final bool isCompleted;
  final String createdAt;

  Todo({
    required this.id,
    required this.userId,
    required this.title,
    required this.isCompleted,
    required this.createdAt,
  });

  factory Todo.fromMap(Map<String, dynamic> map) => Todo(
    id: map['id'],
    userId: map['user_id'],
    title: map['title'],
    isCompleted: map['is_completed'] == 1,
    createdAt: map['created_at']?.toString() ?? '',
  );
}

// =============================================================================
// 3. DTO LAYER — API input/output shapes
// =============================================================================

class RegisterRequestDto {
  final String name, email, password;
  RegisterRequestDto(this.name, this.email, this.password);
  static RegisterRequestDto? fromJson(Map<String, dynamic>? j) =>
      (j?['name'] != null && j?['email'] != null && j?['password'] != null)
      ? RegisterRequestDto(j!['name'], j['email'], j['password'])
      : null;
}

class LoginRequestDto {
  final String email, password;
  LoginRequestDto(this.email, this.password);
  static LoginRequestDto? fromJson(Map<String, dynamic>? j) =>
      (j?['email'] != null && j?['password'] != null)
      ? LoginRequestDto(j!['email'], j['password'])
      : null;
}

class UserResponseDto {
  final int id;
  final String name;
  final String? email;
  final String createdAt;

  UserResponseDto({
    required this.id,
    required this.name,
    this.email,
    required this.createdAt,
  });

  factory UserResponseDto.fromEntity(User user, {bool includeEmail = false}) =>
      UserResponseDto(
        id: user.id,
        name: user.name,
        email: includeEmail ? user.email : null,
        createdAt: user.createdAt,
      );

  Map<String, dynamic> toMap() => {
    "id": id,
    "name": name,
    if (email != null) "email": email,
    "created_at": createdAt,
  };
}

class TodoResponseDto {
  final int id;
  final String title;
  final bool isCompleted;

  TodoResponseDto({
    required this.id,
    required this.title,
    required this.isCompleted,
  });

  factory TodoResponseDto.fromEntity(Todo todo) => TodoResponseDto(
    id: todo.id,
    title: todo.title,
    isCompleted: todo.isCompleted,
  );

  Map<String, dynamic> toMap() => {
    "id": id,
    "title": title,
    "is_completed": isCompleted,
  };
}

class AuthResponseDto {
  final UserResponseDto user;
  final String token;
  AuthResponseDto(this.user, this.token);
  Map<String, dynamic> toMap() => {"user": user.toMap(), "token": token};
}

// =============================================================================
// 4. REPOSITORY LAYER — Raw DB access, returns entities
// =============================================================================

class UserRepository {
  void createUser(RegisterRequestDto dto, String hashedPassword) {
    final stmt = AppDatabase.db.prepare(
      'INSERT INTO users (name, email, password) VALUES (?, ?, ?)',
    );
    stmt.execute([dto.name, dto.email, hashedPassword]);
    stmt.dispose();
  }

  User? findByEmail(String email) {
    final results = AppDatabase.db.select(
      'SELECT * FROM users WHERE email = ?',
      [email],
    );
    return results.isEmpty ? null : User.fromMap(results.first);
  }

  User? findById(String id) {
    final results = AppDatabase.db.select('SELECT * FROM users WHERE id = ?', [
      id,
    ]);
    return results.isEmpty ? null : User.fromMap(results.first);
  }

  List<User> fetchAllUsers() {
    return AppDatabase.db
        .select('SELECT * FROM users ORDER BY id DESC')
        .map((row) => User.fromMap(row))
        .toList();
  }
}

class TodoRepository {
  List<Todo> fetchAllTodos() {
    return AppDatabase.db
        .select('SELECT * FROM todos')
        .map((row) => Todo.fromMap(row))
        .toList();
  }
}

// =============================================================================
// 5. SERVICE LAYER — Business logic, returns DTOs
// =============================================================================

class UserService {
  final UserRepository _userRepo;
  UserService(this._userRepo);

  String _hashPassword(String password) {
    final bytes = utf8.encode('${password}daho_salt');
    return sha256.convert(bytes).toString();
  }

  void register(RegisterRequestDto dto) {
    try {
      _userRepo.createUser(dto, _hashPassword(dto.password));
    } catch (e) {
      if (e.toString().contains('UNIQUE')) {
        throw Exception('Email already registered');
      }
      throw Exception('Server error');
    }
  }

  AuthResponseDto login(LoginRequestDto dto) {
    final user = _userRepo.findByEmail(dto.email);
    if (user == null || user.password != _hashPassword(dto.password)) {
      throw Exception('Invalid email or password');
    }

    final jwt = JWT({
      'user_id': user.id,
      'exp':
          DateTime.now().add(Duration(hours: 24)).millisecondsSinceEpoch ~/
          1000,
    });
    final token = jwt.sign(SecretKey(jwtSecret));

    return AuthResponseDto(
      UserResponseDto.fromEntity(user, includeEmail: true),
      token,
    );
  }

  UserResponseDto? getProfile(String id) {
    final user = _userRepo.findById(id);
    return user != null
        ? UserResponseDto.fromEntity(user, includeEmail: true)
        : null;
  }

  List<UserResponseDto> getAllUsers() {
    return _userRepo
        .fetchAllUsers()
        .map((u) => UserResponseDto.fromEntity(u))
        .toList();
  }
}

class TodoService {
  final TodoRepository _todoRepo;
  TodoService(this._todoRepo);

  List<TodoResponseDto> getAllTodos() {
    return _todoRepo
        .fetchAllTodos()
        .map((t) => TodoResponseDto.fromEntity(t))
        .toList();
  }
}

// =============================================================================
// 6. HTTP HANDLERS
// =============================================================================

class AuthHandler {
  final UserService _userService;
  AuthHandler(this._userService);

  DahoResponse register(DahoRequest req, DahoResponse res) {
    final dto = RegisterRequestDto.fromJson(req.body);
    if (dto == null)
      return res.badRequest({"error": "Missing required fields"});

    try {
      _userService.register(dto);
      return res.ok({
        "status": "success",
        "message": "Registration successful",
      });
    } catch (e) {
      return res.badRequest({
        "error": e.toString().replaceAll("Exception: ", ""),
      });
    }
  }

  DahoResponse login(DahoRequest req, DahoResponse res) {
    final dto = LoginRequestDto.fromJson(req.body);
    if (dto == null) {
      return res.badRequest({"error": "Email and password are required"});
    }

    try {
      final AuthResponseDto authObj = _userService.login(dto);
      return res.ok({"status": "success", "data": authObj.toMap()});
    } catch (e) {
      return res.unauthorized({
        "error": e.toString().replaceAll("Exception: ", ""),
      });
    }
  }
}

class UserHandler {
  final UserService _userService;
  UserHandler(this._userService);

  DahoResponse getProfile(DahoRequest req, DahoResponse res) {
    final UserResponseDto? userObj = _userService.getProfile(
      req.params['user_id'] ?? '',
    );
    if (userObj == null) {
      return res.notFound({"error": "User not found"});
    }
    return res.ok({"status": "success", "data": userObj.toMap()});
  }

  DahoResponse fetchAllUsers(DahoRequest req, DahoResponse res) {
    final List<UserResponseDto> userObjects = _userService.getAllUsers();
    return res.ok({
      "status": "success",
      "total": userObjects.length,
      "data": userObjects.map((e) => e.toMap()).toList(),
    });
  }
}

class TodoHandler {
  final TodoService _todoService;
  TodoHandler(this._todoService);

  Future<DahoResponse> fetchAllTodos(DahoRequest req, DahoResponse res) async {
    final List<TodoResponseDto> todoObjects = _todoService.getAllTodos();
    return res.ok({
      "status": "success",
      "total": todoObjects.length,
      "data": todoObjects.map((e) => e.toMap()).toList(),
    });
  }
}

// =============================================================================
// 7. MIDDLEWARE & ENTRY POINT
// =============================================================================

/// JWT authentication middleware. Verifies the Bearer token and injects
/// the user ID into `req.params['user_id']` for downstream handlers.
Future<void> jwtAuthMiddleware(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  final authHeader = req.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    res.unauthorized({"error": "Bearer token not provided"});
    return;
  }
  try {
    final jwt = JWT.verify(authHeader.substring(7), SecretKey(jwtSecret));
    req.params['user_id'] = jwt.payload['user_id'].toString();
    await next();
  } on JWTException catch (e) {
    res.unauthorized({"error": "Invalid token: ${e.message}"});
    return;
  }
}

/// Route setup — must be a top-level function (Isolate constraint).
void setupRoutes(Daho app) {
  AppDatabase.init();

  // Manual dependency injection
  final userRepository = UserRepository();
  final todoRepository = TodoRepository();

  final userService = UserService(userRepository);
  final todoService = TodoService(todoRepository);

  final authHandler = AuthHandler(userService);
  final userHandler = UserHandler(userService);
  final todoHandler = TodoHandler(todoService);

  // Public routes (no auth)
  final authGroup = app.group('/auth');
  authGroup.post('/register', authHandler.register);
  authGroup.post('/login', authHandler.login);

  // Protected routes (JWT middleware)
  final apiGroup = app.group('/api');
  apiGroup.use(jwtAuthMiddleware);
  apiGroup.get('/profile', userHandler.getProfile);
  apiGroup.get('/users', userHandler.fetchAllUsers);
  apiGroup.get('/todos', todoHandler.fetchAllTodos);

  // Native fast path — served entirely in C, never touches Dart
  app.fastPath('/ping', '{"message": "pong"}', contentType: 'application/json');
}

void main() {
  final app = Daho(
    // Set a 10 MB body limit (default is 4 MB)
    config: const DahoConfig(bodyLimit: 10 * 1024 * 1024),
  );

  app.listen(
    8081,
    routes: setupRoutes,
    onStart: () {
      print('JWT REST API running at http://127.0.0.1:8081');
      print('---');
      print('Public:  POST /auth/register, POST /auth/login');
      print('Protected: GET /api/profile, /api/users, /api/todos');
    },
  );
}
