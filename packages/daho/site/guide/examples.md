# Examples

Progressive examples demonstrating Daho's features, from basic to advanced.

## Basics

### 01 — Hello World
**File:** [`example/01_hello_world.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/01_hello_world.dart)

The simplest possible Daho server. Shows the `AppBuilder` pattern, `app.get()`, `res.ok()`, and `app.listen()`.

```dart
void setupRoutes(Daho app) {
  app.get('/', (req, res) => res.ok({'message': 'Hello, Daho!'}));
}
```

---

### 02 — Routing
**File:** [`example/02_routing.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/02_routing.dart)

All HTTP methods (GET/POST/PUT/DELETE/PATCH), query parameters, path parameters, and request body parsing.

---

### 03 — Middleware
**File:** [`example/03_middleware.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/03_middleware.dart)

Built-in middleware: logger, CORS, secure headers, gzip compression. Also shows a custom API key middleware.

---

### 04 — Route Groups
**File:** [`example/04_route_groups.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/04_route_groups.dart)

Route groups with shared prefix and scoped middleware. Public vs protected route separation.

---

## Intermediate

### 05 — Request & Response
**File:** [`example/05_request_response.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/05_request_response.dart)

Full DahoRequest/DahoResponse API: status helpers, redirects, cookies, fluent chaining.

---

### 06 — Static Files
**File:** [`example/06_serving_static_files.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/06_serving_static_files.dart)

`serveStatic()` for zero-copy file serving and `fastPath()` for native C responses.

---

### 07 — Configuration
**File:** [`example/07_configuration.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/07_configuration.dart)

All `DahoConfig` options with explanations: body limit, concurrency, timeouts, trust proxy, custom handlers.

---

### 08 — Error Handling
**File:** [`example/08_error_handling.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/08_error_handling.dart)

Custom `errorHandler` and `notFoundHandler` functions.

---

### 09 — Cookies
**File:** [`example/09_cookies.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/09_cookies.dart)

Cookie management: set, read, clear. Cookie attributes (maxAge, httpOnly, secure, sameSite).

---

### 10 — File Upload
**File:** [`example/10_file_upload.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/10_file_upload.dart)

Multipart file upload with `req.files` and `UploadedFile.save()`.

---

## Advanced

### 11 — Testing
**File:** [`example/11_testing.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/11_testing.dart)

In-process testing patterns with `DahoTester`.

---

### 12 — Concurrency Client
**File:** [`example/12_concurrency_client.dart`](https://github.com/nicholasnbg/daho/blob/main/packages/daho/example/12_concurrency_client.dart)

Client-side concurrency test that proves the server handles requests concurrently.

---

### JWT REST API
**Directory:** [`example/advanced/jwt_rest_api/`](https://github.com/nicholasnbg/daho/tree/main/packages/daho/example/advanced/jwt_rest_api)

A full-featured REST API demonstrating:
- JWT authentication with Bearer tokens
- SQLite database with WAL mode
- Layered architecture: Entity → DTO → Repository → Service → Handler
- Route groups with scoped middleware
- `DahoConfig` with custom body limit

---

## Running Examples

```bash
# From packages/daho directory:
dart run example/01_hello_world.dart

# Then test with curl:
curl http://localhost:8080
```
