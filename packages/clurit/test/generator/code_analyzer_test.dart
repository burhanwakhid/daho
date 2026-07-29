import 'package:clurit/src/generator/code_analyzer.dart';
import 'package:test/test.dart';

void main() {
  group('CodeAnalyzer', () {
    test('classifies a \$state field with its literal type inferred', () {
      final model = CodeAnalyzer.analyze('var count = \$state(0);');
      expect(model.stateFields, hasLength(1));
      expect(model.stateFields.single.name, 'count');
      expect(model.stateFields.single.type, 'int');
      expect(model.stateFields.single.initializerSource, '0');
    });

    test('respects an explicit declared type over inference', () {
      final model = CodeAnalyzer.analyze('double count = \$state(0);');
      expect(model.stateFields.single.type, 'double');
    });

    test('reads the type argument off \$state<T>(...) when no declared type', () {
      final model = CodeAnalyzer.analyze('var items = \$state<List<String>>([]);');
      expect(model.stateFields.single.type, 'List<String>');
    });

    test('classifies a single-expression \$derived field', () {
      final model = CodeAnalyzer.analyze(
        'var count = \$state(0);\nfinal doubled = \$derived(count * 2);',
      );
      expect(model.derivedFields, hasLength(1));
      expect(model.derivedFields.single.name, 'doubled');
      expect(model.derivedFields.single.exprSource, 'count * 2');
      expect(model.derivedFields.single.blockBodySource, isNull);
    });

    test('classifies a block-bodied \$derived.by field', () {
      final model = CodeAnalyzer.analyze(r'''
final greeting = $derived.by(() {
  final name = 'World';
  return 'Hello, $name!';
});
''');
      expect(model.derivedFields, hasLength(1));
      expect(model.derivedFields.single.exprSource, isNull);
      expect(model.derivedFields.single.blockBodySource, contains("return 'Hello"));
    });

    test('classifies a \$props field with a generic type argument', () {
      final model = CodeAnalyzer.analyze('final title = \$props<String>();');
      expect(model.propFields, hasLength(1));
      expect(model.propFields.single.name, 'title');
      expect(model.propFields.single.type, 'String');
    });

    test('classifies a \$props field with an explicit override name', () {
      final model = CodeAnalyzer.analyze(
        "final pageTitle = \$props<String>('title');",
      );
      expect(model.propFields.single.overrideName, 'title');
    });

    test('extracts an \$effect call from onInit and strips it from the method', () {
      final model = CodeAnalyzer.analyze(r'''
var count = $state(0);

void onInit() {
  print('mounted');
  $effect(() {
    print('count is $count');
  });
}
''');
      expect(model.effects, hasLength(1));
      expect(model.effects.single.bodySource, contains("print('count is"));
      // onInit's (stripped) source lives in its own field, never
      // plainMemberSources — it's emitted client-only (see
      // CodeEmitter.emitClient), since its body commonly does browser-only
      // work that wouldn't compile in the server output.
      expect(model.onInitSource, contains("print('mounted')"));
      expect(model.onInitSource, isNot(contains(r'$effect')));
      expect(model.plainMemberSources, isEmpty);
    });

    test('emits an empty onInit() when it contains only an effect', () {
      final model = CodeAnalyzer.analyze(r'''
var count = $state(0);
void onInit() {
  $effect(() { print(count); });
}
''');
      expect(model.effects, hasLength(1));
      expect(model.hasOnInit, isTrue);
      // The shell must still exist — CodeEmitter._emitHydrate always calls
      // onInit() once, so a declaration must be present even though every
      // original statement was consumed as an effect.
      expect(model.onInitSource, 'void onInit() {}');
    });

    test('hasOnInit is false when no onInit is declared', () {
      final model = CodeAnalyzer.analyze('var count = \$state(0);');
      expect(model.hasOnInit, isFalse);
    });

    test('records event handler method names', () {
      final model = CodeAnalyzer.analyze(r'''
var count = $state(0);
void increment() { count = count + 1; }
void reset() { count = 0; }
''');
      expect(model.eventHandlerNames, unorderedEquals(['increment', 'reset']));
    });

    test('copies plain (non-rune) fields and methods through verbatim', () {
      final model = CodeAnalyzer.analyze(r'''
final label = 'Static Label';
static const int max = 10;
void doNothing() {}
''');
      expect(model.stateFields, isEmpty);
      expect(model.derivedFields, isEmpty);
      expect(
        model.plainMemberSources.any((s) => s.contains("'Static Label'")),
        isTrue,
      );
      expect(model.plainMemberSources.any((s) => s.contains('max')), isTrue);
      expect(model.eventHandlerNames, contains('doNothing'));
    });

    test('handles multi-line signatures, generics, and doc comments '
        'that broke the old regex-based generator', () {
      final model = CodeAnalyzer.analyze(r'''
/// A doc comment above a field.
var items = $state<List<int>>([]);

/// A doc comment above a method with a multi-line, generic signature.
Map<String, List<int>> buildIndex(
  List<int> values,
  int Function(int) keyOf,
) {
  return {};
}
''');
      expect(model.stateFields.single.name, 'items');
      expect(
        model.plainMemberSources.any((s) => s.contains('buildIndex')),
        isTrue,
      );
    });

    test('handles async onInit with awaited statements alongside an effect', () {
      final model = CodeAnalyzer.analyze(r'''
var count = $state(0);

void onInit() async {
  await Future.delayed(Duration(milliseconds: 10));
  $effect(() { print(count); });
}
''');
      expect(model.effects, hasLength(1));
      expect(
        model.onInitSource,
        contains('Future.delayed'),
      );
    });
  });
}
