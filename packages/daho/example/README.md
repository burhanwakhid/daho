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
| — | [advanced/jwt_rest_api/](advanced/jwt_rest_api/) | Full REST API with JWT auth, SQLite, and layered architecture |

## Running an Example

```bash
# From the packages/daho directory:
dart run example/01_hello_world.dart
```

Then open `http://localhost:8080` or use `curl` to test.
