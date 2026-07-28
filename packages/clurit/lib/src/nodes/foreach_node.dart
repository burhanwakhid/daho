import '../expression.dart';
import 'node.dart';

/// A node for @foreach/@endforeach loop rendering.
///
/// Provides a `$loop` variable with iteration metadata.
class ForeachNode extends Node {
  final String iterableExpr;
  final String variable;
  final String? key;
  final List<Node> body;

  ForeachNode({
    required this.iterableExpr,
    required this.variable,
    this.key,
    required this.body,
  });

  @override
  String compile(Map<String, dynamic> context) {
    final iterable = ExpressionEvaluator.evaluate(iterableExpr, context);
    if (iterable is! Iterable) return '';

    final buf = StringBuffer();
    final items = iterable.toList();
    final count = items.length;

    for (int i = 0; i < count; i++) {
      final item = items[i];

      // Create loop context as a Map for easy property access
      final loopData = {
        'index': i,
        'iteration': i + 1,
        'remaining': count - i - 1,
        'count': count,
        'first': i == 0,
        'last': i == count - 1,
        'even': i % 2 == 0,
        'odd': i % 2 != 0,
        'depth': 1,
      };

      // Build item context
      final itemContext = Map<String, dynamic>.from(context);
      itemContext[variable] = item;
      if (key != null && item is Map) {
        itemContext[key!] = item.keys.first;
      }
      itemContext['loop'] = loopData;

      for (final node in body) {
        buf.write(node.compile(itemContext));
      }
    }

    return buf.toString();
  }
}
