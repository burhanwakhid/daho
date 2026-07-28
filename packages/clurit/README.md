# Clurit

A Blade-inspired template engine for Dart.

## Features

- **Blade Syntax** — `{{ $var }}`, `@if`, `@foreach`, `@extends`
- **Full Expressions** — Method calls, operators, ternary, null-aware
- **Auto-escaping** — `{{ }}` escapes HTML, `{!! !!}` for raw
- **Template Inheritance** — `@extends`, `@section`, `@yield`
- **Components** — `@component`, `@slot`
- **Caching** — File-based compilation cache

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

## License

MIT
