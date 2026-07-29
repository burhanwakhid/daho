# Clurit Roadmap: Closing the Gap with Blazor

Clurit already covers Blazor's core `@code`-in-template model (`$state`/`$derived`/`$effect`/`$props`,
compile-time reactivity, file-based routing). This roadmap tracks the remaining pieces that make
Blazor apps feel complete — chiefly **typed data fetching** (`HttpClient` + models + DI) and
**reusable interactive components** (`<Card>`, `<Loading />`) — using `views/posts.clurit`
(`example/with_daho/views/posts.clurit`) as the running example of what's still awkward today.

Status legend: ✅ done · 🚧 partial / workaround exists · ❌ not started

## 1. Typed models from plain Dart classes

**Status: 🚧 partial.** Nothing stops you from writing a normal Dart class and using it as a
`$props<Post>()` value or inside `$state<List<Post>>([])` today — `CodeAnalyzer` only cares about
the rune call shape, not the type argument. What's missing is JSON (de)serialization: today
`posts.clurit`'s `onInit()` hand-decodes `List<Map<String, dynamic>>` and templates index into the
map (`$post['title']`) instead of a typed `Post.title`.

- ❌ A `@JsonModel` (or similar) annotation + generator that turns
  ```dart
  @JsonModel()
  class Post {
    final int userId;
    final int id;
    final String title;
    final String body;
  }
  ```
  into `Post.fromJson(Map<String, dynamic>)` / `toJson()` — likely by shelling out to (or
  reusing generator plumbing similar to) `json_serializable` rather than reinventing it.
- ❌ Teach `code_analyzer.dart` to recognize `$state<List<Post>>(...)`/`$props<Post>()` type
  arguments that resolve to a `@JsonModel` class, so generated constructor/state code can call
  `.fromJson`/`.toJson` automatically where relevant (e.g. serializing `initialStateJson()`).

## 2. `HttpClient` abstraction (server + client, one API)

**Status: ❌ not started.** This is the biggest real gap. `posts.clurit` today calls
`web.window.fetch(...)` directly — browser-only (`dart:js_interop`), which is exactly why
`code_analyzer.dart` had to grow `_usesClientOnlyApi` detection to keep it out of the server
build. There is no way to fetch the same data during SSR (for a fast first paint with no loading
spinner) and again on the client without writing two implementations.

- ❌ Define one `HttpClient` interface in `clurit` (request/response, JSON helpers) with two
  backends: `dart:io HttpClient` (or `package:http`) server-side, `package:web` `fetch` client-side
  — conditional-imported the way `package:http` itself does it.
- ❌ Decide the authoring API. Two shapes to weigh:
  - `final api = inject<HttpClient>();` (Blazor-style DI, see §3) — needs a service container.
  - A plain top-level/ambient `http` available inside `@code` without DI, simpler but less
    testable/mockable.
- ❌ Generated code must keep the http-call site compilable on **both** targets (today's
  `clientOnlyMemberSources` split assumes browser-only code is client-exclusive; a shared
  `HttpClient` call needs to be emitted into `emitServer()` too).
- ❌ Update `posts.clurit` to use the new API once it exists, dropping the hand-rolled
  `.fetch(...).toJS/.toDart` dance and `jsonDecode` boilerplate.

## 3. Dependency injection (`inject<T>()`)

**Status: ❌ not started.** Blazor's `@inject HttpClient Http` / constructor-injected services
(`PostService`) let a component depend on a service without knowing how it's constructed. Clurit's
only current analog is `$props<T>()`, which is per-render request data, not a shared singleton
service.

- ❌ A registration API (likely on the `Daho`/`clurit_daho` side, mirroring
  `app.configureClurit(components: ...)`): `app.provide<PostService>(() => PostService(httpClient))`.
- ❌ An `inject<T>()` rune recognized by `code_analyzer.dart` the same way `$props<T>()` is —
  compiles to a constructor parameter resolved from the service container at construction time
  (server) and from a client-side registry populated at bootstrap (client), rather than from
  per-request `data`.
- Depends on §2 existing first, since the motivating use case is injecting an `HttpClient` or a
  hand-written service that wraps one (`PostService`, matching the "enterprise" Blazor pattern in
  the request).

## 4. Reusable interactive components (`<Card>`, `<Loading />`)

**Status: ❌ not started, and the largest architectural change here.** Today exactly one
`@code`-bearing component exists per page (noted already in README's roadmap as the blocker for
`$bindable()`). There's no way to extract `@if($loading) { <p>Loading...</p> }` into a `<Loading />`
tag reused across `posts.clurit` and future pages — every page's markup is fully inline.

- ❌ Custom-tag resolution at build time: teach the template resolver (`template_resolver.dart`)
  to recognize `<ComponentName ...>` tags (PascalCase, distinguishing them from real HTML elements)
  and splice in another `.clurit` file's template, similar to how `@include` already splices
  Blade partials — but for components that may themselves carry `@code`/state.
  - Note: static, non-reactive composition already exists via `@component`/`@slot`
    (`packages/clurit/lib/src/nodes/`) — check whether that mechanism can be extended for
    reactive components instead of building a fully separate path.
- ❌ Props passing: `<Card title="{{ $post.title }}">` → compiles to a nested component
  constructor call with those values, which is a much bigger id/anchor bookkeeping problem than
  today's single flat `renderInitial()`/`hydrate()` per page (nested components each need their
  own capture/update scope within the parent's DOM walk).
- ❌ `$bindable()` (two-way prop binding into a child, e.g. a `<Input />` wrapping `cl-model`) —
  already flagged in README as blocked on this.

## 5. Lifecycle naming parity, and a real bug: `onDestroy()` is dead code

**Status: 🚧 partial — `onInit()` is done; `onDestroy()` is a bug, not a roadmap item.**
`onInit()` is correctly emitted and invoked from `hydrate()` (async-aware `await`). `onDestroy()`
is emitted by `code_emitter.dart` but **no call site anywhere invokes it** — today it is dead code,
so any cleanup a developer writes there (clearing a timer, closing a stream, unsubscribing from an
effect) silently never runs. This isn't a "nice to have" like the naming question (Blazor's
`OnInitializedAsync` vs. Clurit's `onInit`, purely cosmetic) — it needs a real caller. The natural
hook point is `CluritRouter._loadPage` (`lib/src/client/router.dart`): before swapping `<main>`'s
innerHTML for the next page, call the outgoing page's `onDestroy()` if it declared one.
- ❌ Wire `onDestroy()` into SPA navigation teardown.
- ❌ (Low priority) Consider an `onMount` alias for `onInit` if it reads more naturally to
  Flutter-background developers — purely cosmetic, not blocking anything.

## 6. Local storage & cookies

**Status: ❌ not started — confirmed absent.** Grepping both `clurit` and `clurit_daho` for
`localStorage`, `sessionStorage`, and `document.cookie`/`Cookie` turns up nothing. Blazor's
`Blazored.LocalStorage`/`ProtectedBrowserStorage` and cookie access from a component are common
enough (session tokens, "remember me" prefs, client-side caches) that this is worth a first-class
primitive rather than telling every developer to drop into raw `dart:js_interop` `web.window.localStorage`
calls inside their `@code` block (the same ergonomic gap `$state`'s runes already solve for reactive
fields).
- ❌ A small `clurit_client` runtime wrapper: `LocalStorage.getItem/setItem/removeItem`,
  equivalent for `sessionStorage` — thin `package:web` wrappers, client-only (same
  `_usesClientOnlyApi` classification `code_analyzer.dart` already does for `web.` calls, so these
  stay out of `emitServer()` automatically once the wrapper's own calls are recognized as
  client-only).
- ❌ Cookie read/write: client-side via `web.document.cookie`, **and** server-side via Daho's
  request/response objects (`clurit_daho`) for reading a cookie during SSR (e.g. an auth token
  that should already influence the first-paint HTML, not just a post-hydration client effect).
- Both are async-observable/read-once values, not reactive by nature — decide whether reading one
  into a `$state` field on `onInit()` (today's manual pattern) is good enough, or whether a
  dedicated rune (`$storage('key')`?) is worth adding. Lean toward "no new rune" unless a second
  concrete use case shows up; `$state` + `onInit()` already covers it without new syntax.

## 7. Route parameters, query strings, and programmatic navigation

**Status: ❌ not started.** Confirmed: `CluritRoutesBuilder` only derives *static* file-based
routes (`index`/`home` → `/`, else `/<filename>` — `clurit_routes_builder.dart`); there is no
`/posts/{id}`-style parameter capture, and no query-string parsing anywhere in the codebase.
`CluritRouter.navigateTo(String path)` (`lib/src/client/router.dart`) exists but isn't reachable
from inside a `@code` block's own methods — it's wired only to intercepted anchor clicks and
`popstate`, so there's no `NavigationManager.NavigateTo()` equivalent a component can call after,
say, a form submit succeeds.
- ❌ Dynamic segments in the file-based convention, e.g. `views/posts/[id].clurit` → `/posts/:id`,
  with the captured `id` exposed as a `$props<String>()`-like value (needs both server-side
  extraction from the request path in `clurit_daho` and client-side extraction in the generated
  router for SPA navigation).
- ❌ Query-string access (`?page=2`) — likely simplest as a plain `$props`-style value sourced from
  `Uri.queryParameters`, mirroring how request `data` already becomes `$props` fields today.
- ❌ Expose the router to component code: something like a `nav` rune/injected value so
  `onSubmit()` can call `nav.navigateTo('/posts/42')` instead of only reacting to clicks.

## 8. `@ref` / element references

**Status: ❌ not started.** `captureClNodes` (`lib/src/client/runtime.dart`) only captures
`cl-click`/`cl-model` elements and anchor-comment ranges into `CapturedNodes` — there's no
`cl-ref="name"` attribute scanned, and no generic named-element map on `CapturedNodes`. Blazor's
`@ref` (getting a raw `ElementReference` for, say, calling `.focus()` on an input, or measuring a
canvas) has no equivalent today; the only way to touch the DOM directly from `@code` is
`web.document.querySelector(...)`, bypassing the captured-node model entirely (and only usable in
client-only code, per `_usesClientOnlyApi`).
- ❌ A `cl-ref="fieldName"` attribute, captured during the existing single DOM walk in
  `captureClNodes` and exposed as a typed `web.Element` field the generated component can read
  after hydration (e.g. inside `onInit()`, guaranteed to run after `_nodes` is populated).

## 9. Form submission & validation

**Status: ❌ not started.** Only `cl-model` two-way binding exists (`bindModels`/`setModelValue`,
`runtime.dart`) — no `<form>` submit interception, no validation-attribute convention, no
error-message binding. Blazor's `EditForm`/`DataAnnotationsValidator`/`ValidationMessage` has no
analog. Lower priority than §2/§6/§7 — most forms can already be built with `cl-model` +
a plain button `cl-click` handler that validates in Dart and sets an `errorMessage` `$state` field
(exactly the pattern `posts.clurit`'s retry-on-error UI already uses) — but a dedicated
`cl-submit`/inline validation-message helper would remove boilerplate once real forms show up.

## 10. `shouldUpdate`/after-render hooks

**Status: ❌ not started, likely low priority.** Every `$state` field's setter unconditionally
calls `markDirty`/`invalidate` (skipping only exact-equality no-ops, per the generated setter shape
in the README). There's no per-effect `shouldUpdate` gate or an `onAfterRender`-style hook
(Blazor's `OnAfterRenderAsync`, used for things like initializing a JS chart library against a
newly-rendered DOM node). Given `@ref` (§8) doesn't exist yet either, this has no concrete blocking
use case today — revisit once §8 lands and something actually needs "run after this ref's element
exists in the DOM."

## Suggested sequencing

1. **§2 HttpClient abstraction** — the concrete pain point in `posts.clurit` today; unblocks
   SSR-time data fetching (no loading spinner on first paint for data available at request time).
2. **§1 Typed models** — layered on top of §2 (fetch a `List<Post>` instead of
   `List<Map<String, dynamic>>`).
3. **§5 fix `onDestroy()` dead code** — small, self-contained bug fix, worth doing early
   regardless of the bigger features since it's silently broken today.
4. **§6 Local storage & cookies** — small, self-contained, no dependency on anything else here;
   common enough (auth tokens, prefs) to be worth pulling forward.
5. **§7 Route params/query strings/programmatic navigation** — independent of the data-fetching
   work; needed as soon as any example wants `/posts/{id}`-style detail pages.
6. **§3 DI (`inject<T>()`)** — once there's an actual service worth injecting (`HttpClient` itself,
   or a hand-written `PostService`).
7. **§8 `@ref`** — needed by, and should land before, §10.
8. **§4 Reusable components** and **§9 forms/validation** last — biggest architectural lift
   (nested id/anchor bookkeeping) and lowest urgency (no concrete form use case yet), respectively.
9. **§10 after-render hooks** — revisit once §8 gives it a concrete use case.
