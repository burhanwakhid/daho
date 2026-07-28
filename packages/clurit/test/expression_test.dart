import 'package:test/test.dart';
import 'package:clurit/src/expression.dart';

void main() {
  group('ExpressionEvaluator', () {
    group('literals', () {
      test('string literal', () {
        expect(ExpressionEvaluator.evaluate("'hello'", {}), 'hello');
        expect(ExpressionEvaluator.evaluate('"world"', {}), 'world');
      });

      test('number literal', () {
        expect(ExpressionEvaluator.evaluate('42', {}), 42);
        expect(ExpressionEvaluator.evaluate('3.14', {}), 3.14);
      });

      test('boolean literal', () {
        expect(ExpressionEvaluator.evaluate('true', {}), true);
        expect(ExpressionEvaluator.evaluate('false', {}), false);
      });

      test('null literal', () {
        expect(ExpressionEvaluator.evaluate('null', {}), isNull);
      });
    });

    group('variable access', () {
      test('simple variable', () {
        final context = {'name': 'Alice'};
        expect(ExpressionEvaluator.evaluate('\$name', context), 'Alice');
      });

      test('variable without dollar sign', () {
        final context = {'name': 'Alice'};
        expect(ExpressionEvaluator.evaluate('name', context), 'Alice');
      });

      test('missing variable returns null', () {
        expect(ExpressionEvaluator.evaluate('\$missing', {}), isNull);
      });

      test('nested variable', () {
        final context = {
          'user': {'name': 'Alice'},
        };
        expect(ExpressionEvaluator.evaluate('\$user.name', context), 'Alice');
      });

      test('array access', () {
        final context = {
          'items': ['a', 'b', 'c'],
        };
        expect(ExpressionEvaluator.evaluate('\$items[0]', context), 'a');
        expect(ExpressionEvaluator.evaluate('\$items[2]', context), 'c');
      });

      test('map access via dot notation', () {
        final context = {
          'data': {'key': 'value'},
        };
        expect(ExpressionEvaluator.evaluate('\$data.key', context), 'value');
      });
    });

    group('operators', () {
      test('negation', () {
        expect(ExpressionEvaluator.evaluate('!true', {}), false);
        expect(ExpressionEvaluator.evaluate('!false', {}), true);
        expect(ExpressionEvaluator.evaluate('!null', {}), true);
        expect(ExpressionEvaluator.evaluate('!0', {}), true);
        expect(ExpressionEvaluator.evaluate('!1', {}), false);
      });

      test('comparison', () {
        expect(ExpressionEvaluator.evaluate('1 == 1', {}), true);
        expect(ExpressionEvaluator.evaluate('1 == 2', {}), false);
        expect(ExpressionEvaluator.evaluate('1 != 2', {}), true);
        expect(ExpressionEvaluator.evaluate('2 > 1', {}), true);
        expect(ExpressionEvaluator.evaluate('1 < 2', {}), true);
        expect(ExpressionEvaluator.evaluate('1 >= 1', {}), true);
        expect(ExpressionEvaluator.evaluate('1 <= 2', {}), true);
      });

      test('logical AND', () {
        expect(ExpressionEvaluator.evaluate('true && true', {}), true);
        expect(ExpressionEvaluator.evaluate('true && false', {}), false);
      });

      test('logical OR', () {
        expect(ExpressionEvaluator.evaluate('true || false', {}), true);
        expect(ExpressionEvaluator.evaluate('false || false', {}), false);
      });
    });

    group('arithmetic', () {
      test('addition', () {
        final context = {'a': 5, 'b': 3};
        expect(ExpressionEvaluator.evaluate('\$a + \$b', context), 8);
      });

      test('subtraction', () {
        final context = {'a': 5, 'b': 3};
        expect(ExpressionEvaluator.evaluate('\$a - \$b', context), 2);
      });

      test('string concatenation', () {
        final context = {'a': 'Hello', 'b': ' World'};
        expect(
          ExpressionEvaluator.evaluate('\$a + \$b', context),
          'Hello World',
        );
      });
    });

    group('property access', () {
      test('list length', () {
        final context = {
          'items': [1, 2, 3],
        };
        expect(ExpressionEvaluator.evaluate('\$items.length', context), 3);
      });

      test('list isEmpty', () {
        expect(
          ExpressionEvaluator.evaluate('\$items.isEmpty', {'items': <int>[]}),
          true,
        );
        expect(
          ExpressionEvaluator.evaluate('\$items.isEmpty', {
            'items': [1],
          }),
          false,
        );
      });

      test('list isNotEmpty', () {
        expect(
          ExpressionEvaluator.evaluate('\$items.isNotEmpty', {
            'items': [1],
          }),
          true,
        );
      });

      test('string length', () {
        final context = {'str': 'hello'};
        expect(ExpressionEvaluator.evaluate('\$str.length', context), 5);
      });

      test('string isEmpty', () {
        expect(
          ExpressionEvaluator.evaluate('\$str.isEmpty', {'str': ''}),
          true,
        );
        expect(
          ExpressionEvaluator.evaluate('\$str.isEmpty', {'str': 'hello'}),
          false,
        );
      });
    });

    group('truthiness', () {
      test('null is falsy', () {
        expect(ExpressionEvaluator.evaluate('null', {}), isNull);
      });

      test('empty string', () {
        final context = {'str': ''};
        expect(ExpressionEvaluator.evaluate('\$str', context), '');
      });

      test('empty list', () {
        final context = {'items': <int>[]};
        expect(ExpressionEvaluator.evaluate('\$items', context), isEmpty);
      });

      test('non-empty values', () {
        expect(ExpressionEvaluator.evaluate('1', {}), 1);
        expect(ExpressionEvaluator.evaluate('"hello"', {}), 'hello');
      });
    });

    group('null-safe access', () {
      test('null-safe on null', () {
        final context = {'user': null};
        expect(ExpressionEvaluator.evaluate('\$user?.name', context), isNull);
      });

      test('null-safe on value', () {
        final context = {
          'user': {'name': 'Alice'},
        };
        expect(ExpressionEvaluator.evaluate('\$user?.name', context), 'Alice');
      });
    });
  });
}
