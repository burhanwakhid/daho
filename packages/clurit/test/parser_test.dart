import 'package:test/test.dart';
import 'package:clurit/src/parser.dart';
import 'package:clurit/src/lexer.dart';
import 'package:clurit/src/nodes/node.dart';
import 'package:clurit/src/nodes/text_node.dart';
import 'package:clurit/src/nodes/echo_node.dart';
import 'package:clurit/src/nodes/if_node.dart';
import 'package:clurit/src/nodes/foreach_node.dart';

void main() {
  group('Parser', () {
    Node dummyResolver(String template, Map<String, dynamic>? data) {
      return TextNode('included: $template');
    }

    List<Node> parse(String source) {
      final tokens = Lexer.tokenize(source);
      final parser = Parser(tokens, includeResolver: dummyResolver);
      return parser.parse();
    }

    group('text nodes', () {
      test('plain text', () {
        final nodes = parse('Hello, World!');
        expect(nodes.length, 1);
        expect(nodes[0], isA<TextNode>());
        expect((nodes[0] as TextNode).content, 'Hello, World!');
      });

      test('empty text', () {
        final nodes = parse('');
        expect(nodes.length, 0);
      });
    });

    group('echo nodes', () {
      test('escaped echo', () {
        final nodes = parse('{{ \$name }}');
        expect(nodes.length, 1);
        expect(nodes[0], isA<EchoNode>());
        final echo = nodes[0] as EchoNode;
        expect(echo.expression, '\$name');
        expect(echo.escaped, isTrue);
      });

      test('raw echo', () {
        final nodes = parse('{!! \$html !!}');
        expect(nodes.length, 1);
        expect(nodes[0], isA<EchoNode>());
        final echo = nodes[0] as EchoNode;
        expect(echo.expression, '\$html');
        expect(echo.escaped, isFalse);
      });
    });

    group('if nodes', () {
      test('simple if', () {
        final nodes = parse('@if(\$show)\n<p>Visible</p>\n@endif');
        expect(nodes.length, 1);
        expect(nodes[0], isA<IfNode>());
        final ifNode = nodes[0] as IfNode;
        expect(ifNode.condition, '\$show');
        expect(ifNode.thenBody.length, greaterThan(0));
        expect(ifNode.elseBody, isNull);
      });

      test('if with else', () {
        final nodes = parse('@if(\$show)\n<p>Yes</p>\n@else\n<p>No</p>\n@endif');
        expect(nodes.length, 1);
        expect(nodes[0], isA<IfNode>());
        final ifNode = nodes[0] as IfNode;
        expect(ifNode.thenBody.length, greaterThan(0));
        expect(ifNode.elseBody, isNotNull);
        expect(ifNode.elseBody!.length, greaterThan(0));
      });
    });

    group('foreach nodes', () {
      test('simple foreach', () {
        final nodes = parse('@foreach(\$items as \$item)\n<p>{{ \$item }}</p>\n@endforeach');
        expect(nodes.length, 1);
        expect(nodes[0], isA<ForeachNode>());
        final foreach = nodes[0] as ForeachNode;
        expect(foreach.iterableExpr, '\$items');
        expect(foreach.variable, 'item');
        expect(foreach.key, isNull);
        expect(foreach.body.length, greaterThan(0));
      });

      test('foreach with key', () {
        final nodes = parse('@foreach(\$items as \$key => \$value)\n<p>{{ \$key }}: {{ \$value }}</p>\n@endforeach');
        expect(nodes.length, 1);
        expect(nodes[0], isA<ForeachNode>());
        final foreach = nodes[0] as ForeachNode;
        expect(foreach.key, 'key');
        expect(foreach.variable, 'value');
      });
    });

    group('comments', () {
      test('comment produces no nodes', () {
        final nodes = parse('{{-- This is a comment --}}');
        expect(nodes.length, 0);
      });

      test('comment between content', () {
        final nodes = parse('Before{{-- comment --}}After');
        expect(nodes.length, 2);
        expect((nodes[0] as TextNode).content, 'Before');
        expect((nodes[1] as TextNode).content, 'After');
      });
    });

    group('mixed content', () {
      test('text and echo', () {
        final nodes = parse('<h1>{{ \$title }}</h1>');
        expect(nodes.length, 3);
        expect(nodes[0], isA<TextNode>());
        expect(nodes[1], isA<EchoNode>());
        expect(nodes[2], isA<TextNode>());
      });

      test('complex template', () {
        final source = '''
<div>
  @if(\$items.isNotEmpty)
    @foreach(\$items as \$item)
      <p>{{ \$item }}</p>
    @endforeach
  @else
    <p>No items</p>
  @endif
</div>
''';
        final nodes = parse(source);
        expect(nodes.length, greaterThan(0));
        // Should have text nodes and an IfNode
        expect(nodes.any((n) => n is IfNode), isTrue);
      });
    });
  });
}
