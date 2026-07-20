# JWT REST API Example

A full-featured REST API built with Daho, demonstrating JWT authentication, SQLite database, and a layered architecture (Controller → Service → Repository).

## Features

- **JWT Authentication** — Register, login, and protect routes with Bearer tokens
- **SQLite Database** — WAL mode for concurrent reads, auto-migrations, seed data
- **Layered Architecture** — Clean separation: Entity, DTO, Repository, Service, Handler
- **Route Groups** — Public (`/auth`) and protected (`/api`) route groups
- **Middleware** — JWT verification middleware scoped to the `/api` group

## Endpoints

### Public (no auth required)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/register` | Register a new user |
| POST | `/auth/login` | Login and receive a JWT token |

### Protected (requires `Authorization: Bearer <token>`)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/profile` | Get current user profile |
| GET | `/api/users` | List all users |
| GET | `/api/todos` | List all todos |

## Running

```bash
# From this directory
dart pub get
dart run bin/server.dart
```

## Example Usage

```bash
# Register
curl -X POST http://localhost:8081/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice", "email": "alice@example.com", "password": "secret123"}'

# Login
curl -X POST http://localhost:8081/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com", "password": "secret123"}'

# Access protected endpoint (use token from login response)
curl http://localhost:8081/api/profile \
  -H "Authorization: Bearer <your-token>"
```
