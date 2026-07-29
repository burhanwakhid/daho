import 'package:build/build.dart';
import 'package:clurit/src/generator/binding_resolver.dart';
import 'package:clurit/src/generator/clurit_generator.dart';
import 'package:clurit/src/generator/code_analyzer.dart';
import 'package:clurit/src/generator/code_emitter.dart';
import 'package:clurit/src/lexer.dart';
import 'package:clurit/src/nodes/text_node.dart';
import 'package:clurit/src/parser.dart';
import 'package:test/test.dart';

/// Runs the exact pipeline `CluritGenerator.build()` runs (lex -> parse ->
/// find @code -> analyze -> resolve bindings -> emit), without going through
/// `package:build`'s `BuildStep`/asset-writer plumbing, since that's thin
/// glue around this pipeline and isn't itself the part with interesting
/// logic to regression-test.
CodeEmitter buildEmitter(String source, {String className = 'TestComponent'}) {
  final tokens = Lexer.tokenize(source);
  final nodes = Parser(tokens, includeResolver: (_, __) => TextNode('')).parse();
  final codeNodes = findCodeNodes(nodes);
  final component = CodeAnalyzer.analyze(codeNodes.first.code);
  final bindings = BindingResolver.resolve(nodes);
  return CodeEmitter(
    className: className,
    templateNodes: nodes,
    component: component,
    bindings: bindings,
  );
}

void main() {
  group('CluritGenerator pipeline', () {
    test('finds no @code nodes in a plain template', () {
      final tokens = Lexer.tokenize('<div>{{ \$title }}</div>');
      final nodes = Parser(tokens, includeResolver: (_, __) => TextNode('')).parse();
      expect(findCodeNodes(nodes), isEmpty);
    });

    test('emitServer generates a component with state/derived/@if bindings', () {
      const source = r'''
@code {
  var count = $state(0);
  final doubled = $derived(count * 2);

  void increment() { count = count + 1; }
}

<div>
  <strong>{{ $count }}</strong>
  <button cl-click="increment">Increment</button>
  @if($count > 10)
    <p>Goal reached!</p>
  @endif
</div>
''';

      final output = buildEmitter(source, className: 'CounterComponent').emitServer();

      expect(output, contains('class CounterComponent extends CluritComponent'));
      expect(output, contains('int _count;'));
      expect(output, contains('int get count => _count;'));
      expect(output, contains("markDirty('count')"));
      expect(output, contains('dynamic get doubled => count * 2;'));
      expect(output, contains('void increment() {count = count + 1;}'));
      expect(output, contains('String renderInitial()'));
      expect(output, contains('Map<String, dynamic> initialStateJson()'));
      expect(output, contains("'count': count,"));
      expect(output, contains('<!--cl:0-->'));
      expect(output, contains('<!--cl-if:1-->'));
      expect(output, contains('ExpressionEvaluator.isTruthy(count > 10)'));
      expect(output, isNot(contains('package:web')));
    });

    test('emitClient generates a hydration subclass with targeted DOM updates', () {
      const source = r'''
@code {
  var count = $state(0);

  void increment() { count = count + 1; }
}

<div>
  <strong>{{ $count }}</strong>
  <button cl-click="increment">Increment</button>
  @if($count > 10)
    <p>Goal reached!</p>
  @endif
</div>
''';

      final output = buildEmitter(
        source,
        className: 'CounterComponent',
      ).emitClient('counter.clurit.dart');

      expect(output, contains('class CounterComponentClient extends CounterComponent'));
      expect(output, contains("import 'counter.clurit.dart';"));
      expect(output, contains('Future<void> hydrate(web.Element root) async'));
      expect(output, contains('_nodes = captureClNodes(root)'));
      expect(output, contains("bindActions(_nodes, {'increment': increment})"));
      expect(output, contains("registerUpdater('count', _applyBinding0)"));
      expect(output, contains("registerUpdater('count', _applyBinding1)"));
      expect(output, contains('_nodes.anchors[0]!.setText('));
      expect(output, contains('_nodes.anchors[1]!.setNodes('));
      expect(output, contains('_fragment1Then()'));
      expect(output, contains('_fragment1Else()'));
    });

    test('emitClient calls an async onInit() once from hydrate(), awaited', () {
      const source = r'''
@code {
  var loaded = $state(false);

  void onInit() async {
    loaded = true;
  }
}

<div>{{ $loaded }}</div>
''';

      final output = buildEmitter(
        source,
        className: 'FetchComponent',
      ).emitClient('fetch.clurit.dart');

      expect(output, contains('await onInit();'));
    });

    test('emitClient calls a synchronous onInit() without awaiting it', () {
      const source = r'''
@code {
  var loaded = $state(false);

  void onInit() {
    loaded = true;
  }
}

<div>{{ $loaded }}</div>
''';

      final output = buildEmitter(
        source,
        className: 'SyncInitComponent',
      ).emitClient('sync_init.clurit.dart');

      // A non-async onInit can't be awaited (`void` isn't a value `await`
      // can operate on) — must be called plainly instead.
      expect(output, contains('    onInit();'));
      expect(output, isNot(contains('await onInit();')));
    });

    test('emitClient does not call onInit() when none is declared', () {
      const source = r'''
@code {
  var count = $state(0);
}

<div>{{ $count }}</div>
''';

      final output = buildEmitter(
        source,
        className: 'NoInitComponent',
      ).emitClient('no_init.clurit.dart');

      expect(output, isNot(contains('onInit')));
    });

    test('emitServer renders an attribute-context echo without anchor comments', () {
      const source = r'''
@code {
  var name = $state('');
}

<input cl-model="name" value="{{ $name }}">
<p>{{ $name }}</p>
''';

      final output = buildEmitter(source, className: 'FormComponent').emitServer();

      expect(output, contains('<input cl-model="name" value="'));
      expect(output, contains('buf.write(escapeHtml(stringify(name)));'));
      // The attribute-context echo isn't anchor-wrapped, but the later
      // element-content echo of the same field still is (as binding id 0,
      // since the attribute-context one never consumed an id).
      expect(output, contains('<!--cl:0-->'));
    });

    test('emitClient wires cl-model two-way binding for a bound state field', () {
      const source = r'''
@code {
  var name = $state('');
}

<input cl-model="name" value="{{ $name }}">
<p>{{ $name }}</p>
''';

      final output = buildEmitter(
        source,
        className: 'FormComponent',
      ).emitClient('form.clurit.dart');

      expect(output, contains("bindModels(_nodes, {'name': (v) => name = v})"));
      expect(
        output,
        contains("registerUpdater('name', () => setModelValue(_nodes, 'name', name.toString()))"),
      );
    });

    test('emitClient coerces cl-model input for a non-String state field', () {
      const source = r'''
@code {
  var age = $state(0);
}

<input cl-model="age" value="{{ $age }}">
''';

      final output = buildEmitter(
        source,
        className: 'AgeComponent',
      ).emitClient('age.clurit.dart');

      expect(
        output,
        contains("bindModels(_nodes, {'age': (v) => age = int.tryParse(v) ?? age})"),
      );
    });

    test('generates \$props as a required constructor parameter', () {
      const source = r'''
@code {
  final title = $props<String>();
}

<h1>{{ $title }}</h1>
''';

      final output = buildEmitter(source, className: 'HeadingComponent').emitServer();

      expect(output, contains('final String title;'));
      expect(output, contains('required this.title'));
    });

    test('includes \$props values (not just \$state) in initialStateJson', () {
      const source = r'''
@code {
  var count = $state(0);
  final title = $props<String>();
}

<h1>{{ $title }}: {{ $count }}</h1>
''';

      final output = buildEmitter(source, className: 'HeadingComponent').emitServer();

      expect(output, contains("'count': count,"));
      expect(output, contains("'title': title,"));
    });

    test('classNameFor derives PascalCase names from file paths', () {
      expect(
        classNameFor(AssetId('app', 'lib/views/pages/counter.clurit')),
        'CounterComponent',
      );
      expect(
        classNameFor(AssetId('app', 'lib/views/user_profile.clurit')),
        'UserProfileComponent',
      );
    });
  });
}
