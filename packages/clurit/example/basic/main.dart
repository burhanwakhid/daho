import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:clurit/clurit.dart';

void main() {
  // Resolve views path relative to this script's location
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final viewsPath = p.join(scriptDir, 'views');

  final engine = CluritEngine(viewsPath: viewsPath, debug: true);

  // Render the home page template
  final html = engine.render('pages/home', {
    'title': 'Clurit Demo',
    'name': 'Alice',
    'items': ['Dart', 'Flutter', 'Clurit'],
  });

  print(html);
}
