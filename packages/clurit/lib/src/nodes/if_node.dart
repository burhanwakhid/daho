import '../expression.dart';
import '../renderer.dart';
import 'node.dart';

/// A node representing an @if conditional block in Clurit.
class IfNode extends Node {
  final String condition;
  final List<Node> thenBody;
  final List<Node>? elseBody;

  IfNode({
    required this.condition,
    required this.thenBody,
    this.elseBody,
  });

  @override
  String compile(Map<String, dynamic> context) {
    final result = ExpressionEvaluator.evaluate(condition, context);
    final isTrue = ExpressionEvaluator.isTruthy(result);

    if (isTrue) {
      return Renderer.render(thenBody, context);
    } else if (elseBody != null) {
      return Renderer.render(elseBody!, context);
    }

    return '';
  }
}
