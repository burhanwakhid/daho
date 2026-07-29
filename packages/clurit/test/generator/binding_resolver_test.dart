import 'package:clurit/src/generator/binding_resolver.dart';
import 'package:clurit/src/lexer.dart';
import 'package:clurit/src/nodes/echo_node.dart';
import 'package:clurit/src/nodes/foreach_node.dart';
import 'package:clurit/src/nodes/if_node.dart';
import 'package:clurit/src/nodes/node.dart';
import 'package:clurit/src/nodes/text_node.dart';
import 'package:clurit/src/parser.dart';
import 'package:test/test.dart';

List<Node> parse(String source) {
  final tokens = Lexer.tokenize(source);
  return Parser(tokens, includeResolver: (_, __) => TextNode('')).parse();
}

void main() {
  group('BindingResolver', () {
    test('assigns no ids when there are no bindings', () {
      final nodes = parse('<div>plain text</div>');
      final model = BindingResolver.resolve(nodes);
      expect(model.ids, isEmpty);
    });

    test('assigns sequential ids to echoes in document order', () {
      final nodes = parse('{{ \$a }}-{{ \$b }}-{{ \$c }}');
      final model = BindingResolver.resolve(nodes);
      final echoes = nodes.whereType<EchoNode>().toList();
      expect(model.idFor(echoes[0]), 0);
      expect(model.idFor(echoes[1]), 1);
      expect(model.idFor(echoes[2]), 2);
    });

    test('assigns an id to an @if and continues numbering inside its body', () {
      final nodes = parse(
        '@if(\$show){{ \$a }}@endif{{ \$b }}',
      );
      final model = BindingResolver.resolve(nodes);
      final ifNode = nodes.whereType<IfNode>().single;
      expect(model.idFor(ifNode), 0);
      expect(model.idFor(ifNode.thenBody.whereType<EchoNode>().single), 1);
      final trailingEcho = nodes.whereType<EchoNode>().single;
      expect(model.idFor(trailingEcho), 2);
    });

    test('descends into both then and else branches', () {
      final nodes = parse(
        '@if(\$show){{ \$a }}@else{{ \$b }}@endif',
      );
      final model = BindingResolver.resolve(nodes);
      final ifNode = nodes.whereType<IfNode>().single;
      expect(model.idFor(ifNode), 0);
      expect(model.idFor(ifNode.thenBody.whereType<EchoNode>().single), 1);
      expect(model.idFor(ifNode.elseBody!.whereType<EchoNode>().single), 2);
    });

    test('assigns an id to @foreach and its nested bindings', () {
      final nodes = parse(
        '@foreach(\$items as \$item){{ \$item }}@endforeach',
      );
      final model = BindingResolver.resolve(nodes);
      final forNode = nodes.whereType<ForeachNode>().single;
      expect(model.idFor(forNode), 0);
      expect(model.idFor(forNode.body.whereType<EchoNode>().single), 1);
    });

    test('ids are stable and unique across a mixed template', () {
      final nodes = parse(r'''
{{ $a }}
@if($show)
  {{ $b }}
  @foreach($items as $item)
    {{ $item }}
  @endforeach
@endif
{{ $c }}
''');
      final model = BindingResolver.resolve(nodes);
      final ids = model.ids.values.toList()..sort();
      expect(ids, [0, 1, 2, 3, 4, 5]);
    });

    test('does not assign an id to an echo inside an attribute value', () {
      final nodes = parse('<input value="{{ \$name }}">');
      final model = BindingResolver.resolve(nodes);
      final echo = nodes.whereType<EchoNode>().single;
      expect(model.has(echo), isFalse);
    });

    test('still assigns an id to an echo in element content after an attribute',
        () {
      final nodes = parse('<input value="{{ \$name }}">{{ \$other }}');
      final model = BindingResolver.resolve(nodes);
      final echoes = nodes.whereType<EchoNode>().toList();
      expect(model.has(echoes[0]), isFalse);
      expect(model.has(echoes[1]), isTrue);
      expect(model.idFor(echoes[1]), 0);
    });

    test(
        'resumes attribute-value tracking correctly across multiple attributes',
        () {
      final nodes = parse(
        '<input value="{{ \$a }}" data-x="static" placeholder="{{ \$b }}">{{ \$c }}',
      );
      final model = BindingResolver.resolve(nodes);
      final echoes = nodes.whereType<EchoNode>().toList();
      expect(model.has(echoes[0]), isFalse); // $a
      expect(model.has(echoes[1]), isFalse); // $b
      expect(model.has(echoes[2]), isTrue); // $c, back in element content
    });
  });
}
