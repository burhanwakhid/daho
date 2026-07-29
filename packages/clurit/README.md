# Clurit

A Blade-inspired template engine for Dart, with Svelte-style compile-time-reactive interactive components.

## Features

- **Blade Syntax** — `{{ $var }}`, `@if`, `@foreach`, `@extends`
- **Full Expressions** — Method calls, operators, ternary, null-aware
- **Auto-escaping** — `{{ }}` escapes HTML, `{!! !!}` for raw
- **Template Inheritance** — `@extends`, `@section`, `@yield`
- **Components** — `@component`, `@slot`
- **Caching** — File-based compilation cache
- **Interactive Components** — Compile-time-reactive `@code` blocks (`$state`/`$derived`/`$effect`/`$props`), compiled by a `build_runner` builder into a shared server + client component — no virtual DOM, no runtime expression evaluation, no full-page re-renders.
- **Client-Side Routing** — Built-in SPA router that preserves SSR state

## Quick Start

```dart
import 'package:clurit/clurit.dart';

void main() {
  final engine = CluritEngine(viewsPath: 'views');

  final html = engine.render('welcome', {
    'title': 'Hello!',
    'users': ['Alice', 'Bob'],
  });

  print(html);
}
```

## Template Syntax

```blade
{{-- Comment --}}
<h1>{{ $title }}</h1>

@if($users.isNotEmpty)
    @foreach($users as $user)
        <p>{{ $user }}</p>
    @endforeach
@else
    <p>No users.</p>
@endif

@include('partials.footer')
```

## With Daho

```dart
import 'package:daho/daho.dart';
import 'package:clurit_daho/clurit_daho.dart';

void setupRoutes(Daho app) {
  app.configureClurit(viewsPath: 'views');

  app.get('/', (req, res) {
    return res.view('home', {'title': 'Home'});
  });
}
```

## Interactive Components

Clurit compiles `@code { }` blocks into fully reactive components at build time — one parse of your `.clurit` file produces **both** the server's `renderInitial()`/`initialStateJson()` **and** the client's `hydrate()`/DOM-update code, so they can never drift out of sync. There is no virtual DOM: every reactive binding is compiled into a targeted update closure that knows exactly which DOM node (or anchor-comment range) to touch.

### 1. Author reactive state with runes

Reactivity is explicit, not inferred — mirroring Svelte 5's runes. A plain field with no rune call is just an inert, non-reactive value.

```blade
@code {
    var count = $state(0);
    final doubled = $derived(count * 2);

    void increment() {
        count = count + 1;
    }
}

<div>
    <p>Count: {{ $count }} (doubled: {{ $doubled }})</p>
    <button cl-click="increment">Increment</button>

    @if($count > 10)
        <p>Goal reached!</p>
    @endif
</div>
```

- **`$state(initial)`** — a reactive field: `var count = $state(0);`
- **`$derived(expr)`** / **`$derived.by(() { ...; return v; })`** — a computed value recomputed from other fields: `final doubled = $derived(count * 2);`
- **`$effect(() { ... })`** — a side effect that reruns after hydration and after any reactive value it reads changes. Declare it inside `onInit()`: `void onInit() { $effect(() { print(count); }); }`
- **`$props<T>()`** — a value sourced from the component's initial render data, exposed as a required constructor parameter: `final title = $props<String>();`

These are compile-time markers only — the generator recognizes their call shape via `package:analyzer` and rewrites them away; none of them exist as real functions at runtime.

### 2. Generate the component

```bash
dart run build_runner build
```

This produces two files next to your template:
- **`counter.clurit.dart`** — the `CluritComponent` subclass: typed reactive fields, computed getters, event handler methods, `renderInitial()`, `initialStateJson()`. No `package:web` import, so a server process can depend on it directly.
- **`counter.clurit.client.dart`** — a subclass adding `hydrate(web.Element root)` and the per-binding DOM update closures. Only ever imported by a client (web) entrypoint.

### 3. Render it server-side

Call the generated component directly from your route handler — no Blade engine involvement for a `@code`-bearing template:

```dart
import 'views/counter.clurit.dart';

final counter = CounterComponent(count: 5);
final html = counter.renderInitial(); // include this in your page, with a
                                       // <script id="clurit-state" type="application/json">
                                       // tag filled from counter.initialStateJson()
```

With `clurit_daho`, `res.view(name, data: {...})` does this for you — see [Daho Integration](#daho-integration) below for how backend data reaches the component via `$props`.

### 4. Hydrate it client-side

```dart
import 'package:clurit/clurit_client.dart';
import 'views/counter.clurit.client.dart';

void main() {
  final root = web.document.querySelector('#app')!;
  final state = readInitialState();
  final component = CounterComponentClient(count: state['count'] as int?);
  component.hydrate(root);
}
```

No action-map registration, no string-keyed dispatch — the generated component wires its own `cl-click` handlers and per-field DOM updaters during `hydrate()`.

### Two-way binding with `cl-model`

`cl-model="fieldName"` on an `<input>`/`<textarea>`/`<select>` binds it two ways to a `$state` field — Svelte's `bind:value` equivalent. Write the field's current value into the attribute yourself with a normal echo (this keeps SSR correct without any build-time HTML rewriting):

```blade
@code {
    var name = $state('');
}

<input cl-model="name" value="{{ $name }}">
<p>Hello, {{ $name }}!</p>
```

Typing into the input updates `name` (and anything else depending on it, like the `<p>` above); changing `name` from anywhere else (another handler, an effect) syncs back into the input's value. `int`/`double`-typed fields get the input's string value parsed automatically; other types are assigned as-is.

## How reactivity is compiled

- Every `{{ }}` echo and `@if`/`@foreach` block is bracketed with a stable anchor comment (`<!--cl:N-->`, `<!--cl-if:N-->`, `<!--cl-for:N-->`) baked into `renderInitial()`'s output — **except** an echo inside an open HTML attribute value (e.g. `value="{{ $name }}"`), where an anchor comment would just be broken literal text; those render their value inline, with no anchor, and stay live only via `cl-model`.
- `hydrate()` walks the DOM **exactly once**, resolving each anchor into a captured `AnchorRange` (and each `cl-click`/`cl-model` element into a captured `Element`) — never re-queried afterward.
- A reactive field's setter calls `markDirty('fieldName')`, which schedules (once per microtask) exactly the update closures registered against that field — not a full-tree re-render or diff.
- `@if`/`@foreach` content is rebuilt via the same `renderInitial()`-style rendering, parsed into real DOM nodes, and swapped into the anchor range. List rebuilds are currently clear-and-rebuild, not yet keyed-diffed (see Roadmap).

## Compiling to WASM

Client bundles compile equally well with `dart compile js` or `dart compile wasm` — nothing in the generated code or runtime is JS-specific, since `package:web`'s bindings target both. Swap:

```bash
dart compile wasm web/main.dart -o web/main.wasm
```

and bootstrap it per the standard dart2wasm loader pattern (a `main.mjs`/`main.support.js` pair is emitted alongside `main.wasm`):

```html
<script type="module">
  import { compileStreaming } from './main.mjs';
  const app = await compileStreaming(fetch('./main.wasm'));
  const instantiated = await app.instantiate({});
  instantiated.invokeMain();
</script>
```

## Daho Integration

`res.view(name, data: {...})` works for a `@code`-bearing template exactly the same way it does for a plain Blade one, without a hand-written factory per component — pass the generated `cluritComponents` registry (see [Generated component registry](#generated-component-registry-clurit_componentsgdart) below) to `configureClurit` once, and every route handler just calls `res.view(name, data: {...})`:

```dart
import 'package:daho/daho.dart';
import 'package:clurit_daho/clurit_daho.dart';
import 'clurit_components.g.dart'; // generated — see below

void setupRoutes(Daho app) {
  app.configureClurit(
    viewsPath: 'views',
    components: cluritComponents,
    // Optional: Provide global state from request (e.g., auth)
    stateProvider: (req) => {
      'isLoggedIn': req.session.has('user'),
    },
  );

  app.get('/', (req, res) {
    return res.view('home', data: {'title': 'Home'});
  });

  // `data` becomes each $props field's value on the other end (see
  // `views/counter.clurit`'s @code block) — the route handler doesn't
  // need to know the component's constructor shape, only its field names.
  app.get('/counter', (req, res) {
    return res.view('counter', data: {'start': 5});
  });
}
```

If you'd rather wire a component's factory by hand (e.g. it's not backed by a `.clurit` file, or needs logic beyond a field-by-field data map), `app.registerComponent(name, factory)` still works standalone. If you already have a component instance in hand, `res.viewComponent(component)` renders it directly without going through the name-based registry at all.

### Generated component registry (`clurit_components.g.dart`)

The same `clurit_routes.yaml` trigger that generates the client bootstrap (below) also generates a server-side factory registry — one `Map` entry per `@code`-bearing page, extracting each `$state`/`$props` field out of the `data` map with the right cast, exactly mirroring what you'd otherwise hand-write:

```dart
// GENERATED — do not edit; regenerate via build_runner
final Map<String, CluritComponent Function(Map<String, dynamic>)> cluritComponents = {
  'index': (data) => IndexComponent(
    counter: data['counter'] as int?,
    message: data['message'] as String, // required $props field — non-nullable
  ),
  'greeter': (data) => GreeterComponent(),
};
```

Note the constructor-argument nullability follows the field kind: `$state` fields are optional (the component has its own default), so extraction is nullable (`as int?`); `$props` fields are `required` and non-nullable on the component, so extraction casts non-null (`as String`) — passing `data` without a required prop throws a clear `TypeError` rather than silently passing `null`.

### SPA Routing & Multi-Page Code Splitting — generated

For a multi-page app, the client bootstrap (deferred-importing every page's component, dispatching on `location.pathname`, wiring `CluritRouter`) is generated too — drop an empty trigger file at the app root, sibling to `main.dart`, and run `dart run build_runner build`:

```
your_app/
├── main.dart
├── clurit_routes.yaml       # empty; just tells the builder where to generate
├── clurit_components.g.dart # generated (see "Daho Integration" above)
├── views/
│   ├── index.clurit         # -> route "/"  ("index"/"home" both mean root)
│   └── greeter.clurit       # -> route "/greeter"
└── web/
    └── main.g.dart           # generated
```

This produces `web/main.g.dart`, importing each page's `*.clurit.client.dart` as a **deferred library** so `dart compile js`/`dart2js` splits it into its own on-demand chunk (`main.dart.js_N.part.js`) — the same mechanism behind Jaspr's `.part.js` code splitting. A page's component code is only ever fetched the first time that page is visited, not bundled into every page's initial payload. It also extracts each page's `$state`/`$props` fields back out of `readInitialState()` with the right cast — the exact boilerplate you'd otherwise hand-write:

```dart
// GENERATED — do not edit; regenerate via build_runner
import '../views/index.clurit.client.dart' deferred as _page0;
import '../views/greeter.clurit.client.dart' deferred as _page1;

Future<void> hydrateCurrentPage(web.Element root) async {
  final state = readInitialState();
  switch (web.window.location.pathname) {
    case '/greeter':
      await _page1.loadLibrary();
      _page1.GreeterComponentClient(greetIndex: state['greetIndex'] as int?).hydrate(root);
      break;
    default:
      await _page0.loadLibrary();
      _page0.IndexComponentClient(counter: state['counter'] as int?, ...).hydrate(root);
      break;
  }
}

void main() {
  final root = web.document.querySelector('#app');
  if (root == null) return;
  hydrateCurrentPage(root);
  CluritRouter(onHydrate: hydrateCurrentPage, contentSelector: '#app').init();
}
```

Compile `web/main.g.dart` itself (not a hand-written `main.dart`) — `dart compile js web/main.g.dart -o web/main.dart.js`. Regenerate whenever a page is added/removed or its `$state`/`$props` fields change. See `example/with_daho` for a working two-page version, verified to fetch each page's chunk lazily on first navigation (dart2js also factors out code shared between deferred libraries into its own chunk, loaded once regardless of which page is visited first).

If you need routing logic this file-based convention can't express (e.g. non-static paths, custom matching), write `hydrateCurrentPage`/`main()` by hand instead — `CluritRouter` and `readInitialState()` are the same public API either way, generation is just a convenience for the common case.

## Roadmap

- **Keyed list diffing**: `@foreach` list rebuilds are currently clear-and-rebuild; upgrade to move/reuse/remove via `cl-key`.
- **`$bindable()`** for parent↔child two-way binding, once nested/composable components exist (today, one interactive component per page).
- **`$loop`** (index/first/last/etc.) inside a reactive `@foreach` isn't supported yet — only in the plain, non-reactive Blade `@foreach`.

See [ROADMAP.md](ROADMAP.md) for the larger Blazor-parity roadmap: a unified `HttpClient` (server + client), typed JSON models, `inject<T>()` dependency injection, and reusable interactive components (`<Card>`, `<Loading />`).

## License

MIT
