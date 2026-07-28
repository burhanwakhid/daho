import '../expression.dart';
import 'node.dart';

/// A node for @if/@elseif/@else/@endif conditional rendering.
class IfNode extends Node {
  final String condition;
  final List<Node> thenBody;
  final List<Node>? elseBody;

  IfNode({required this.condition, required this.thenBody, this.elseBody});

  @override
  String compile(Map<String, dynamic> context) {
    final result = ExpressionEvaluator.evaluate(condition, context);
    if (_isTruthy(result)) {
      return _compileBody(thenBody, context);
    } else if (elseBody != null) {
      return _compileBody(elseBody!, context);
    }
    return '';
  }

  static bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is double) return value != 0.0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static String _compileBody(List<Node> nodes, Map<String, dynamic> context) {
    final buf = StringBuffer();
    for (final node in nodes) {
      buf.write(node.compile(context));
    }
    return buf.toString();
  }
}
