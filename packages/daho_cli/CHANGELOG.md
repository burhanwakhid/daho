## 0.1.3+1

- Fix: `envTemplate`'s generated `.env.example` hardcoded `DATABASE_URL=.../daho_app`, but `dockerComposeTemplate` creates the Postgres database as `POSTGRES_DB: $name` (the actual project name) — for any project not literally named `daho_app`, `docker-compose up -d` created a database that `.env`'s `DATABASE_URL` didn't point at, so `daho auth setup-db` always failed with `database "<name>" does not exist`. `envTemplate` now takes the project name and uses it as the database name, matching `docker-compose.yml`.

## 0.1.3

- Fix: `daho build` ran its own `findH2oHeader()`/`findH2oLib()` pre-flight check *before* invoking CMake, and on Linux `findH2oLib()` only recognized a shared `libh2o-evloop.so` — never the static `libh2o-evloop.a` that the 0.1.2 from-source build (and generated Dockerfiles) actually produce. It reported "H2O not found" and bailed out before CMake — which finds `.a` files just fine — ever ran. `findH2oLib()` now also checks for `.a`, and `daho build` no longer duplicates this check at all; it lets CMake's own `find_library` (the single source of truth already used by `c_src/CMakeLists.txt`) decide, only printing the install hint if the actual `cmake` configure step fails.

## 0.1.2

- Fix: generated Dockerfiles (`daho create --auth`/non-auth) apt-installed `libh2o-evloop-dev`, which does not exist on Debian/Ubuntu — every Docker build failed with "Unable to locate package". Both templates now build H2O's `libh2o-evloop` target from source instead, matching what `brew install h2o` provides on macOS.
- Fix: `daho auth add`'s dependency insertion used `replaceFirst(RegExp(...), r'$0...')`, but Dart's `replaceFirst` doesn't support `$0`/`$1` backreferences — it silently replaced the entire existing `dependencies:` block with the literal text `$0...`, destroying every dependency already in `pubspec.yaml`.
- Fix: `daho create --auth`'s generated `bin/server.dart`/`bin/migrate.dart` imported `'auth.dart'` as a bare relative import, which resolves relative to their own directory (`bin/`), not `lib/` where `auth.dart` is actually written — the scaffolded project never compiled.
- Fix: generated `setupRoutes` built `AuthDatabase`/`JwtService`/`SessionManager` in `main()` and referenced them from the top-level routes builder — broken for the same worker-Isolate reason as the `daho` package's example fix above. Everything is now built fresh inside `setupRoutes`.
- Fix: `daho auth add` never generated `bin/migrate.dart`, but `daho auth setup-db` unconditionally shells out to it — running the documented workflow on a project set up via `auth add` (rather than `create --auth`) always failed.
- Fix: `daho_auth` has `publish_to: none` (not published to pub.dev), so the generated `daho_auth: ^0.1.0` hosted dependency never resolved. `daho create --auth` and `daho auth add` now both accept `--local <path-to-packages/daho>` and emit a path dependency to the sibling `packages/daho_auth` too.
- Fix: generated `lib/auth.dart` used `String.fromEnvironment`, which only reads compile-time `--define` flags — it silently ignored a real `.env` file or shell-exported environment variable, so every secret always fell back to its default. Replaced with a generated `lib/env.dart` that reads real process environment variables, falling back to `.env` if present.
- Fix: generated routes configured Google/GitHub `OAuthConfig` (from `--provider`) but never actually instantiated `GoogleOAuthProvider`/`GitHubOAuthProvider` or passed them to `AuthRoutes` — the OAuth routes were never registered regardless of `--provider`. Providers are now created automatically whenever their client id/secret are set.
- Fix: migration templates were stale (only 4 of the 6 `daho_auth` migrations) — added `005_create_oauth_exchange_codes.sql` and `006_add_role_to_users.sql`.
- `daho doctor`'s H2O install hint no longer points at the nonexistent `libh2o-evloop-dev` package; it now prints the from-source build command.

## 0.1.1

- Add daho auth commands

## 0.1.0

- Initial release.
- `daho create <name>` — scaffold a new Daho server project.
- `daho build` — compile the native H2O wrapper via CMake.
- `daho run` — build if needed, then start the server.
- `daho doctor` — verify toolchain (Dart, CMake, H2O).

