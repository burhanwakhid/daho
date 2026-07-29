import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:clurit/clurit.dart';
import 'views/pages/counter.clurit.dart';

void main() {
  // Resolve views path relative to this script's location
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final viewsPath = p.join(scriptDir, 'views');

  final engine = CluritEngine(viewsPath: viewsPath, debug: true);

  print('--- Rendering Home Page (plain Blade template) ---');
  final homeHtml = engine.render('pages/home', {
    'title': 'Clurit Demo',
    'name': 'Alice',
    'items': ['Dart', 'Flutter', 'Clurit'],
  });
  print(homeHtml);

  print('\n--- Rendering Counter Page (compiled @code component) ---');
  // A @code-bearing template's generated component is constructed and
  // rendered directly, bypassing the Blade engine.
  final counter = CounterComponent(count: 5);
  final html =
      '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Counter Demo</title></head>
<body>
<div id="app">${counter.renderInitial()}</div>
<script id="clurit-state" type="application/json">${jsonEncode(counter.initialStateJson())}</script>
<script src="main.dart.js" defer></script>
</body>
</html>
''';
  print(html);
}
