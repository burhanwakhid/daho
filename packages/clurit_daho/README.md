# clurit_daho

Daho HTTP framework integration for the [Clurit](https://pub.dev/packages/clurit) template engine.

## Features

- `app.configureClurit(viewsPath: 'views')` — Configure template engine
- `res.view('template', {'key': 'value'})` — Render template as HTML response

## Quick Start

```dart
import 'package:daho/daho.dart';
import 'package:clurit_daho/clurit_daho.dart';

void setupRoutes(Daho app) {
  app.configureClurit(viewsPath: 'views', debug: true);

  app.get('/', (req, res) {
    return res.view('welcome', {
      'title': 'Hello Clurit!',
      'users': ['Alice', 'Bob'],
    });
  });
}
```

## Template Example

Create `views/welcome.clurit`:

```blade
<!DOCTYPE html>
<html>
<head><title>{{ $title }}</title></head>
<body>
    <h1>{{ $title }}</h1>
    <ul>
        @foreach($users as $user)
            <li>{{ $user }}</li>
        @endforeach
    </ul>
</body>
</html>
```

## License

MIT
