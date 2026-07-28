# Daho Examples

Progressive examples demonstrating Daho's features, from basic to advanced.

## Prerequisites

- Dart SDK ^3.9
- H2O + CMake installed ([see Getting Started](../README.md#requirements))

## Examples

### Basics

| # | File | What it demonstrates |
|---|------|---------------------|
| 01 | [01_hello_world.dart](01_hello_world.dart) | Simplest server, `AppBuilder` pattern, `app.listen` |
| 02 | [02_routing.dart](02_routing.dart) | All HTTP methods (GET/POST/PUT/DELETE/PATCH), query params, path params |
| 03 | [03_middleware.dart](03_middleware.dart) | Built-in middleware: logger, CORS, secure headers, compression |
| 04 | [04_route_groups.dart](04_route_groups.dart) | Route groups with shared prefix and scoped middleware |

### Intermediate

| # | File | What it demonstrates |
|---|------|---------------------|
| 05 | [05_request_response.dart](05_request_response.dart) | Full DahoRequest/DahoResponse API: status helpers, redirects, cookies, chaining |
| 06 | [06_serving_static_files.dart](06_serving_static_files.dart) | `serveStatic()` for file serving, `fastPath()` for native C responses |
| 07 | [07_configuration.dart](07_configuration.dart) | All `DahoConfig` options with explanations |
| 08 | [08_error_handling.dart](08_error_handling.dart) | Custom `errorHandler` and `notFoundHandler` |
| 09 | [09_cookies.dart](09_cookies.dart) | Cookie management: set, read, clear |
| 10 | [10_file_upload.dart](10_file_upload.dart) | Multipart file upload with `req.files` and `UploadedFile.save()` |

### Advanced

| # | File | What it demonstrates |
|---|------|---------------------|
| 11 | [11_testing.dart](11_testing.dart) | In-process testing with `DahoTester` |
| 12 | [12_concurrency_client.dart](12_concurrency_client.dart) | Client-side concurrency test (requires a running server) |
| 13 | [13_authentication.dart](13_authentication.dart) | JWT authentication with `daho_auth` (PostgreSQL required) |
| 14 | [14_templates.dart](14_templates.dart) | Template engine with `clurit` (Blade-like syntax) |
| — | [advanced/jwt_rest_api/](advanced/jwt_rest_api/) | Full REST API with JWT auth, SQLite, and layered architecture |

## Running an Example

```bash
# From the packages/daho directory:
dart run example/01_hello_world.dart
```

Then open `http://localhost:8080` or use `curl` to test.

## Authentication Example (13)

Requires PostgreSQL and `daho_auth` package:

```bash
# 1. Start PostgreSQL (or use docker-compose)
docker-compose up -d

# 2. Run the example
dart run example/13_authentication.dart

# 3. Test registration
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com","password":"password123","name":"Alice"}'

# 4. Test login
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com","password":"password123"}'

# 5. Access protected endpoint (use token from login response)
curl http://localhost:8080/api/profile \
  -H "Authorization: Bearer <access_token>"
```

## Template Engine Example (14)

Uses `clurit` package for Blade-like templates:

```bash
# Run the example
dart run example/14_templates.dart

# Test pages
curl http://localhost:8080/          # Home page
curl http://localhost:8080/users     # Users list
curl http://localhost:8080/about     # About page
curl http://localhost:8080/profile/1 # User profile
```

Template files are in `advanced/templates/views/`:
- `layouts/main.clurit` — Base layout with navigation
- `pages/home.clurit` — Home page with @foreach loop
- `pages/users.clurit` — Users table with conditional rendering
- `pages/about.clurit` — About page with @include
- `pages/profile.clurit` — Profile page with @if/@else
- `partials/cta.clurit` — Reusable call-to-action component
- `partials/links.clurit` — Reusable links section
