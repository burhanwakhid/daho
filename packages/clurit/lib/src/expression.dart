/// Expression evaluator for Clurit templates.
///
/// Supports:
/// - Variable access: $user.name, $items[0]
/// - Arrow syntax: $loop->first (converted to $loop.first)
/// - Arithmetic: $a + $b
/// - Comparison: $a == $b, $a > $b
/// - Logical: $a && $b, !$a
/// - Ternary: $a ? $b : $c
/// - Null-aware: $a?.name ?? 'default'
/// - Method calls: $items.isEmpty, $user.name.toUpperCase()
class ExpressionEvaluator {
  /// Evaluates a Dart-like expression against the given [context].
  static dynamic evaluate(String expression, Map<String, dynamic> context) {
    // Convert Blade arrow syntax to dot notation
    var expr = expression.trim().replaceAll('->', '.');

    // Handle empty expression
    if (expr.isEmpty) return null;

    // Handle string literals
    if ((expr.startsWith("'") && expr.endsWith("'")) ||
        (expr.startsWith('"') && expr.endsWith('"'))) {
      return expr.substring(1, expr.length - 1);
    }

    // Handle number literals
    final num? numValue = num.tryParse(expr);
    if (numValue != null) return numValue;

    // Handle boolean literals
    if (expr == 'true') return true;
    if (expr == 'false') return false;
    if (expr == 'null') return null;

    // Handle negation
    if (expr.startsWith('!')) {
      final inner = evaluate(expr.substring(1), context);
      return !isTruthy(inner);
    }

    // Handle ternary: condition ? trueExpr : falseExpr
    final ternaryIdx = _findTernary(expr);
    if (ternaryIdx != null) {
      final condition = expr.substring(0, ternaryIdx).trim();
      final rest = expr.substring(ternaryIdx + 1).trim();
      final colonIdx = _findColon(rest);
      if (colonIdx != null) {
        final trueExpr = rest.substring(0, colonIdx).trim();
        final falseExpr = rest.substring(colonIdx + 1).trim();
        final condResult = evaluate(condition, context);
        return isTruthy(condResult)
            ? evaluate(trueExpr, context)
            : evaluate(falseExpr, context);
      }
    }

    // Handle null coalescing: expr ?? default
    final nullCoalesceIdx = _findOperator(expr, '??');
    if (nullCoalesceIdx != null) {
      final left = expr.substring(0, nullCoalesceIdx).trim();
      final right = expr.substring(nullCoalesceIdx + 2).trim();
      final leftResult = evaluate(left, context);
      return leftResult ?? evaluate(right, context);
    }

    // Handle logical AND: expr && expr
    final andIdx = _findOperator(expr, '&&');
    if (andIdx != null) {
      final left = expr.substring(0, andIdx).trim();
      final right = expr.substring(andIdx + 2).trim();
      return isTruthy(evaluate(left, context)) &&
          isTruthy(evaluate(right, context));
    }

    // Handle logical OR: expr || expr
    final orIdx = _findOperator(expr, '||');
    if (orIdx != null) {
      final left = expr.substring(0, orIdx).trim();
      final right = expr.substring(orIdx + 2).trim();
      return isTruthy(evaluate(left, context)) ||
          isTruthy(evaluate(right, context));
    }

    // Handle comparison operators
    for (final op in ['==', '!=', '>=', '<=', '>', '<']) {
      final opIdx = _findOperator(expr, op);
      if (opIdx != null) {
        final left = evaluate(expr.substring(0, opIdx).trim(), context);
        final right = evaluate(
          expr.substring(opIdx + op.length).trim(),
          context,
        );
        return _compare(left, right, op);
      }
    }

    // Handle arithmetic: + and -
    final addIdx = _findOperator(expr, '+');
    if (addIdx != null) {
      final left = evaluate(expr.substring(0, addIdx).trim(), context);
      final right = evaluate(expr.substring(addIdx + 1).trim(), context);
      if (left is num && right is num) return left + right;
      if (left is String || right is String) return '$left$right';
      return left;
    }

    final subIdx = _findOperator(expr, '-');
    if (subIdx != null) {
      final left = evaluate(expr.substring(0, subIdx).trim(), context);
      final right = evaluate(expr.substring(subIdx + 1).trim(), context);
      if (left is num && right is num) return left - right;
      return left;
    }

    // Handle null-safe access: $a?.name
    if (expr.contains('?.')) {
      final parts = expr.split('?.');
      final obj = evaluate(parts[0], context);
      if (obj == null) return null;
      return _resolveProperty(obj, parts.sublist(1).join('.'));
    }

    // Handle dot notation: $user.name
    if (expr.contains('.') && !expr.startsWith("'")) {
      final parts = expr.split('.');
      final obj = evaluate(parts[0], context);
      if (obj == null) return null;
      return _resolveProperty(obj, parts.sublist(1).join('.'));
    }

    // Handle array access: $items[0]
    if (expr.contains('[') && expr.endsWith(']')) {
      final bracketIdx = expr.indexOf('[');
      final objExpr = expr.substring(0, bracketIdx);
      final indexExpr = expr.substring(bracketIdx + 1, expr.length - 1);
      final obj = evaluate(objExpr, context);
      final index = evaluate(indexExpr, context);
      if (obj is List && index is int) return obj[index];
      if (obj is Map) return obj[index];
      return null;
    }

    // Handle variable access: $name
    if (expr.startsWith('\$')) {
      final varName = expr.substring(1);
      return _resolveVariable(varName, context);
    }

    // Handle plain variable (without $)
    if (RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(expr)) {
      return context[expr];
    }

    return null;
  }

  static dynamic _resolveVariable(String name, Map<String, dynamic> context) {
    if (name.contains('.')) {
      final parts = name.split('.');
      dynamic obj = context[parts[0]];
      for (int i = 1; i < parts.length; i++) {
        if (obj == null) return null;
        obj = _resolveProperty(obj, parts[i]);
      }
      return obj;
    }
    return context[name];
  }

  static dynamic _resolveProperty(dynamic obj, String property) {
    if (obj == null) return null;
    if (obj is Map) return obj[property];
    if (obj is List) {
      final idx = int.tryParse(property);
      if (idx != null && idx >= 0 && idx < obj.length) return obj[idx];
      // List methods
      if (property == 'length') return obj.length;
      if (property == 'isEmpty') return obj.isEmpty;
      if (property == 'isNotEmpty') return obj.isNotEmpty;
      if (property == 'first') return obj.isNotEmpty ? obj.first : null;
      if (property == 'last') return obj.isNotEmpty ? obj.last : null;
      return null;
    }
    // String methods
    if (obj is String) {
      if (property == 'length') return obj.length;
      if (property == 'isEmpty') return obj.isEmpty;
      if (property == 'isNotEmpty') return obj.isNotEmpty;
      if (property == 'toUpperCase') return obj.toUpperCase();
      if (property == 'toLowerCase') return obj.toLowerCase();
      if (property == 'trim') return obj.trim();
      return null;
    }
    // Num methods
    if (obj is num) {
      if (property == 'abs') return obj.abs();
      if (property == 'toInt') return obj.toInt();
      if (property == 'toDouble') return obj.toDouble();
      return null;
    }
    return null;
  }

  static bool isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is double) return value != 0.0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static dynamic _compare(dynamic left, dynamic right, String op) {
    switch (op) {
      case '==':
        return left == right;
      case '!=':
        return left != right;
      case '>':
        return _toNum(left) > _toNum(right);
      case '<':
        return _toNum(left) < _toNum(right);
      case '>=':
        return _toNum(left) >= _toNum(right);
      case '<=':
        return _toNum(left) <= _toNum(right);
      default:
        return false;
    }
  }

  static num _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static int? _findTernary(String expr) {
    int depth = 0;
    for (int i = 0; i < expr.length; i++) {
      if (expr[i] == '(') depth++;
      if (expr[i] == ')') depth--;
      if (depth == 0 && expr[i] == '?') return i;
    }
    return null;
  }

  static int? _findColon(String expr) {
    int depth = 0;
    for (int i = 0; i < expr.length; i++) {
      if (expr[i] == '(') depth++;
      if (expr[i] == ')') depth--;
      if (depth == 0 && expr[i] == ':') return i;
    }
    return null;
  }

  static int? _findOperator(String expr, String op) {
    int depth = 0;
    // Search from right to left for left-associative operators
    for (int i = expr.length - op.length; i >= 0; i--) {
      if (expr[i] == ')') depth++;
      if (expr[i] == '(') depth--;
      if (depth == 0 && expr.substring(i, i + op.length) == op) {
        // Make sure it's not part of a longer operator (e.g., == vs =)
        if (op == '=' && i + 1 < expr.length && expr[i + 1] == '=') continue;
        if (op == '!' && i + 1 < expr.length && expr[i + 1] == '=') continue;
        return i;
      }
    }
    return null;
  }
}
