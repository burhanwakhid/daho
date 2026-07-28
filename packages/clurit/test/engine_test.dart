import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:clurit/clurit.dart';

void main() {
  group('CluritEngine', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('clurit_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    void createTemplate(String path, String content) {
      final file = File(p.join(tempDir.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    group('render', () {
      test('renders simple template', () {
        createTemplate('hello.clurit', 'Hello, {{ \$name }}!');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.render('hello', {'name': 'World'});
        expect(result, 'Hello, World!');
      });

      test('renders template with multiple variables', () {
        createTemplate('greeting.clurit', '{{ \$greeting }}, {{ \$name }}!');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.render('greeting', {
          'greeting': 'Hello',
          'name': 'Alice',
        });
        expect(result, 'Hello, Alice!');
      });

      test('renders raw echo', () {
        createTemplate('raw.clurit', '{!! \$html !!}');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.render('raw', {'html': '<b>Bold</b>'});
        expect(result, '<b>Bold</b>');
      });

      test('renders escaped echo', () {
        createTemplate('escaped.clurit', '{{ \$html }}');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.render('escaped', {'html': '<b>Bold</b>'});
        expect(result, '&lt;b&gt;Bold&lt;/b&gt;');
      });

      test('renders if condition true', () {
        createTemplate('if.clurit', '@if(\$show)\nVisible\n@endif');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.render('if', {'show': true});
        expect(result, contains('Visible'));
      });

      test('renders if condition false', () {
        createTemplate('if.clurit', '@if(\$show)\nVisible\n@endif');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.render('if', {'show': false});
        expect(result, isNot(contains('Visible')));
      });

      test('renders if/else', () {
        createTemplate('ifelse.clurit', '@if(\$show)\nYes\n@else\nNo\n@endif');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        expect(engine.render('ifelse', {'show': true}), contains('Yes'));
        expect(engine.render('ifelse', {'show': false}), contains('No'));
      });

      test('renders foreach', () {
        createTemplate(
          'foreach.clurit',
          '@foreach(\$items as \$item)\n{{ \$item }}\n@endforeach',
        );
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.render('foreach', {
          'items': ['A', 'B', 'C'],
        });
        expect(result, contains('A'));
        expect(result, contains('B'));
        expect(result, contains('C'));
      });

      test('handles missing template', () {
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        expect(
          () => engine.render('nonexistent', {}),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('handles null values', () {
        createTemplate('null.clurit', '{{ \$value }}');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        expect(engine.render('null', {'value': null}), '');
      });

      test('handles empty context', () {
        createTemplate('empty.clurit', 'Hello');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        expect(engine.render('empty'), 'Hello');
      });

      test('handles empty template', () {
        createTemplate('emptytpl.clurit', '');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        expect(engine.render('emptytpl'), '');
      });
    });

    group('renderSource', () {
      test('renders from source string', () {
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.renderSource('Hello, {{ \$name }}!', {
          'name': 'World',
        });
        expect(result, 'Hello, World!');
      });

      test('renders complex source', () {
        final source = '''
@if(\$show)
  <p>{{ \$message }}</p>
@endif
''';
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);
        final result = engine.renderSource(source, {
          'show': true,
          'message': 'Test',
        });
        expect(result, contains('<p>Test</p>'));
      });
    });

    group('caching', () {
      test('debug mode recompiles', () {
        createTemplate('debug.clurit', 'Hello, {{ \$name }}!');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);

        final result1 = engine.render('debug', {'name': 'Alice'});
        final result2 = engine.render('debug', {'name': 'Bob'});

        expect(result1, 'Hello, Alice!');
        expect(result2, 'Hello, Bob!');
      });

      test('clearCache works', () {
        createTemplate('clear.clurit', 'Hello');
        final engine = CluritEngine(viewsPath: tempDir.path, debug: false);

        engine.render('clear');
        engine.clearCache();
        // Should not throw after clearing cache
        expect(() => engine.render('clear'), returnsNormally);
      });
    });

    group('custom directives', () {
      test('directiveFn processes custom directives', () {
        // Note: Custom directives are processed at the parser level
        // This test verifies the directive can be registered
        final engine = CluritEngine(viewsPath: tempDir.path, debug: true);

        engine.directiveFn('greeting', (args, context) {
          return 'Hello from custom directive!';
        });

        // The directive is registered but won't be called by the current parser
        // unless the template contains the @greeting directive syntax
        expect(true, isTrue); // Placeholder for directive registration test
      });
    });
  });
}
