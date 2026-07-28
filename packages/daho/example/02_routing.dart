/// 02 — Routing
///
/// Demonstrates all HTTP methods and parameter extraction:
/// - GET, POST, PUT, DELETE, PATCH
/// - Query parameters: `req.query['key']`
/// - Path parameters: `req.params['name']`
/// - Request body: `req.body` (JSON, form-encoded, or text)
///
/// Run:  dart run example/02_routing.dart
/// Test:
///   curl http://localhost:8080
///   curl http://localhost:8080/search?q=dart&limit=10
///   curl http://localhost:8080/users/42
///   curl -X POST http://localhost:8080/users -H "Content-Type: application/json" -d '{"name":"Ada"}'
///   curl -X PUT http://localhost:8080/users/42 -H "Content-Type: application/json" -d '{"name":"Ada Lovelace"}'
///   curl -X PATCH http://localhost:8080/users/42 -H "Content-Type: application/json" -d '{"name":"A. Lovelace"}'
///   curl -X DELETE http://localhost:8080/users/42
library;

import 'package:daho/daho.dart';

void setupRoutes(Daho app) {
  // GET with plain text response
  app.get('/', (req, res) {
    return res.send('Welcome to Daho Framework!');
  });

  // GET with query parameters: /search?q=dart&limit=10
  app.get('/search', (req, res) {
    final query = req.query['q'] ?? '';
    final limit = req.query['limit'] ?? '10';
    return res.ok({'query': query, 'limit': int.tryParse(limit) ?? 10});
  });

  // GET with path parameter: /users/:id
  app.get('/users/:id', (req, res) {
    final userId = req.params['id'];
    return res.ok({'id': userId, 'name': 'User $userId'});
  });

  // POST — create a resource (returns 201)
  app.post('/users', (req, res) {
    final body = req.body;
    return res.status(201).json({'message': 'User created', 'data': body});
  });

  // PUT — full update of a resource
  app.put('/users/:id', (req, res) {
    return res.ok({
      'message': 'User ${req.params['id']} fully updated',
      'data': req.body,
    });
  });

  // PATCH — partial update of a resource
  app.patch('/users/:id', (req, res) {
    return res.ok({
      'message': 'User ${req.params['id']} partially updated',
      'data': req.body,
    });
  });

  // DELETE — remove a resource (returns 204 No Content)
  app.delete('/users/:id', (req, res) {
    return res.status(204).send('');
  });
}

void main() {
  final app = Daho();
  app.listen(
    8080,
    routes: setupRoutes,
    onStart: () => print('Server running at http://127.0.0.1:8080'),
  );
}
