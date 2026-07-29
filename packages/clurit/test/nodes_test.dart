import 'package:test/test.dart';
import 'package:clurit/src/nodes/text_node.dart';
import 'package:clurit/src/nodes/echo_node.dart';
import 'package:clurit/src/nodes/if_node.dart';
import 'package:clurit/src/nodes/foreach_node.dart';

void main() {
  group('TextNode', () {
    test('compiles to content', () {
      final node = TextNode('Hello, World!');
      expect(node.compile({}), 'Hello, World!');
    });

    test('compiles empty content', () {
      final node = TextNode('');
      expect(node.compile({}), '');
    });

    test('compiles HTML content', () {
      final node = TextNode('<div class="test">Content</div>');
      expect(node.compile({}), '<div class="test">Content</div>');
    });
  });

  group('EchoNode', () {
    test('compiles escaped variable', () {
      final node = EchoNode('\$name', escaped: true);
      expect(node.compile({'name': 'Alice'}), 'Alice');
    });

    test('escapes HTML in escaped mode', () {
      final node = EchoNode('\$html', escaped: true);
      expect(
        node.compile({'html': '<script>alert("xss")</script>'}),
        '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;',
      );
    });

    test('does not escape in raw mode', () {
      final node = EchoNode('\$html', escaped: false);
      expect(node.compile({'html': '<b>Bold</b>'}), '<b>Bold</b>');
    });

    test('handles null value', () {
      final node = EchoNode('\$missing', escaped: true);
      expect(node.compile({}), '');
    });

    test('handles numeric value', () {
      final node = EchoNode('\$count', escaped: true);
      expect(node.compile({'count': 42}), '42');
    });

    test('handles boolean value', () {
      final node = EchoNode('\$active', escaped: true);
      expect(node.compile({'active': true}), 'true');
    });

    test('handles list value', () {
      final node = EchoNode('\$items', escaped: true);
      expect(
        node.compile({
          'items': [1, 2, 3],
        }),
        '1, 2, 3',
      );
    });
  });

  group('IfNode', () {
    test('renders then body when condition is truthy', () {
      final node = IfNode(condition: '\$show', thenBody: [TextNode('Visible')]);
      expect(node.compile({'show': true}), 'Visible');
    });

    test('does not render then body when condition is falsy', () {
      final node = IfNode(condition: '\$show', thenBody: [TextNode('Visible')]);
      expect(node.compile({'show': false}), '');
    });

    test('renders else body when condition is falsy', () {
      final node = IfNode(
        condition: '\$show',
        thenBody: [TextNode('Yes')],
        elseBody: [TextNode('No')],
      );
      expect(node.compile({'show': false}), 'No');
    });

    test('handles null condition', () {
      final node = IfNode(
        condition: '\$value',
        thenBody: [TextNode('Yes')],
        elseBody: [TextNode('No')],
      );
      expect(node.compile({'value': null}), 'No');
    });

    test('handles empty list condition', () {
      final node = IfNode(
        condition: '\$items',
        thenBody: [TextNode('Has items')],
        elseBody: [TextNode('No items')],
      );
      expect(node.compile({'items': <int>[]}), 'No items');
    });

    test('handles non-empty list condition', () {
      final node = IfNode(
        condition: '\$items',
        thenBody: [TextNode('Has items')],
        elseBody: [TextNode('No items')],
      );
      expect(
        node.compile({
          'items': [1, 2, 3],
        }),
        'Has items',
      );
    });

    test('handles non-empty string condition', () {
      final node = IfNode(
        condition: '\$str',
        thenBody: [TextNode('Has string')],
        elseBody: [TextNode('No string')],
      );
      expect(node.compile({'str': 'hello'}), 'Has string');
    });

    test('handles empty string condition', () {
      final node = IfNode(
        condition: '\$str',
        thenBody: [TextNode('Has string')],
        elseBody: [TextNode('No string')],
      );
      expect(node.compile({'str': ''}), 'No string');
    });

    test('does not inject any cl-if attribute (plain render only)', () {
      final node = IfNode(
        condition: '\$show',
        thenBody: [TextNode('<div class="a">Visible</div>')],
      );
      expect(node.compile({'show': true}), '<div class="a">Visible</div>');
    });

    test('renders multi-root content unmodified', () {
      final node = IfNode(
        condition: '\$show',
        thenBody: [TextNode('<p>One</p><p>Two</p>')],
      );
      expect(node.compile({'show': true}), '<p>One</p><p>Two</p>');
    });

    test('renders self-closing tags unmodified', () {
      final node = IfNode(
        condition: '\$show',
        thenBody: [TextNode('<input type="text"/>')],
      );
      expect(node.compile({'show': true}), '<input type="text"/>');
    });

    test('renders content with > inside attributes unmodified', () {
      final node = IfNode(
        condition: '\$show',
        thenBody: [TextNode('<div data-expr="1 > 0">Visible</div>')],
      );
      expect(
        node.compile({'show': true}),
        '<div data-expr="1 > 0">Visible</div>',
      );
    });
  });

  group('ForeachNode', () {
    test('renders each item', () {
      final node = ForeachNode(
        iterableExpr: '\$items',
        variable: 'item',
        body: [
          TextNode('Item: '),
          EchoNode('\$item', escaped: true),
          TextNode('\n'),
        ],
      );
      final result = node.compile({
        'items': ['A', 'B', 'C'],
      });
      expect(result, contains('Item: A'));
      expect(result, contains('Item: B'));
      expect(result, contains('Item: C'));
    });

    test('provides loop metadata', () {
      final node = ForeachNode(
        iterableExpr: '\$items',
        variable: 'item',
        body: [EchoNode('\$item', escaped: true)],
      );
      final result = node.compile({
        'items': ['A', 'B'],
      });
      expect(result, contains('A'));
      expect(result, contains('B'));
    });

    test('handles empty iterable', () {
      final node = ForeachNode(
        iterableExpr: '\$items',
        variable: 'item',
        body: [TextNode('Item')],
      );
      expect(node.compile({'items': <int>[]}), '');
    });

    test('handles non-iterable', () {
      final node = ForeachNode(
        iterableExpr: '\$value',
        variable: 'item',
        body: [TextNode('Item')],
      );
      expect(node.compile({'value': 'not a list'}), '');
    });

    test('renders correct number of items', () {
      final node = ForeachNode(
        iterableExpr: '\$items',
        variable: 'item',
        body: [TextNode('-'), EchoNode('\$item', escaped: true), TextNode('-')],
      );
      final result = node.compile({
        'items': ['X', 'Y'],
      });
      expect(result, contains('-X-'));
      expect(result, contains('-Y-'));
    });

    test('does not inject cl-ssr-for markers or a hydration template block',
        () {
      final node = ForeachNode(
        iterableExpr: '\$items',
        variable: 'item',
        body: [
          TextNode('<li>'),
          EchoNode('\$item', escaped: true),
          TextNode('</li>')
        ],
      );
      final result = node.compile({
        'items': ['A', 'B'],
      });
      expect(result, '<li>A</li><li>B</li>');
      expect(result, isNot(contains('cl-ssr-for')));
      expect(result, isNot(contains('<template')));
    });

    test('renders multi-root item bodies with attributes containing >', () {
      final node = ForeachNode(
        iterableExpr: '\$items',
        variable: 'item',
        body: [TextNode('<div data-expr="1 > 0"></div><span></span>')],
      );
      final result = node.compile({
        'items': ['A'],
      });
      expect(result, '<div data-expr="1 > 0"></div><span></span>');
    });
  });
}
