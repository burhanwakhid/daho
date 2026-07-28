import '../expression.dart';
import '../helpers.dart';
import 'node.dart';

/// A node that outputs an expression result.
///
/// [escaped] determines whether HTML escaping is applied:
/// - `{{ expr }}` → escaped (default)
/// - `{!! expr !!}` → raw (unescaped)
class EchoNode extends Node {
  final String expression;
  final bool escaped;

  EchoNode(this.expression, {this.escaped = true});

  @override
  String compile(Map<String, dynamic> context) {
    final value = ExpressionEvaluator.evaluate(expression, context);
    final str = stringify(value);
    return escaped ? escapeHtml(str) : str;
  }
}
