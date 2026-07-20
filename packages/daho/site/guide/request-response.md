# Request & Response

## DahoRequest

The incoming HTTP request handed to route handlers and middleware.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `method` | `String` | HTTP method (`GET`, `POST`, etc.) |
| `path` | `String` | Request path (e.g., `/users/42`) |
| `query` | `Map<String, String>` | Query parameters |
| `params` | `Map<String, String>` | Path parameters (`:id` → `'42'`) |
| `ip` | `String` | Client IP address |
| `headers` | `Map<String, String>` | Request headers (lowercase keys) |
| `body` | `dynamic` | Parsed request body (lazy) |
| `files` | `Map<String, UploadedFile>` | Uploaded files (lazy) |
| `cookies` | `Map<String, String>` | Parsed cookies (lazy) |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `header(name)` | `String?` | Case-insensitive header lookup |

### Body Parsing

The body is parsed lazily — only decoded when `req.body` or `req.files` is first accessed:

- **JSON** (`application/json`) → `Map` or `List`
- **Form-encoded** (`application/x-www-form-urlencoded`) → `Map<String, String>`
- **Multipart** (`multipart/form-data`) → `Map<String, String>` for fields, `req.files` for files
- **Plain text** → `String`

```dart
app.post('/users', (req, res) {
  final data = req.body; // Parsed based on Content-Type
  return res.ok(data);
});
```

### Reading Headers

```dart
// Case-insensitive lookup
final userAgent = req.header('user-agent');
final contentType = req.header('content-type');

// All headers
final allHeaders = req.headers;
```

## DahoResponse

The response builder handed to route handlers. Every mutating method returns `this` for fluent chaining.

### Sending Data

| Method | Description |
|--------|-------------|
| `send(text)` | Send plain text |
| `json(data)` | Serialize as JSON |
| `bytes(raw)` | Send raw bytes |

```dart
res.send('Hello');                           // text/plain
res.json({'name': 'Ada'});                   // application/json
res.bytes([0x89, 0x50, 0x4E, 0x47]);        // application/octet-stream
```

### Status Helpers

| Method | Status | Description |
|--------|--------|-------------|
| `ok(data)` | 200 | Success |
| `badRequest(data)` | 400 | Client error |
| `unauthorized(data)` | 401 | Authentication required |
| `forbidden(data)` | 403 | Access denied |
| `notFound(data)` | 404 | Resource not found |
| `internalServerError(data)` | 500 | Server error |

Each auto-detects the body type: `String` → text, `Map`/`List` → JSON, `List<int>` → bytes, `null` → empty.

```dart
res.ok({'users': [...]});              // 200 + JSON
res.badRequest({'error': 'Invalid'});  // 400 + JSON
res.notFound('Page not found');        // 404 + text
```

### Redirects

| Method | Status | Description |
|--------|--------|-------------|
| `movedPermanently(location)` | 301 | Permanent redirect |
| `found(location)` | 302 | Temporary redirect |
| `seeOther(location)` | 303 | Redirect after POST |
| `notModified()` | 304 | Not modified |

```dart
res.movedPermanently('/new-page');
res.found('/login');
```

### Setting Headers

```dart
res.header('X-Custom', 'value');
res.status(201);
```

### Fluent Chaining

All methods return `this`, so you can chain them:

```dart
res
    .status(201)
    .header('X-Request-Id', 'abc123')
    .json({'created': true});
```

## Cookies

### Setting Cookies

```dart
res.cookie(
  'session',
  'abc123',
  maxAge: Duration(hours: 1),
  httpOnly: true,
  secure: true,
  sameSite: 'Lax',
  path: '/',
  domain: '.example.com',
);
```

### Reading Cookies

```dart
final sessionId = req.cookies['session'];
```

### Clearing Cookies

```dart
res.clearCookie('session');
res.clearCookie('theme', path: '/settings');
```

## UploadedFile

Files from `multipart/form-data` uploads:

| Property | Type | Description |
|----------|------|-------------|
| `filename` | `String` | Original filename |
| `contentType` | `String` | MIME type (e.g., `image/png`) |
| `bytes` | `List<int>` | Raw file contents |

| Method | Description |
|--------|-------------|
| `save(path)` | Write to disk (synchronous) |
| `saveAsync(path)` | Write to disk (asynchronous) |

```dart
app.post('/upload', (req, res) {
  final avatar = req.files['avatar'];
  if (avatar == null) return res.badRequest({'error': 'No file'});

  avatar.save('./uploads/${avatar.filename}');

  return res.ok({
    'filename': avatar.filename,
    'type': avatar.contentType,
    'size': avatar.bytes.length,
  });
});
```
