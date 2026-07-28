# Clurit Template Engine

Clurit is a Blade-inspired template engine for Dart, designed to work seamlessly with Daho.

## Features

- **Blade Syntax** — `{{ $var }}`, `@if`, `@foreach`, `@extends`
- **Auto-escaping** — `{{ }}` escapes HTML, `{!! !!}` for raw output
- **Template Inheritance** — `@extends`, `@section`, `@yield`
- **Components** — `@component`, `@slot`
- **Control Structures** — `@if`, `@foreach`, `@for`, `@while`
- **Includes** — `@include`, `@includeIf`
- **Caching** — File-based compilation cache

## Installation

```yaml
dependencies:
  daho: ^0.1.0
  clurit_daho: ^0.1.0
```

## Quick Start

```dart
import 'package:daho/daho.dart';
import 'package:clurit_daho/clurit_daho.dart';

void setupRoutes(Daho app) {
  // Configure template engine
  app.configureClurit(viewsPath: 'views', debug: true);

  app.get('/', (req, res) {
    return res.view('welcome', {
      'title': 'Hello Clurit!',
      'users': ['Alice', 'Bob', 'Charlie'],
    });
  });
}
```

## Template Syntax

### Echoing Variables

```blade
{{-- Escaped output (auto HTML-escaped) --}}
<h1>{{ $title }}</h1>

{{-- Raw output (no escaping) --}}
<div>{!! $htmlContent !!}</div>

{{-- With expressions --}}
<p>{{ $user?.name ?? 'Guest' }}</p>
<p>{{ $items.length > 0 ? '$items.length items' : 'No items' }}</p>
```

### Control Structures

```blade
{{-- If/ElseIf/Else --}}
@if($user != null)
    <p>Welcome, {{ $user['name'] }}!</p>
@elseif($guest)
    <p>Welcome, Guest!</p>
@else
    <p>Please log in.</p>
@endif

{{-- Unless --}}
@unless($isAdmin)
    <p>Admin only</p>
@endunless

{{-- Foreach --}}
@foreach($items as $item)
    <div class="{{ $loop->first ? 'first' : '' }}">
        {{ $loop->iteration }}. {{ $item['name'] }}
    </div>
@endforeach

{{-- For --}}
@for($i = 0; $i < $count; $i++)
    <span>{{ $i }}</span>
@endfor
```

### Template Inheritance

**Layout** (`views/layouts/main.clurit`):
```blade
<!DOCTYPE html>
<html>
<head>
    <title>{{ $title }} - My App</title>
    @yield('styles')
</head>
<body>
    <nav>@include('partials.nav')</nav>
    <main>@yield('content')</main>
    <footer>@yield('footer')</footer>
    @stack('scripts')
</body>
</html>
```

**Page** (`views/pages/home.clurit`):
```blade
@extends('layouts.main')

@section('content')
    <h1>Welcome, {{ $name }}!</h1>
    @foreach($items as $item)
        <p>{{ $item }}</p>
    @endforeach
@endsection

@push('scripts')
    <script src="/js/home.js"></script>
@endpush
```

### Includes

```blade
{{-- Include a partial --}}
@include('partials.header')

{{-- Include with data --}}
@include('partials.card', {'title': 'Special Card'})

{{-- Include if exists --}}
@includeIf('partials.optional')
```

### Components & Slots

**Component** (`views/components/alert.clurit`):
```blade
<div class="alert alert-{{ $type ?? 'info' }}">
    <h4>{{ $title }}</h4>
    <div>{{ $slot }}</div>
    @if($footer != null)
        <div class="alert-footer">{{ $footer }}</div>
    @endif
</div>
```

**Usage**:
```blade
@component('components.alert', {'type': 'success', 'title': 'Done!'})
    <p>Operation completed.</p>
    
    @slot('footer')
        <button>OK</button>
    @endslot
@endcomponent
```

### Stacks

```blade
{{-- In child template --}}
@push('scripts')
    <script src="/js/page.js"></script>
@endpush

{{-- In layout --}}
<head>@stack('styles')</head>
<body>@stack('scripts')</body>
```

### Comments

```blade
{{-- This comment won't appear in HTML --}}
```

### Loop Variable

Inside `@foreach`, `$loop` provides:

| Property | Description |
|----------|-------------|
| `$loop->index` | 0-based index |
| `$loop->iteration` | 1-based iteration |
| `$loop->count` | Total items |
| `$loop->first` | Is first |
| `$loop->last` | Is last |
| `$loop->even` | Is even |
| `$loop->odd` | Is odd |

## With Daho

```dart
import 'package:daho/daho.dart';
import 'package:clurit_daho/clurit_daho.dart';

void setupRoutes(Daho app) {
  app.configureClurit(viewsPath: 'views', debug: true);

  app.get('/', (req, res) {
    return res.view('pages/home', {
      'title': 'Home',
      'name': 'Alice',
      'items': ['Dart', 'Flutter', 'Clurit'],
    });
  });

  app.get('/users/:id', (req, res) {
    return res.view('pages/user', {
      'userId': req.params['id'],
    });
  });
}
```

## Standalone Usage

```dart
import 'package:clurit/clurit.dart';

void main() {
  final engine = CluritEngine(
    viewsPath: 'views',
    cachePath: '.clurit_cache',
    debug: false,
  );

  final html = engine.render('welcome', {
    'title': 'Hello!',
    'users': ['Alice', 'Bob'],
  });

  print(html);
}
```

## Custom Directives

```dart
engine.directiveFn('datetime', (args, context) {
  final format = args.isNotEmpty ? args[0] : 'yyyy-MM-dd';
  return DateFormat(format).format(DateTime.now());
});

// Usage in template:
// @datetime('yyyy-MM-dd HH:mm')
```
