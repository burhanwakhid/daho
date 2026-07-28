/// 14 — Templates with Clurit
///
/// Demonstrates the Clurit template engine:
/// - Template rendering with data
/// - Template inheritance (@extends, @section, @yield)
/// - Control structures (@if, @foreach)
/// - Includes (@include)
/// - Auto-escaping ({{ }}) vs raw ({!! !!})
/// - Daho integration with res.view()
///
/// Run:  dart run example/14_templates.dart
/// Test:
///   curl http://localhost:8080/
///   curl http://localhost:8080/users
///   curl http://localhost:8080/about
library;

import 'package:daho/daho.dart';
import 'package:clurit_daho/clurit_daho.dart';

void setupRoutes(Daho app) {
  // Configure Clurit template engine
  app.configureClurit(
    viewsPath: 'example/advanced/templates/views',
    debug: true, // Recompile on every request (development mode)
  );

  app.use(Middlewares.logger());

  // Home page — renders a template with data
  app.get('/', (req, res) {
    return res.view('pages/home', {
      'title': 'Home',
      'name': 'Alice',
      'items': ['Dart', 'Flutter', 'Daho', 'Clurit'],
    });
  });

  // Users page — demonstrates @foreach and @if
  app.get('/users', (req, res) {
    return res.view('pages/users', {
      'title': 'Users',
      'users': [
        {'name': 'Alice', 'email': 'alice@example.com', 'role': 'admin'},
        {'name': 'Bob', 'email': 'bob@example.com', 'role': 'user'},
        {'name': 'Charlie', 'email': 'charlie@example.com', 'role': 'user'},
      ],
    });
  });

  // About page — demonstrates template inheritance
  app.get('/about', (req, res) {
    return res.view('pages/about', {
      'title': 'About',
      'description': 'Daho is a fast HTTP framework for Dart.',
    });
  });

  // Profile page — demonstrates @if/@else
  app.get('/profile/:id', (req, res) {
    final userId = req.params['id'];
    // Simulate user lookup
    final user = userId == '1'
        ? {
            'name': 'Alice',
            'email': 'alice@example.com',
            'bio': 'Dart developer',
          }
        : null;

    return res.view('pages/profile', {
      'title': 'Profile',
      'user': user,
      'userId': userId,
    });
  });
}

void main() {
  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () {
      print('Template example running at http://127.0.0.1:8080');
      print('---');
      print('Pages: /, /users, /about, /profile/1, /profile/999');
    },
  );
}
