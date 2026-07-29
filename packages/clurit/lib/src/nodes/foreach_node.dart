import '../expression.dart';
import '../renderer.dart';
import 'node.dart';

/// A node representing a @foreach loop in Clurit.
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
    final items = ExpressionEvaluator.evaluate(iterableExpr, context);
    final buf = StringBuffer();

    if (items is! Iterable) return buf.toString();

    int index = 0;
    final total = items.length;

    for (final item in items) {
      final loopContext = Map<String, dynamic>.from(context);
      loopContext[variable] = item;
      if (key != null) {
        if (items is Map) {
          loopContext[key!] = (items as Map).keys.elementAt(index);
        } else {
          loopContext[key!] = index;
        }
      }

      loopContext['loop'] = {
        'index': index,
        'iteration': index + 1,
        'remaining': total - (index + 1),
        'count': total,
        'first': index == 0,
        'last': index == total - 1,
        'even': index % 2 == 1,
        'odd': index % 2 == 0,
      };

      buf.write(Renderer.render(body, loopContext));
      index++;
    }

    return buf.toString();
  }
}
