## 0.1.0+1

- Redesigned `@code` interactive components around Svelte-style compile-time
  reactivity (`$state`, `$derived`/`$derived.by`, `$effect`, `$props`), replacing
  the previous broken Blazor-style SSR+WASM hydration approach.
- New `build_runner` builder (`CluritGenerator`) that parses `@code` with
  `package:analyzer` and emits one `<name>.clurit.dart` (server) +
  `<name>.clurit.client.dart` (client) pair per template from a single source
  of truth — no more server/client drift.
- Compile-time anchor-comment bindings (`<!--cl:N-->`, `<!--cl-if:N-->`,
  `<!--cl-for:N-->`) with a single-DOM-walk hydration pass and targeted,
  dependency-driven DOM updates — no virtual DOM, no runtime expression
  evaluation, no full-page re-renders.
- `cl-click` event binding and `cl-model` two-way binding.
- `@extends`/`@section`/`@yield`/`@stack`/`@include` composition now resolves
  correctly for `@code`-bearing templates (previously silently dropped).
- `CluritRoutesBuilder`: generates the client bootstrap (`web/main.g.dart`,
  file-based routing, deferred-import code splitting per page) and the
  server-side component-factory registry (`clurit_components.g.dart`) from a
  single trigger file, removing hand-written `app.registerComponent(...)`
  boilerplate.
- Fixed `build.yaml`'s `auto_apply` so the generators actually apply to real
  downstream consumer packages, not just this repo's own examples.
- Fixed several generated-code correctness bugs: double-nullable constructor
  parameters, unconditional `await` on synchronous `onInit()`, and
  browser-only (`package:web`) code leaking into server-safe output.
- Added `ROADMAP.md` tracking remaining Blazor-parity gaps (typed HTTP
  client, JSON models, dependency injection, reusable components, local
  storage/cookies, route parameters, `@ref`, form validation).

## 0.1.0

- Initial release.
- Blade-inspired template syntax ({{ }}, @if, @foreach, @extends).
- Full Dart expression evaluator.
- Auto HTML escaping by default, {!! !!} for raw output.
- Template inheritance (@extends, @section, @yield).
- Includes (@include, @includeIf).
- Components with slots (@component, @slot).
- Control structures (@if, @elseif, @else, @foreach, @for, @while).
- Stacks (@push, @stack).
- Comments ({{-- --}}).
- Custom directives.
- In-memory and file-based template caching.
